import 'dart:async';
import 'package:flutter/services.dart';
import 'models/anchor_blueprint.dart';
import 'models/poi_model.dart';
import 'models/ar_event.dart';

// Flutter-side wrapper for the two platform channels.
// Sends commands to native via MethodChannel and receives events via EventChannel.
// The channel names here are the authoritative contract - native must match exactly.
class ARSessionBridge {
  static const _methodChannel = MethodChannel('com.tileapp/ar_methods');
  static const _eventChannel = EventChannel('com.tileapp/ar_events');

  StreamSubscription<AREvent>? _subscription;

  // Send session data to native. Call after the platform view is created.
  // Native side buffers this until its ARCore session is running.
  Future<void> initializeARSession({
    required List<AnchorBlueprint> anchors,
    required List<POIModel> pois,
    bool debugMode = false,
  }) async {
    await _methodChannel.invokeMethod('initializeARSession', {
      'anchors': anchors.map((a) => a.toChannelMap()).toList(),
      'pois': pois.map((p) => p.toChannelMap()).toList(),
      'debugMode': debugMode,
    });
  }

  // Toggle debug visualisers (axes, wireframes) at runtime without restart.
  Future<void> setDebugMode(bool enabled) async {
    await _methodChannel.invokeMethod('setDebugMode', {'enabled': enabled});
  }

  // Send calibration UI state to native so selection/locking stays future-proof.
  // Phase 1 uses enabled + selected anchor; Phase 2 can turn on image overlay.
  Future<void> setCalibrationViewState({
    required bool enabled,
    String? referenceAnchorId,
    String? editedAnchorId,
    bool showReferenceImage = false,
    double referenceImageOpacity = 0.0,
    bool freezeCorrection = false,
  }) async {
    assert(referenceImageOpacity >= 0.0 && referenceImageOpacity <= 1.0);
    await _methodChannel.invokeMethod('setCalibrationViewState', {
      'enabled': enabled,
      'reference_anchor_id': referenceAnchorId,
      'edited_anchor_id': editedAnchorId,
      'show_reference_image': showReferenceImage,
      'reference_image_opacity': referenceImageOpacity,
      'freeze_correction': freezeCorrection,
    });
  }

  // Update one anchor blueprint in native memory and re-apply correction if possible.
  Future<void> updateAnchorBlueprint({
    required String id,
    required double x,
    required double y,
    required double z,
    required double yawDegrees,
    double? physicalWidthMeters,
  }) async {
    final args = <String, Object?>{
      'id': id,
      'blueprint_x': x,
      'blueprint_y': y,
      'blueprint_z': z,
      'blueprint_yaw_degrees': yawDegrees,
    };
    if (physicalWidthMeters != null) {
      args['physical_width_meters'] = physicalWidthMeters;
    }
    await _methodChannel.invokeMethod('updateAnchorBlueprint', args);
  }

  // Update one POI blueprint in native memory so its marker node moves immediately.
  Future<void> updatePOIBlueprint({
    required String id,
    required double x,
    required double y,
    required double z,
  }) async {
    await _methodChannel.invokeMethod('updatePOIBlueprint', {
      'id': id,
      'blueprint_x': x,
      'blueprint_y': y,
      'blueprint_z': z,
    });
  }

  // Pause the ARCore session (called when app goes to background).
  Future<void> pauseSession() async {
    await _methodChannel.invokeMethod('pauseSession', {});
  }

  // Resume the ARCore session after backgrounding.
  Future<void> resumeSession() async {
    await _methodChannel.invokeMethod('resumeSession', {});
  }

  // Expose a typed broadcast stream of native events.
  // Callers subscribe via listen(); the cubit holds the single subscription.
  Stream<AREvent> get events {
    return _eventChannel
        .receiveBroadcastStream()
        .map((dynamic data) => AREvent.fromMap(data as Map));
  }

  // Cancel active subscription and release channel resources.
  void dispose() {
    _subscription?.cancel();
  }
}
