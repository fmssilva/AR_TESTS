import 'overlay_data.dart';

// Sealed class hierarchy for all events sent from native -> Flutter via EventChannel.
// Every event carries a required "type" discriminator key.
sealed class AREvent {
  const AREvent();

  // Parse a raw MethodChannel/EventChannel map into the correct typed subclass.
  factory AREvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type'] as String;
    return switch (type) {
      'session_ready' => const SessionReadyEvent(),
      'session_error' => SessionErrorEvent(map['message'] as String),
      'anchor_detected' => AnchorDetectedEvent(
          anchorId: map['anchor_id'] as String,
          distanceMeters: (map['distance_meters'] as num).toDouble(),
          detectedX: (map['detected_x'] as num).toDouble(),
          detectedY: (map['detected_y'] as num).toDouble(),
          detectedZ: (map['detected_z'] as num).toDouble(),
        ),
      'anchor_lost' => AnchorLostEvent(map['anchor_id'] as String),
      'poi_tapped' => POITappedEvent(map['poi_id'] as String),
      'debug_log' => DebugLogEvent(map['message'] as String),
      'overlay_update' => OverlayUpdateEvent(OverlayData.fromMap(map)),
      _ => UnknownEvent(type),
    };
  }
}

// Native AR session initialised and ready to receive anchor + POI data.
class SessionReadyEvent extends AREvent {
  const SessionReadyEvent();
}

// Native session encountered an unrecoverable error.
class SessionErrorEvent extends AREvent {
  final String message;
  const SessionErrorEvent(this.message);
}

// ARCore detected and is tracking a registered image anchor.
// Includes the raw drifted world-space position for diagnostic logging.
class AnchorDetectedEvent extends AREvent {
  final String anchorId;
  final double distanceMeters;
  final double detectedX;
  final double detectedY;
  final double detectedZ;

  const AnchorDetectedEvent({
    required this.anchorId,
    required this.distanceMeters,
    required this.detectedX,
    required this.detectedY,
    required this.detectedZ,
  });
}

// Previously tracked anchor left the camera frustum or tracking was lost.
class AnchorLostEvent extends AREvent {
  final String anchorId;
  const AnchorLostEvent(this.anchorId);
}

// User tapped a POI billboard node in the 3D scene.
class POITappedEvent extends AREvent {
  final String poiId;
  const POITappedEvent(this.poiId);
}

// Debug-mode only: diagnostic message from the native render loop.
class DebugLogEvent extends AREvent {
  final String message;
  const DebugLogEvent(this.message);
}

// Catch-all for forward-compatibility with future event types.
class UnknownEvent extends AREvent {
  final String type;
  const UnknownEvent(this.type);
}

// Per-frame 2D overlay update: world-to-screen projections of origin, axes, and POIs.
// Sent every ~3 frames while the world root is visible.
class OverlayUpdateEvent extends AREvent {
  final OverlayData data;
  const OverlayUpdateEvent(this.data);
}

