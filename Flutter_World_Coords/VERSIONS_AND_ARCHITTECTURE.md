# AR Wall App — Version & Architecture Decisions

> Date: June 2026 | Status: Android implementing, iOS deferred

---

## Repository

**SceneView** (unified monorepo — formerly `sceneview-android`):  
`https://github.com/sceneview/sceneview`  
Maven: `io.github.sceneview:arsceneview:<version>`

---

## Final Version Decisions

### Android — `arsceneview:2.2.1` ✅ (keep, do NOT upgrade to 4.x now)

| | 2.2.1 | 4.18.0 |
|---|---|---|
| API style | View-based (`ARSceneView extends SurfaceView`) | Compose-only (`@Composable fun ARSceneView`) |
| Flutter PlatformView fit | **Perfect** — return `ARSceneView` directly as `getView()` | Requires `ComposeView` wrapper + Compose Gradle plugin + BOM |
| Node types available | `Node`, `ViewNode`, `CubeNode`, `SphereNode`, `ImageNode` | Adds `TextNode`, `BillboardNode` (same nodes otherwise) |
| AR tracking quality | ARCore SDK 1.x | ARCore SDK 1.x (same underlying engine — no difference) |
| Maintenance | Superseded; source archived in monorepo | Active |
| Risk for this project | **Low** — minimal API fixes needed | High — complete Kotlin rewrite required |

**Decision rationale:** ARCore tracking precision, drift correction math, and Filament rendering quality are *identical* between 2.x and 4.x — SceneView is a thin wrapper over the same ARCore SDK and Filament renderer. The View-based `ARSceneView` in 2.2.1 embeds into Flutter PlatformView with zero overhead, while 4.x requires a `ComposeView` wrapper introducing Compose lifecycle complexity into a Flutter context. Upgrade to 4.x when a specific 4.x-only feature is actually needed.

**Upgrade trigger:** If we need `TextNode` 3D labels in AR space (currently handled by Flutter 2D overlay), reconsider 4.x then.

### iOS — Raw ARKit + RealityKit (implement when Android is validated)

| Library | Status | Min iOS | Notes |
|---|---|---|---|
| SceneViewSwift 4.18.0 | **Alpha** | iOS 18.0 | Official SceneView iOS. Too new, Alpha status, too restrictive iOS min. |
| ARKit + SceneKit | Maintenance mode | iOS 11 | Apple stopped adding AR features after ARKit 4 (2020). Avoid for new projects. |
| **ARKit + RealityKit** | **Production** ✅ | **iOS 13.0** | Apple's recommended path. `ARImageTrackingConfiguration` fully supported. Active development. |

**Decision:** Use raw ARKit + RealityKit when iOS implementation begins. Same platform channel protocol as Android. No shared native library — separate Swift implementation mirrors the Kotlin one.

### Flutter cross-platform AR packages — all unusable

| Package | Status |
|---|---|
| `ar_flutter_plugin` | Dead — last commit 2022, requires `sdk <3.0.0`, incompatible with Flutter 3.x |
| `arkit_plugin` | iOS-only, actively maintained (v1.4.0 June 2026), no Android |
| `ar_core_flutter_plugin` | Deleted from pub.dev |
| `sceneview_flutter` | Alpha, Git dependency only, iOS 18+ minimum |

**Decision:** Custom PlatformView bridges on both platforms (what we have). No shared package exists that is both maintained and cross-platform.

---

## Architecture (current, keep as-is)

```
Flutter / Dart Layer
├── ARMath (pure Dart, unit-testable math)
├── ARConfigLoader (JSON → models)
├── ARSessionBridge (MethodChannel + EventChannel)
├── WallViewCubit (state machine)
└── UI (WallViewportPage, AROverlay, POIDetailSheet)
        │ Platform Channels
        ↓
Android / Kotlin Layer
├── NativeARViewFactory (PlatformViewFactory)
├── NativeARViewController (PlatformView, View=ARSceneView)
├── WorldCoordinateManager (drift correction math: M = T_drifted × T_blueprint⁻¹)
├── POINodeBuilder (Node graph under world root)
├── DiagnosticRenderer (debug geometry)
└── ARModels (data holders)
        │ (deferred)
        ↓
iOS / Swift Layer (future)
├── NativeARViewFactory → NativeARViewController
├── WorldCoordinateManager.swift (same correction formula)
├── POINodeBuilder.swift
└── ARModels.swift
```

### Key invariants (do not change without full test cycle)

1. **Correction formula**: `M = T_drifted × T_blueprint⁻¹` (proof in `AR_WALL_3D_MATH_CORRECTIONS.md`)
2. **One world root node**: all 150 POI nodes are children of one `Node`. One correction call moves all POIs.
3. **Blueprint coords are global**: POI positions in `poi_config.json` are in global blueprint space, NOT local to any anchor.
4. **Positive yaw = clockwise from above**: `buildBlueprintMatrix` uses `setRotationY(+radians(yaw))` — right-hand math.
5. **Platform channels stay fixed**: `com.tileapp/ar_methods`, `com.tileapp/ar_events`, `com.tileapp/native_ar_view`.

---

## Android API Fixes Applied (2.2.1)

The `arsceneview:2.2.1` JAR uses `ARSceneView` (capital AR), not `ArSceneView`. The original code had the wrong class name, causing cascade compile errors. Fixes applied:

| Error | Fix |
|---|---|
| `Unresolved reference 'ArSceneView'` | Renamed to `ARSceneView` in all 4 files |
| `arSceneView.addChildNode(node)` on scene | Changed to `arSceneView.addNode(node)` (SceneView$addNode method) |
| `ViewNode(engine, materialLoader)` | Replaced with `Node(engine)` — POI labels shown via Flutter 2D overlay |
| `onSessionUpdated = { _, frame ->` | Added explicit types `{ _: Session, frame: Frame ->` |
| `onTapAr = { hitResult, _ ->` | Fixed to `{ _: HitResult, node: Node? ->` + used `node?.name` |
| `arSceneView.arSession` | Added `onSessionCreated` callback to capture session |
| `arSceneView.pause(arSceneView)` | Changed to `capturedSession?.pause()` |
| `frame.getUpdatedAugmentedImages()` | Passes `frame` parameter into handler function |

---

## iOS Implementation Plan (future)

When implementing iOS:
1. Create Swift files mirroring the Kotlin structure
2. Use `ARImageTrackingConfiguration` (not `ARWorldTrackingConfiguration`) for image-only tracking — faster, more stable for known anchor images
3. Drift correction: `correctionTransform = drifted * blueprint.inverse` (same formula, `simd_float4x4`)
4. `ARAnchor` for world root; `RealityKit.Entity` for POI nodes
5. Platform channel protocol stays identical — Dart layer requires zero changes

---

## Links

- Repo: https://github.com/sceneview/sceneview
- ARCore AugmentedImage docs: https://developers.google.com/ar/develop/augmented-images
- ARKit ARImageTrackingConfiguration: https://developer.apple.com/documentation/arkit/arimagetrackingconfiguration
- Correction formula proof: `AR_WALL_3D_MATH_CORRECTIONS.md` Part 1
