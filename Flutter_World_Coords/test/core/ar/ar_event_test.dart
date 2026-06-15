import 'package:flutter_test/flutter_test.dart';
import 'package:ar_wall_app/core/ar/models/ar_event.dart';

void main() {
  group('AREvent.fromMap', () {
    test('Parses session_ready', () {
      final event = AREvent.fromMap({'type': 'session_ready'});
      expect(event, isA<SessionReadyEvent>());
    });

    test('Parses session_error with message', () {
      final event = AREvent.fromMap({
        'type': 'session_error',
        'message': 'Camera permission denied',
      });
      expect(event, isA<SessionErrorEvent>());
      expect((event as SessionErrorEvent).message, equals('Camera permission denied'));
    });

    test('Parses anchor_detected with full double precision', () {
      final event = AREvent.fromMap({
        'type': 'anchor_detected',
        'anchor_id': 'anchor_05',
        'distance_meters': 1.234567,
        'detected_x': 9.712345,
        'detected_y': 1.498765,
        'detected_z': -0.002341,
      });
      expect(event, isA<AnchorDetectedEvent>());
      final e = event as AnchorDetectedEvent;
      expect(e.anchorId, equals('anchor_05'));
      expect(e.distanceMeters, closeTo(1.234567, 0.000001));
      expect(e.detectedX, closeTo(9.712345, 0.000001));
      expect(e.detectedY, closeTo(1.498765, 0.000001));
      expect(e.detectedZ, closeTo(-0.002341, 0.000001));
    });

    test('Parses anchor_lost with anchor id', () {
      final event = AREvent.fromMap({'type': 'anchor_lost', 'anchor_id': 'anchor_02'});
      expect(event, isA<AnchorLostEvent>());
      expect((event as AnchorLostEvent).anchorId, equals('anchor_02'));
    });

    test('Parses poi_tapped with poi id', () {
      final event = AREvent.fromMap({'type': 'poi_tapped', 'poi_id': 'poi_042'});
      expect(event, isA<POITappedEvent>());
      expect((event as POITappedEvent).poiId, equals('poi_042'));
    });

    test('Parses debug_log with message', () {
      final event = AREvent.fromMap({'type': 'debug_log', 'message': 'Delta x=0.02m'});
      expect(event, isA<DebugLogEvent>());
      expect((event as DebugLogEvent).message, equals('Delta x=0.02m'));
    });

    test('Handles unknown event type without throwing', () {
      final event = AREvent.fromMap({'type': 'future_event_type_v2'});
      expect(event, isA<UnknownEvent>());
      expect((event as UnknownEvent).type, equals('future_event_type_v2'));
    });

    test('Parses numeric distance from int (type coercion from native)', () {
      // Native Kotlin may send int for a whole-number distance.
      final event = AREvent.fromMap({
        'type': 'anchor_detected',
        'anchor_id': 'anchor_01',
        'distance_meters': 2,
        'detected_x': 1,
        'detected_y': 1,
        'detected_z': 0,
      });
      final e = event as AnchorDetectedEvent;
      expect(e.distanceMeters, closeTo(2.0, 0.001));
    });
  });
}
