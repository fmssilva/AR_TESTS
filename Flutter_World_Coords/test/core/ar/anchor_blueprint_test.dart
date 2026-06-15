import 'package:flutter_test/flutter_test.dart';
import 'package:ar_wall_app/core/ar/models/anchor_blueprint.dart';

void main() {
  group('AnchorBlueprint.fromJson', () {
    test('Parses all fields correctly from valid JSON map', () {
      final json = {
        'id': 'anchor_03',
        'image_asset_name': 'anchor_03',
        'physical_width_meters': 0.40,
        'blueprint_position': {'x': 7.5, 'y': 1.5, 'z': 0.0},
        'blueprint_yaw_degrees': 0.0,
      };
      final anchor = AnchorBlueprint.fromJson(json);
      expect(anchor.id, equals('anchor_03'));
      expect(anchor.imageAssetName, equals('anchor_03'));
      expect(anchor.physicalWidthMeters, closeTo(0.40, 0.001));
      expect(anchor.blueprintPosition.x, closeTo(7.5, 0.001));
      expect(anchor.blueprintPosition.y, closeTo(1.5, 0.001));
      expect(anchor.blueprintPosition.z, closeTo(0.0, 0.001));
      expect(anchor.blueprintYawDegrees, closeTo(0.0, 0.001));
    });

    test('toChannelMap preserves full double precision', () {
      final json = {
        'id': 'anchor_01',
        'image_asset_name': 'anchor_01',
        'physical_width_meters': 0.40,
        'blueprint_position': {'x': 1.123456789, 'y': 1.5, 'z': 0.0},
        'blueprint_yaw_degrees': 0.0,
      };
      final anchor = AnchorBlueprint.fromJson(json);
      final map = anchor.toChannelMap();
      expect(map['blueprint_x'], closeTo(1.123456789, 0.000000001));
      expect(map['id'], equals('anchor_01'));
      expect(map['image_asset_name'], equals('anchor_01'));
    });

    test('toChannelMap includes all required MethodChannel keys', () {
      final json = {
        'id': 'anchor_02',
        'image_asset_name': 'anchor_02',
        'physical_width_meters': 0.35,
        'blueprint_position': {'x': 3.5, 'y': 1.5, 'z': 0.0},
        'blueprint_yaw_degrees': 5.0,
      };
      final map = AnchorBlueprint.fromJson(json).toChannelMap();
      expect(map.containsKey('id'), isTrue);
      expect(map.containsKey('image_asset_name'), isTrue);
      expect(map.containsKey('physical_width_meters'), isTrue);
      expect(map.containsKey('blueprint_x'), isTrue);
      expect(map.containsKey('blueprint_y'), isTrue);
      expect(map.containsKey('blueprint_z'), isTrue);
      expect(map.containsKey('blueprint_yaw_degrees'), isTrue);
    });

    test('Parses physical_width_meters as int (type coercion from JSON)', () {
      // JSON may parse whole numbers as int on some platforms.
      final json = {
        'id': 'anchor_04',
        'image_asset_name': 'anchor_04',
        'physical_width_meters': 1,
        'blueprint_position': {'x': 10, 'y': 1, 'z': 0},
        'blueprint_yaw_degrees': 0,
      };
      final anchor = AnchorBlueprint.fromJson(json);
      expect(anchor.physicalWidthMeters, closeTo(1.0, 0.001));
      expect(anchor.blueprintPosition.x, closeTo(10.0, 0.001));
    });
  });
}
