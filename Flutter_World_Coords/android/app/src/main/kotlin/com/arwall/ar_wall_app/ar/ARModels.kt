package com.arwall.ar_wall_app.ar

import com.google.ar.core.Pose
import kotlin.math.cos
import kotlin.math.sin

// Immutable native representation of an anchor blueprint parsed from MethodChannel.
// blueprintPose holds the true physical wall-coordinate position.
data class AnchorBlueprintNative(
    val id: String,
    val imageAssetName: String,
    val physicalWidthMeters: Float,
    val blueprintPose: Pose
) {
    companion object {
        // Parse from the flat map format sent by ARSessionBridge.toChannelMap().
        fun from(map: Map<*, *>): AnchorBlueprintNative? {
            val id         = map["id"] as? String ?: return null
            val imageName  = map["image_asset_name"] as? String ?: return null
            val width      = (map["physical_width_meters"] as? Number)?.toFloat() ?: return null
            val x          = (map["blueprint_x"] as? Number)?.toFloat() ?: return null
            val y          = (map["blueprint_y"] as? Number)?.toFloat() ?: return null
            val z          = (map["blueprint_z"] as? Number)?.toFloat() ?: return null
            val yawDegrees = (map["blueprint_yaw_degrees"] as? Number)?.toFloat() ?: 0f
            // ARCore AugmentedImage local frame: X=right, Y=outward(toward camera), Z=down.
            // Our blueprint frame:               X=right, Y=up along wall,           Z=outward.
            // To convert image-local → flat-wall blueprint we apply Rx(+90°).
            // Then we rotate that blueprint frame around global +Y by blueprint_yaw_degrees.
            // Positive yaw is clockwise viewed from above, matching the Dart ARMath contract.
            // blueprintPose = Pose(translation, rotation) where rotation = Ry(yaw) × Rx(+90°) maps
            // image-local coordinates BACK to blueprint coordinates, so that
            // correctionPose = driftedPose × blueprintPose^-1 correctly places POI nodes:
            //   blueprint-Y (up) → world-up    ✓
            //   blueprint-Z (out)→ world-toward-camera ✓
            val halfYawRadians = Math.toRadians((yawDegrees / 2.0).toDouble()).toFloat()
            val rx90Pose = Pose(floatArrayOf(0f, 0f, 0f), floatArrayOf(0.7071068f, 0f, 0f, 0.7071068f))
            val yawPose = Pose(
                floatArrayOf(0f, 0f, 0f),
                floatArrayOf(0f, sin(halfYawRadians), 0f, cos(halfYawRadians))
            )
            val combinedRotation = yawPose.compose(rx90Pose).rotationQuaternion
            val pose = Pose(floatArrayOf(x, y, z), combinedRotation)
            return AnchorBlueprintNative(id, imageName, width, pose)
        }
    }
}

// Immutable native representation of a POI node parsed from MethodChannel.
data class POINative(
    val id: String,
    val label: String,
    val description: String,
    val x: Float,
    val y: Float,
    val z: Float,
    val iconName: String
) {
    companion object {
        fun from(map: Map<*, *>): POINative? {
            return POINative(
                id          = map["id"] as? String ?: return null,
                label       = map["label"] as? String ?: return null,
                description = map["description"] as? String ?: return null,
                x           = (map["blueprint_x"] as? Number)?.toFloat() ?: return null,
                y           = (map["blueprint_y"] as? Number)?.toFloat() ?: return null,
                z           = (map["blueprint_z"] as? Number)?.toFloat() ?: return null,
                iconName    = map["icon_name"] as? String ?: return null
            )
        }
    }
}
