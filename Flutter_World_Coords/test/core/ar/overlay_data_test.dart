import 'dart:ui';

import 'package:ar_wall_app/core/ar/models/overlay_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('viewportToCanvasPoint', () {
    test('maps normalized center to logical canvas center', () {
      const size = Size(1280, 800);

      final point = viewportToCanvasPoint(size, 0.5, 0.5);

      expect(point.dx, 640);
      expect(point.dy, 400);
    });

    test('maps normalized bottom-right to logical canvas bounds', () {
      const size = Size(1280, 800);

      final point = viewportToCanvasPoint(size, 1.0, 1.0);

      expect(point.dx, 1280);
      expect(point.dy, 800);
    });
  });

  group('POIScreenPos.toCanvasOffset', () {
    test('uses logical canvas size rather than native pixel dimensions', () {
      const poi = POIScreenPos(id: 'TR', label: 'TR', x: 0.75, y: 0.25);
      const size = Size(1200, 900);

      final point = poi.toCanvasOffset(size);

      expect(point.dx, 900);
      expect(point.dy, 225);
    });
  });

  group('OverlayData.fromMap', () {
    test('parses normalized overlay positions unchanged', () {
      final overlay = OverlayData.fromMap({
        'ox': 0.1,
        'oy': 0.2,
        'origin_visible': false,
        'origin_wall_distance_meters': -0.03,
        'xx': 0.3,
        'xy': 0.4,
        'axis_x_visible': true,
        'yx': 0.5,
        'yy': 0.6,
        'axis_y_visible': false,
        'zx': 0.7,
        'zy': 0.8,
        'axis_z_visible': true,
        'pois': [
          {'id': 'BL', 'label': 'BL', 'x': 0.0, 'y': 1.0, 'wall_distance_meters': 0.05},
        ],
        'anchors': [
          {
            'id': 'anchor_01',
            'tlx': 0.1,
            'tly': 0.2,
            'tl_wall_distance_meters': -0.01,
            'trx': 0.3,
            'try': 0.2,
            'tr_wall_distance_meters': 0.02,
            'brx': 0.3,
            'bry': 0.4,
            'br_wall_distance_meters': 0.03,
            'blx': 0.1,
            'bly': 0.4,
            'bl_wall_distance_meters': -0.04,
          },
        ],
      });

      expect(overlay.originX, 0.1);
      expect(overlay.originY, 0.2);
      expect(overlay.originVisible, isFalse);
      expect(overlay.originWallDistanceMeters, -0.03);
      expect(overlay.axisXVisible, isTrue);
      expect(overlay.axisYVisible, isFalse);
      expect(overlay.axisZVisible, isTrue);
      expect(overlay.pois.single.x, 0.0);
      expect(overlay.pois.single.y, 1.0);
      expect(overlay.pois.single.wallDistanceMeters, 0.05);
      expect(overlay.anchors.single.id, 'anchor_01');
      expect(overlay.anchors.single.tlx, 0.1);
      expect(overlay.anchors.single.brWallDistanceMeters, 0.03);
    });

    test('defaults visibility flags to true for older native payloads', () {
      final overlay = OverlayData.fromMap({
        'ox': 0.1,
        'oy': 0.2,
        'xx': 0.3,
        'xy': 0.4,
        'yx': 0.5,
        'yy': 0.6,
        'zx': 0.7,
        'zy': 0.8,
        'pois': const [],
        'anchors': const [],
      });

      expect(overlay.originVisible, isTrue);
      expect(overlay.originWallDistanceMeters, 0.0);
      expect(overlay.axisXVisible, isTrue);
      expect(overlay.axisYVisible, isTrue);
      expect(overlay.axisZVisible, isTrue);
      expect(overlay.anchors, isEmpty);
    });
  });
}