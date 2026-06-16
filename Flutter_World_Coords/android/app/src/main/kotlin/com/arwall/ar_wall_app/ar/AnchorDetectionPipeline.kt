package com.arwall.ar_wall_app.ar

import com.google.ar.core.AugmentedImage
import com.google.ar.core.Pose
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.sqrt

// =============================================================================
// AnchorDetectionPipeline
//
// Phase 2 explicit runtime pipeline:
//   1. raw detections
//   2. FULL_TRACKING gate
//   3. per-anchor batch accumulators
//   4. per-anchor averaged raw detections
//   5. per-anchor correction poses
//   6. quality scoring / normalized weights
//   7. weighted fusion of correction poses
//   8. apply world pose
//
// A fusion cycle closes when any anchor reaches MAX_BATCH_SIZE samples.
// All anchors that are still visible and have at least MIN_ELIGIBLE_SAMPLES
// contribute to the fused correction for that cycle. The cycle buffers are then
// cleared together and a new cycle begins.
// =============================================================================
class AnchorDetectionPipeline(
    private val worldCoordinateManager: WorldCoordinateManager,
) {

    companion object {
        const val MAX_BATCH_SIZE = 8
        const val MIN_ELIGIBLE_SAMPLES = 4
        const val DISTANCE_EPSILON_SQ = 0.01f
        const val JUMP_POSITION_ALERT_METERS = 0.05f
        const val JUMP_ROTATION_ALERT_DEGREES = 3f
        const val SINGLE_ANCHOR_BOOTSTRAP_CYCLES = 2
        const val SINGLE_ANCHOR_LARGE_CORRECTION_STABLE_CYCLES = 2
        const val SINGLE_ANCHOR_LARGE_CORRECTION_POSITION_METERS = 0.10f
        const val SINGLE_ANCHOR_LARGE_CORRECTION_ROTATION_DEGREES = 10f
        const val SINGLE_ANCHOR_TRUSTED_POSITION_METERS = 0.15f
        const val SINGLE_ANCHOR_TRUSTED_ROTATION_DEGREES = 20f
    }

    private val cycleBuffer = PerAnchorFusionCycleBuffer(
        maxBatchSize = MAX_BATCH_SIZE,
        minEligibleSamples = MIN_ELIGIBLE_SAMPLES,
    )
    private var runtimeBypassLogged = false
    private var inHoldMode = false
    private var singleAnchorStableCyclesSinceResetOrPause = 0
    private val trustedCorrectionPoseByAnchorId = mutableMapOf<String, Pose>()

    fun onDetection(raw: RawAnchorDetection) {
        if (!worldCoordinateManager.shouldAcceptRuntimePipelineDetections()) {
            if (!runtimeBypassLogged) {
                runtimeBypassLogged = true
                android.util.Log.d(
                    "DetectionPipeline",
                    "[PIPELINE] bypass runtime_pipeline reason=calibration_or_frozen",
                )
            }
            return
        }
        if (runtimeBypassLogged) {
            runtimeBypassLogged = false
            android.util.Log.d("DetectionPipeline", "[PIPELINE] runtime_pipeline_resumed")
        }

        val full = keepOnlyFullTracking(raw) ?: run {
            onAnchorPaused(raw.anchorId)
            return
        }

        val cycleClosure = cycleBuffer.onFullTrackingDetection(full)
        if (inHoldMode && cycleBuffer.hasVisibleAnchors()) {
            inHoldMode = false
            android.util.Log.d(
                "DetectionPipeline",
                "[PIPELINE] hold_exit anchor=${full.anchorId} dist=${full.distanceMeters.f3()}m",
            )
        }

        val eligibleBatches = cycleClosure?.eligibleBatches ?: return
        val correctionCandidates = eligibleBatches.mapNotNull { batch ->
            val correctionPose = worldCoordinateManager.computeCorrectionPose(
                batch.anchorId,
                batch.averagedPose,
            ) ?: run {
                android.util.Log.w(
                    "DetectionPipeline",
                    "[PIPELINE] correction_skip anchor=${batch.anchorId} reason=missing_blueprint",
                )
                return@mapNotNull null
            }
            CorrectionCandidate(
                anchorId = batch.anchorId,
                sampleCount = batch.sampleCount,
                averagedDistanceMeters = batch.averagedDistanceMeters,
                averagedExtentXMeters = batch.averagedExtentXMeters,
                averagedExtentZMeters = batch.averagedExtentZMeters,
                translationSpreadMeters = batch.translationSpreadMeters,
                averagedRawPose = batch.averagedPose,
                correctionPose = correctionPose,
            )
        }

        if (correctionCandidates.isEmpty()) {
            android.util.Log.w(
                "DetectionPipeline",
                "[PIPELINE] cycle_drop trigger=${cycleClosure.triggerAnchorId} reason=no_valid_candidates",
            )
            return
        }

        val previousWorldPose = worldCoordinateManager.currentCorrectionPose()
        val fusionResult = fuseCorrectionCandidates(correctionCandidates)
        val poseDelta = previousWorldPose?.let { measurePoseDelta(it, fusionResult.fusedPose) }
        val jumpAlert = poseDelta != null &&
            (poseDelta.positionMeters >= JUMP_POSITION_ALERT_METERS ||
                poseDelta.rotationDegrees >= JUMP_ROTATION_ALERT_DEGREES)
        val weightSummary = fusionResult.weightedCandidates.joinToString(" ") {
            "${it.anchorId}(n=${it.sampleCount},d=${it.averagedDistanceMeters.f3()},ext=${it.averagedExtentXMeters.f3()}x${it.averagedExtentZMeters.f3()},spr=${it.translationSpreadMeters.f3()},wd=${it.distanceScore.f3()},wb=${it.batchScore.f3()},w=${it.normalizedWeight.f3()})"
        }
        val deltaSummary = when {
            poseDelta == null -> "first_apply"
            else -> "dPos=${poseDelta.positionMeters.f3()}m dRot=${poseDelta.rotationDegrees.f1()}deg${if (jumpAlert) " jump_alert=true" else ""}"
        }

        val singleAnchorCandidate = correctionCandidates.singleOrNull()
        val nextSingleAnchorStableCycles = if (singleAnchorCandidate != null) {
            singleAnchorStableCyclesSinceResetOrPause + 1
        } else {
            0
        }
        val trustedSingleAnchorPose = singleAnchorCandidate?.let {
            trustedCorrectionPoseByAnchorId[it.anchorId]
        }
        val trustedSingleAnchorDelta = if (singleAnchorCandidate != null && trustedSingleAnchorPose != null) {
            measurePoseDelta(trustedSingleAnchorPose, singleAnchorCandidate.correctionPose)
        } else {
            null
        }

        val singleAnchorRejectReason = when {
            singleAnchorCandidate == null -> null
            previousWorldPose == null && nextSingleAnchorStableCycles < SINGLE_ANCHOR_BOOTSTRAP_CYCLES ->
                "bootstrap_guard"
            trustedSingleAnchorDelta != null &&
                (trustedSingleAnchorDelta.positionMeters >= SINGLE_ANCHOR_TRUSTED_POSITION_METERS ||
                    trustedSingleAnchorDelta.rotationDegrees >= SINGLE_ANCHOR_TRUSTED_ROTATION_DEGREES) ->
                "anchor_history_guard"
            poseDelta != null &&
                (poseDelta.positionMeters >= SINGLE_ANCHOR_LARGE_CORRECTION_POSITION_METERS ||
                    poseDelta.rotationDegrees >= SINGLE_ANCHOR_LARGE_CORRECTION_ROTATION_DEGREES) &&
                nextSingleAnchorStableCycles < SINGLE_ANCHOR_LARGE_CORRECTION_STABLE_CYCLES ->
                "stability_guard"
            else -> null
        }

        if (singleAnchorRejectReason != null) {
            singleAnchorStableCyclesSinceResetOrPause = nextSingleAnchorStableCycles
            val trustedDeltaSummary = if (trustedSingleAnchorDelta != null) {
                " trusted_dPos=${trustedSingleAnchorDelta.positionMeters.f3()}m trusted_dRot=${trustedSingleAnchorDelta.rotationDegrees.f1()}deg"
            } else {
                ""
            }
            android.util.Log.w(
                "DetectionPipeline",
                "[PIPELINE] fuse_rejected trigger=${cycleClosure.triggerAnchorId} reason=$singleAnchorRejectReason stable_cycles=$nextSingleAnchorStableCycles anchors=$weightSummary fused=(${fusionResult.fusedPose.tx().f3()},${fusionResult.fusedPose.ty().f3()},${fusionResult.fusedPose.tz().f3()}) $deltaSummary$trustedDeltaSummary",
            )
            return
        }

        android.util.Log.d(
            "DetectionPipeline",
            "[PIPELINE] fuse trigger=${cycleClosure.triggerAnchorId} anchors=$weightSummary fused=(${fusionResult.fusedPose.tx().f3()},${fusionResult.fusedPose.ty().f3()},${fusionResult.fusedPose.tz().f3()}) $deltaSummary",
        )

        if (singleAnchorCandidate != null) {
            singleAnchorStableCyclesSinceResetOrPause = nextSingleAnchorStableCycles
        } else {
            singleAnchorStableCyclesSinceResetOrPause = 0
        }
        correctionCandidates.forEach { candidate ->
            trustedCorrectionPoseByAnchorId[candidate.anchorId] = candidate.correctionPose
        }
        worldCoordinateManager.applyWorldPose(fusionResult.fusedPose)
    }

    fun onAnchorPaused(anchorId: String) {
        cycleBuffer.onAnchorPaused(anchorId)
        updateHoldState(anchorId, "paused")
    }

    fun onAnchorLost(anchorId: String) {
        cycleBuffer.onAnchorLost(anchorId)
        updateHoldState(anchorId, "lost")
    }

    fun reset() {
        cycleBuffer.reset()
        inHoldMode = false
        runtimeBypassLogged = false
        singleAnchorStableCyclesSinceResetOrPause = 0
        trustedCorrectionPoseByAnchorId.clear()
    }

    private fun keepOnlyFullTracking(raw: RawAnchorDetection): FullTrackingDetection? {
        return if (raw.trackingMethod == AugmentedImage.TrackingMethod.FULL_TRACKING) {
            FullTrackingDetection(
                anchorId = raw.anchorId,
                pose = raw.pose,
                distanceMeters = raw.distanceMeters,
                extentXMeters = raw.extentXMeters,
                extentZMeters = raw.extentZMeters,
            )
        } else {
            null
        }
    }

    private fun updateHoldState(anchorId: String, reason: String) {
        if (!cycleBuffer.hasVisibleAnchors() && !inHoldMode) {
            inHoldMode = true
            singleAnchorStableCyclesSinceResetOrPause = 0
            val last = worldCoordinateManager.currentCorrectionPose()
            val poseText = if (last != null) {
                "last_world=(${last.tx().f3()},${last.ty().f3()},${last.tz().f3()})"
            } else {
                "last_world=none"
            }
            android.util.Log.d(
                "DetectionPipeline",
                "[PIPELINE] hold_enter reason=$reason anchor=$anchorId $poseText",
            )
        }
    }

    private fun fuseCorrectionCandidates(candidates: List<CorrectionCandidate>): FusionResult {
        val rawWeights = candidates.map { candidate ->
            val distanceScore = 1f / (candidate.averagedDistanceMeters * candidate.averagedDistanceMeters + DISTANCE_EPSILON_SQ)
            val batchScore = candidate.sampleCount.toFloat() / MAX_BATCH_SIZE.toFloat()
            distanceScore * batchScore
        }
        val rawWeightSum = rawWeights.sum().takeIf { it > 0f } ?: 1f

        val weightedCandidates = candidates.mapIndexed { index, candidate ->
            val distanceScore = 1f / (candidate.averagedDistanceMeters * candidate.averagedDistanceMeters + DISTANCE_EPSILON_SQ)
            val batchScore = candidate.sampleCount.toFloat() / MAX_BATCH_SIZE.toFloat()
            candidate.withWeights(
                distanceScore = distanceScore,
                batchScore = batchScore,
                normalizedWeight = rawWeights[index] / rawWeightSum,
            )
        }

        if (weightedCandidates.size == 1) {
            return FusionResult(weightedCandidates, weightedCandidates.first().correctionPose)
        }

        val fusedTx = weightedCandidates.sumOf { (it.correctionPose.tx() * it.normalizedWeight).toDouble() }.toFloat()
        val fusedTy = weightedCandidates.sumOf { (it.correctionPose.ty() * it.normalizedWeight).toDouble() }.toFloat()
        val fusedTz = weightedCandidates.sumOf { (it.correctionPose.tz() * it.normalizedWeight).toDouble() }.toFloat()

        val referenceRotation = weightedCandidates.first().correctionPose.rotationQuaternion
        var qx = 0f
        var qy = 0f
        var qz = 0f
        var qw = 0f
        for (candidate in weightedCandidates) {
            val q = candidate.correctionPose.rotationQuaternion
            val sign = if (q[0] * referenceRotation[0] + q[1] * referenceRotation[1] + q[2] * referenceRotation[2] + q[3] * referenceRotation[3] < 0f) -1f else 1f
            qx += q[0] * sign * candidate.normalizedWeight
            qy += q[1] * sign * candidate.normalizedWeight
            qz += q[2] * sign * candidate.normalizedWeight
            qw += q[3] * sign * candidate.normalizedWeight
        }
        val mag = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
        val fusedRotation = if (mag > 0f) {
            floatArrayOf(qx / mag, qy / mag, qz / mag, qw / mag)
        } else {
            floatArrayOf(0f, 0f, 0f, 1f)
        }

        return FusionResult(
            weightedCandidates = weightedCandidates,
            fusedPose = Pose(floatArrayOf(fusedTx, fusedTy, fusedTz), fusedRotation),
        )
    }

    private fun measurePoseDelta(previous: Pose, next: Pose): PoseDelta {
        val dx = next.tx() - previous.tx()
        val dy = next.ty() - previous.ty()
        val dz = next.tz() - previous.tz()
        val positionMeters = sqrt(dx * dx + dy * dy + dz * dz)

        val previousQ = previous.rotationQuaternion
        val nextQ = next.rotationQuaternion
        val dot = (previousQ[0] * nextQ[0] + previousQ[1] * nextQ[1] + previousQ[2] * nextQ[2] + previousQ[3] * nextQ[3])
            .coerceIn(-1f, 1f)
        val rotationDegrees = Math.toDegrees(2.0 * acos(abs(dot).toDouble())).toFloat()
        return PoseDelta(positionMeters, rotationDegrees)
    }
}

data class RawAnchorDetection(
    val anchorId: String,
    val trackingMethod: AugmentedImage.TrackingMethod,
    val pose: Pose,
    val distanceMeters: Float,
    val extentXMeters: Float,
    val extentZMeters: Float,
)

private data class FullTrackingDetection(
    val anchorId: String,
    val pose: Pose,
    val distanceMeters: Float,
    val extentXMeters: Float,
    val extentZMeters: Float,
)

private data class EligibleAnchorBatch(
    val anchorId: String,
    val sampleCount: Int,
    val averagedDistanceMeters: Float,
    val averagedExtentXMeters: Float,
    val averagedExtentZMeters: Float,
    val translationSpreadMeters: Float,
    val averagedPose: Pose,
)

private data class ClosedFusionCycle(
    val triggerAnchorId: String,
    val eligibleBatches: List<EligibleAnchorBatch>,
)

private data class CorrectionCandidate(
    val anchorId: String,
    val sampleCount: Int,
    val averagedDistanceMeters: Float,
    val averagedExtentXMeters: Float,
    val averagedExtentZMeters: Float,
    val translationSpreadMeters: Float,
    val averagedRawPose: Pose,
    val correctionPose: Pose,
    val distanceScore: Float = 0f,
    val batchScore: Float = 0f,
    val normalizedWeight: Float = 0f,
) {
    fun withWeights(distanceScore: Float, batchScore: Float, normalizedWeight: Float): CorrectionCandidate =
        copy(distanceScore = distanceScore, batchScore = batchScore, normalizedWeight = normalizedWeight)
}

private data class FusionResult(
    val weightedCandidates: List<CorrectionCandidate>,
    val fusedPose: Pose,
)

private data class PoseDelta(
    val positionMeters: Float,
    val rotationDegrees: Float,
)

private class PerAnchorFusionCycleBuffer(
    private val maxBatchSize: Int,
    private val minEligibleSamples: Int,
) {

    private val visibleAnchorIds = linkedSetOf<String>()
    private val anchorStates = linkedMapOf<String, AnchorBatchState>()

    fun onFullTrackingDetection(detection: FullTrackingDetection): ClosedFusionCycle? {
        val wasVisible = detection.anchorId in visibleAnchorIds
        visibleAnchorIds.add(detection.anchorId)
        val state = anchorStates.getOrPut(detection.anchorId) { AnchorBatchState(detection.anchorId) }
        val retainedBefore = state.sampleCount
        val sampleCount = state.addSample(
            pose = detection.pose,
            distanceMeters = detection.distanceMeters,
            extentXMeters = detection.extentXMeters,
            extentZMeters = detection.extentZMeters,
        )

        if (!wasVisible && retainedBefore > 0) {
            android.util.Log.d(
                "DetectionPipeline",
                "[PIPELINE] resume_with_retained anchor=${detection.anchorId} retained=$retainedBefore dist_range=${state.distanceRangeSummary()} spread=${state.translationSpreadMeters().f3()} first_new_dist=${detection.distanceMeters.f3()}m",
            )
        }

        if (sampleCount == 1) {
            android.util.Log.d(
                "DetectionPipeline",
                "[PIPELINE] batch_start anchor=${detection.anchorId} dist=${detection.distanceMeters.f3()}m ext=${detection.extentXMeters.f3()}x${detection.extentZMeters.f3()} raw=(${detection.pose.tx().f3()},${detection.pose.ty().f3()},${detection.pose.tz().f3()})",
            )
        }

        if (sampleCount < maxBatchSize) {
            return null
        }

        val eligible = anchorStates.values
            .filter { it.anchorId in visibleAnchorIds && it.sampleCount >= minEligibleSamples }
            .map { it.toEligibleAnchorBatch() }
            .sortedBy { it.averagedDistanceMeters }
        val skipped = anchorStates.values
            .filter { it.anchorId in visibleAnchorIds && it.sampleCount < minEligibleSamples }
            .joinToString(" ") { "${it.anchorId}(n=${it.sampleCount})" }

        val eligibleSummary = eligible.joinToString(" ") {
            "${it.anchorId}(n=${it.sampleCount},d=${it.averagedDistanceMeters.f3()},ext=${it.averagedExtentXMeters.f3()}x${it.averagedExtentZMeters.f3()},spr=${it.translationSpreadMeters.f3()})"
        }
        android.util.Log.d(
            "DetectionPipeline",
            "[PIPELINE] cycle_close trigger=${detection.anchorId} visible=${visibleAnchorIds.size} eligible=$eligibleSummary${if (skipped.isNotEmpty()) " skipped=$skipped" else ""}",
        )

        clearCycleSamples()
        return ClosedFusionCycle(
            triggerAnchorId = detection.anchorId,
            eligibleBatches = eligible,
        )
    }

    fun onAnchorPaused(anchorId: String) {
        val wasVisible = visibleAnchorIds.remove(anchorId)
        if (wasVisible) {
            val state = anchorStates[anchorId]
            val discarded = state?.sampleCount ?: 0
            val distanceRange = if (state != null && discarded > 0) state.distanceRangeSummary() else null
            val spreadMeters = if (state != null && discarded > 0) state.translationSpreadMeters().f3() else null
            state?.clearSamples()
            android.util.Log.d(
                "DetectionPipeline",
                "[PIPELINE] anchor_paused=$anchorId visible=${visibleAnchorIds.size} discarded_samples=$discarded${if (distanceRange != null && spreadMeters != null) " dist_range=$distanceRange spread=$spreadMeters" else ""}",
            )
        }
    }

    fun onAnchorLost(anchorId: String) {
        val wasVisible = visibleAnchorIds.remove(anchorId)
        val removed = anchorStates.remove(anchorId)
        if (wasVisible || removed != null) {
            android.util.Log.d(
                "DetectionPipeline",
                "[PIPELINE] anchor_lost=$anchorId visible=${visibleAnchorIds.size} discarded_samples=${removed?.sampleCount ?: 0}",
            )
        }
    }

    fun reset() {
        visibleAnchorIds.clear()
        anchorStates.clear()
        android.util.Log.d("DetectionPipeline", "[PIPELINE] cycle_reset")
    }

    fun hasVisibleAnchors(): Boolean = visibleAnchorIds.isNotEmpty()

    private fun clearCycleSamples() {
        val iterator = anchorStates.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            entry.value.clearSamples()
            if (entry.key !in visibleAnchorIds) {
                iterator.remove()
            }
        }
    }
}

private class AnchorBatchState(
    val anchorId: String,
) {

    private val translations = mutableListOf<FloatArray>()
    private val rotations = mutableListOf<FloatArray>()
    private val distances = mutableListOf<Float>()
    private val extentsX = mutableListOf<Float>()
    private val extentsZ = mutableListOf<Float>()

    val sampleCount: Int
        get() = translations.size

    fun addSample(
        pose: Pose,
        distanceMeters: Float,
        extentXMeters: Float,
        extentZMeters: Float,
    ): Int {
        translations.add(floatArrayOf(pose.tx(), pose.ty(), pose.tz()))
        rotations.add(pose.rotationQuaternion)
        distances.add(distanceMeters)
        extentsX.add(extentXMeters)
        extentsZ.add(extentZMeters)
        return sampleCount
    }

    fun toEligibleAnchorBatch(): EligibleAnchorBatch {
        val averagedPose = averagePose(translations, rotations)
        val averagedDistance = distances.sum() / distances.size
        return EligibleAnchorBatch(
            anchorId = anchorId,
            sampleCount = sampleCount,
            averagedDistanceMeters = averagedDistance,
            averagedExtentXMeters = extentsX.sum() / extentsX.size,
            averagedExtentZMeters = extentsZ.sum() / extentsZ.size,
            translationSpreadMeters = translationSpreadMeters(),
            averagedPose = averagedPose,
        )
    }

    fun distanceRangeSummary(): String {
        val min = distances.minOrNull() ?: return "none"
        val max = distances.maxOrNull() ?: return "none"
        return "${min.f3()}..${max.f3()}m"
    }

    fun translationSpreadMeters(): Float {
        if (translations.isEmpty()) return 0f
        var minX = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        var minZ = Float.POSITIVE_INFINITY
        var maxZ = Float.NEGATIVE_INFINITY
        for (t in translations) {
            minX = minOf(minX, t[0])
            maxX = maxOf(maxX, t[0])
            minY = minOf(minY, t[1])
            maxY = maxOf(maxY, t[1])
            minZ = minOf(minZ, t[2])
            maxZ = maxOf(maxZ, t[2])
        }
        val dx = maxX - minX
        val dy = maxY - minY
        val dz = maxZ - minZ
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    fun clearSamples() {
        translations.clear()
        rotations.clear()
        distances.clear()
        extentsX.clear()
        extentsZ.clear()
    }

    private fun averagePose(
        translations: List<FloatArray>,
        rotations: List<FloatArray>,
    ): Pose {
        val meanTx = translations.sumOf { it[0].toDouble() }.toFloat() / translations.size
        val meanTy = translations.sumOf { it[1].toDouble() }.toFloat() / translations.size
        val meanTz = translations.sumOf { it[2].toDouble() }.toFloat() / translations.size

        val ref = rotations.first()
        var qx = 0f
        var qy = 0f
        var qz = 0f
        var qw = 0f
        for (q in rotations) {
            val sign = if (q[0] * ref[0] + q[1] * ref[1] + q[2] * ref[2] + q[3] * ref[3] < 0f) -1f else 1f
            qx += q[0] * sign
            qy += q[1] * sign
            qz += q[2] * sign
            qw += q[3] * sign
        }
        val mag = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
        val averagedRotation = if (mag > 0f) {
            floatArrayOf(qx / mag, qy / mag, qz / mag, qw / mag)
        } else {
            floatArrayOf(0f, 0f, 0f, 1f)
        }

        return Pose(floatArrayOf(meanTx, meanTy, meanTz), averagedRotation)
    }
}

private fun Float.f3(): String = String.format("%.3f", this)
private fun Float.f1(): String = String.format("%.1f", this)
