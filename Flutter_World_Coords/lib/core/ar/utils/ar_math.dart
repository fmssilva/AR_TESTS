import 'package:vector_math/vector_math_64.dart';

// Pure Dart math utilities for AR coordinate calculations.
// No platform dependencies — 100% unit-testable on the Dart VM.
// All transforms use column-vector convention (same as ARCore/SceneView/simd).
class ARMath {
  ARMath._();

  // ─────────────────────────────────────────────────────────────────────────
  // CORE CORRECTION
  // ─────────────────────────────────────────────────────────────────────────

  // Computes M = T_drifted x T_blueprint^-1.
  //
  // Apply this as worldRootNode.worldTransform (absolute, not cumulative).
  //
  // Proof: worldRootNode.transform x T_blueprint = T_drifted
  //        -> worldRootNode.transform = T_drifted x T_blueprint^-1
  //
  // WRONG formula (from earlier drafts): T_blueprint x T_drifted^-1
  // With wrong formula a POI 0.3m right of an anchor at x=10 ends up at x=18 — 16m off.
  static Matrix4 calculateCorrectionDelta({
    required Matrix4 blueprintTransform,
    required Matrix4 driftedTransform,
  }) {
    final Matrix4 invertedBlueprint = Matrix4.copy(blueprintTransform)..invert();
    // T_drifted x T_blueprint^-1
    return driftedTransform * invertedBlueprint;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRANSFORM BUILDERS
  // ─────────────────────────────────────────────────────────────────────────

  // Builds a 4x4 blueprint transform from a 3D position and Y-axis yaw (degrees).
  //
  // Sign convention: positive yaw_degrees = wall segment rotates clockwise when viewed
  // from above (standard site-measurement convention). This maps to -yaw in right-hand
  // math, so local +X along wall yields global (cos yaw, 0, -sin yaw) in XZ.
  //
  // For a flat wall at 0°:   local +X = global +X
  // For a concave wall at 15°: local +X has negative Z component (curves into room)
  static Matrix4 buildBlueprintMatrix(Vector3 position, double yawDegrees) {
    final Matrix4 m = Matrix4.identity();
    // Standard right-hand Y-axis rotation.
    // Positive yaw = wall segment angled so that +X (right along wall) maps to
    // (cos yaw, 0, -sin yaw) in global XZ, i.e. Z becomes more negative going right.
    m.setRotationY(radians(yawDegrees));
    m.setTranslation(position);
    return m;
  }

  // Transforms a point from anchor LOCAL space to GLOBAL blueprint space.
  //
  // Use this when a POI is measured as a local offset from a nearby anchor
  // and must be converted to global blueprint coords for poi_config.json.
  //
  // Example: anchor at (12, 1.5, -0.85) with rotY=15°, POI 0.3m right along wall:
  //   localOffset = Vector3(0.3, 0, 0)
  //   globalPos   = anchorMatrix x localOffset
  static Vector3 localToGlobalBlueprint({
    required Matrix4 anchorBlueprintMatrix,
    required Vector3 localOffset,
  }) {
    final Vector4 result = anchorBlueprintMatrix *
        Vector4(localOffset.x, localOffset.y, localOffset.z, 1.0);
    return Vector3(result.x, result.y, result.z);
  }

  // Computes the 4 corners of an anchor image in GLOBAL blueprint space.
  // Corners are defined around the anchor center (local origin = image center):
  //   TL = (-w/2, +h/2, 0),  TR = (+w/2, +h/2, 0)
  //   BL = (-w/2, -h/2, 0),  BR = (+w/2, -h/2, 0)
  static Map<String, Vector3> computeAnchorCorners({
    required Matrix4 anchorBlueprintMatrix,
    required double physicalWidthMeters,
    required double physicalHeightMeters,
  }) {
    final double hw = physicalWidthMeters / 2;
    final double hh = physicalHeightMeters / 2;
    return {
      'TL': localToGlobalBlueprint(
          anchorBlueprintMatrix: anchorBlueprintMatrix,
          localOffset: Vector3(-hw, hh, 0)),
      'TR': localToGlobalBlueprint(
          anchorBlueprintMatrix: anchorBlueprintMatrix,
          localOffset: Vector3(hw, hh, 0)),
      'BL': localToGlobalBlueprint(
          anchorBlueprintMatrix: anchorBlueprintMatrix,
          localOffset: Vector3(-hw, -hh, 0)),
      'BR': localToGlobalBlueprint(
          anchorBlueprintMatrix: anchorBlueprintMatrix,
          localOffset: Vector3(hw, -hh, 0)),
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DECOMPOSE (for unit tests and diagnostic logging only)
  // Lerp/Slerp interpolation runs natively — not in Dart.
  // ─────────────────────────────────────────────────────────────────────────

  // Decomposes a 4x4 matrix into translation + quaternion rotation + scale.
  // Used in tests to inspect what a correction delta encodes.
  static ({Vector3 translation, Quaternion rotation, Vector3 scale}) decomposeMatrix(
      Matrix4 m) {
    final Vector3 t = Vector3.zero();
    final Quaternion q = Quaternion.identity();
    final Vector3 s = Vector3.zero();
    m.decompose(t, q, s);
    return (translation: t, rotation: q, scale: s);
  }

  // Extract the translation column from a 4x4 transform matrix.
  static Vector3 extractTranslation(Matrix4 m) => m.getTranslation();

  // Linear interpolation between two Vector3 positions.
  static Vector3 lerpVector3(Vector3 a, Vector3 b, double t) => Vector3(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      );

  // ─────────────────────────────────────────────────────────────────────────
  // VALIDATION
  // ─────────────────────────────────────────────────────────────────────────

  // A valid correction matrix must have a positive determinant.
  // Negative determinant = world is spatially mirrored — critical bug indicator.
  static bool isCorrectionValid(Matrix4 m) => m.determinant() > 0.0;
}

