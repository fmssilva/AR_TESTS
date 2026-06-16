package com.arwall.ar_wall_app.ar

import com.google.ar.core.Pose
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.node.Node
import kotlin.math.sqrt

// Manages the single world root node that parents all POI nodes.
// Applies drift correction from the closest visible image anchor.
// One correction call updates all POIs simultaneously via the shared parent transform.
class WorldCoordinateManager(private val arSceneView: ARSceneView) {

    val worldRootNode: Node = Node(arSceneView.engine)
    val xAxisMarker: Node = Node(arSceneView.engine)
    val yAxisMarker: Node = Node(arSceneView.engine)
    val zAxisMarker: Node = Node(arSceneView.engine)

    private val blueprintPoses: MutableMap<String, Pose> = mutableMapOf()
    private var configuredPois: List<POINative> = emptyList()
    private var calibrationAnchorLockId: String? = null
    private var correctionFrozen = false
    private var lastAppliedCorrectionPose: Pose? = null
    private var correctionCount = 0

    init {
        arSceneView.addChildNode(worldRootNode)
        worldRootNode.isVisible = false
        xAxisMarker.position = Float3(1f, 0f, 0f)
        yAxisMarker.position = Float3(0f, 1f, 0f)
        zAxisMarker.position = Float3(0f, 0f, 1f)
        worldRootNode.addChildNode(xAxisMarker)
        worldRootNode.addChildNode(yAxisMarker)
        worldRootNode.addChildNode(zAxisMarker)
    }

    fun registerBlueprints(anchors: List<AnchorBlueprintNative>) {
        blueprintPoses.clear()
        for (anchor in anchors) { blueprintPoses[anchor.id] = anchor.blueprintPose }
    }

    fun registerPOIs(pois: List<POINative>) { configuredPois = pois }

    fun updateBlueprintPose(anchorId: String, blueprintPose: Pose) {
        blueprintPoses[anchorId] = blueprintPose
    }

    fun setCalibrationAnchorLock(anchorId: String?) {
        calibrationAnchorLockId = anchorId
        android.util.Log.d("WorldCoordManager", "[CALIBRATION_LOCK] reference=$anchorId")
    }

    fun setCorrectionFrozen(frozen: Boolean) {
        correctionFrozen = frozen
        android.util.Log.d("WorldCoordManager", "[CALIBRATION_FREEZE] frozen=$frozen lock=$calibrationAnchorLockId")
    }

    fun currentCorrectionPose(): Pose? = lastAppliedCorrectionPose
    fun isCorrectionFrozen(): Boolean = correctionFrozen

    fun currentWallDistanceMeters(worldPos: Float3): Float? {
        val correctionPose = lastAppliedCorrectionPose ?: return null
        val local = correctionPose.inverse().transformPoint(floatArrayOf(worldPos.x, worldPos.y, worldPos.z))
        return local[2]
    }

    fun shouldAcceptRuntimePipelineDetections(): Boolean {
        return calibrationAnchorLockId == null && !correctionFrozen
    }

    // Compute the world correction implied by one detected anchor pose.
    // correctionPose = T_drifted × T_blueprint^-1
    fun computeCorrectionPose(anchorId: String, driftedPose: Pose): Pose? {
        val blueprintPose = blueprintPoses[anchorId] ?: return null
        return driftedPose.compose(blueprintPose.inverse())
    }

    // Apply drift correction directly, bypassing the batch filter.
    // Used exclusively by the calibration tool.
    fun applyCorrection(anchorId: String, driftedPose: Pose, cameraDistance: Float, ignoreFreeze: Boolean = false) {
        val lockedAnchorId = calibrationAnchorLockId
        if (lockedAnchorId != null && lockedAnchorId != anchorId) return
        if (correctionFrozen && !ignoreFreeze) return
        val blueprintPose = blueprintPoses[anchorId] ?: return
        val correctionPose = driftedPose.compose(blueprintPose.inverse())
        applyWorldPose(correctionPose)
        correctionCount++
        if (correctionCount == 1) {
            logMathPipeline(anchorId, driftedPose, blueprintPose, correctionPose)
        } else if (correctionCount % 150 == 0) {
            android.util.Log.d("WorldCoordManager",
                "[CORRECTION_DIRECT] #$correctionCount from '$anchorId': pos=(${f(correctionPose.tx())}, ${f(correctionPose.ty())}, ${f(correctionPose.tz())})")
        }
    }

    fun applyWorldPose(pose: Pose) {
        lastAppliedCorrectionPose = pose
        arSceneView.post {
            worldRootNode.worldPosition = Float3(pose.tx(), pose.ty(), pose.tz())
            val q = pose.rotationQuaternion
            worldRootNode.worldQuaternion = dev.romainguy.kotlin.math.Quaternion(q[0], q[1], q[2], q[3])
            worldRootNode.isVisible = true
        }
    }

    private fun logMathPipeline(anchorId: String, driftedPose: Pose, blueprintPose: Pose, correctionPose: Pose) {
        val dQ = driftedPose.rotationQuaternion
        val bQ = blueprintPose.rotationQuaternion
        val cQ = correctionPose.rotationQuaternion
        val cm = FloatArray(16)
        correctionPose.toMatrix(cm, 0)
        fun applyM(x: Float, y: Float, z: Float): FloatArray {
            val out = FloatArray(4)
            android.opengl.Matrix.multiplyMV(out, 0, cm, 0, floatArrayOf(x, y, z, 1f), 0)
            return out
        }
        android.util.Log.d("WorldCoordMath", "=== MATH PIPELINE ===")
        android.util.Log.d("WorldCoordMath", "STEP1  Anchor AR world pos    : (${f(driftedPose.tx())}, ${f(driftedPose.ty())}, ${f(driftedPose.tz())})")
        android.util.Log.d("WorldCoordMath", "STEP1  Anchor rotation quat   : [${f4(dQ[0])}, ${f4(dQ[1])}, ${f4(dQ[2])}, ${f4(dQ[3])}] (x,y,z,w)")
        android.util.Log.d("WorldCoordMath", "STEP2  Blueprint anchor pos   : (${f(blueprintPose.tx())}, ${f(blueprintPose.ty())}, ${f(blueprintPose.tz())})")
        android.util.Log.d("WorldCoordMath", "STEP2  Blueprint rotation quat: [${f4(bQ[0])}, ${f4(bQ[1])}, ${f4(bQ[2])}, ${f4(bQ[3])}]")
        android.util.Log.d("WorldCoordMath", "STEP3  correction pos: (${f(correctionPose.tx())}, ${f(correctionPose.ty())}, ${f(correctionPose.tz())})")
        android.util.Log.d("WorldCoordMath", "STEP3  correction rot: [${f4(cQ[0])}, ${f4(cQ[1])}, ${f4(cQ[2])}, ${f4(cQ[3])}]")
        val o = applyM(0f,0f,0f); val ax = applyM(1f,0f,0f); val ay = applyM(0f,1f,0f); val az = applyM(0f,0f,1f)
        android.util.Log.d("WorldCoordMath", "STEP4  Blueprint axes in ARCore world space:")
        android.util.Log.d("WorldCoordMath", "       +X(right) -> world delta: (${f(ax[0]-o[0])}, ${f(ax[1]-o[1])}, ${f(ax[2]-o[2])})")
        android.util.Log.d("WorldCoordMath", "       +Y(up)    -> world delta: (${f(ay[0]-o[0])}, ${f(ay[1]-o[1])}, ${f(ay[2]-o[2])})")
        android.util.Log.d("WorldCoordMath", "       +Z(out)   -> world delta: (${f(az[0]-o[0])}, ${f(az[1]-o[1])}, ${f(az[2]-o[2])})")
        android.util.Log.d("WorldCoordMath", "STEP5  Configured POI world positions:")
        for (poi in configuredPois) {
            val w = applyM(poi.x, poi.y, poi.z)
            android.util.Log.d("WorldCoordMath", "       ${poi.id} blueprint(${f(poi.x)},${f(poi.y)},${f(poi.z)}) -> world(${f(w[0])}, ${f(w[1])}, ${f(w[2])})")
        }
        android.util.Log.d("WorldCoordMath", "=== END MATH PIPELINE ===")
    }

    private fun f(v: Float)  = String.format("%.3f", v)
    private fun f4(v: Float) = String.format("%.4f", v)
}
