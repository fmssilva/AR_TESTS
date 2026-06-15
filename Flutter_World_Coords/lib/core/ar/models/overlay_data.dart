import 'dart:ui' show Offset, Size;
import 'package:flutter/foundation.dart';

Offset viewportToCanvasPoint(Size size, double x, double y) =>
  Offset(x * size.width, y * size.height);

// Normalized viewport position for one POI dot in the 2D overlay.
// x/y are in [0,1] relative to the native AR view.
@immutable
class POIScreenPos {
  final String id;
  final String label;
  final double x;
  final double y;

  const POIScreenPos({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
  });

  Offset toCanvasOffset(Size size) => viewportToCanvasPoint(size, x, y);
}

// Snapshot of all normalized viewport positions needed to render the AR overlay on a given frame.
// Produced by Kotlin world-to-screen projection, consumed by AROverlay's CustomPainter.
@immutable
class OverlayData {
  // World-coordinate origin (blueprint position 0,0,0) projected to the viewport.
  final double originX, originY;
  final bool originVisible;

  // Endpoints of the 1-metre axis vectors projected to the viewport.
  final double axisXx, axisXy; // +X  (red)
  final bool axisXVisible;
  final double axisYx, axisYy; // +Y  (green)
  final bool axisYVisible;
  final double axisZx, axisZy; // +Z  (blue)
  final bool axisZVisible;

  // All POI viewport positions.
  final List<POIScreenPos> pois;

  const OverlayData({
    required this.originX,
    required this.originY,
    required this.originVisible,
    required this.axisXx,
    required this.axisXy,
    required this.axisXVisible,
    required this.axisYx,
    required this.axisYy,
    required this.axisYVisible,
    required this.axisZx,
    required this.axisZy,
    required this.axisZVisible,
    required this.pois,
  });

  factory OverlayData.fromMap(Map<dynamic, dynamic> m) {
    final rawPois = m['pois'] as List? ?? [];
    final pois = rawPois.map((p) {
      final pm = p as Map;
      return POIScreenPos(
        id: pm['id'] as String,
        label: pm['label'] as String,
        x: (pm['x'] as num).toDouble(),
        y: (pm['y'] as num).toDouble(),
      );
    }).toList();

    return OverlayData(
      originX: (m['ox'] as num).toDouble(),
      originY: (m['oy'] as num).toDouble(),
      originVisible: m['origin_visible'] as bool? ?? true,
      axisXx: (m['xx'] as num).toDouble(),
      axisXy: (m['xy'] as num).toDouble(),
      axisXVisible: m['axis_x_visible'] as bool? ?? true,
      axisYx: (m['yx'] as num).toDouble(),
      axisYy: (m['yy'] as num).toDouble(),
      axisYVisible: m['axis_y_visible'] as bool? ?? true,
      axisZx: (m['zx'] as num).toDouble(),
      axisZy: (m['zy'] as num).toDouble(),
      axisZVisible: m['axis_z_visible'] as bool? ?? true,
      pois: pois,
    );
  }
}
