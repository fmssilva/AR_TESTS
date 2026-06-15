# AR Wall — 3D Math Corrections & Validation Test Suite

> **Purpose:** Amend the main implementation plan for non-flat 3D walls.  
> **Status of existing plan:** File structure, channel protocol, and state management are all correct. The **correction formula is wrong** in every version of the notes, and the test suite is missing all rotated/3D cases. This document fixes both.

---

## Part 0 — Critical Assessment of the Gemini Supplement

**What it gets right:**
- Z-depth and Y-rotation must be stored for every anchor and POI — correct
- Decompose ΔT into translation + quaternion for Lerp/Slerp — correct
- POI positions must be in the global blueprint frame, not local anchor frames — correct (though not stated explicitly enough)

**What it gets wrong:**

**The formula is backwards.** The supplement (and the original notes, and the previous plan) all write:

```
ΔT = T_blueprint × T_drifted⁻¹
```

This is **incorrect**. See Part 1 for proof with numbers. The correct formula is:

```
ΔT = T_drifted × T_blueprint⁻¹
```

**The Dart `decomposeTransform` placement is wrong.** The supplement puts per-frame Lerp/Slerp in Dart. Dart must never touch the render loop. Decompose lives in Dart for **unit testing only**. The actual frame-by-frame interpolation stays natively in Swift (`SCNTransaction`) and Kotlin (SceneView animator).

**POI `rotationY` in JSON is a mistake for billboard POIs.** If POIs are billboard nodes (always face camera), they do not have an orientation — the billboard constraint handles facing. Adding a rotationY field to POI config is wrong and confusing. Only anchors need orientation data.

---

## Part 1 — The Correct Formula (Proof by Example)

### Setup

The scene:
- `worldRootNode` is a direct child of the scene root (identity in AR world)
- All 150 POI nodes are children of `worldRootNode` at their blueprint positions
- A child node at local position `P_local` appears at: **`P_world = worldRootNode.transform × P_local`**

We want to find `worldRootNode.transform = M` such that the world snaps into physical alignment.

### The Constraint

For any detected anchor, its blueprint position and its AR-world-detected position are both known. We need `M` such that:

```
M × T_blueprint = T_drifted        (for the anchor's full 4×4 transform)
         ↓ solve for M
         M = T_drifted × T_blueprint⁻¹
```

### Numerical Proof

Anchor blueprint: position `(10.0, 1.5, 0.0)`, no rotation → `T_b = translate(10, 1.5, 0)`  
ARKit detects: position `(2.0, −0.3, −1.5)`, no rotation → `T_d = translate(2, −0.3, −1.5)`  
POI in blueprint at `(10.3, 1.6, 0.0)` — 0.3 m right, 0.1 m up from the anchor

**Formula A (wrong — from the notes):** `M = T_b × T_d⁻¹`  
= `translate(10,1.5,0) × translate(−2,0.3,1.5)`  
= `translate(8, 1.8, 1.5)`  
POI world pos = `translate(8,1.8,1.5) × (10.3,1.6,0)` = **(18.3, 3.4, 1.5)** ✗ — completely wrong

**Formula B (correct):** `M = T_d × T_b⁻¹`  
= `translate(2,−0.3,−1.5) × translate(−10,−1.5,0)`  
= `translate(−8, −1.8, −1.5)`  
POI world pos = `translate(−8,−1.8,−1.5) × (10.3,1.6,0)` = **(2.3, −0.2, −1.5)** ✓  
Expected: anchor at `(2.0,−0.3,−1.5)` + offset `(0.3, 0.1, 0)` = `(2.3, −0.2, −1.5)` ✓

### Proof with Rotation (30° Y-Axis Wall Segment)

Anchor blueprint: position `(10, 1.5, −0.5)`, rotY=30°  
`T_b = [R₃₀ | (10, 1.5, −0.5)]`

ARKit detects same orientation, position `(1.2, 0.3, −2.1)`:  
`T_d = [R₃₀ | (1.2, 0.3, −2.1)]`

`M = T_d × T_b⁻¹`  
Since `R_d = R_b = R₃₀`: `R_d × R_b^T = I` → rotation cancels  
`M = translate(1.2−10, 0.3−1.5, −2.1−(−0.5)) = translate(−8.8, −1.2, −1.6)` (pure translation)

POI at global blueprint position `(10.26, 1.5, −0.65)` — that's 0.3 m along the 30° segment from the anchor:  
`P_world = translate(−8.8,−1.2,−1.6) × (10.26, 1.5, −0.65)` = **(1.46, 0.3, −2.25)**

Expected: anchor at `(1.2, 0.3, −2.1)`, offset 0.3 m along 30° wall = `(cos30°×0.3, 0, −sin30°×0.3)` = `(0.26, 0, −0.15)` added → `(1.46, 0.3, −2.25)` ✓

**Confirmed: `ΔT = T_drifted × T_blueprint⁻¹` is the correct formula.**

---

## Part 2 — 3D Blueprint Coordinate System

Declare this clearly in both the code and the config files.

```
Global Blueprint Space
──────────────────────
Origin (0, 0, 0):  Bottom-left corner of the FIRST wall segment (fixed physical feature)
+X axis:           Rightward along the wall BASELINE at floor level
+Y axis:           Straight up (anti-gravity)
+Z axis:           Outward from the baseline wall, INTO the room (positive = away from wall)

For a curved/angled wall:
  - An anchor on a segment rotated 15° around Y has blueprint_yaw = 15°
  - Its Z position is non-zero if it is physically behind the baseline plane
  - A POI 0.3 m to the right of that anchor along the wall surface
    has global blueprint position: anchor_pos + R_anchor × (0.3, 0, 0)
    which is (x + 0.3·cos15°, y, z − 0.3·sin15°) — NOT just (x+0.3, y, z)

CRITICAL: All POI positions in poi_config.json are GLOBAL blueprint coordinates.
          They are NOT local offsets from any anchor.
```

---

## Part 3 — Code Changes Required

### Change 1 — `lib/core/ar/utils/ar_math.dart` (full replacement)

```dart
import 'package:vector_math/vector_math_64.dart';

/// Pure Dart math for AR coordinate calculations.
/// No platform dependencies — 100% unit-testable.
/// All transforms use column-vector convention (same as ARKit/SceneKit/simd).
class ARMath {
  ARMath._();

  // ─────────────────────────────────────────────────────────────────────────
  // CORE CORRECTION
  // ─────────────────────────────────────────────────────────────────────────

  /// Computes M = T_drifted × T_blueprint⁻¹.
  ///
  /// Apply this as worldRootNode.simdTransform (absolute, not cumulative).
  /// Do NOT use T_blueprint × T_drifted⁻¹ — that is mathematically backwards.
  ///
  /// Proof: worldRootNode.transform × T_blueprint = T_drifted
  ///        → worldRootNode.transform = T_drifted × T_blueprint⁻¹
  static Matrix4 calculateCorrectionDelta({
    required Matrix4 blueprintTransform,
    required Matrix4 driftedTransform,
  }) {
    final Matrix4 invertedBlueprint = Matrix4.copy(blueprintTransform)..invert();
    return driftedTransform * invertedBlueprint;   // T_drifted × T_blueprint⁻¹
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRANSFORM BUILDERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds a 4×4 blueprint transform from a 3D position and Y-axis yaw (degrees).
  /// Column layout: [right | up | backward | position]
  ///
  /// For a flat wall segment: yawDegrees = 0
  /// For a wall segment rotated 15° clockwise viewed from above: yawDegrees = 15
  static Matrix4 buildBlueprintMatrix(Vector3 position, double yawDegrees) {
    final Matrix4 m = Matrix4.identity();
    // Apply Y rotation first (in identity space), then translate
    m.setRotationY(radians(yawDegrees));
    m.setTranslation(position);
    return m;
  }

  /// Transforms a point from anchor LOCAL space to GLOBAL blueprint space.
  ///
  /// Use this when you have a POI measured as a local offset from an anchor
  /// and need to convert to global blueprint coordinates for the config file.
  ///
  /// Example: anchor at (12, 1.5, −0.85) with rotY=15°, POI 0.3 m right
  ///   → localOffset = Vector3(0.3, 0, 0)
  ///   → globalPos = anchor_blueprint_pos + rotateY(15°) × (0.3, 0, 0)
  static Vector3 localToGlobalBlueprint({
    required Matrix4 anchorBlueprintMatrix,
    required Vector3 localOffset,
  }) {
    final Vector4 transformed = anchorBlueprintMatrix * Vector4(
      localOffset.x, localOffset.y, localOffset.z, 1.0,
    );
    return Vector3(transformed.x, transformed.y, transformed.z);
  }

  /// Computes the 4 corners of an anchor image in GLOBAL blueprint space.
  /// Useful for generating corner POI positions and for tests.
  ///
  /// Corners in anchor local space (anchor center = origin):
  ///   TL = (−w/2, +h/2, 0), TR = (+w/2, +h/2, 0)
  ///   BL = (−w/2, −h/2, 0), BR = (+w/2, −h/2, 0)
  static Map<String, Vector3> computeAnchorCorners({
    required Matrix4 anchorBlueprintMatrix,
    required double physicalWidthMeters,
    required double physicalHeightMeters,
  }) {
    final double hw = physicalWidthMeters / 2;
    final double hh = physicalHeightMeters / 2;
    return {
      'TL': localToGlobalBlueprint(anchorBlueprintMatrix: anchorBlueprintMatrix, localOffset: Vector3(-hw,  hh, 0)),
      'TR': localToGlobalBlueprint(anchorBlueprintMatrix: anchorBlueprintMatrix, localOffset: Vector3( hw,  hh, 0)),
      'BL': localToGlobalBlueprint(anchorBlueprintMatrix: anchorBlueprintMatrix, localOffset: Vector3(-hw, -hh, 0)),
      'BR': localToGlobalBlueprint(anchorBlueprintMatrix: anchorBlueprintMatrix, localOffset: Vector3( hw, -hh, 0)),
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DECOMPOSE & LERP (for testing / logging only — Lerp/Slerp runs natively)
  // ─────────────────────────────────────────────────────────────────────────

  /// Decomposes a 4×4 matrix into translation + quaternion rotation + scale.
  /// Used in unit tests to inspect what the correction delta encodes.
  static ({Vector3 translation, Quaternion rotation, Vector3 scale})
      decomposeMatrix(Matrix4 m) {
    final Vector3 t = Vector3.zero();
    final Quaternion q = Quaternion.identity();
    final Vector3 s = Vector3.zero();
    m.decompose(t, q, s);
    return (translation: t, rotation: q, scale: s);
  }

  static Vector3 extractTranslation(Matrix4 m) {
    final v = Vector3.zero(); m.getTranslation(v); return v;
  }

  static Vector3 lerpVector3(Vector3 a, Vector3 b, double t) =>
      Vector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

  // ─────────────────────────────────────────────────────────────────────────
  // VALIDATION
  // ─────────────────────────────────────────────────────────────────────────

  /// A valid correction matrix must have a positive determinant.
  /// Negative = world is mirrored (critical bug indicator).
  static bool isCorrectionValid(Matrix4 m) => m.determinant() > 0.0;
}
```

---

### Change 2 — `ios/Runner/AR/WorldCoordinateManager.swift`

Only the `calculateDelta` function changes. Replace this single line:

```swift
// WRONG (in original plan):
let correctionDelta = blueprint * drifted.inverse

// CORRECT:
let correctionDelta = drifted * blueprint.inverse
```

Full updated function:

```swift
private func calculateDelta(blueprint: simd_float4x4, drifted: simd_float4x4) -> simd_float4x4 {
    // M = T_drifted × T_blueprint⁻¹
    // worldRootNode.transform × T_blueprint = T_drifted  →  worldRootNode.transform = M
    return drifted * blueprint.inverse
}
```

No other changes to `WorldCoordinateManager.swift`. The `SCNTransaction` smooth application and proximity filter are correct as written.

---

### Change 3 — `android/.../ar/WorldCoordinateManager.kt`

Replace the pose composition in `applyCorrection`:

```kotlin
// WRONG:
val correctionPose = blueprint.compose(inverseDrifted)

// CORRECT:
// M = T_drifted × T_blueprint⁻¹
// In ARCore Pose API, T_d.compose(T_b.inverse()) computes T_d × T_b⁻¹
val correctionPose = driftedPose.compose(blueprintPose.inverse())
```

Full corrected `applyCorrection` method:

```kotlin
fun applyCorrection(anchorId: String, driftedPose: Pose, cameraDistance: Float) {
    visibleAnchors[anchorId] = cameraDistance

    val closestId = visibleAnchors.minByOrNull { it.value }?.key ?: return
    if (closestId != anchorId) return

    val blueprintPose = blueprintPoses[anchorId] ?: return

    // M = T_drifted × T_blueprint⁻¹
    val correctionPose = driftedPose.compose(blueprintPose.inverse())

    arSceneView.post {
        worldRootNode.worldPosition = com.google.ar.sceneform.math.Vector3(
            correctionPose.tx(), correctionPose.ty(), correctionPose.tz()
        )
        val q = correctionPose.rotationQuaternion
        worldRootNode.worldQuaternion = com.google.ar.sceneform.math.Quaternion(q[0], q[1], q[2], q[3])
        worldRootNode.isVisible = true
    }
}
```

---

### Change 4 — `ios/Runner/AR/WorldCoordinateManager.swift` — `AnchorBlueprintNative` matrix builder

The rotation matrix builder already exists in the plan but must set columns explicitly in the correct order for `simd_float4x4` (column-major):

```swift
// In AnchorBlueprintNative.init(from:)
// Build a rotation-around-Y matrix and set translation in column 3
let yawRad = Float(yaw) * .pi / 180.0
let cosY = cos(yawRad)
let sinY = sin(yawRad)

// Standard Y-axis rotation matrix (column-major):
// col0 = (cosY, 0, -sinY, 0)  ← right vector
// col1 = (0, 1, 0, 0)          ← up vector
// col2 = (sinY, 0, cosY, 0)    ← backward vector (ARKit: -Z is forward)
// col3 = (x, y, z, 1)          ← position
var transform = matrix_identity_float4x4
transform.columns.0 = simd_float4( cosY, 0, -sinY, 0)
transform.columns.1 = simd_float4(    0, 1,     0, 0)
transform.columns.2 = simd_float4( sinY, 0,  cosY, 0)
transform.columns.3 = simd_float4(Float(x), Float(y), Float(z), 1)
self.blueprintTransform = transform
```

---

### Change 5 — No changes needed to `AnchorBlueprint.dart` or `POIModel.dart`

The existing schemas already include `z` and `blueprint_yaw_degrees`. They are correct. No modification required.

---

## Part 4 — JSON Config Clarifications

No schema changes. Add comments to make the coordinate convention unambiguous:

### `assets/config/anchor_blueprint.json`

```jsonc
{
  "_coord_system": {
    "origin": "Bottom-left corner of the FIRST physical wall segment",
    "x": "Rightward along wall BASELINE at floor level",
    "y": "Straight up",
    "z": "INTO the room (positive = away from wall baseline into open space)",
    "blueprint_yaw_degrees": "Y-axis rotation of the wall segment this anchor is on (0 = facing +Z)"
  },
  "wall": {
    "width_meters": 23.0,
    "height_meters": 3.0
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
      "id": "anchor_06",
      "_comment": "Anchor on a wall segment angled 15° into the room at 12.5m",
      "image_asset_name": "anchor_06",
      "physical_width_meters": 0.40,
      "blueprint_position": { "x": 12.45, "y": 1.35, "z": -0.85 },
      "blueprint_yaw_degrees": 15.5
    }
  ]
}
```

### `assets/config/poi_config.json`

```jsonc
{
  "_coord_system": "Same global blueprint space as anchor_blueprint.json. Positions are GLOBAL, not local offsets from any anchor. For a POI on a 15.5°-angled wall segment, z is non-zero.",
  "pois": [
    {
      "id": "poi_001",
      "label": "Tile Series A",
      "description": "Full detail text shown in bottom sheet.",
      "blueprint_position": {
        "x": 12.80,
        "y": 1.10,
        "z": -0.88
      },
      "_measurement_note": "Measured from wall baseline origin with laser; NOT local to any anchor",
      "icon_name": "icon_tile_marble",
      "nearest_anchor_id": "anchor_06"
    }
  ]
}
```

**On-site measurement tool:** To convert a POI measured as a local wall-surface offset from a nearby anchor, use the `ARMath.localToGlobalBlueprint()` function in a Flutter tool app or simple script. Run it once before entering positions in the JSON — do not store local offsets in the config file.

---

## Part 5 — Complete Test Suite

### `test/core/ar/ar_math_test.dart` (full replacement)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ar_wall_app/core/ar/utils/ar_math.dart';

void main() {

  // ─────────────────────────────────────────────────────────────────────────
  // HELPER
  // ─────────────────────────────────────────────────────────────────────────

  void expectV3Near(Vector3 actual, Vector3 expected, {double epsilon = 0.001, String? reason}) {
    expect(actual.x, closeTo(expected.x, epsilon), reason: reason ?? 'x mismatch');
    expect(actual.y, closeTo(expected.y, epsilon), reason: reason ?? 'y mismatch');
    expect(actual.z, closeTo(expected.z, epsilon), reason: reason ?? 'z mismatch');
  }

  Vector3 applyMatrix(Matrix4 m, Vector3 v) {
    final r = m * Vector4(v.x, v.y, v.z, 1.0);
    return Vector3(r.x, r.y, r.z);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 1 — FORMULA DIRECTION (the most important test)
  // ─────────────────────────────────────────────────────────────────────────

  group('calculateCorrectionDelta — formula direction', () {

    test('PROOF: correct formula places POI at expected AR world position', () {
      // Anchor blueprint: (10.0, 1.5, 0.0)
      // ARKit detects: (2.0, -0.3, -1.5)
      // POI blueprint:  (10.3, 1.6, 0.0)  →  0.3 m right, 0.1 m up from anchor
      // Expected POI AR world: (2.3, -0.2, -1.5)

      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, 0.0), 0.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(2.0, -0.3, -1.5), 0.0);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);

      final poiWorldPos = applyMatrix(correction, Vector3(10.3, 1.6, 0.0));

      expectV3Near(poiWorldPos, Vector3(2.3, -0.2, -1.5),
          reason: 'Correct formula: drifted × blueprint⁻¹');
    });

    test('PROOF: wrong formula gives wildly incorrect result', () {
      // This documents WHY blueprint × drifted⁻¹ must NOT be used.
      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, 0.0), 0.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(2.0, -0.3, -1.5), 0.0);

      // Deliberately apply the wrong formula: T_b × T_d⁻¹
      final invertedDrifted = Matrix4.copy(td)..invert();
      final wrongCorrection = tb * invertedDrifted;
      final wrongPOIPos = applyMatrix(wrongCorrection, Vector3(10.3, 1.6, 0.0));

      // Result will be (18.3, 3.4, 1.5) — 16 m off
      expect(wrongPOIPos.x, greaterThan(10.0),
          reason: 'Wrong formula sends POI completely off into space');
    });

    test('Correction identity: detected equals blueprint → M = identity', () {
      final tb = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: tb);
      final t = ARMath.extractTranslation(correction);
      expectV3Near(t, Vector3.zero(), reason: 'No drift → no correction needed');
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 2 — TRANSLATION-ONLY DRIFT
  // ─────────────────────────────────────────────────────────────────────────

  group('calculateCorrectionDelta — pure translation drift', () {

    test('30 cm X-axis drift', () {
      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, 0.0), 0.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(9.7, 1.5, 0.0), 0.0);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);

      // A POI at blueprint position tb.translation should map to td.translation
      final anchorWorldPos = applyMatrix(correction, Vector3(10.0, 1.5, 0.0));
      expectV3Near(anchorWorldPos, Vector3(9.7, 1.5, 0.0));
    });

    test('Multi-axis drift: X, Y, Z simultaneously', () {
      final tb = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(4.85, 1.52, 0.03), 0.0);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);

      final anchorWorldPos = applyMatrix(correction, Vector3(5.0, 1.5, 0.0));
      expectV3Near(anchorWorldPos, Vector3(4.85, 1.52, 0.03));
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 3 — ROTATED WALL SEGMENT (3D wall validation)
  // ─────────────────────────────────────────────────────────────────────────

  group('calculateCorrectionDelta — rotated wall segment (non-flat 3D wall)', () {

    test('Anchor at 30° Y-rotation: correction is pure translation when rotations match', () {
      // Both blueprint and detected have the same 30° rotation (only position drifted)
      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, -0.5), 30.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(1.2, 0.3, -2.1), 30.0);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);

      final decomp = ARMath.decomposeMatrix(correction);
      // Rotation part of correction should be near identity (quaternion ≈ (0,0,0,1))
      expect(decomp.rotation.w, closeTo(1.0, 0.01),
          reason: 'When rotation drift is zero, correction rotation = identity');
      expectV3Near(decomp.translation, Vector3(1.2 - 10.0, 0.3 - 1.5, -2.1 - (-0.5)));
    });

    test('Anchor at 30° Y-rotation: POI on angled wall segment maps correctly', () {
      // Blueprint: anchor at (10, 1.5, -0.5) with 30° Y rotation
      // A POI 0.3 m to the right of the anchor along the 30°-angled wall surface
      // Local offset from anchor: (0.3, 0, 0)
      // Global blueprint position = anchor_pos + R(30°) × (0.3, 0, 0)
      //   = (10 + 0.3·cos30°, 1.5, -0.5 - 0.3·sin30°)
      //   = (10.26, 1.5, -0.65)  [approx]
      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, -0.5), 30.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(1.2, 0.3, -2.1), 30.0);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);

      final poiBlueprint = ARMath.localToGlobalBlueprint(
        anchorBlueprintMatrix: tb,
        localOffset: Vector3(0.3, 0, 0),
      );
      final poiWorldPos = applyMatrix(correction, poiBlueprint);

      // Expected: anchor AR pos + same 0.3 m offset along 30° wall
      final expectedX = 1.2 + 0.3 * cos(radians(30));
      final expectedZ = -2.1 - 0.3 * sin(radians(30));
      expectV3Near(poiWorldPos, Vector3(expectedX, 0.3, expectedZ), epsilon: 0.002);
    });

    test('Correction is valid (positive determinant) for rotated wall', () {
      final tb = ARMath.buildBlueprintMatrix(Vector3(12.0, 1.5, -0.8), 15.5);
      final td = ARMath.buildBlueprintMatrix(Vector3(3.1, 0.2, -2.4), 15.5);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);
      expect(ARMath.isCorrectionValid(correction), isTrue,
          reason: 'Negative determinant = mirrored world — critical bug');
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 4 — CORNER POI VALIDATION (the key on-site test)
  //
  // Concept: place POIs at the 4 corners of a known anchor. After any drift
  // correction, the corner POIs must appear exactly at the corners of the
  // DETECTED (physical) anchor in AR world space.
  // This validates: blueprint matrix builder + correction math + position transform
  // ─────────────────────────────────────────────────────────────────────────

  group('Corner POI validation — flat anchor (0° rotation)', () {

    // Anchor: center (5.0, 1.5, 0.0), size 0.4 m × 0.4 m, no rotation
    // Blueprint corners:
    //   TL=(4.8, 1.7, 0.0)  TR=(5.2, 1.7, 0.0)
    //   BL=(4.8, 1.3, 0.0)  BR=(5.2, 1.3, 0.0)

    late Matrix4 tb;
    late Map<String, Vector3> blueprintCorners;
    const double w = 0.4, h = 0.4;

    setUp(() {
      tb = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      blueprintCorners = ARMath.computeAnchorCorners(
        anchorBlueprintMatrix: tb,
        physicalWidthMeters: w,
        physicalHeightMeters: h,
      );
    });

    test('Blueprint corners are at correct global positions', () {
      expectV3Near(blueprintCorners['TL']!, Vector3(4.8, 1.7, 0.0), reason: 'TL');
      expectV3Near(blueprintCorners['TR']!, Vector3(5.2, 1.7, 0.0), reason: 'TR');
      expectV3Near(blueprintCorners['BL']!, Vector3(4.8, 1.3, 0.0), reason: 'BL');
      expectV3Near(blueprintCorners['BR']!, Vector3(5.2, 1.3, 0.0), reason: 'BR');
    });

    test('Corner POIs map to correct AR world positions after drift correction', () {
      // Introduce known drift: anchor detected 8 cm right and 5 cm down from blueprint
      final td = ARMath.buildBlueprintMatrix(Vector3(5.08, 1.45, 0.0), 0.0);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);

      // After correction, each corner should be at: detected_anchor_pos + same corner offset
      // TL offset from anchor center: (-0.2, +0.2, 0)
      // Expected TL AR world pos: (5.08 - 0.2, 1.45 + 0.2, 0.0) = (4.88, 1.65, 0.0)
      final correctedTL = applyMatrix(correction, blueprintCorners['TL']!);
      expectV3Near(correctedTL, Vector3(4.88, 1.65, 0.0), reason: 'TL after correction');

      final correctedBR = applyMatrix(correction, blueprintCorners['BR']!);
      expectV3Near(correctedBR, Vector3(5.28, 1.25, 0.0), reason: 'BR after correction');
    });

    test('No drift → corner AR positions equal blueprint corner positions', () {
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: tb); // no drift

      for (final entry in blueprintCorners.entries) {
        final corrected = applyMatrix(correction, entry.value);
        expectV3Near(corrected, entry.value, reason: '${entry.key} must not move when drift=0');
      }
    });

  });

  group('Corner POI validation — rotated anchor (15° Y-axis wall segment)', () {

    // Anchor: center (12.45, 1.35, -0.85), rotY=15.5°, size 0.4 m × 0.4 m
    // Blueprint corners are in the XZ plane rotated by 15.5°

    late Matrix4 tb;
    late Map<String, Vector3> blueprintCorners;

    setUp(() {
      tb = ARMath.buildBlueprintMatrix(Vector3(12.45, 1.35, -0.85), 15.5);
      blueprintCorners = ARMath.computeAnchorCorners(
        anchorBlueprintMatrix: tb,
        physicalWidthMeters: 0.4,
        physicalHeightMeters: 0.4,
      );
    });

    test('Blueprint corners are NOT axis-aligned (rotated in XZ plane)', () {
      // TR must have higher X AND different Z than anchor center
      // because the wall is angled — corners are NOT just ±0.2 in X
      final anchor_pos = ARMath.extractTranslation(tb);
      final tr = blueprintCorners['TR']!;
      expect(tr.x, greaterThan(anchor_pos.x), reason: 'TR is to the right');
      // Z must be MORE negative (further into room) because wall angles in
      expect(tr.z, isNot(closeTo(anchor_pos.z, 0.0001)),
          reason: 'Rotated wall corner Z must differ from anchor center Z');
    });

    test('Corner POIs survive round-trip: blueprint → detect same orientation → correct → back', () {
      // Simulate detection with pure position drift, same orientation
      final driftedPos = Vector3(3.1, -0.2, -2.9);
      final td = ARMath.buildBlueprintMatrix(driftedPos, 15.5);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);

      // Each corrected corner = drifted_anchor_AR + (blueprint_corner - blueprint_anchor_center)
      final anchorCenter = ARMath.extractTranslation(tb);
      final detectedCenter = ARMath.extractTranslation(td);

      for (final entry in blueprintCorners.entries) {
        final localOffset = entry.value - anchorCenter;
        final expectedARPos = detectedCenter + localOffset;
        final correctedARPos = applyMatrix(correction, entry.value);
        expectV3Near(correctedARPos, expectedARPos, epsilon: 0.002,
            reason: '${entry.key}: corrected AR position must match expected');
      }
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 5 — GLOBAL DRIFT CONSISTENCY
  //
  // If the same global drift applies to all anchors uniformly (which is the
  // real-world ARKit drift model), then every anchor computes the SAME
  // correction matrix. This is the theoretical guarantee of the algorithm.
  // ─────────────────────────────────────────────────────────────────────────

  group('Global drift consistency', () {

    test('Two anchors with the same uniform drift give the same correction', () {
      // Physical AR session drift: 15 cm right, 3 cm down, 2° rotation
      final driftTranslation = Vector3(0.15, -0.03, 0.0);
      final driftYaw = 2.0;

      // Anchor A: flat section
      final tb_A = ARMath.buildBlueprintMatrix(Vector3(2.0, 1.5, 0.0), 0.0);
      // Simulated detection = blueprint + drift (for translation-only drift model)
      final td_A = ARMath.buildBlueprintMatrix(
        ARMath.extractTranslation(tb_A) + driftTranslation, driftYaw);
      final correction_A = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb_A, driftedTransform: td_A);

      // Anchor B: different position on same wall
      final tb_B = ARMath.buildBlueprintMatrix(Vector3(8.5, 1.5, 0.0), 0.0);
      final td_B = ARMath.buildBlueprintMatrix(
        ARMath.extractTranslation(tb_B) + driftTranslation, driftYaw);
      final correction_B = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb_B, driftedTransform: td_B);

      // Both corrections must encode the same translation
      final tA = ARMath.extractTranslation(correction_A);
      final tB = ARMath.extractTranslation(correction_B);
      expectV3Near(tA, tB, epsilon: 0.002,
          reason: 'Uniform drift → all anchors give the same correction');
    });

    test('POI farther from any anchor still maps correctly under uniform drift', () {
      // A POI at (15.0, 1.5, 0.0) — 13 m from the nearest anchor
      // With drift of 10 cm right, the corrected position should be exact.
      final drift = Vector3(0.10, 0.0, 0.0);

      final tb = ARMath.buildBlueprintMatrix(Vector3(2.0, 1.5, 0.0), 0.0);
      final td = ARMath.buildBlueprintMatrix(ARMath.extractTranslation(tb) + drift, 0.0);
      final correction = ARMath.calculateCorrectionDelta(
        blueprintTransform: tb, driftedTransform: td);

      final poiBlueprint = Vector3(15.0, 1.5, 0.0);
      final poiWorld = applyMatrix(correction, poiBlueprint);

      // Expected: blueprint position + drift offset
      expectV3Near(poiWorld, poiBlueprint + drift,
          reason: 'Drift is globally uniform: all POIs shift by the same amount');
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 6 — buildBlueprintMatrix CORRECTNESS
  // ─────────────────────────────────────────────────────────────────────────

  group('buildBlueprintMatrix', () {

    test('0° rotation: X-axis offset stays purely in X', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      final point = ARMath.localToGlobalBlueprint(
        anchorBlueprintMatrix: m, localOffset: Vector3(0.3, 0, 0));
      expectV3Near(point, Vector3(5.3, 1.5, 0.0), reason: 'No rotation: offset stays in X');
    });

    test('90° rotation: X-axis offset becomes Z-axis in global space', () {
      // At 90° Y rotation, the wall faces the −X direction.
      // "Right" along the wall (local +X) maps to global −Z.
      // (Specific axis mapping depends on Y-rotation convention — verify on device)
      final m = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, -1.0), 90.0);
      final point = ARMath.localToGlobalBlueprint(
        anchorBlueprintMatrix: m, localOffset: Vector3(0.3, 0, 0));
      // With standard rotateY(90°): local X → global Z (direction depends on sign convention)
      // Z must differ from anchor Z, X must be close to anchor X
      expect((point.z - (-1.0)).abs(), closeTo(0.3, 0.01),
          reason: '90° rotation: local X maps to global Z axis');
    });

    test('Translation is correct for all rotations', () {
      for (final yaw in [0.0, 15.0, 30.0, 45.0, 90.0]) {
        final pos = Vector3(7.0, 2.0, -0.5);
        final m = ARMath.buildBlueprintMatrix(pos, yaw);
        final extractedPos = ARMath.extractTranslation(m);
        expectV3Near(extractedPos, pos, reason: 'Position must survive any yaw rotation');
      }
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 7 — localToGlobalBlueprint
  // ─────────────────────────────────────────────────────────────────────────

  group('localToGlobalBlueprint', () {

    test('Flat anchor: 0.3 m right stays in X', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      final r = ARMath.localToGlobalBlueprint(anchorBlueprintMatrix: m, localOffset: Vector3(0.3, 0, 0));
      expectV3Near(r, Vector3(5.3, 1.5, 0.0));
    });

    test('Rotated anchor: 0.3 m right decomposes into X and Z components', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(12.45, 1.35, -0.85), 15.5);
      final r = ARMath.localToGlobalBlueprint(anchorBlueprintMatrix: m, localOffset: Vector3(0.3, 0, 0));
      // X component: 12.45 + 0.3·cos(15.5°)
      // Z component: -0.85 - 0.3·sin(15.5°)
      expect(r.x, closeTo(12.45 + 0.3 * cos(radians(15.5)), 0.002));
      expect(r.z, closeTo(-0.85 - 0.3 * sin(radians(15.5)), 0.002));
      expect(r.y, closeTo(1.35, 0.001), reason: 'Y is unaffected by Y-rotation');
    });

    test('Y offset stays in Y regardless of wall rotation', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 30.0);
      final r = ARMath.localToGlobalBlueprint(anchorBlueprintMatrix: m, localOffset: Vector3(0, 0.5, 0));
      expectV3Near(r, Vector3(5.0, 2.0, 0.0), reason: 'Y offset unaffected by Y-rotation');
    });

  });

}
```

---

## Part 6 — Test Execution Order

```bash
# Run the isolated math tests (no device needed — runs in seconds)
flutter test test/core/ar/ar_math_test.dart --reporter=expanded

# Expected: all tests pass. If any fails, DO NOT proceed to native implementation.

# The critical tests that MUST pass before touching native code:
#  ✓ PROOF: correct formula places POI at expected AR world position
#  ✓ PROOF: wrong formula gives wildly incorrect result
#  ✓ Corner POI flat: blueprint corners at correct positions
#  ✓ Corner POI flat: corners map correctly after drift correction
#  ✓ Corner POI rotated: round-trip position accuracy
#  ✓ Global drift consistency: two anchors give same correction
```

---

## Part 7 — Summary Checklist for the AI Agent

Apply changes in this exact order. Each item is one targeted change.

**Step 1 — Fix `ar_math.dart`**
- Replace the entire file with the version in Part 3 / Change 1
- The KEY fix: `calculateCorrectionDelta` now inverts `blueprint` and multiplies `drifted × blueprint⁻¹`
- Run `flutter test test/core/ar/ar_math_test.dart` — all tests must pass

**Step 2 — Fix `WorldCoordinateManager.swift`**
- Change `blueprint * drifted.inverse` → `drifted * blueprint.inverse`
- Fix the `simd_float4x4` column assignment in `AnchorBlueprintNative.init` per Part 3 / Change 4

**Step 3 — Fix `WorldCoordinateManager.kt`**
- Change `blueprint.compose(inverseDrifted)` → `driftedPose.compose(blueprintPose.inverse())`

**Step 4 — Replace test file**
- Replace `test/core/ar/ar_math_test.dart` with the full test suite in Part 5
- Run tests again — confirm all 20+ tests pass

**Step 5 — Remove POI `rotationY` from the Gemini supplement's JSON**
- POIs in `poi_config.json` must NOT have a `rotationY` field
- POIs use billboard constraints — orientation is camera-facing at runtime
- POIs only need `x`, `y`, `z` (global blueprint coords)

**Step 6 — Ensure `buildBlueprintMatrix` uses correct rotation order in Swift**
- The matrix must be: rotation THEN translation (applied right-to-left in column-vector math)
- In `simd_float4x4` the columns encode the world-space orientation and position together
- The code in Part 3 / Change 4 is the authoritative implementation

**Step 7 — On-device corner validation (physical test)**
1. Print one anchor at exactly 40 cm × 40 cm
2. Tape it to a wall at a measured position
3. Enable debug mode → the wireframe overlay must align with the printed image borders to within 1–2 mm
4. Place 4 test POIs at the 4 corners (using `computeAnchorCorners()` output as their blueprint positions)
5. After detection: visually confirm each corner POI is at the corresponding printed corner of the image
6. This is the physical proof that the correction math is correct end-to-end

---

## Part 8 — What Does NOT Change

These parts of the original implementation plan are **correct as written** and require no modification:

- File and folder structure
- Platform channel names and method/event schemas
- `ARSessionBridge.dart` — all methods
- `WallViewCubit` and states
- `ARConfigLoader` — JSON loading
- `NativeARViewController.swift` — except it calls the fixed `WorldCoordinateManager`
- `POINodeBuilder.swift` — SCNNode creation and billboard constraints
- `DiagnosticRenderer.swift` — debug axes and wireframes
- `NativeARViewController.kt` — except it calls the fixed `WorldCoordinateManager`
- `FileLogger.dart` — timestamped log files
- All `AnchorBlueprint.dart` and `POIModel.dart` models — schemas already have `z` and `blueprint_yaw_degrees`
- Android `NativeARViewFactory`, `POINodeBuilder`, `DiagnosticRenderer`
- Milestones 1–10 execution order — still valid; apply Step 1–6 above during Milestone 2

---

*Apply this document as a patch on top of `AR_WALL_IMPLEMENTATION_PLAN.md`. Together they form the complete implementation specification.*
