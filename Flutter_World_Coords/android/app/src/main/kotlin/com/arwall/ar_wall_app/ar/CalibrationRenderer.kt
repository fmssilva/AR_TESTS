package com.arwall.ar_wall_app.ar

import com.google.ar.core.AugmentedImage
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.node.Node

data class AnchorScreenSource(
    val id: String,
    val topLeft: Float3,
    val topRight: Float3,
    val bottomRight: Float3,
    val bottomLeft: Float3,
)

private data class AnchorBorderNodes(
    val parent: Node,
    val topLeft: Node,
    val topRight: Node,
    val bottomRight: Node,
    val bottomLeft: Node,
)

// Hold calibration-native view state so phase 2 can add reference-image rendering
// without changing the Flutter<->native channel contract again.
data class CalibrationViewStateNative(
    val enabled: Boolean,
    val referenceAnchorId: String?,
    val editedAnchorId: String?,
    val showReferenceImage: Boolean,
    val referenceImageOpacity: Float,
    val freezeCorrection: Boolean,
) {
    companion object {
        // Parse the view-state payload sent by Flutter.
        fun from(map: Map<*, *>): CalibrationViewStateNative {
            val opacity = ((map["reference_image_opacity"] as? Number)?.toFloat() ?: 0f)
                .coerceIn(0f, 1f)
            return CalibrationViewStateNative(
                enabled = map["enabled"] as? Boolean ?: false,
                referenceAnchorId = map["reference_anchor_id"] as? String,
                editedAnchorId = map["edited_anchor_id"] as? String,
                showReferenceImage = map["show_reference_image"] as? Boolean ?: false,
                referenceImageOpacity = opacity,
                freezeCorrection = map["freeze_correction"] as? Boolean ?: false,
            )
        }
    }
}

// Reserve the calibration-visualization seam for future anchor image overlays.
// Phase 1 uses this only as state storage + logging so option B can layer on top.
class CalibrationRenderer(
    private val arSceneView: ARSceneView,
    private val worldCoordinateManager: WorldCoordinateManager,
) {

    private var viewState = CalibrationViewStateNative(
        enabled = false,
        referenceAnchorId = null,
        editedAnchorId = null,
        showReferenceImage = false,
        referenceImageOpacity = 0f,
        freezeCorrection = false,
    )
    private val borderNodesById = linkedMapOf<String, AnchorBorderNodes>()
    private val anchorBlueprintsById = linkedMapOf<String, AnchorBlueprintNative>()

    // Build lightweight anchor border markers under the shared world root.
    fun configureAnchors(anchors: Collection<AnchorBlueprintNative>) {
        clearVisuals()
        anchorBlueprintsById.clear()
        for (anchor in anchors) {
            anchorBlueprintsById[anchor.id] = anchor
            borderNodesById[anchor.id] = buildAnchorBorderNodes(anchor)
        }
        updateVisibility()
        android.util.Log.d(
            "CalibrationRenderer",
            "[CALIBRATION_BORDERS] configured=${anchors.size}"
        )
    }

    // Update one anchor border transform after a calibration nudge.
    fun updateAnchorBlueprint(id: String, anchor: AnchorBlueprintNative) {
        anchorBlueprintsById[id] = anchor
        val borderNodes = borderNodesById[id] ?: buildAnchorBorderNodes(anchor).also {
            borderNodesById[id] = it
        }
        applyAnchorPose(borderNodes.parent, anchor.blueprintPose)
        applyAnchorBounds(borderNodes, anchor)
        borderNodes.parent.isVisible = viewState.enabled
        android.util.Log.d(
            "CalibrationRenderer",
            "[CALIBRATION_BORDERS] updated id=$id width=${anchor.physicalWidthMeters} ratio=${anchor.imageAspectRatio}"
        )
    }

    // Expose current anchor border corner positions for Flutter overlay projection.
    fun getAnchorScreenSources(): List<AnchorScreenSource> {
        if (!viewState.enabled) return emptyList()
        return borderNodesById.map { (id, nodes) ->
            AnchorScreenSource(
                id = id,
                topLeft = nodes.topLeft.worldPosition,
                topRight = nodes.topRight.worldPosition,
                bottomRight = nodes.bottomRight.worldPosition,
                bottomLeft = nodes.bottomLeft.worldPosition,
            )
        }
    }

    // Apply current calibration view state.
    fun setViewState(nextState: CalibrationViewStateNative) {
        viewState = nextState
        updateVisibility()
        android.util.Log.d(
            "CalibrationRenderer",
            "[CALIBRATION_VIEW] enabled=${nextState.enabled} frozen=${nextState.freezeCorrection} reference=${nextState.referenceAnchorId} edited=${nextState.editedAnchorId} showRef=${nextState.showReferenceImage} opacity=${nextState.referenceImageOpacity}"
        )
    }

    // Observe tracked anchors so phase 2 can attach overlay geometry here.
    fun onAnchorTracked(image: AugmentedImage) {
        val overlayAnchorId = viewState.editedAnchorId ?: viewState.referenceAnchorId ?: return
        if (!viewState.enabled || image.name != overlayAnchorId) return
        if (viewState.showReferenceImage) {
            android.util.Log.d(
                "CalibrationRenderer",
                "[CALIBRATION_VIEW] tracked anchor='$overlayAnchorId' referenceImageRequested opacity=${viewState.referenceImageOpacity} flutter_overlay_expected=true"
            )
        }
    }

    // Clear transient calibration visuals.
    private fun clearVisuals() {
        val existingNodes = borderNodesById.values.toList()
        borderNodesById.clear()
        arSceneView.post {
            existingNodes.forEach { nodes ->
                nodes.parent.destroy()
            }
        }
    }

    private fun updateVisibility() {
        arSceneView.post {
            borderNodesById.values.forEach { nodes ->
                nodes.parent.isVisible = viewState.enabled
            }
        }
    }

    private fun buildAnchorBorderNodes(anchor: AnchorBlueprintNative): AnchorBorderNodes {
        val parent = Node(arSceneView.engine)
        applyAnchorPose(parent, anchor.blueprintPose)

        val topLeft = Node(arSceneView.engine)
        val topRight = Node(arSceneView.engine)
        val bottomRight = Node(arSceneView.engine)
        val bottomLeft = Node(arSceneView.engine)

        parent.addChildNode(topLeft)
        parent.addChildNode(topRight)
        parent.addChildNode(bottomRight)
        parent.addChildNode(bottomLeft)
        worldCoordinateManager.worldRootNode.addChildNode(parent)

        val borderNodes = AnchorBorderNodes(
            parent = parent,
            topLeft = topLeft,
            topRight = topRight,
            bottomRight = bottomRight,
            bottomLeft = bottomLeft,
        )
        applyAnchorBounds(borderNodes, anchor)
        parent.isVisible = viewState.enabled

        return borderNodes
    }

    private fun applyAnchorBounds(nodes: AnchorBorderNodes, anchor: AnchorBlueprintNative) {
        val halfWidth = anchor.physicalWidthMeters / 2f
        val halfHeight = (anchor.physicalWidthMeters * anchor.imageAspectRatio) / 2f
        // ARCore image-local plane spans X/Z. Local +Y is the image normal.
        // Put the overlay rectangle on X/Z so the blueprint Rx(+90deg) mapping
        // lands it on the wall plane instead of projecting it out toward camera.
        nodes.topLeft.position = Float3(-halfWidth, 0f, -halfHeight)
        nodes.topRight.position = Float3(halfWidth, 0f, -halfHeight)
        nodes.bottomRight.position = Float3(halfWidth, 0f, halfHeight)
        nodes.bottomLeft.position = Float3(-halfWidth, 0f, halfHeight)
    }

    private fun applyAnchorPose(node: Node, pose: com.google.ar.core.Pose) {
        node.position = Float3(pose.tx(), pose.ty(), pose.tz())
        val q = pose.rotationQuaternion
        node.quaternion = dev.romainguy.kotlin.math.Quaternion(q[0], q[1], q[2], q[3])
    }
}