package com.arwall.ar_wall_app.ar

import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.ar.ARSceneView

// Builds and attaches one Node per POI definition under the world root.
// Nodes are invisible position markers in blueprint local space.
// Their worldPosition (after parent correction) is projected to screen for the Flutter 2D overlay.
class POINodeBuilder(
    private val pois: List<POINative>,
    private val sceneView: ARSceneView,
    private val worldCoordinateManager: WorldCoordinateManager
) {
    // Accessible so NativeARViewController can read worldPositions for projection.
    internal val builtNodes = mutableListOf<io.github.sceneview.node.Node>()
    private val nodeLabels  = mutableMapOf<String, String>()  // id -> display label
    private val nodesById   = mutableMapOf<String, io.github.sceneview.node.Node>()

    // Instantiate one Node per POI and attach them to the world root.
    fun buildAll() {
        for (poi in pois) {
            val node = io.github.sceneview.node.Node(sceneView.engine)
            node.name     = poi.id
            node.position = Float3(poi.x, poi.y, poi.z)
            nodeLabels[poi.id] = poi.label
            nodesById[poi.id] = node
            worldCoordinateManager.worldRootNode.addChildNode(node)
            builtNodes.add(node)
            android.util.Log.d("POINodeBuilder",
                "POI '${poi.id}' (${poi.label}) placed at blueprint local (${poi.x}, ${poi.y}, ${poi.z})")
        }
        android.util.Log.d("POINodeBuilder",
            "Built ${builtNodes.size} POI markers under worldRoot")
    }

    // Returns (id, label, worldPosition) for each POI — called on main thread for projection.
    fun getNodePositions(): List<Triple<String, String, Float3>> =
        builtNodes.map { node ->
            Triple(node.name ?: "?", nodeLabels[node.name] ?: node.name ?: "?", node.worldPosition)
        }

    // Update one POI marker in blueprint-local coordinates.
    fun updateNodePosition(id: String, x: Float, y: Float, z: Float): Boolean {
        val node = nodesById[id] ?: return false
        node.position = Float3(x, y, z)
        android.util.Log.d("POINodeBuilder",
            "POI '$id' updated to blueprint local ($x, $y, $z)")
        return true
    }

    // Remove all previously built nodes (called on session re-init).
    fun clearAll() {
        builtNodes.forEach { it.destroy() }
        builtNodes.clear()
        nodeLabels.clear()
        nodesById.clear()
    }
}

