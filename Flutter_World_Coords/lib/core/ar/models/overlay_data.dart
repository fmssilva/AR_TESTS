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
  final double wallDistanceMeters;

  const POIScreenPos({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    this.wallDistanceMeters = 0.0,
  });

  Offset toCanvasOffset(Size size) => viewportToCanvasPoint(size, x, y);
}

@immutable
class AnchorScreenQuad {
  final String id;
  final double tlx;
  final double tly;
  final double tlWallDistanceMeters;
  final double trx;
  final double try_;
  final double trWallDistanceMeters;
  final double brx;
  final double bry;
  final double brWallDistanceMeters;
  final double blx;
  final double bly;
  final double blWallDistanceMeters;

  const AnchorScreenQuad({
    required this.id,
    required this.tlx,
    required this.tly,
    this.tlWallDistanceMeters = 0.0,
    required this.trx,
    required this.try_,
    this.trWallDistanceMeters = 0.0,
    required this.brx,
    required this.bry,
    this.brWallDistanceMeters = 0.0,
    required this.blx,
    required this.bly,
    this.blWallDistanceMeters = 0.0,
  });

  List<Offset> toCanvasOffsets(Size size) => [
        viewportToCanvasPoint(size, tlx, tly),
        viewportToCanvasPoint(size, trx, try_),
        viewportToCanvasPoint(size, brx, bry),
        viewportToCanvasPoint(size, blx, bly),
      ];
}

// Snapshot of all normalized viewport positions needed to render the AR overlay on a given frame.
// Produced by Kotlin world-to-screen projection, consumed by AROverlay's CustomPainter.
@immutable
class OverlayData {
  // World-coordinate origin (blueprint position 0,0,0) projected to the viewport.
  final double originX, originY;
  final bool originVisible;
  final double originWallDistanceMeters;

  // Endpoints of the 1-metre axis vectors projected to the viewport.
  final double axisXx, axisXy; // +X  (red)
  final bool axisXVisible;
  final double axisYx, axisYy; // +Y  (green)
  final bool axisYVisible;
  final double axisZx, axisZy; // +Z  (blue)
  final bool axisZVisible;

  // All POI viewport positions.
  final List<POIScreenPos> pois;
  final List<AnchorScreenQuad> anchors;

  const OverlayData({
    required this.originX,
    required this.originY,
    required this.originVisible,
    this.originWallDistanceMeters = 0.0,
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
    required this.anchors,
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
        wallDistanceMeters: (pm['wall_distance_meters'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    final rawAnchors = m['anchors'] as List? ?? [];
    final anchors = rawAnchors.map((a) {
      final am = a as Map;
      return AnchorScreenQuad(
        id: am['id'] as String,
        tlx: (am['tlx'] as num).toDouble(),
        tly: (am['tly'] as num).toDouble(),
        tlWallDistanceMeters:
          (am['tl_wall_distance_meters'] as num?)?.toDouble() ?? 0.0,
        trx: (am['trx'] as num).toDouble(),
        try_: (am['try'] as num).toDouble(),
        trWallDistanceMeters:
          (am['tr_wall_distance_meters'] as num?)?.toDouble() ?? 0.0,
        brx: (am['brx'] as num).toDouble(),
        bry: (am['bry'] as num).toDouble(),
        brWallDistanceMeters:
          (am['br_wall_distance_meters'] as num?)?.toDouble() ?? 0.0,
        blx: (am['blx'] as num).toDouble(),
        bly: (am['bly'] as num).toDouble(),
        blWallDistanceMeters:
          (am['bl_wall_distance_meters'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    return OverlayData(
      originX: (m['ox'] as num).toDouble(),
      originY: (m['oy'] as num).toDouble(),
      originVisible: m['origin_visible'] as bool? ?? true,
        originWallDistanceMeters:
          (m['origin_wall_distance_meters'] as num?)?.toDouble() ?? 0.0,
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
      anchors: anchors,
    );
  }
}
