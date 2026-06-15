import 'package:vector_math/vector_math_64.dart';

// Immutable data class for a single Point of Interest on the tile wall.
// Blueprint position is in wall-coordinate space (origin = bottom-left corner).
class POIModel {
  final String id;
  final String label;
  final String description;
  final Vector3 blueprintPosition;
  final String iconName;
  final String nearestAnchorId;

  const POIModel({
    required this.id,
    required this.label,
    required this.description,
    required this.blueprintPosition,
    required this.iconName,
    required this.nearestAnchorId,
  });

  // Construct from poi_config.json map format.
  factory POIModel.fromJson(Map<String, dynamic> json) {
    final pos = json['blueprint_position'] as Map<String, dynamic>;
    return POIModel(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String,
      blueprintPosition: Vector3(
        (pos['x'] as num).toDouble(),
        (pos['y'] as num).toDouble(),
        (pos['z'] as num).toDouble(),
      ),
      iconName: json['icon_name'] as String,
      nearestAnchorId: json['nearest_anchor_id'] as String,
    );
  }

  // Serialize to flat map for MethodChannel transmission to native layer.
  // nearestAnchorId is metadata only — not sent to native (all POIs share
  // one world root and are corrected together).
  Map<String, dynamic> toChannelMap() => {
        'id': id,
        'label': label,
        'description': description,
        'blueprint_x': blueprintPosition.x,
        'blueprint_y': blueprintPosition.y,
        'blueprint_z': blueprintPosition.z,
        'icon_name': iconName,
      };
}
