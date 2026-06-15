# AR Wall — Complete Implementation Plan for AI Agent

> **Target:** A production-grade Flutter app with native ARKit (iOS) and ARCore (Android) integration  
> **Scale:** 23-meter indoor tile wall · 10–20 image anchors · 150 interactive POIs  

---

## Part 1 — Architecture Overview

```
┌────────────────────────────────────────────────────────────┐
│                   Flutter / Dart Layer                      │
│                                                            │
│  ┌──────────────────┐   ┌───────────────────────────────┐  │
│  │  Presentation    │   │   State (WallViewCubit)       │  │
│  │  WallViewportPage│   │   Loading → Ready → Tracking  │  │
│  │  AROverlay       │   │   POI detail state            │  │
│  │  POIDetailSheet  │   └───────────────────────────────┘  │
│  └──────────────────┘               │                      │
│           │                         │                      │
│  ┌────────────────────────────────────────────────────┐    │
│  │             ARSessionBridge                        │    │
│  │  MethodChannel  ←→  initializeARSession            │    │
│  │                     setDebugMode / pauseSession    │    │
│  │  EventChannel   ←   session_ready / anchor events  │    │
│  │                     poi_tapped / debug_log         │    │
│  └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
                       │ Platform Channel │
┌────────────────────────────────────────────────────────────┐
│                   Native Layer                              │
│                                                            │
│  iOS (Swift / ARKit + SceneKit)                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ NativeARViewFactory → NativeARViewController          │  │
│  │   ARSCNView + ARWorldTrackingConfiguration           │  │
│  │   WorldCoordinateManager (correction math + lerp)    │  │
│  │   POINodeBuilder (SCNNode billboards)                │  │
│  │   DiagnosticRenderer (debug axes / wireframes)       │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  Android (Kotlin / ARCore + SceneView)                     │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ NativeARViewFactory → NativeARViewController          │  │
│  │   ArSceneView (SceneView library)                    │  │
│  │   AugmentedImageDatabase                            │  │
│  │   WorldCoordinateManager (same logic, Kotlin)        │  │
│  │   POINodeBuilder (ModelNode / BillboardNode)         │  │
│  │   DiagnosticRenderer                                │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Math lives natively.** Drift correction matrices are computed in Swift/Kotlin inside the render loop. Dart never touches frame-level transforms.
2. **Config drives content.** Anchor blueprints and POI positions live in JSON asset files. No hardcoding.
3. **One world root node.** All 150 POI nodes are children of a single root node. Correction = one transform update.
4. **Push events only.** Native → Flutter events fire only on state changes (anchor detected/lost, POI tapped, session ready). Not per frame.
5. **POIs invisible until first correction.** Prevents confusing placement before calibration fires.
6. **Debug mode is a runtime toggle.** `setDebugMode(true)` shows axes, wireframes, drift deltas. Never visible in production.

---

## Part 2 — Complete File Structure

```
ar_wall_app/
│
├── assets/
│   ├── config/
│   │   ├── anchor_blueprint.json       ← True physical anchor positions (measured on-site)
│   │   └── poi_config.json             ← 150 POIs: id, label, description, position
│   └── ar_anchors/                     ← Reference images (for Android; iOS uses Xcode AR group)
│       ├── anchor_01.jpg
│       └── ... up to anchor_20.jpg
│
├── lib/
│   ├── main.dart
│   │
│   ├── core/
│   │   ├── ar/
│   │   │   ├── models/
│   │   │   │   ├── anchor_blueprint.dart   ← Data class: id, imageName, physicalWidth, blueprintTransform
│   │   │   │   ├── poi_model.dart           ← Data class: id, label, description, blueprintPosition
│   │   │   │   └── ar_event.dart            ← Sealed class for all native→Flutter events
│   │   │   ├── utils/
│   │   │   │   └── ar_math.dart             ← Pure Dart: calculateCorrectionDelta, lerp, slerp
│   │   │   ├── ar_session_bridge.dart       ← MethodChannel + EventChannel wrapper
│   │   │   └── ar_native_view.dart          ← UiKitView / PlatformViewLink widget
│   │   ├── config/
│   │   │   └── ar_config_loader.dart        ← Loads + validates JSON from assets
│   │   └── logging/
│   │       └── file_logger.dart             ← Timestamped log files on device
│   │
│   └── features/
│       └── wall_view/
│           ├── cubit/
│           │   ├── wall_view_cubit.dart     ← State machine: init, ready, tracking, error
│           │   └── wall_view_state.dart     ← State definitions
│           └── presentation/
│               ├── wall_viewport_page.dart  ← Root Stack: native AR view + Flutter overlay
│               ├── ar_overlay.dart          ← Tracking status chip, zone indicator HUD
│               └── poi_detail_sheet.dart    ← Bottom sheet shown on POI tap
│
├── test/
│   ├── core/
│   │   ├── ar/
│   │   │   ├── ar_math_test.dart
│   │   │   ├── anchor_blueprint_test.dart
│   │   │   └── ar_event_test.dart
│   │   └── config/
│   │       └── ar_config_loader_test.dart
│   └── features/
│       └── wall_view/
│           └── wall_view_cubit_test.dart
│
├── ios/
│   └── Runner/
│       ├── AppDelegate.swift               ← Registers view factory + method/event channels
│       └── AR/
│           ├── NativeARViewFactory.swift
│           ├── NativeARViewController.swift ← ARSCNView delegate, channel handler
│           ├── WorldCoordinateManager.swift ← Delta math + smooth root node correction
│           ├── POINodeBuilder.swift         ← SCNNode factory for each POI
│           └── DiagnosticRenderer.swift     ← Axes, wireframes, grid (debug only)
│
└── android/
    └── app/src/main/
        ├── kotlin/com/yourorg/ar_wall_app/
        │   ├── MainActivity.kt             ← Registers view factory + channels
        │   └── ar/
        │       ├── NativeARViewFactory.kt
        │       ├── NativeARViewController.kt
        │       ├── WorldCoordinateManager.kt
        │       ├── POINodeBuilder.kt
        │       └── DiagnosticRenderer.kt
        └── assets/
            └── ar_anchors/                 ← Copies of reference images for ARCore database
```

---

## Part 3 — Data Schemas

### `assets/config/anchor_blueprint.json`

```json
{
  "wall": {
    "width_meters": 23.0,
    "height_meters": 3.0,
    "coordinate_origin": "bottom_left_corner",
    "axes": {
      "x": "right along wall base",
      "y": "up the wall face",
      "z": "outward from wall into room"
    }
  },
  "anchors": [
    {
      "id": "anchor_01",
      "image_asset_name": "anchor_01",
      "physical_width_meters": 0.40,
      "blueprint_position": { "x": 1.0, "y": 1.5, "z": 0.0 },
      "blueprint_yaw_degrees": 0.0
    },
    {
      "id": "anchor_02",
      "image_asset_name": "anchor_02",
      "physical_width_meters": 0.40,
      "blueprint_position": { "x": 3.5, "y": 1.5, "z": 0.0 },
      "blueprint_yaw_degrees": 0.0
    }
  ]
}
```

**Note on `physical_width_meters`:** This is the single most impactful accuracy parameter. Measure the physical print/tile exactly with a ruler. A 5mm error here causes proportional positional errors across the entire wall.

### `assets/config/poi_config.json`

```json
{
  "pois": [
    {
      "id": "poi_001",
      "label": "Tile Series A — Marble",
      "description": "Full description text shown in the detail sheet.",
      "blueprint_position": { "x": 1.2, "y": 1.9, "z": 0.08 },
      "icon_name": "icon_tile_marble",
      "nearest_anchor_id": "anchor_01"
    },
    {
      "id": "poi_002",
      "label": "Grout Reference",
      "description": "...",
      "blueprint_position": { "x": 1.8, "y": 1.2, "z": 0.08 },
      "icon_name": "icon_grout",
      "nearest_anchor_id": "anchor_01"
    }
  ]
}
```

**`nearest_anchor_id`** is metadata for tooling and logging. The system does NOT use it to decide POI visibility — all 150 POIs live under the single world root and are all transformed together.

---

## Part 4 — Platform Channel Protocol

All communication goes through two channels. The contract below is authoritative — the Swift, Kotlin, and Dart implementations must match it exactly.

### MethodChannel: `com.tileapp/ar_methods`

| Direction | Method Name | Arguments (map) | Return |
|---|---|---|---|
| Flutter → Native | `initializeARSession` | `{ anchors: [AnchorMap], pois: [POIMap], debugMode: bool }` | `"ok"` or throws |
| Flutter → Native | `setDebugMode` | `{ enabled: bool }` | `"ok"` |
| Flutter → Native | `pauseSession` | `{}` | `"ok"` |
| Flutter → Native | `resumeSession` | `{}` | `"ok"` |

**AnchorMap schema** (sent inside `initializeARSession`):
```
{ "id": String, "image_asset_name": String, "physical_width_meters": double,
  "blueprint_x": double, "blueprint_y": double, "blueprint_z": double,
  "blueprint_yaw_degrees": double }
```

**POIMap schema** (sent inside `initializeARSession`):
```
{ "id": String, "label": String, "description": String,
  "blueprint_x": double, "blueprint_y": double, "blueprint_z": double,
  "icon_name": String }
```

### EventChannel: `com.tileapp/ar_events`

Every event is a `Map<String, dynamic>` with a required `"type"` key.

```
Session events:
  { "type": "session_ready" }
  { "type": "session_error", "message": String }

Anchor events:
  { "type": "anchor_detected", "anchor_id": String, "distance_meters": double,
    "detected_x": double, "detected_y": double, "detected_z": double }
  { "type": "anchor_lost", "anchor_id": String }

POI events:
  { "type": "poi_tapped", "poi_id": String }

Debug events (only when debugMode=true):
  { "type": "debug_log", "message": String }
```

---

## Part 5 — Dart Layer: Complete Specifications

### `core/ar/models/anchor_blueprint.dart`

```dart
import 'package:vector_math/vector_math_64.dart';

class AnchorBlueprint {
  final String id;
  final String imageAssetName;
  final double physicalWidthMeters;
  final Vector3 blueprintPosition;
  final double blueprintYawDegrees;

  const AnchorBlueprint({
    required this.id,
    required this.imageAssetName,
    required this.physicalWidthMeters,
    required this.blueprintPosition,
    required this.blueprintYawDegrees,
  });

  factory AnchorBlueprint.fromJson(Map<String, dynamic> json) {
    final pos = json['blueprint_position'] as Map<String, dynamic>;
    return AnchorBlueprint(
      id: json['id'] as String,
      imageAssetName: json['image_asset_name'] as String,
      physicalWidthMeters: (json['physical_width_meters'] as num).toDouble(),
      blueprintPosition: Vector3(
        (pos['x'] as num).toDouble(),
        (pos['y'] as num).toDouble(),
        (pos['z'] as num).toDouble(),
      ),
      blueprintYawDegrees: (json['blueprint_yaw_degrees'] as num).toDouble(),
    );
  }

  // Flat map for MethodChannel serialization
  Map<String, dynamic> toChannelMap() => {
    'id': id,
    'image_asset_name': imageAssetName,
    'physical_width_meters': physicalWidthMeters,
    'blueprint_x': blueprintPosition.x,
    'blueprint_y': blueprintPosition.y,
    'blueprint_z': blueprintPosition.z,
    'blueprint_yaw_degrees': blueprintYawDegrees,
  };
}
```

### `core/ar/models/poi_model.dart`

```dart
import 'package:vector_math/vector_math_64.dart';

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
```

### `core/ar/models/ar_event.dart`

```dart
sealed class AREvent {
  const AREvent();

  factory AREvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type'] as String;
    return switch (type) {
      'session_ready'     => const SessionReadyEvent(),
      'session_error'     => SessionErrorEvent(map['message'] as String),
      'anchor_detected'   => AnchorDetectedEvent(
          anchorId: map['anchor_id'] as String,
          distanceMeters: (map['distance_meters'] as num).toDouble(),
          detectedX: (map['detected_x'] as num).toDouble(),
          detectedY: (map['detected_y'] as num).toDouble(),
          detectedZ: (map['detected_z'] as num).toDouble(),
        ),
      'anchor_lost'       => AnchorLostEvent(map['anchor_id'] as String),
      'poi_tapped'        => POITappedEvent(map['poi_id'] as String),
      'debug_log'         => DebugLogEvent(map['message'] as String),
      _                   => UnknownEvent(type),
    };
  }
}

class SessionReadyEvent extends AREvent { const SessionReadyEvent(); }
class SessionErrorEvent extends AREvent {
  final String message;
  const SessionErrorEvent(this.message);
}
class AnchorDetectedEvent extends AREvent {
  final String anchorId;
  final double distanceMeters;
  final double detectedX, detectedY, detectedZ;
  const AnchorDetectedEvent({
    required this.anchorId, required this.distanceMeters,
    required this.detectedX, required this.detectedY, required this.detectedZ,
  });
}
class AnchorLostEvent extends AREvent {
  final String anchorId;
  const AnchorLostEvent(this.anchorId);
}
class POITappedEvent extends AREvent {
  final String poiId;
  const POITappedEvent(this.poiId);
}
class DebugLogEvent extends AREvent {
  final String message;
  const DebugLogEvent(this.message);
}
class UnknownEvent extends AREvent {
  final String type;
  const UnknownEvent(this.type);
}
```

### `core/ar/utils/ar_math.dart`

```dart
import 'package:vector_math/vector_math_64.dart';

/// Pure Dart math utilities for AR coordinate calculations.
/// No platform dependencies — 100% unit-testable.
class ARMath {
  ARMath._();

  /// Computes the correction matrix needed to align the drifted AR world
  /// back onto the true physical blueprint.
  ///
  /// Formula: ΔT = T_blueprint × T_drifted⁻¹
  ///
  /// Apply this to the world root node's transform (absolute, not cumulative).
  static Matrix4 calculateCorrectionDelta({
    required Matrix4 blueprintTransform,
    required Matrix4 driftedTransform,
  }) {
    final invertedDrifted = Matrix4.copy(driftedTransform)..invert();
    return blueprintTransform * invertedDrifted;
  }

  /// Builds a Matrix4 from a position and yaw rotation (rotation around Y axis).
  /// Used to convert blueprint JSON data into a full transform matrix.
  static Matrix4 buildBlueprintMatrix(Vector3 position, double yawDegrees) {
    final matrix = Matrix4.identity();
    matrix.setTranslation(position);
    matrix.rotate(Vector3(0, 1, 0), radians(yawDegrees));
    return matrix;
  }

  /// Lerp between two Vector3 positions.
  static Vector3 lerpVector3(Vector3 from, Vector3 to, double t) {
    return Vector3(
      from.x + (to.x - from.x) * t,
      from.y + (to.y - from.y) * t,
      from.z + (to.z - from.z) * t,
    );
  }

  /// Extract translation vector from a 4x4 matrix.
  static Vector3 extractTranslation(Matrix4 matrix) {
    final v = Vector3.zero();
    matrix.getTranslation(v);
    return v;
  }

  /// Checks that a correction matrix determinant is positive.
  /// A negative determinant means the coordinate space is mirrored (a critical bug).
  static bool isCorrectionValid(Matrix4 correctionMatrix) {
    return correctionMatrix.determinant() > 0.0;
  }
}
```

### `core/ar/ar_session_bridge.dart`

```dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'models/anchor_blueprint.dart';
import 'models/poi_model.dart';
import 'models/ar_event.dart';

class ARSessionBridge {
  static const _methodChannel = MethodChannel('com.tileapp/ar_methods');
  static const _eventChannel = EventChannel('com.tileapp/ar_events');

  StreamSubscription? _subscription;

  /// Send anchor blueprints + POIs to native. Call this AFTER receiving
  /// SessionReadyEvent, or during session_ready handling in the cubit.
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

  Future<void> setDebugMode(bool enabled) async {
    await _methodChannel.invokeMethod('setDebugMode', {'enabled': enabled});
  }

  Future<void> pauseSession() async {
    await _methodChannel.invokeMethod('pauseSession', {});
  }

  Future<void> resumeSession() async {
    await _methodChannel.invokeMethod('resumeSession', {});
  }

  /// Start receiving native events. Returns a Stream of typed AREvent objects.
  Stream<AREvent> get events {
    return _eventChannel
        .receiveBroadcastStream()
        .map((dynamic data) => AREvent.fromMap(data as Map));
  }

  void dispose() {
    _subscription?.cancel();
  }
}
```

### `core/ar/ar_native_view.dart`

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ARNativeView extends StatelessWidget {
  const ARNativeView({super.key});

  static const _viewType = 'com.tileapp/native_ar_view';

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return const UiKitView(
        viewType: _viewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: StandardMessageCodec(),
      );
    } else if (Platform.isAndroid) {
      return PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (params) =>
            PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: _viewType,
              layoutDirection: TextDirection.ltr,
              creationParamsCodec: const StandardMessageCodec(),
            )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..create(),
      );
    }
    return const Center(child: Text('AR not supported on this platform'));
  }
}
```

### `core/config/ar_config_loader.dart`

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import '../ar/models/anchor_blueprint.dart';
import '../ar/models/poi_model.dart';

class ARConfigLoader {
  static const _anchorBlueprintPath = 'assets/config/anchor_blueprint.json';
  static const _poiConfigPath = 'assets/config/poi_config.json';

  Future<List<AnchorBlueprint>> loadAnchors() async {
    final raw = await rootBundle.loadString(_anchorBlueprintPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['anchors'] as List;
    return list
        .map((e) => AnchorBlueprint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<POIModel>> loadPOIs() async {
    final raw = await rootBundle.loadString(_poiConfigPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['pois'] as List;
    return list
        .map((e) => POIModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
```

### `core/logging/file_logger.dart`

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Writes timestamped AR debug logs to a file on the device.
/// File name includes session start time to prevent overwriting crash logs.
class FileLogger {
  static File? _logFile;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    _logFile = File('${dir.path}/ar_session_$timestamp.txt');
    _initialized = true;
    await log('=== AR Session started ===');
  }

  static Future<void> log(String message) async {
    if (!_initialized) return;
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $message\n';
    debugPrint(line.trim()); // Also prints to IDE console when connected
    await _logFile?.writeAsString(line, mode: FileMode.append);
  }

  /// Returns the path to the current log file (shown in debug screen).
  static String? get logFilePath => _logFile?.path;
}
```

### `features/wall_view/cubit/wall_view_state.dart`

```dart
import '../../../core/ar/models/poi_model.dart';

sealed class WallViewState {
  const WallViewState();
}

class WallViewLoading extends WallViewState {
  const WallViewLoading();
}

class WallViewReady extends WallViewState {
  final List<POIModel> pois;
  final String? activeAnchorId;         // Most recently detected anchor
  final Set<String> detectedAnchorIds;  // All anchors seen this session
  final String? tappedPOIId;            // null when no POI selected

  const WallViewReady({
    required this.pois,
    this.activeAnchorId,
    this.detectedAnchorIds = const {},
    this.tappedPOIId,
  });

  POIModel? get tappedPOI =>
      tappedPOIId == null ? null : pois.firstWhere((p) => p.id == tappedPOIId);

  WallViewReady copyWith({
    String? activeAnchorId,
    Set<String>? detectedAnchorIds,
    String? tappedPOIId,
    bool clearTappedPOI = false,
  }) {
    return WallViewReady(
      pois: pois,
      activeAnchorId: activeAnchorId ?? this.activeAnchorId,
      detectedAnchorIds: detectedAnchorIds ?? this.detectedAnchorIds,
      tappedPOIId: clearTappedPOI ? null : (tappedPOIId ?? this.tappedPOIId),
    );
  }
}

class WallViewError extends WallViewState {
  final String message;
  const WallViewError(this.message);
}
```

### `features/wall_view/cubit/wall_view_cubit.dart`

```dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/ar/ar_session_bridge.dart';
import '../../../core/ar/models/ar_event.dart';
import '../../../core/config/ar_config_loader.dart';
import '../../../core/logging/file_logger.dart';
import 'wall_view_state.dart';

class WallViewCubit extends Cubit<WallViewState> {
  final ARSessionBridge _bridge;
  final ARConfigLoader _configLoader;
  final bool debugMode;

  StreamSubscription<AREvent>? _eventSubscription;

  WallViewCubit({
    required ARSessionBridge bridge,
    required ARConfigLoader configLoader,
    this.debugMode = false,
  })  : _bridge = bridge,
        _configLoader = configLoader,
        super(const WallViewLoading());

  Future<void> initialize() async {
    try {
      await FileLogger.init();
      await FileLogger.log('WallViewCubit: loading config files');

      final anchors = await _configLoader.loadAnchors();
      final pois = await _configLoader.loadPOIs();

      await FileLogger.log('Config loaded: ${anchors.length} anchors, ${pois.length} POIs');

      // Subscribe to native events BEFORE sending session data
      _eventSubscription = _bridge.events.listen(_handleNativeEvent);

      // Native view may already be ready (view created before cubit initialized)
      // or may send session_ready later. We send init data now regardless;
      // the native side buffers it until its AR session is running.
      await _bridge.initializeARSession(
        anchors: anchors,
        pois: pois,
        debugMode: debugMode,
      );

      emit(WallViewReady(pois: pois));
    } catch (e, stack) {
      await FileLogger.log('FATAL: initialization failed: $e\n$stack');
      emit(WallViewError('Failed to initialize AR session: $e'));
    }
  }

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
        FileLogger.log('Anchor detected: $id at distance ${dist.toStringAsFixed(2)}m '
            '| detected=(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})');
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

      case DebugLogEvent(message: final msg):
        FileLogger.log('[NATIVE DEBUG] $msg');

      case UnknownEvent(type: final t):
        FileLogger.log('Unknown native event type: $t');
    }
  }

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
```

### `features/wall_view/presentation/wall_viewport_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/ar/ar_native_view.dart';
import '../cubit/wall_view_cubit.dart';
import '../cubit/wall_view_state.dart';
import 'ar_overlay.dart';
import 'poi_detail_sheet.dart';

class WallViewportPage extends StatefulWidget {
  const WallViewportPage({super.key});

  @override
  State<WallViewportPage> createState() => _WallViewportPageState();
}

class _WallViewportPageState extends State<WallViewportPage> {
  @override
  void initState() {
    super.initState();
    context.read<WallViewCubit>().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<WallViewCubit, WallViewState>(
        listenWhen: (_, current) =>
            current is WallViewReady && current.tappedPOIId != null,
        listener: (context, state) {
          if (state is WallViewReady && state.tappedPOI != null) {
            showModalBottomSheet(
              context: context,
              builder: (_) => POIDetailSheet(poi: state.tappedPOI!),
            ).whenComplete(() => context.read<WallViewCubit>().dismissPOIDetail());
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              // Bottom layer: full-screen native AR view
              const Positioned.fill(child: ARNativeView()),

              // Middle layer: loading/error overlays
              if (state is WallViewLoading)
                const Center(child: CircularProgressIndicator()),
              if (state is WallViewError)
                Center(
                  child: Text('Error: ${state.message}',
                      style: const TextStyle(color: Colors.red)),
                ),

              // Top layer: status HUD (only when ready)
              if (state is WallViewReady)
                AROverlay(
                  activeAnchorId: state.activeAnchorId,
                  detectedCount: state.detectedAnchorIds.length,
                ),
            ],
          );
        },
      ),
    );
  }
}
```

### `features/wall_view/presentation/ar_overlay.dart`

```dart
import 'package:flutter/material.dart';

class AROverlay extends StatelessWidget {
  final String? activeAnchorId;
  final int detectedCount;

  const AROverlay({
    super.key,
    required this.activeAnchorId,
    required this.detectedCount,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              activeAnchorId != null
                  ? '📍 Tracking: $activeAnchorId  ·  $detectedCount anchors found'
                  : '🔍 Scanning for anchors...',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## Part 6 — iOS Native Layer (Swift)

### `ios/Runner/AppDelegate.swift`

```swift
import UIKit
import Flutter
import ARKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  private var nativeARViewFactory: NativeARViewFactory?
  private var arEventChannel: FlutterEventChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController
    let registrar = controller.registrar(forPlugin: "ARWallPlugin")

    // 1. Create the event channel FIRST
    arEventChannel = FlutterEventChannel(
      name: "com.tileapp/ar_events",
      binaryMessenger: controller.binaryMessenger
    )

    // 2. Create the native view factory, injecting the event channel messenger
    nativeARViewFactory = NativeARViewFactory(
      messenger: controller.binaryMessenger,
      methodChannelName: "com.tileapp/ar_methods",
      eventChannelName: "com.tileapp/ar_events"
    )

    // 3. Register the factory under the view type key
    registrar.register(nativeARViewFactory!, withId: "com.tileapp/native_ar_view")

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### `ios/Runner/AR/NativeARViewFactory.swift`

```swift
import Flutter
import UIKit

class NativeARViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let methodChannelName: String
  private let eventChannelName: String

  init(messenger: FlutterBinaryMessenger, methodChannelName: String, eventChannelName: String) {
    self.messenger = messenger
    self.methodChannelName = methodChannelName
    self.eventChannelName = eventChannelName
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return NativeARViewController(
      frame: frame,
      messenger: messenger,
      methodChannelName: methodChannelName,
      eventChannelName: eventChannelName
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}
```

### `ios/Runner/AR/NativeARViewController.swift`

```swift
import Flutter
import UIKit
import ARKit
import SceneKit

class NativeARViewController: NSObject, FlutterPlatformView, ARSCNViewDelegate, FlutterStreamHandler {

  // MARK: - Properties
  private let sceneView: ARSCNView
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private let worldCoordinateManager: WorldCoordinateManager
  private let diagnosticRenderer: DiagnosticRenderer
  private var poiNodeBuilder: POINodeBuilder?
  private var debugMode = false

  // MARK: - Init
  init(frame: CGRect, messenger: FlutterBinaryMessenger, methodChannelName: String, eventChannelName: String) {
    sceneView = ARSCNView(frame: frame)
    methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)

    let worldRootNode = SCNNode()
    worldRootNode.name = "world_root"
    worldCoordinateManager = WorldCoordinateManager(worldRootNode: worldRootNode)
    diagnosticRenderer = DiagnosticRenderer(sceneView: sceneView)

    super.init()

    sceneView.delegate = self
    sceneView.scene.rootNode.addChildNode(worldRootNode)

    // World root starts invisible until first drift correction fires
    worldRootNode.opacity = 0

    eventChannel.setStreamHandler(self)
    setupMethodChannelHandler()
  }

  func view() -> UIView { return sceneView }

  // MARK: - FlutterStreamHandler
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    sendEvent(["type": "session_ready"])
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  private func sendEvent(_ map: [String: Any]) {
    DispatchQueue.main.async { self.eventSink?(map) }
  }

  // MARK: - MethodChannel Handler
  private func setupMethodChannelHandler() {
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "initializeARSession":
        self.handleInitializeARSession(call.arguments, result: result)
      case "setDebugMode":
        let args = call.arguments as? [String: Any]
        self.debugMode = args?["enabled"] as? Bool ?? false
        self.diagnosticRenderer.setDebugMode(self.debugMode)
        result("ok")
      case "pauseSession":
        self.sceneView.session.pause()
        result("ok")
      case "resumeSession":
        self.startARSession(withExistingConfig: true)
        result("ok")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleInitializeARSession(_ args: Any?, result: @escaping FlutterResult) {
    guard let map = args as? [String: Any],
          let anchorMaps = map["anchors"] as? [[String: Any]],
          let poiMaps = map["pois"] as? [[String: Any]] else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing anchors or pois", details: nil))
      return
    }

    let anchors = anchorMaps.compactMap { AnchorBlueprintNative(from: $0) }
    let pois = poiMaps.compactMap { POINative(from: $0) }
    self.debugMode = map["debugMode"] as? Bool ?? false

    worldCoordinateManager.registerBlueprints(anchors: anchors)

    poiNodeBuilder = POINodeBuilder(pois: pois, parentNode: worldCoordinateManager.worldRootNode)
    poiNodeBuilder?.buildAll()

    diagnosticRenderer.setDebugMode(debugMode)
    startARSession(withExistingConfig: false)

    result("ok")
  }

  // MARK: - AR Session
  private func startARSession(withExistingConfig: Bool) {
    guard ARWorldTrackingConfiguration.isSupported else {
      sendEvent(["type": "session_error", "message": "ARWorldTracking not supported on this device"])
      return
    }

    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravity
    configuration.maximumNumberOfTrackedImages = 3

    if let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
      configuration.detectionImages = referenceImages
    }

    sceneView.session.run(
      configuration,
      options: withExistingConfig ? [] : [.resetTracking, .removeExistingAnchors]
    )
  }

  // MARK: - ARSCNViewDelegate
  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let imageAnchor = anchor as? ARImageAnchor else { return }
    let anchorName = imageAnchor.referenceImage.name ?? ""

    let driftedTransform = imageAnchor.transform
    let cameraPos = sceneView.session.currentFrame?.camera.transform.columns.3
    let distance = cameraPos.map {
      simd_length(simd_float3($0.x, $0.y, $0.z) - simd_float3(
        driftedTransform.columns.3.x,
        driftedTransform.columns.3.y,
        driftedTransform.columns.3.z
      ))
    } ?? Float.greatestFiniteMagnitude

    // Apply correction (WorldCoordinateManager applies proximity filter)
    worldCoordinateManager.applyCorrection(
      anchorId: anchorName,
      driftedTransform: driftedTransform,
      cameraDistance: distance
    )

    // Reveal world root on first successful correction
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.5
    worldCoordinateManager.worldRootNode.opacity = 1
    SCNTransaction.commit()

    // Debug visualizer
    if debugMode {
      diagnosticRenderer.renderAnchorDebug(on: node, imageAnchor: imageAnchor)
    }

    // Send event to Flutter
    sendEvent([
      "type": "anchor_detected",
      "anchor_id": anchorName,
      "distance_meters": Double(distance),
      "detected_x": Double(driftedTransform.columns.3.x),
      "detected_y": Double(driftedTransform.columns.3.y),
      "detected_z": Double(driftedTransform.columns.3.z),
    ])

    if debugMode {
      let t = driftedTransform.columns.3
      sendEvent(["type": "debug_log",
        "message": "Anchor \(anchorName) at (\(String(format: "%.3f", t.x)), \(String(format: "%.3f", t.y)), \(String(format: "%.3f", t.z))) dist=\(String(format: "%.2f", distance))m"])
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    // Re-run correction on tracking update for maximum precision
    guard let imageAnchor = anchor as? ARImageAnchor,
          imageAnchor.isTracked else { return }
    let anchorName = imageAnchor.referenceImage.name ?? ""
    let cameraPos = sceneView.session.currentFrame?.camera.transform.columns.3
    let t = imageAnchor.transform.columns.3
    let distance = cameraPos.map {
      simd_length(simd_float3($0.x, $0.y, $0.z) - simd_float3(t.x, t.y, t.z))
    } ?? Float.greatestFiniteMagnitude
    worldCoordinateManager.applyCorrection(
      anchorId: anchorName, driftedTransform: imageAnchor.transform, cameraDistance: distance
    )
  }

  func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
    guard let imageAnchor = anchor as? ARImageAnchor else { return }
    sendEvent(["type": "anchor_lost", "anchor_id": imageAnchor.referenceImage.name ?? ""])
  }

  // MARK: - Tap Handling
  func handleTap(at point: CGPoint) {
    let hitResults = sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
    if let hit = hitResults.first, let poiId = hit.node.name {
      sendEvent(["type": "poi_tapped", "poi_id": poiId])
    }
  }
}
```

### `ios/Runner/AR/WorldCoordinateManager.swift`

```swift
import SceneKit
import ARKit

class WorldCoordinateManager {
  let worldRootNode: SCNNode

  // Blueprint data: anchorId → true physical transform matrix
  private var blueprintTransforms: [String: simd_float4x4] = [:]

  // Proximity tracking: currently visible anchors and their distances
  private var visibleAnchors: [String: Float] = [:]

  private var lastCorrectionAnchorId: String?

  init(worldRootNode: SCNNode) {
    self.worldRootNode = worldRootNode
  }

  func registerBlueprints(anchors: [AnchorBlueprintNative]) {
    for anchor in anchors {
      blueprintTransforms[anchor.id] = anchor.blueprintTransform
    }
  }

  /// Applies a smooth drift correction if this anchor is the closest visible one.
  func applyCorrection(anchorId: String, driftedTransform: simd_float4x4, cameraDistance: Float) {
    visibleAnchors[anchorId] = cameraDistance

    // Only apply correction from the closest visible anchor
    guard let closestId = visibleAnchors.min(by: { $0.value < $1.value })?.key,
          closestId == anchorId,
          let blueprint = blueprintTransforms[anchorId] else {
      return
    }

    // ΔT = T_blueprint × T_drifted⁻¹
    let correctionDelta = blueprint * driftedTransform.inverse

    // Smooth application via SCNTransaction (acts as Lerp/Slerp on the node's transform)
    DispatchQueue.main.async {
      SCNTransaction.begin()
      SCNTransaction.animationDuration = 0.75
      SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      self.worldRootNode.simdTransform = correctionDelta
      SCNTransaction.commit()
    }

    lastCorrectionAnchorId = anchorId
  }

  func anchorLost(_ anchorId: String) {
    visibleAnchors.removeValue(forKey: anchorId)
  }
}

// MARK: - Native data holders (parsed from MethodChannel maps)
struct AnchorBlueprintNative {
  let id: String
  let physicalWidthMeters: Float
  let blueprintTransform: simd_float4x4

  init?(from map: [String: Any]) {
    guard let id = map["id"] as? String,
          let width = map["physical_width_meters"] as? Double,
          let x = map["blueprint_x"] as? Double,
          let y = map["blueprint_y"] as? Double,
          let z = map["blueprint_z"] as? Double,
          let yaw = map["blueprint_yaw_degrees"] as? Double else { return nil }

    self.id = id
    self.physicalWidthMeters = Float(width)

    // Build transform: translation only for flat wall (yaw = 0 typically)
    var transform = matrix_identity_float4x4
    transform.columns.3 = simd_float4(Float(x), Float(y), Float(z), 1)
    // Apply yaw rotation around Y axis if needed
    let yawRad = Float(yaw) * .pi / 180
    let cosY = cos(yawRad), sinY = sin(yawRad)
    transform.columns.0 = simd_float4(cosY, 0, -sinY, 0)
    transform.columns.2 = simd_float4(sinY, 0,  cosY, 0)
    self.blueprintTransform = transform
  }
}

struct POINative {
  let id: String
  let label: String
  let description: String
  let position: SCNVector3
  let iconName: String

  init?(from map: [String: Any]) {
    guard let id = map["id"] as? String,
          let label = map["label"] as? String,
          let description = map["description"] as? String,
          let x = map["blueprint_x"] as? Double,
          let y = map["blueprint_y"] as? Double,
          let z = map["blueprint_z"] as? Double,
          let icon = map["icon_name"] as? String else { return nil }
    self.id = id
    self.label = label
    self.description = description
    self.position = SCNVector3(x, y, z)
    self.iconName = icon
  }
}
```

### `ios/Runner/AR/POINodeBuilder.swift`

```swift
import SceneKit

class POINodeBuilder {
  private let pois: [POINative]
  private let parentNode: SCNNode

  init(pois: [POINative], parentNode: SCNNode) {
    self.pois = pois
    self.parentNode = parentNode
  }

  /// Creates one SCNNode per POI and attaches them all as children of the world root.
  func buildAll() {
    for poi in pois {
      let node = buildNode(for: poi)
      node.position = poi.position
      node.name = poi.id // Used for tap detection

      // Billboard constraint: always face the camera
      let billboardConstraint = SCNBillboardConstraint()
      billboardConstraint.freeAxes = .Y
      node.constraints = [billboardConstraint]

      parentNode.addChildNode(node)
    }
  }

  private func buildNode(for poi: POINative) -> SCNNode {
    // Create a flat plane for the billboard
    let plane = SCNPlane(width: 0.12, height: 0.06)
    plane.cornerRadius = 0.01

    // Use a material with the icon image if available, otherwise solid color
    let material = SCNMaterial()
    if let image = UIImage(named: poi.iconName) {
      material.diffuse.contents = image
    } else {
      material.diffuse.contents = UIColor.systemBlue
    }
    material.isDoubleSided = true
    plane.materials = [material]

    // Add text label below the billboard
    let text = SCNText(string: poi.label, extrusionDepth: 0.001)
    text.font = UIFont.systemFont(ofSize: 0.03, weight: .medium)
    text.flatness = 0.1
    let textMaterial = SCNMaterial()
    textMaterial.diffuse.contents = UIColor.white
    text.materials = [textMaterial]
    let textNode = SCNNode(geometry: text)
    textNode.scale = SCNVector3(0.3, 0.3, 0.3)
    textNode.position = SCNVector3(-0.05, -0.045, 0)

    let containerNode = SCNNode(geometry: plane)
    containerNode.addChildNode(textNode)
    containerNode.name = poi.id // Propagate ID for hit testing
    return containerNode
  }
}
```

### `ios/Runner/AR/DiagnosticRenderer.swift`

```swift
import SceneKit
import ARKit

class DiagnosticRenderer {
  private weak var sceneView: ARSCNView?
  private var debugMode = false
  private var debugNodes: [SCNNode] = []

  init(sceneView: ARSCNView) {
    self.sceneView = sceneView
  }

  func setDebugMode(_ enabled: Bool) {
    debugMode = enabled
    if !enabled {
      debugNodes.forEach { $0.removeFromParentNode() }
      debugNodes.removeAll()
    }
    sceneView?.debugOptions = enabled
      ? [.showFeaturePoints, .showWorldOrigin]
      : []
  }

  /// Renders debug axes and wireframe at a detected image anchor node.
  func renderAnchorDebug(on node: SCNNode, imageAnchor: ARImageAnchor) {
    guard debugMode else { return }

    let axisLength: Float = 0.15
    let img = imageAnchor.referenceImage

    // RGB axes
    let xAxis = makeAxisLine(length: axisLength, color: .red, direction: SCNVector3(axisLength, 0, 0))
    let yAxis = makeAxisLine(length: axisLength, color: .green, direction: SCNVector3(0, axisLength, 0))
    let zAxis = makeAxisLine(length: axisLength, color: .blue, direction: SCNVector3(0, 0, axisLength))

    // Wireframe border matching image physical size
    let frame = makeWireframe(
      width: CGFloat(img.physicalSize.width),
      height: CGFloat(img.physicalSize.height)
    )

    [xAxis, yAxis, zAxis, frame].forEach {
      node.addChildNode($0)
      debugNodes.append($0)
    }
  }

  private func makeAxisLine(length: Float, color: UIColor, direction: SCNVector3) -> SCNNode {
    let cylinder = SCNCylinder(radius: 0.003, height: CGFloat(length))
    cylinder.firstMaterial?.diffuse.contents = color
    let node = SCNNode(geometry: cylinder)
    node.position = SCNVector3(direction.x / 2, direction.y / 2, direction.z / 2)
    // Rotate cylinder to point in the right direction (cylinders default to Y axis)
    if direction.x != 0 { node.eulerAngles = SCNVector3(0, 0, Float.pi / 2) }
    if direction.z != 0 { node.eulerAngles = SCNVector3(Float.pi / 2, 0, 0) }
    return node
  }

  private func makeWireframe(width: CGFloat, height: CGFloat) -> SCNNode {
    let plane = SCNPlane(width: width, height: height)
    plane.firstMaterial?.diffuse.contents = UIColor.green.withAlphaComponent(0.3)
    plane.firstMaterial?.fillMode = .lines
    plane.firstMaterial?.isDoubleSided = true
    return SCNNode(geometry: plane)
  }
}
```

---

## Part 7 — Android Native Layer (Kotlin)

### `android/app/build.gradle` — dependencies to add

```groovy
dependencies {
    // ARCore + SceneView (replaces raw GLSurface — handles Filament, ARCore session, etc.)
    implementation 'io.github.sceneview:arsceneview:2.2.1'

    // Flutter plugin support (already present in standard Flutter project)
    implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.7.0'
}
```

### `android/.../MainActivity.kt`

```kotlin
package com.yourorg.ar_wall_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "com.tileapp/ar_methods"
        const val EVENT_CHANNEL  = "com.tileapp/ar_events"
        const val VIEW_TYPE      = "com.tileapp/native_ar_view"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            VIEW_TYPE,
            NativeARViewFactory(
                messenger = flutterEngine.dartExecutor.binaryMessenger,
                methodChannelName = METHOD_CHANNEL,
                eventChannelName = EVENT_CHANNEL
            )
        )
    }
}
```

### `android/.../ar/NativeARViewFactory.kt`

```kotlin
package com.yourorg.ar_wall_app.ar

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeARViewFactory(
    private val messenger: BinaryMessenger,
    private val methodChannelName: String,
    private val eventChannelName: String
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativeARViewController(
            context = context,
            messenger = messenger,
            methodChannelName = methodChannelName,
            eventChannelName = eventChannelName
        )
    }
}
```

### `android/.../ar/NativeARViewController.kt`

```kotlin
package com.yourorg.ar_wall_app.ar

import android.content.Context
import android.graphics.BitmapFactory
import android.view.View
import com.google.ar.core.AugmentedImage
import com.google.ar.core.AugmentedImageDatabase
import com.google.ar.core.Config
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.ArSceneView
import io.github.sceneview.ar.arcore.getUpdatedAugmentedImages
import io.github.sceneview.math.Position
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class NativeARViewController(
    private val context: Context,
    messenger: BinaryMessenger,
    methodChannelName: String,
    eventChannelName: String
) : PlatformView, EventChannel.StreamHandler {

    private val arSceneView = ArSceneView(context)
    private val methodChannel = MethodChannel(messenger, methodChannelName)
    private val eventChannel = EventChannel(messenger, eventChannelName)
    private var eventSink: EventChannel.EventSink? = null

    private val worldCoordinateManager = WorldCoordinateManager(arSceneView)
    private val diagnosticRenderer = DiagnosticRenderer(arSceneView)
    private var poiNodeBuilder: POINodeBuilder? = null
    private var debugMode = false

    init {
        eventChannel.setStreamHandler(this)
        setupMethodChannel()
        setupARSession()
    }

    override fun getView(): View = arSceneView
    override fun dispose() {
        arSceneView.destroy()
        methodChannel.setMethodCallHandler(null)
    }

    // FlutterStreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        sendEvent(mapOf("type" to "session_ready"))
    }
    override fun onCancel(arguments: Any?) { eventSink = null }

    private fun sendEvent(map: Map<String, Any>) {
        arSceneView.post { eventSink?.success(map) }
    }

    private fun setupMethodChannel() {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeARSession" -> {
                    val args = call.arguments as? Map<*, *>
                    handleInitialize(args, result)
                }
                "setDebugMode" -> {
                    debugMode = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean ?: false
                    diagnosticRenderer.setDebugMode(debugMode)
                    result.success("ok")
                }
                "pauseSession"  -> { arSceneView.pause(arSceneView); result.success("ok") }
                "resumeSession" -> { arSceneView.resume(arSceneView); result.success("ok") }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleInitialize(args: Map<*, *>?, result: MethodChannel.Result) {
        if (args == null) { result.error("INVALID_ARGS", "null args", null); return }

        @Suppress("UNCHECKED_CAST")
        val anchorMaps = args["anchors"] as? List<Map<*, *>> ?: emptyList()
        @Suppress("UNCHECKED_CAST")
        val poiMaps = args["pois"] as? List<Map<*, *>> ?: emptyList()
        debugMode = args["debugMode"] as? Boolean ?: false

        val anchors = anchorMaps.mapNotNull { AnchorBlueprintNative.from(it) }
        val pois = poiMaps.mapNotNull { POINative.from(it) }

        worldCoordinateManager.registerBlueprints(anchors)
        poiNodeBuilder = POINodeBuilder(context, pois, arSceneView, worldCoordinateManager)
        poiNodeBuilder?.buildAll()
        diagnosticRenderer.setDebugMode(debugMode)

        // Build image database with loaded reference images
        setupImageDatabase(anchors)

        result.success("ok")
    }

    private fun setupARSession() {
        arSceneView.onSessionUpdated = { _, frame ->
            val updatedImages = frame.getUpdatedAugmentedImages()
            for (image in updatedImages) {
                when (image.trackingState) {
                    TrackingState.TRACKING -> handleAnchorTracked(image)
                    TrackingState.STOPPED  -> sendEvent(mapOf("type" to "anchor_lost", "anchor_id" to image.name))
                    else -> Unit
                }
            }
        }

        arSceneView.onTapAr = { hitResult, _ ->
            val node = arSceneView.children.firstOrNull { it.name != null && it == hitResult.node }
            node?.name?.let { sendEvent(mapOf("type" to "poi_tapped", "poi_id" to it)) }
        }
    }

    private fun handleAnchorTracked(image: AugmentedImage) {
        val pose = image.centerPose
        val cameraPose = arSceneView.arSession?.currentFrame?.camera?.pose ?: return
        val dist = Math.sqrt(
            Math.pow((pose.tx() - cameraPose.tx()).toDouble(), 2.0) +
            Math.pow((pose.ty() - cameraPose.ty()).toDouble(), 2.0) +
            Math.pow((pose.tz() - cameraPose.tz()).toDouble(), 2.0)
        ).toFloat()

        worldCoordinateManager.applyCorrection(image.name, pose, dist)

        sendEvent(mapOf(
            "type" to "anchor_detected",
            "anchor_id" to image.name,
            "distance_meters" to dist.toDouble(),
            "detected_x" to pose.tx().toDouble(),
            "detected_y" to pose.ty().toDouble(),
            "detected_z" to pose.tz().toDouble()
        ))

        if (debugMode) {
            diagnosticRenderer.renderAnchorDebug(image)
            sendEvent(mapOf("type" to "debug_log",
                "message" to "Anchor ${image.name} detected @ dist=${String.format("%.2f", dist)}m"))
        }
    }

    private fun setupImageDatabase(anchors: List<AnchorBlueprintNative>) {
        val session = arSceneView.arSession ?: return
        val db = AugmentedImageDatabase(session)
        for (anchor in anchors) {
            try {
                val stream = context.assets.open("ar_anchors/${anchor.imageAssetName}.jpg")
                val bitmap = BitmapFactory.decodeStream(stream)
                db.addImage(anchor.id, bitmap, anchor.physicalWidthMeters)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        val config = Config(session)
        config.augmentedImageDatabase = db
        config.focusMode = Config.FocusMode.AUTO
        config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
        session.configure(config)
    }
}
```

### `android/.../ar/WorldCoordinateManager.kt`

```kotlin
package com.yourorg.ar_wall_app.ar

import com.google.ar.core.Pose
import dev.romainguy.kotlin.math.Float4x4
import dev.romainguy.kotlin.math.inverse
import dev.romainguy.kotlin.math.translation
import io.github.sceneview.ar.ArSceneView
import io.github.sceneview.node.Node

class WorldCoordinateManager(private val arSceneView: ArSceneView) {

    // The single root node that parents all POI nodes
    val worldRootNode: Node = Node(arSceneView.engine)

    private val blueprintPoses: MutableMap<String, Pose> = mutableMapOf()
    private val visibleAnchors: MutableMap<String, Float> = mutableMapOf()

    init {
        arSceneView.addChildNode(worldRootNode)
        worldRootNode.isVisible = false  // Hidden until first correction
    }

    fun registerBlueprints(anchors: List<AnchorBlueprintNative>) {
        for (anchor in anchors) {
            blueprintPoses[anchor.id] = anchor.blueprintPose
        }
    }

    fun applyCorrection(anchorId: String, driftedPose: Pose, cameraDistance: Float) {
        visibleAnchors[anchorId] = cameraDistance

        // Only apply from the closest visible anchor (proximity filter)
        val closestId = visibleAnchors.minByOrNull { it.value }?.key ?: return
        if (closestId != anchorId) return

        val blueprint = blueprintPoses[anchorId] ?: return

        // ΔT = T_blueprint × T_drifted⁻¹
        // Compose as Pose: blueprint compose inverse(drifted)
        val inverseDrifted = driftedPose.inverse()
        val correctionPose = blueprint.compose(inverseDrifted)

        arSceneView.post {
            // SceneView's Node uses a smooth animator when transform changes
            worldRootNode.worldPosition = com.google.ar.sceneform.math.Vector3(
                correctionPose.tx(), correctionPose.ty(), correctionPose.tz()
            )
            // Apply quaternion rotation
            val q = correctionPose.rotationQuaternion
            worldRootNode.worldQuaternion = com.google.ar.sceneform.math.Quaternion(q[0], q[1], q[2], q[3])
            worldRootNode.isVisible = true
        }
    }

    fun anchorLost(anchorId: String) {
        visibleAnchors.remove(anchorId)
    }
}

// Extension to invert ARCore Pose
private fun Pose.inverse(): Pose = this.inverse()

data class AnchorBlueprintNative(
    val id: String,
    val imageAssetName: String,
    val physicalWidthMeters: Float,
    val blueprintPose: Pose
) {
    companion object {
        fun from(map: Map<*, *>): AnchorBlueprintNative? {
            val id = map["id"] as? String ?: return null
            val imageName = map["image_asset_name"] as? String ?: return null
            val width = (map["physical_width_meters"] as? Number)?.toFloat() ?: return null
            val x = (map["blueprint_x"] as? Number)?.toFloat() ?: return null
            val y = (map["blueprint_y"] as? Number)?.toFloat() ?: return null
            val z = (map["blueprint_z"] as? Number)?.toFloat() ?: return null
            val pose = Pose.makeTranslation(x, y, z)
            return AnchorBlueprintNative(id, imageName, width, pose)
        }
    }
}

data class POINative(
    val id: String, val label: String, val description: String,
    val x: Float, val y: Float, val z: Float, val iconName: String
) {
    companion object {
        fun from(map: Map<*, *>): POINative? {
            return POINative(
                id = map["id"] as? String ?: return null,
                label = map["label"] as? String ?: return null,
                description = map["description"] as? String ?: return null,
                x = (map["blueprint_x"] as? Number)?.toFloat() ?: return null,
                y = (map["blueprint_y"] as? Number)?.toFloat() ?: return null,
                z = (map["blueprint_z"] as? Number)?.toFloat() ?: return null,
                iconName = map["icon_name"] as? String ?: return null
            )
        }
    }
}
```

---

## Part 8 — Tests

### `test/core/ar/ar_math_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ar_wall_app/core/ar/utils/ar_math.dart';

void main() {
  group('ARMath.calculateCorrectionDelta', () {
    test('Corrects 30cm drift on X axis', () {
      final blueprint = Matrix4.identity()..setTranslation(Vector3(10.0, 1.5, 0.0));
      final drifted   = Matrix4.identity()..setTranslation(Vector3(9.7, 1.5, 0.0));

      final delta = ARMath.calculateCorrectionDelta(
        blueprintTransform: blueprint, driftedTransform: drifted);

      final translation = ARMath.extractTranslation(delta);
      expect(translation.x, closeTo(0.3, 0.0001));
      expect(translation.y, closeTo(0.0, 0.0001));
      expect(translation.z, closeTo(0.0, 0.0001));
    });

    test('Corrects drift on all axes simultaneously', () {
      final blueprint = Matrix4.identity()..setTranslation(Vector3(5.0, 1.5, 0.0));
      final drifted   = Matrix4.identity()..setTranslation(Vector3(4.85, 1.52, 0.03));

      final delta = ARMath.calculateCorrectionDelta(
        blueprintTransform: blueprint, driftedTransform: drifted);

      final t = ARMath.extractTranslation(delta);
      expect(t.x, closeTo(0.15, 0.001));
      expect(t.y, closeTo(-0.02, 0.001));
      expect(t.z, closeTo(-0.03, 0.001));
    });

    test('Returns identity when blueprint equals drifted (no drift)', () {
      final m = Matrix4.identity()..setTranslation(Vector3(5.0, 1.5, 0.0));
      final delta = ARMath.calculateCorrectionDelta(blueprintTransform: m, driftedTransform: m);
      final t = ARMath.extractTranslation(delta);
      expect(t.x, closeTo(0.0, 0.0001));
      expect(t.y, closeTo(0.0, 0.0001));
      expect(t.z, closeTo(0.0, 0.0001));
    });

    test('CRITICAL: Determinant must be positive (no mirror inversion)', () {
      final blueprint = Matrix4.identity()..setTranslation(Vector3(10.0, 1.5, 0.0));
      final drifted   = Matrix4.identity()..setTranslation(Vector3(9.8, 1.5, -0.1));
      final delta = ARMath.calculateCorrectionDelta(
        blueprintTransform: blueprint, driftedTransform: drifted);
      expect(ARMath.isCorrectionValid(delta), isTrue,
          reason: 'A negative determinant means the world is mirrored — critical bug');
    });
  });

  group('ARMath.lerpVector3', () {
    test('50% lerp gives midpoint', () {
      final from = Vector3(0, 0, 0);
      final to   = Vector3(10, 4, 2);
      final mid  = ARMath.lerpVector3(from, to, 0.5);
      expect(mid.x, closeTo(5.0, 0.001));
      expect(mid.y, closeTo(2.0, 0.001));
    });

    test('t=0 returns from', () {
      final from = Vector3(1, 2, 3);
      final result = ARMath.lerpVector3(from, Vector3(10, 10, 10), 0.0);
      expect(result.x, closeTo(1.0, 0.001));
    });

    test('t=1 returns to', () {
      final to = Vector3(7, 8, 9);
      final result = ARMath.lerpVector3(Vector3.zero(), to, 1.0);
      expect(result.x, closeTo(7.0, 0.001));
    });
  });

  group('ARMath.buildBlueprintMatrix', () {
    test('Creates identity-rotation matrix at given position', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(3.5, 1.5, 0.0), 0.0);
      final t = ARMath.extractTranslation(m);
      expect(t.x, closeTo(3.5, 0.001));
      expect(t.y, closeTo(1.5, 0.001));
      expect(t.z, closeTo(0.0, 0.001));
    });
  });
}
```

### `test/core/ar/ar_event_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ar_wall_app/core/ar/models/ar_event.dart';

void main() {
  group('AREvent.fromMap', () {
    test('Parses session_ready', () {
      final event = AREvent.fromMap({'type': 'session_ready'});
      expect(event, isA<SessionReadyEvent>());
    });

    test('Parses anchor_detected with full precision', () {
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
    });

    test('Parses poi_tapped', () {
      final event = AREvent.fromMap({'type': 'poi_tapped', 'poi_id': 'poi_042'});
      expect(event, isA<POITappedEvent>());
      expect((event as POITappedEvent).poiId, equals('poi_042'));
    });

    test('Parses debug_log', () {
      final event = AREvent.fromMap({'type': 'debug_log', 'message': 'Delta x=0.02m'});
      expect(event, isA<DebugLogEvent>());
    });

    test('Handles unknown event type gracefully', () {
      final event = AREvent.fromMap({'type': 'future_event_type'});
      expect(event, isA<UnknownEvent>());
    });
  });
}
```

### `test/core/ar/anchor_blueprint_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ar_wall_app/core/ar/models/anchor_blueprint.dart';

void main() {
  group('AnchorBlueprint.fromJson', () {
    test('Parses correctly from valid JSON map', () {
      final json = {
        'id': 'anchor_03',
        'image_asset_name': 'anchor_03',
        'physical_width_meters': 0.40,
        'blueprint_position': {'x': 7.5, 'y': 1.5, 'z': 0.0},
        'blueprint_yaw_degrees': 0.0,
      };
      final anchor = AnchorBlueprint.fromJson(json);
      expect(anchor.id, equals('anchor_03'));
      expect(anchor.physicalWidthMeters, closeTo(0.40, 0.001));
      expect(anchor.blueprintPosition.x, closeTo(7.5, 0.001));
    });

    test('toChannelMap preserves double precision', () {
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
    });
  });
}
```

---

## Part 9 — Step-by-Step Execution Order

Follow this order exactly. **Do not proceed to the next milestone until all tests in the current one pass.**

### Milestone 1 — Project Initialization [DONE]
```bash
flutter create --org com.arwall --platforms=android ar_wall_app
cd ar_wall_app
flutter pub add vector_math flutter_bloc path_provider
```
- Full directory structure from Part 2 created
- `assets/config/` paths declared in `pubspec.yaml`
- `flutter pub get` succeeds — 75 packages resolved

### Milestone 2 — Data Layer & Math Core [DONE]
**Files implemented:**
- `assets/config/anchor_blueprint.json` (3 anchors)
- `assets/config/poi_config.json` (5 test POIs)
- `core/ar/models/anchor_blueprint.dart`
- `core/ar/models/poi_model.dart`
- `core/ar/models/ar_event.dart`
- `core/ar/utils/ar_math.dart`
- `core/config/ar_config_loader.dart`

**Tests run and passed:**
- `flutter test test/core/ar/ar_math_test.dart` — 14/14
- `flutter test test/core/ar/ar_event_test.dart` — 7/7
- `flutter test test/core/ar/anchor_blueprint_test.dart` — 4/4

### Milestone 3 — Bridge & Logging Layer [DONE]
**Files implemented:**
- `core/ar/ar_session_bridge.dart`
- `core/ar/ar_native_view.dart`
- `core/logging/file_logger.dart`
`flutter analyze` — zero errors.

### Milestone 4 — State Management [DONE]
**Files implemented:**
- `features/wall_view/cubit/wall_view_state.dart`
- `features/wall_view/cubit/wall_view_cubit.dart`

### Milestone 5 — Flutter UI Shell [DONE]
**Files implemented:**
- `features/wall_view/presentation/wall_viewport_page.dart`
- `features/wall_view/presentation/ar_overlay.dart`
- `features/wall_view/presentation/poi_detail_sheet.dart`
- `lib/main.dart`

### Milestone 6 — iOS Native Foundation
**SKIPPED** — Android ARCore only for this phase.
- `assets/config/poi_config.json` (put 5-10 test POIs)
- `core/ar/models/anchor_blueprint.dart`
- `core/ar/models/poi_model.dart`
- `core/ar/models/ar_event.dart`
- `core/ar/utils/ar_math.dart`
- `core/config/ar_config_loader.dart`

**Tests to run and pass:**
```bash
flutter test test/core/ar/ar_math_test.dart
flutter test test/core/ar/ar_event_test.dart
flutter test test/core/ar/anchor_blueprint_test.dart
```

### Milestone 3 — Bridge & Logging Layer (Day 1-2)
**Files to implement:**
- `core/ar/ar_session_bridge.dart`
- `core/ar/ar_native_view.dart`
- `core/logging/file_logger.dart`

**Verify:** No tests yet at this stage, but run `flutter analyze` — zero errors.

### Milestone 4 — State Management (Day 2)
**Files to implement:**
- `features/wall_view/cubit/wall_view_state.dart`
- `features/wall_view/cubit/wall_view_cubit.dart`

**Tests to run:**
```bash
flutter pub add bloc_test mockito build_runner --dev
flutter test test/features/wall_view/wall_view_cubit_test.dart
```
Cubit tests use a mocked `ARSessionBridge` and verify state transitions.

### Milestone 5 — Flutter UI Shell (Day 2-3)
**Files to implement:**
- `features/wall_view/presentation/wall_viewport_page.dart`
- `features/wall_view/presentation/ar_overlay.dart`
- `features/wall_view/presentation/poi_detail_sheet.dart`
- `main.dart` (BlocProvider wiring)

**Verify:** `flutter run` on a device shows a loading state (native view may be blank at this point — that's expected).

### Milestone 6 — iOS Native Foundation (Day 3-4)
**Files to implement:**
- `ios/Runner/AppDelegate.swift` (register factory + channels)
- `ios/Runner/AR/NativeARViewFactory.swift`
- `ios/Runner/AR/WorldCoordinateManager.swift` (AnchorBlueprintNative, POINative structs)
- `ios/Runner/AR/NativeARViewController.swift` (just session setup + image detection logging)

Add camera usage: in `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for augmented reality.</string>
```

Add AR reference image group in Xcode: Assets.xcassets → New AR Resources Group → "AR Resources" → Add all `anchor_*.jpg` images with correct physical sizes.

**Verify on device:** App opens, camera shows, console prints "Anchor detected: anchor_01" when you hold the anchor image in front of the camera. **Do not add POIs yet.**

### Milestone 7 — iOS World Correction + Debug Renderer (Day 4-5)
**Files to implement:**
- `ios/Runner/AR/DiagnosticRenderer.swift`
- `ios/Runner/AR/POINodeBuilder.swift`

Wire `WorldCoordinateManager` corrections into `NativeARViewController.renderer(_:didAdd:for:)` and `renderer(_:didUpdate:for:)`.

**On-device verification (single anchor):**
1. Place one anchor image on a wall
2. Enable debug mode
3. Verify RGB axes appear on the anchor, correctly oriented (red=right, green=up, blue=out from wall)
4. Verify no mirroring (green line must point up the wall, not into the floor)
5. Hold a ruler up to the screen — the wireframe should match the printed image size exactly

### Milestone 8 — iOS Full 150 POI Test (Day 5)
Load all 150 POIs from config. Run on device.

**Performance check:** Enable Instruments (Xcode). Profile frame rate while all 150 nodes are visible. Must sustain 60fps.

**Drift check:** Walk the length of the wall. Check log file for drift deltas. They should converge (get smaller) as more anchor detections occur.

### Milestone 9 — Android Native (Day 6-7)
Mirror Milestones 6-8 in Kotlin using the SceneView library. Follow the same verification steps.

**Android-specific check:** Ensure `AugmentedImageDatabase` compiles without errors. Log database image count.

### Milestone 10 — Full Integration & Log Review (Day 7-8)
- Connect both platforms
- Load full 150 POIs config
- Walk the 23-meter wall on both devices
- Retrieve log file: Navigate to the hidden debug screen showing `ar_debug_logs.txt` content
- Verify: `Anchor detected` events interleaved correctly along the wall
- Verify: Drift deltas decrease over time (no compounding error)
- Verify: POI tap → bottom sheet shows correct label and description
- Performance: Both devices sustain 60fps with all 150 POIs visible

---

## Part 10 — Verification Checklist

### Math Correctness
- [ ] `ar_math_test.dart` — 100% pass
- [ ] Determinant test passes (no mirror inversion)
- [ ] Correction returns identity when blueprint equals drifted

### Channel Integrity
- [ ] `ar_event_test.dart` — all event types parse correctly with double precision
- [ ] POI maps serialize/deserialize without float precision loss

### Physical Accuracy (on-device)
- [ ] Single anchor: wireframe matches physical image borders exactly
- [ ] Axes: red=right, green=up, blue=out from wall (no inversions)
- [ ] 1-meter grid overlay aligns with physical measuring tape across 23 meters
- [ ] POI tap detected correctly and correct `poi_id` reaches Flutter

### Performance
- [ ] 150 POIs visible: ≥60fps on both iOS and Android
- [ ] No Dart work in render loop (all transform math stays native)
- [ ] EventChannel sends max ~1 event/second at steady state (not per frame)

### Stability
- [ ] App handles camera permission denial gracefully
- [ ] App handles ARCore not installed (Android)
- [ ] App handles no anchor detected for 30 seconds (world root stays hidden, status shows "scanning")
- [ ] Session pause/resume works (backgrounding the app and returning)

---

## Part 11 — On-Site Calibration Workflow

**This step happens before any development.** Without real measurements, the blueprint JSON is guesswork.

1. **Install the anchors physically** on the wall. Print 10–20 images at a known exact size (recommend 40cm × 40cm).
2. **Measure from a fixed reference point** (bottom-left wall corner) to the center of each anchor using a laser measure.
3. **Record measurements** in the format: `{ x_from_left_meters, y_from_floor_meters }`. Z is always 0 (wall surface).
4. **Measure each POI position** relative to the same reference point. POIs are typically at Z=0.05–0.10 (slightly in front of the wall surface).
5. **Enter all measurements** into `anchor_blueprint.json` and `poi_config.json`.
6. **Double-check** by computing the distance between adjacent anchors mathematically and verifying it against a physical tape measure.

---

## Part 12 — Dependencies Summary

### `pubspec.yaml`
```yaml
dependencies:
  flutter:
    sdk: flutter
  vector_math: ^2.1.4
  flutter_bloc: ^8.1.5
  path_provider: ^2.1.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  bloc_test: ^9.1.7
  mockito: ^5.4.4
  build_runner: ^2.4.8

flutter:
  assets:
    - assets/config/anchor_blueprint.json
    - assets/config/poi_config.json
    - assets/ar_anchors/
```

### `android/app/build.gradle`
```groovy
implementation 'io.github.sceneview:arsceneview:2.2.1'
```

### Milestone 9 — Android Native (ARCore) [DONE]
**Files implemented:**
- `android/app/src/main/kotlin/com/arwall/ar_wall_app/MainActivity.kt`
- `android/app/src/main/kotlin/.../ar/NativeARViewFactory.kt`
- `android/app/src/main/kotlin/.../ar/NativeARViewController.kt`
- `android/app/src/main/kotlin/.../ar/WorldCoordinateManager.kt`
- `android/app/src/main/kotlin/.../ar/POINodeBuilder.kt`
- `android/app/src/main/kotlin/.../ar/DiagnosticRenderer.kt`
- `android/app/src/main/kotlin/.../ar/ARModels.kt`
- `android/app/build.gradle.kts` — minSdk=24, arsceneview:2.2.1 dependency
- `android/app/src/main/AndroidManifest.xml` — camera permission, ARCore required meta-data

### Milestone 10 — Full Integration [PARTIALLY DONE — pending on-device corner validation]
- [DONE] Add real anchor image to `assets/ar_anchors/` and `android/app/src/main/assets/ar_anchors/`
- [DONE] Update `anchor_blueprint.json` with real on-site measurement (1.01m painting)
- [DONE] `flutter analyze` — 0 issues
- [DONE] `flutter test` — 34/34 passing (new comprehensive 3D math test suite)
- [DONE] `debugMode: true` enabled in `main.dart` for device testing
- Connect Android phone (adb wireless) and run `flutter run`
- Visual verification: 4 corner POI labels at exact corners of the painting
- Pull device logs: `adb pull <log_path> .`

### Milestone 11 — 3D Math Corrections [DONE]
**Applied from `AR_WALL_3D_MATH_CORRECTIONS.md`:**
- [DONE] `lib/core/ar/utils/ar_math.dart` — fixed formula `M = T_drifted × T_blueprint⁻¹` (was backwards), corrected `buildBlueprintMatrix` rotation sign, added `localToGlobalBlueprint`, `computeAnchorCorners`, `decomposeMatrix`
- [DONE] `android/.../ar/WorldCoordinateManager.kt` — fixed `driftedPose.compose(blueprintPose.inverse())`, removed broken custom `Pose.inverse()` extension, ARCore built-in used
- [DONE] `test/core/ar/ar_math_test.dart` — full replacement with 34-test comprehensive suite covering formula proof, rotated wall segments, corner POI validation, global drift consistency
- [DONE] `assets/config/anchor_blueprint.json` — removed `.jpg` extension from `image_asset_name` (Kotlin code appends it)
- [DONE] `android/app/src/main/assets/ar_anchors/Anchor_Painting_For_Test_World_Coord.jpg` — copied for ARCore image database

---

*Implementation status: Android ARCore phase complete + 3D math corrections applied. Unit tests: 34/34 pass. flutter analyze: 0 issues. debugMode=true. Next step: on-device corner validation.*
