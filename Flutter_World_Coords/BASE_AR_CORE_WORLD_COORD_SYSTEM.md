after this we also implemented: 
- accept updates from detected anchors with only FULL_TRACKING confidence and not LAST_KNOWN_POSE... 
  



  
# AR Wall World Coordinate System Report

Status as of 2026-06-15.

This document is a compact but complete report of what the project currently implements, why the system is structured this way, which difficult problems had to be solved to arrive here, and what is currently validated versus still deferred.

## 1. Executive Summary

The current project is an Android-first Flutter AR application that uses a native ARCore pipeline to detect known image anchors, solve a world correction transform, and render POI markers through a Flutter 2D overlay.

The final design is intentionally split like this:

- Native Kotlin owns ARCore session state, anchor detection, world transforms, and world-to-screen projection.
- Flutter owns app state, configuration loading, event handling, the overlay painter, and the POI detail UI.
- JSON assets define anchors and POIs so geometry is data-driven rather than hardcoded.

The most important architectural decision is that all POIs live under a single native world root node. When an anchor is detected, the app computes one correction transform and applies it to that root. This moves all POIs together and guarantees consistency across the whole wall coordinate system.

The current implementation is working on device: anchors load, POIs project into the correct screen positions, the earlier sticky overlay bug is gone, and the filtered runtime logs confirm correct image-database setup plus correct visibility transitions.

## 2. What The App Currently Implements

### 2.1 Coordinate Model

The app uses a blueprint coordinate system defined in `assets/config/anchor_blueprint.json`:

- Origin: bottom-left corner of the wall.
- +X: right along the wall.
- +Y: up the wall.
- +Z: outward from the wall into the room.

Anchors are defined by:

- id
- image asset name
- physical width in meters
- blueprint position
- blueprint yaw

POIs are defined by:

- id
- label
- description
- blueprint position
- icon name
- nearest anchor id metadata

Important: POIs are stored in global blueprint coordinates, not local anchor coordinates.

### 2.2 Flutter Layer

The Flutter layer currently provides:

- `ARConfigLoader` to load anchor and POI JSON assets.
- `ARSessionBridge` to talk to native through `MethodChannel` and `EventChannel`.
- `WallViewCubit` as the main session state machine.
- `WallViewportPage` as the main screen.
- `AROverlay` as the 2D overlay painter for origin, axes, and POIs.
- `POIDetailSheet` for tap-driven detail UI.

The cubit flow is:

1. Load config from assets.
2. Wait for the native PlatformView to be created.
3. Subscribe to native events.
4. Send anchors and POIs to native.
5. Receive `anchor_detected`, `poi_tapped`, and `overlay_update` events.
6. Keep Flutter UI state in sync with the native session.

### 2.3 Native Android Layer

The Kotlin layer currently provides:

- `NativeARViewFactory` and `NativeARViewController` for the Flutter PlatformView bridge.
- `WorldCoordinateManager` for correction math and world-root updates.
- `ARModels` for native parsing of anchor and POI data.
- `POINodeBuilder` for creating one native position marker per POI.
- `DiagnosticRenderer` for debug-mode hooks.

The native AR loop is:

1. Build an ARCore `AugmentedImageDatabase` from configured anchor images.
2. Detect tracked anchors.
3. Convert detected anchor pose into the project blueprint frame.
4. Compute correction transform.
5. Apply it to the world root node.
6. Project origin, axes, and POI positions to normalized viewport coordinates.
7. Stream overlay updates back to Flutter.

### 2.4 Current Test Scope

The project currently includes focused tests for:

- correction math
- anchor serialization
- native event parsing
- overlay coordinate normalization
- ready-state overlay persistence behavior
- a Kotlin-side coordinate transform test file

The strongest test surface is the pure-Dart math layer, where the correction formula and rotated-wall cases are explicitly validated.

## 3. Current Data Flow

The implemented end-to-end data flow is:

```text
JSON assets
	-> Flutter models
	-> WallViewCubit
	-> ARSessionBridge
	-> MethodChannel initializeARSession
	-> NativeARViewController
	-> ARModels / POINodeBuilder / image database setup
	-> ARCore detects image anchor
	-> WorldCoordinateManager computes correction
	-> Native projects POIs to normalized viewport space
	-> EventChannel overlay_update
	-> OverlayData
	-> AROverlay painter
```

This split is deliberate. The app does not attempt to compute per-frame spatial math in Dart. Flutter is used only as the UI consumer of already-solved world data.

## 4. Key Files And Their Roles

### 4.1 Core Flutter Files

- `lib/core/ar/ar_session_bridge.dart`
	Sends `initializeARSession`, `setDebugMode`, `pauseSession`, `resumeSession` and exposes the typed event stream.

- `lib/features/wall_view/cubit/wall_view_cubit.dart`
	The session orchestrator. It loads config, subscribes to native events, emits `WallViewReady`, tracks active anchor state, POI taps, and overlay data.

- `lib/core/ar/models/ar_event.dart`
	Defines the typed contract for native events.

- `lib/core/ar/models/overlay_data.dart`
	Holds normalized screen coordinates for origin, axes, and POIs.

- `lib/features/wall_view/presentation/ar_overlay.dart`
	Paints the 2D overlay using normalized viewport positions converted into Flutter logical canvas coordinates.

### 4.2 Core Native Files

- `android/app/src/main/kotlin/com/arwall/ar_wall_app/ar/NativeARViewController.kt`
	The main native bridge. It manages ARCore session callbacks, image database setup, channel events, overlay projection, and runtime logging.

- `android/app/src/main/kotlin/com/arwall/ar_wall_app/ar/WorldCoordinateManager.kt`
	The core spatial authority. It stores blueprint poses, chooses the closest visible anchor, computes correction, and applies it to the world root.

- `android/app/src/main/kotlin/com/arwall/ar_wall_app/ar/ARModels.kt`
	Parses flat channel maps and applies the anchor rotation fix required to align ARCore image-local coordinates with the project blueprint coordinates.

- `android/app/src/main/kotlin/com/arwall/ar_wall_app/ar/POINodeBuilder.kt`
	Creates one invisible native node per POI under the corrected world root. These nodes are not final UI; they are spatial markers used for projection.

### 4.3 Config And Diagnostics Files

- `assets/config/anchor_blueprint.json`
	Defines the wall system and currently contains two anchors.

- `assets/config/poi_config.json`
	Defines four corner POIs used to validate placement.

- `capture_flutter_logs_utf8.ps1`
	Captures filtered logs in UTF-8 and includes `ARController`, `ARProjection`, `WorldCoordManager`, `WorldCoordMath`, and related signals.

### 4.4 Documentation Files

- `AR_WALL_IMPLEMENTATION_PLAN.md`
	Original architecture and project structure intent.

- `AR_WALL_3D_MATH_CORRECTIONS.md`
	Formal math correction note that fixes the earlier wrong transform formula.

- `VERSIONS_AND_ARCHITTECTURE.md`
	Documents why the project stayed on SceneView 2.2.1 and why Android was prioritized.

- `SMOTH_AND_PRECISION.md`
	Captures future ideas about smoothing, batching, and robustness improvements.

## 5. The Critical Implementation Decisions

### 5.1 One Corrected World Root

All POIs are children of one native `worldRootNode`.

Why this matters:

- one correction updates everything consistently
- avoids per-POI drift logic
- makes reasoning about the wall coordinate system much simpler
- allows all POIs to be projected using native world positions after correction

### 5.2 Native Math, Flutter UI

The system deliberately avoids doing render-loop spatial work in Dart.

Why:

- ARCore frame state is native
- platform render timing is native
- world correction should not cross the Flutter boundary every frame
- Flutter is better used for expressive overlay UI and state-driven interaction

### 5.3 2D Flutter Overlay Instead Of Native 3D Labels

POIs are currently drawn as Flutter overlay elements rather than native 3D text or view nodes.

Why:

- Flutter labels are easier to style and expand into richer UI
- tap/detail flows are easier to manage in Flutter
- the app needed correctness and debuggability first, not rich native 3D presentation
- using native marker nodes only for projection keeps the geometry simple

### 5.4 Width-Only Anchor Semantics

The final anchor model stores physical width only.

Why:

- ARCore `AugmentedImageDatabase.addImage()` is width-based
- height is derived from the bitmap aspect ratio
- introducing explicit height into the anchor config created unnecessary ambiguity for the current Android implementation

This was explored, then reverted back to width-only as the cleanest correct model for the current project.

## 6. The Hard Problems We Had To Solve

This section is the most important part of the report. The project did not become correct by one single fix. It required solving multiple independent failures across coordinate math, asset loading, projection, session lifecycle, and diagnostics.

### 6.1 The Correction Formula Was Initially Backwards

One of the earliest deep issues was that the common-looking formula

```text
T_blueprint x T_drifted^-1
```

is wrong for this system.

The correct formula is:

```text
T_drifted x T_blueprint^-1
```

Why:

- the world root must be the transform that maps blueprint space into the detected AR world pose
- if `M x T_blueprint = T_drifted`, then `M = T_drifted x T_blueprint^-1`

This was not just a theoretical cleanup. It produced massive positional error when wrong. The math tests explicitly demonstrate that the wrong formula can place a POI many meters away from where it belongs.

Current implementation:

```dart
static Matrix4 calculateCorrectionDelta({
	required Matrix4 blueprintTransform,
	required Matrix4 driftedTransform,
}) {
	final Matrix4 invertedBlueprint = Matrix4.copy(blueprintTransform)..invert();
	return driftedTransform * invertedBlueprint;
}
```

And on Android:

```kotlin
val correctionPose = driftedPose.compose(blueprintPose.inverse())
```

### 6.2 ARCore Image Coordinates Did Not Match The Project Blueprint Frame

Another difficult issue was that ARCore image-local coordinates do not match the project wall blueprint coordinates.

The app blueprint expects:

- X = right
- Y = up
- Z = outward

ARCore image-local space does not naturally align with that. Without compensating for the frame mismatch, the math can look superficially valid while the wall axes still behave incorrectly.

The fix was to apply an `Rx(+90 deg)` rotation when constructing the anchor blueprint pose on the native side.

Current implementation:

```kotlin
val bpRotation = floatArrayOf(0.7071068f, 0f, 0f, 0.7071068f)
val pose = Pose(floatArrayOf(x, y, z), bpRotation)
```

This was one of the major reasons the POIs eventually started landing in their expected wall-relative positions.

### 6.3 The Native Session Was Not Always Ready When Flutter Sent Anchors

Another failure mode was a lifecycle race: Flutter could send `initializeARSession` before the ARCore session was fully captured on the native side.

Symptoms:

- image database setup could happen too early
- anchors could fail to register reliably
- behavior depended on the timing of PlatformView creation versus AR session startup

The fix was to buffer anchors until the session became available, then apply them on `onSessionCreated` or, if that callback had already been missed, on the first `onSessionUpdated` frame.

This removed a non-deterministic initialization bug that would otherwise keep resurfacing in runtime tests.

### 6.4 The Top-Right Anchor Looked Missing Even Though The File Existed

This was a subtle but important debugging trap.

Observed behavior:

- the file existed in `assets/ar_anchors/`
- native logs still reported that `Anchor_Painting_TOP_RIGHT.jpg` could not be found

Root cause:

- the native loader was reading the legacy Android asset mirror
- only one anchor image existed there
- both images actually existed in the Flutter asset bundle

The fix was to load from the Flutter asset path first, with the legacy path only as fallback.

Current implementation direction:

```kotlin
val flutterAssetPath = "flutter_assets/assets/ar_anchors/${anchor.imageAssetName}.jpg"
val legacyAssetPath = "ar_anchors/${anchor.imageAssetName}.jpg"
```

This solved the false "missing anchor" diagnosis and both anchors now load into the ARCore image database.

### 6.5 Projection Was Correct In World Space But Wrong On Screen

One of the hardest debugging stages was when the relative world math was becoming correct, but the POIs still appeared in the wrong screen position.

The root problem was a screen-space mismatch:

- native projection values were being treated in a way that did not align with Flutter canvas sizing
- Android physical/native pixels and Flutter logical canvas pixels were not being handled consistently

The final fix had two parts:

1. Native projection was normalized to viewport space in `[0, 1]`.
2. Flutter converted normalized coordinates into logical canvas coordinates using the current painter size.

Flutter-side conversion:

```dart
Offset viewportToCanvasPoint(Size size, double x, double y) =>
	Offset(x * size.width, y * size.height);
```

Native-side normalized projection logic:

```kotlin
return Pair(
		(ndcX + 1f) / 2f,
		(1f - ndcY) / 2f
)
```

This was the key fix for the "POIs are not in the correct place on the screen" phase.

### 6.6 Overlay Persistence And The Sticky POI Problem Were Two Different Problems

The project had two closely related but distinct overlay issues.

Problem A:

- after first detection, overlay should not disappear just because the anchor is temporarily offscreen

Problem B:

- some POIs became "sticky" at screen edges because stale overlay state was not being replaced properly when everything went offscreen

These needed different solutions.

The final behavior is:

- the last valid world transform is kept after first anchor lock
- overlay state is not cleared just because the origin is offscreen
- when all POIs are offscreen, native still sends a fresh `overlay_update` with empty POI data and updated visibility flags

This combination removed the stale edge artifacts while preserving persistent spatial context.

### 6.7 Logs Were Initially Too Noisy And Also Incorrectly Encoded

Another major practical difficulty was not just solving bugs, but getting trustworthy logs.

Two issues existed:

- PowerShell output encoding produced garbled text in `_out.txt`
- raw ARCore logs were too noisy to be useful during focused debugging

The solution was:

- force UTF-8 output in `capture_flutter_logs_utf8.ps1`
- write both raw and filtered log files
- include only high-value tags in the filtered capture

This made runtime diagnosis much faster and enabled focused inspection of:

- image database setup
- correction math
- session lifecycle
- projection visibility transitions

### 6.8 We Needed Visibility-Transition Logs, Not Per-Frame Projection Spam

When diagnosing the sticky behavior, per-frame projection logs would have been too noisy.

The clean solution was to log only visibility transitions.

Example behavior now visible in logs:

- `TR 0->1` when the top-right POI becomes visible
- `BR 1->0, TR 1->0` when tracked POIs go offscreen or tracking is lost

This produces exactly the debugging signal needed for projection issues without flooding the capture.

### 6.9 Width-Vs-Height Anchor Modeling Needed A Clean Decision

At one point the design explored explicit width-plus-height semantics for anchors.

That path was rejected for the current implementation because:

- Android uses ARCore image width as the authoritative physical size input
- mixing height into the anchor model at this phase created more conceptual noise than real precision gain

The project therefore returned to a width-only anchor definition, which now matches the actual ARCore contract used at runtime.

## 7. Important Code Excerpts That Define The Current System

### 7.1 Channel Contract

```dart
static const _methodChannel = MethodChannel('com.tileapp/ar_methods');
static const _eventChannel = EventChannel('com.tileapp/ar_events');
```

This contract is the bridge between Flutter state and native AR execution.

### 7.2 Native Correction Application

```kotlin
val correctionPose = driftedPose.compose(blueprintPose.inverse())

worldRootNode.worldPosition = Float3(
		correctionPose.tx(), correctionPose.ty(), correctionPose.tz()
)
worldRootNode.worldQuaternion = Quaternion(q[0], q[1], q[2], q[3])
worldRootNode.isVisible = true
```

This is the moment the entire wall coordinate system is aligned to the detected anchor.

### 7.3 Native POI Spatial Markers

```kotlin
val node = io.github.sceneview.node.Node(sceneView.engine)
node.name = poi.id
node.position = Float3(poi.x, poi.y, poi.z)
worldCoordinateManager.worldRootNode.addChildNode(node)
```

These nodes are not visual POI widgets. They are geometric reference points for corrected projection.

### 7.4 Overlay Projection Contract

```dart
class OverlayData {
	final double originX, originY;
	final bool originVisible;
	final double axisXx, axisXy;
	final bool axisXVisible;
	final double axisYx, axisYy;
	final bool axisYVisible;
	final double axisZx, axisZy;
	final bool axisZVisible;
	final List<POIScreenPos> pois;
}
```

The overlay is now driven by normalized projected geometry rather than ad hoc screen math.

## 8. Validation Evidence

### 8.1 Unit And Parsing Tests

The current tests validate:

- the correction formula direction
- translation-only drift cases
- rotated wall segments
- corner POI placement expectations
- anchor serialization precision
- native event parsing
- overlay normalization behavior
- overlay persistence behavior in `WallViewReady.copyWith`

### 8.2 Runtime Validation

Recent runtime logs confirm:

- both anchor images were added to the ARCore image database
- the database was configured with two images
- both anchors were detected at runtime
- visibility transitions occurred correctly instead of staying sticky

This matches the current manual observation: POIs appear in the correct position and are no longer sticky.

## 9. Current Project Status

### 9.1 What Is Working

- Android Flutter-to-native AR pipeline
- config-driven anchors and POIs
- correct correction formula
- corrected ARCore-to-blueprint axis mapping
- world-root-based POI placement
- normalized native-to-Flutter overlay projection
- persistent overlay after initial lock
- no stale sticky POIs at screen edges
- Flutter asset-first anchor loading
- concise useful AR debug logging
- UTF-8 filtered log capture
- focused math and model tests

### 9.2 What Is Intentionally Deferred

- iOS implementation
- multi-anchor weighted fusion beyond closest-anchor filtering
- temporal batching / outlier rejection / smoothing filters
- richer 3D-native POI presentation
- broader end-to-end integration testing layers

### 9.3 Current Limitations

- the current runtime path is Android-first
- the current config is still a focused test configuration with two anchors and four POIs
- the correction update is direct rather than filtered over time
- anchor selection currently trusts the closest visible anchor instead of a more advanced fusion strategy

## 10. Why The Current Design Is Good

The system is in a good state now because the major failure modes were solved at the root instead of patched superficially.

The final design is coherent:

- one coordinate system
- one world root
- one authoritative native correction path
- one normalized overlay projection contract
- one filtered logging path that exposes the right signals

Most importantly, the project now has a consistent explanation for the full chain:

1. how anchors are defined
2. how they are interpreted by ARCore
3. how they are converted into blueprint space
4. how correction is computed
5. how POIs inherit that correction
6. how those POIs are projected to Flutter
7. how the overlay remains visually correct through visibility changes

That end-to-end coherence is the real achievement of the current implementation.

## 11. Short Final Status Statement

The project currently implements a correct and test-backed Android AR wall coordinate system that uses native anchor detection and correction math, streams normalized projection data to Flutter, and renders stable non-sticky POIs in the right on-screen positions. The hardest problems solved were the transform direction, the ARCore-axis mismatch, the Flutter-vs-native screen coordinate mismatch, the stale overlay behavior, the native asset-path bug, and the need for clean filtered runtime diagnostics.

The codebase now reflects those solutions clearly, and the current runtime behavior matches the intended design.
