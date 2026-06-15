import 'package:vector_math/vector_math_64.dart';

// Immutable data class representing a single physical image anchor on the wall.
// Carries both asset reference data and its true blueprint coordinate.
class AnchorBlueprint {
  final String id;
  final String imageAssetName;
  final double physicalWidthMeters;
  final Vector3 blueprintPosition;
  final double blueprintYawDegrees;

  const AnchorBlueprint({
    required this.id,
    required this.imageAssetName,
    required this.physicalWidthMeters,
    required this.blueprintPosition,
    required this.blueprintYawDegrees,
  });

  // Construct from the anchor_blueprint.json map format.
  factory AnchorBlueprint.fromJson(Map<String, dynamic> json) {
    final pos = json['blueprint_position'] as Map<String, dynamic>;
    return AnchorBlueprint(
      id: json['id'] as String,
      imageAssetName: json['image_asset_name'] as String,
      physicalWidthMeters: (json['physical_width_meters'] as num).toDouble(),
      blueprintPosition: Vector3(
        (pos['x'] as num).toDouble(),
        (pos['y'] as num).toDouble(),
        (pos['z'] as num).toDouble(),
      ),
      blueprintYawDegrees: (json['blueprint_yaw_degrees'] as num).toDouble(),
    );
  }

  // Serialize to flat map for MethodChannel transmission to native layer.
  Map<String, dynamic> toChannelMap() => {
        'id': id,
        'image_asset_name': imageAssetName,
        'physical_width_meters': physicalWidthMeters,
        'blueprint_x': blueprintPosition.x,
        'blueprint_y': blueprintPosition.y,
        'blueprint_z': blueprintPosition.z,
        'blueprint_yaw_degrees': blueprintYawDegrees,
      };
}
