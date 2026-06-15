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
