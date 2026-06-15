package com.arwall.ar_wall_app.ar

import android.opengl.Matrix
import com.google.ar.core.Pose
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.node.Node

// Manages the single world root node that parents all POI nodes.
// Applies drift correction from the closest visible image anchor.
// One correction call updates all POIs simultaneously via the shared parent transform.
class WorldCoordinateManager(private val arSceneView: ARSceneView) {

    // Single root node — all POIs are children. Correct once, all POIs move together.
    val worldRootNode: Node = Node(arSceneView.engine)

    // Axis marker nodes at (1,0,0), (0,1,0), (0,0,1) in local blueprint space.
    // Reading their worldPosition after correction gives the projected 1m axis endpoints.
    val xAxisMarker: Node = Node(arSceneView.engine)
    val yAxisMarker: Node = Node(arSceneView.engine)
    val zAxisMarker: Node = Node(arSceneView.engine)

    // True physical blueprint poses keyed by anchor id.
    private val blueprintPoses: MutableMap<String, Pose> = mutableMapOf()
    // Configured POIs in blueprint space for one-time pipeline logging.
    private var configuredPois: List<POINative> = emptyList()

    // Live distances to currently visible anchors — drives the proximity filter.
    private val visibleAnchors: MutableMap<String, Float> = mutableMapOf()

    // Throttle per-frame correction log.
    private var correctionCount = 0

    init {
        arSceneView.addChildNode(worldRootNode)
        worldRootNode.isVisible = false

        // Axis markers: 1m from origin along each blueprint axis.
        xAxisMarker.position = Float3(1f, 0f, 0f)
        yAxisMarker.position = Float3(0f, 1f, 0f)
        zAxisMarker.position = Float3(0f, 0f, 1f)
        worldRootNode.addChildNode(xAxisMarker)
        worldRootNode.addChildNode(yAxisMarker)
        worldRootNode.addChildNode(zAxisMarker)
    }

    // Store blueprint poses keyed by anchor id for later correction computation.
    fun registerBlueprints(anchors: List<AnchorBlueprintNative>) {
        blueprintPoses.clear()
        for (anchor in anchors) {
            blueprintPoses[anchor.id] = anchor.blueprintPose
        }
    }

    // Store the configured POIs so debug logs reflect the actual current blueprint.
    fun registerPOIs(pois: List<POINative>) {
        configuredPois = pois
    }

    // Apply drift correction from the given anchor if it is the closest visible one.
    // correctionPose = T_drifted × T_blueprint^-1
    // Sets worldRootNode so that any child at blueprint local position p
    // appears at correctionPose × p in AR world space.
    fun applyCorrection(anchorId: String, driftedPose: Pose, cameraDistance: Float) {
        visibleAnchors[anchorId] = cameraDistance

        // Proximity filter: only trust the closest visible anchor.
        val closestId = visibleAnchors.minByOrNull { it.value }?.key ?: return
        if (closestId != anchorId) return

        val blueprintPose = blueprintPoses[anchorId] ?: return
        val correctionPose = driftedPose.compose(blueprintPose.inverse())

        arSceneView.post {
            worldRootNode.worldPosition = Float3(
                correctionPose.tx(), correctionPose.ty(), correctionPose.tz()
            )
            val q = correctionPose.rotationQuaternion
            worldRootNode.worldQuaternion = dev.romainguy.kotlin.math.Quaternion(
                q[0], q[1], q[2], q[3]
            )
            worldRootNode.isVisible = true
        }

        correctionCount++
        if (correctionCount == 1) {
            logMathPipeline(anchorId, driftedPose, blueprintPose, correctionPose)
        } else if (correctionCount % 150 == 0) {
            android.util.Log.d("WorldCoordManager",
                "[CORRECTION] #$correctionCount from '$anchorId': " +
                "pos=(${f(correctionPose.tx())}, ${f(correctionPose.ty())}, ${f(correctionPose.tz())})")
        }
    }

    // One-time verbose log of the full coordinate transform pipeline.
    private fun logMathPipeline(
        anchorId: String,
        driftedPose: Pose,
        blueprintPose: Pose,
        correctionPose: Pose
    ) {
        val dQ = driftedPose.rotationQuaternion
        val bQ = blueprintPose.rotationQuaternion
        val cQ = correctionPose.rotationQuaternion

        // Build the 4×4 correction matrix so we can transform arbitrary points.
        val cm = FloatArray(16)
        correctionPose.toMatrix(cm, 0)

        fun applyM(x: Float, y: Float, z: Float): FloatArray {
            val out = FloatArray(4)
            android.opengl.Matrix.multiplyMV(
                out, 0, cm, 0, floatArrayOf(x, y, z, 1f), 0)
            return out
        }

        android.util.Log.d("WorldCoordMath", "=== MATH PIPELINE ===")
        android.util.Log.d("WorldCoordMath",
            "STEP1  Anchor AR world pos    : (${f(driftedPose.tx())}, ${f(driftedPose.ty())}, ${f(driftedPose.tz())})")
        android.util.Log.d("WorldCoordMath",
            "STEP1  Anchor rotation quat   : [${f4(dQ[0])}, ${f4(dQ[1])}, ${f4(dQ[2])}, ${f4(dQ[3])}] (x,y,z,w)")
        android.util.Log.d("WorldCoordMath",
            "STEP2  Blueprint anchor pos   : (${f(blueprintPose.tx())}, ${f(blueprintPose.ty())}, ${f(blueprintPose.tz())})")
        android.util.Log.d("WorldCoordMath",
            "STEP2  Blueprint rotation quat: [${f4(bQ[0])}, ${f4(bQ[1])}, ${f4(bQ[2])}, ${f4(bQ[3])}] (x,y,z,w)")
        android.util.Log.d("WorldCoordMath",
            "STEP2  Note: this is the configured blueprint frame expressed in ARCore image-local coordinates")
        android.util.Log.d("WorldCoordMath",
            "STEP3  correction pos (=blueprint origin world): (${f(correctionPose.tx())}, ${f(correctionPose.ty())}, ${f(correctionPose.tz())})")
        android.util.Log.d("WorldCoordMath",
            "STEP3  correction rot quat      : [${f4(cQ[0])}, ${f4(cQ[1])}, ${f4(cQ[2])}, ${f4(cQ[3])}]")
        android.util.Log.d("WorldCoordMath",
            "STEP3  Note: this is the live blueprint-to-AR-world correction and should vary with anchor pose")

        // Blueprint/config axes expressed in the current ARCore world frame.
        val o  = applyM(0f, 0f, 0f)
        val ax = applyM(1f, 0f, 0f)
        val ay = applyM(0f, 1f, 0f)
        val az = applyM(0f, 0f, 1f)
        android.util.Log.d("WorldCoordMath", "STEP4  Blueprint/config axes expressed in current ARCore world space:")
        android.util.Log.d("WorldCoordMath",
            "       +X(right along wall in config) → world delta: (${f(ax[0]-o[0])}, ${f(ax[1]-o[1])}, ${f(ax[2]-o[2])})")
        android.util.Log.d("WorldCoordMath",
            "       +Y(up wall in config)         → world delta: (${f(ay[0]-o[0])}, ${f(ay[1]-o[1])}, ${f(ay[2]-o[2])})")
        android.util.Log.d("WorldCoordMath",
            "       +Z(out of wall in config)     → world delta: (${f(az[0]-o[0])}, ${f(az[1]-o[1])}, ${f(az[2]-o[2])})")

        android.util.Log.d("WorldCoordMath", "STEP5  Configured POI world positions:")
        for (poi in configuredPois) {
            val w = applyM(poi.x, poi.y, poi.z)
            android.util.Log.d("WorldCoordMath",
                "       ${poi.id} blueprint(${f(poi.x)},${f(poi.y)},${f(poi.z)}) " +
                "→ world(${f(w[0])}, ${f(w[1])}, ${f(w[2])})")
        }
        android.util.Log.d("WorldCoordMath", "=== END MATH PIPELINE ===")
    }

    // Remove a lost anchor from the visibility map.
    fun anchorLost(anchorId: String) {
        visibleAnchors.remove(anchorId)
    }

    private fun f(v: Float)  = String.format("%.3f", v)
    private fun f4(v: Float) = String.format("%.4f", v)
}

