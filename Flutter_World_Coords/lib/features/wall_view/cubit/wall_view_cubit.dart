import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/ar/ar_session_bridge.dart';
import '../../../core/ar/models/anchor_blueprint.dart';
import '../../../core/ar/models/ar_event.dart';
import '../../../core/ar/models/poi_model.dart';
import '../../../core/config/ar_config_loader.dart';
import '../../../core/logging/file_logger.dart';
import 'wall_view_state.dart';

// State machine for the wall AR session lifecycle.
// Transitions: Loading -> Ready (on successful init) or Error (on any failure).
// Once Ready, anchor detection and POI tap events drive copyWith updates.
class WallViewCubit extends Cubit<WallViewState> {
  final ARSessionBridge _bridge;
  final ARConfigLoader _configLoader;
  final bool debugMode;

  StreamSubscription<AREvent>? _eventSubscription;

  // Loaded once in loadConfig(); used when the PlatformView fires onViewCreated.
  List<AnchorBlueprint>? _pendingAnchors;
  List<POIModel>? _pendingPois;

  WallViewCubit({
    required ARSessionBridge bridge,
    required ARConfigLoader configLoader,
    this.debugMode = false,
  })  : _bridge = bridge,
        _configLoader = configLoader,
        super(const WallViewLoading());

  // Step 1 — Load JSON config files.
  // Call from initState(); this does NOT touch any platform channels.
  Future<void> loadConfig() async {
    try {
      await FileLogger.init();
      await FileLogger.log('WallViewCubit: loading config files');

      _pendingAnchors = await _configLoader.loadAnchors();
      _pendingPois = await _configLoader.loadPOIs();

      await FileLogger.log(
          'Config loaded: ${_pendingAnchors!.length} anchors, ${_pendingPois!.length} POIs');
    } catch (e, stack) {
      await FileLogger.log('FATAL: config load failed: $e\n$stack');
      emit(WallViewError('Failed to load AR config: $e'));
    }
  }

  // Step 2 — Wire up channels and push config to native.
  // Call ONLY from ARNativeView.onViewCreated, which fires after the Android
  // PlatformView is created and the MethodChannel/EventChannel handlers are registered.
  Future<void> initializeChannels() async {
    await FileLogger.log('initializeChannels: called');
    final anchors = _pendingAnchors;
    final pois = _pendingPois;
    if (anchors == null || pois == null) {
      await FileLogger.log(
          'initializeChannels: ABORTED — config not loaded (anchors=${anchors == null}, pois=${pois == null})');
      emit(const WallViewError('Config not loaded before channel init'));
      return;
    }
    await FileLogger.log(
        'initializeChannels: config OK — ${anchors.length} anchors, ${pois.length} POIs');

    try {
      // Subscribe before sending init data so we never miss session_ready.
      await FileLogger.log('initializeChannels: subscribing to EventChannel');
      _eventSubscription = _bridge.events.listen(
        _handleNativeEvent,
        onError: (Object e) =>
            FileLogger.log('EventChannel error: $e'),
      );
      await FileLogger.log('initializeChannels: EventChannel subscribed');

      await FileLogger.log('initializeChannels: invoking initializeARSession on MethodChannel');
      await _bridge.initializeARSession(
        anchors: anchors,
        pois: pois,
        debugMode: debugMode,
      );
      await FileLogger.log('initializeChannels: initializeARSession returned OK');

      emit(WallViewReady(pois: pois));
      await FileLogger.log('initializeChannels: emitted WallViewReady — ${pois.length} POIs');
    } catch (e, stack) {
      await FileLogger.log(
          'FATAL: channel init failed [${e.runtimeType}]: $e\n$stack');
      emit(WallViewError('Failed to initialize AR session: $e'));
    }
  }

  // Legacy alias kept so existing call-sites compile without changes.
  // Prefer calling loadConfig() + initializeChannels() separately.
  Future<void> initialize() async {
    await loadConfig();
  }

  // Route incoming native events to the appropriate state update.
  void _handleNativeEvent(AREvent event) {
    switch (event) {
      case SessionReadyEvent():
        FileLogger.log('Native AR session ready');

      case SessionErrorEvent(message: final msg):
        FileLogger.log('Native session error: $msg');
        emit(WallViewError(msg));

      case AnchorDetectedEvent(
          anchorId: final id,
          distanceMeters: final dist,
          detectedX: final x,
          detectedY: final y,
          detectedZ: final z,
        ):
        FileLogger.log(
            'Anchor detected: $id dist=${dist.toStringAsFixed(2)}m '
            'pos=(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})');
        final current = state;
        if (current is WallViewReady) {
          emit(current.copyWith(
            activeAnchorId: id,
            detectedAnchorIds: {...current.detectedAnchorIds, id},
          ));
        }

      case AnchorLostEvent(anchorId: final id):
        FileLogger.log('Anchor lost: $id');

      case POITappedEvent(poiId: final id):
        FileLogger.log('POI tapped: $id');
        final current = state;
        if (current is WallViewReady) {
          emit(current.copyWith(tappedPOIId: id));
        }

      case OverlayUpdateEvent(data: final overlay):
        final current = state;
        if (current is WallViewReady) {
          emit(current.copyWith(overlayData: overlay));
        }

      case DebugLogEvent(message: final msg):
        FileLogger.log('[NATIVE DEBUG] $msg');

      case UnknownEvent(type: final t):
        FileLogger.log('Unknown native event type: $t');
    }
  }

  // Clear the tapped POI id - called when the detail sheet is dismissed.
  void dismissPOIDetail() {
    final current = state;
    if (current is WallViewReady) {
      emit(current.copyWith(clearTappedPOI: true));
    }
  }

  @override
  Future<void> close() {
    _eventSubscription?.cancel();
    _bridge.dispose();
    return super.close();
  }
}
