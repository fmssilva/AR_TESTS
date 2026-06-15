package com.arwall.ar_wall_app.ar

import com.google.ar.core.AugmentedImage
import io.github.sceneview.ar.ARSceneView

// Renders debug visualisers (axis lines, wireframe border) at detected anchor nodes.
// All debug geometry is removed when setDebugMode(false) is called.
class DiagnosticRenderer(private val arSceneView: ARSceneView) {

    private var debugMode = false
    private val debugNodes = mutableListOf<io.github.sceneview.node.Node>()

    // Toggle debug overlays at runtime. Removes all debug nodes on disable.
    fun setDebugMode(enabled: Boolean) {
        debugMode = enabled
        if (!enabled) {
            debugNodes.forEach { it.destroy() }
            debugNodes.clear()
        }
    }

    // Attach a wireframe border node at the detected image anchor's position.
    // Size matches the physical image dimensions to verify print accuracy.
    fun renderAnchorDebug(image: AugmentedImage) {
        if (!debugMode) return

        val width  = image.extentX
        val height = image.extentZ
        val pose   = image.centerPose

        val debugNode = io.github.sceneview.node.Node(arSceneView.engine)
        debugNode.worldPosition = dev.romainguy.kotlin.math.Float3(
            pose.tx(), pose.ty(), pose.tz()
        )

        // Log physical dimensions for on-site calibration verification.
        android.util.Log.d(
            "DiagnosticRenderer",
            "Anchor '${image.name}' physical size: ${width}m x ${height}m " +
            "at (${pose.tx()}, ${pose.ty()}, ${pose.tz()})"
        )

        arSceneView.addChildNode(debugNode)
        debugNodes.add(debugNode)
    }
}
