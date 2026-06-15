import 'dart:math' show cos, sin;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ar_wall_app/core/ar/utils/ar_math.dart';

void main() {

  // ─────────────────────────────────────────────────────────────────────────
  // HELPER
  // ─────────────────────────────────────────────────────────────────────────

  void expectV3Near(Vector3 actual, Vector3 expected,
      {double epsilon = 0.001, String? reason}) {
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
      // ARCore detects:   ( 2.0,-0.3,-1.5)
      // POI blueprint:    (10.3, 1.6, 0.0) = 0.3 m right, 0.1 m up from anchor
      // Expected POI AR world: (2.3, -0.2, -1.5)
      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, 0.0), 0.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(2.0, -0.3, -1.5), 0.0);
      final correction = ARMath.calculateCorrectionDelta(
          blueprintTransform: tb, driftedTransform: td);

      final poiWorldPos = applyMatrix(correction, Vector3(10.3, 1.6, 0.0));
      expectV3Near(poiWorldPos, Vector3(2.3, -0.2, -1.5),
          reason: 'Correct formula: drifted x blueprint^-1');
    });

    test('PROOF: wrong formula gives wildly incorrect result', () {
      // Documents WHY blueprint x drifted^-1 must NOT be used.
      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, 0.0), 0.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(2.0, -0.3, -1.5), 0.0);

      // Deliberately apply the wrong formula: T_b x T_d^-1
      final invertedDrifted = Matrix4.copy(td)..invert();
      final wrongCorrection = tb * invertedDrifted;
      final wrongPOIPos = applyMatrix(wrongCorrection, Vector3(10.3, 1.6, 0.0));

      // Result will be (18.3, 3.4, 1.5) — 16 m off
      expect(wrongPOIPos.x, greaterThan(10.0),
          reason: 'Wrong formula sends POI completely off into space');
    });

    test('Correction identity: detected equals blueprint => M = identity', () {
      final tb = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      final correction = ARMath.calculateCorrectionDelta(
          blueprintTransform: tb, driftedTransform: tb);
      final t = ARMath.extractTranslation(correction);
      expectV3Near(t, Vector3.zero(), reason: 'No drift => no correction needed');
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

    test('Anchor at 30 deg Y-rotation: correction is pure translation when rotations match', () {
      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, -0.5), 30.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(1.2, 0.3, -2.1), 30.0);
      final correction = ARMath.calculateCorrectionDelta(
          blueprintTransform: tb, driftedTransform: td);

      final decomp = ARMath.decomposeMatrix(correction);
      // When both matrices have the same rotation, the correction rotation is identity
      expect(decomp.rotation.w, closeTo(1.0, 0.01),
          reason: 'When rotation drift is zero, correction rotation = identity');
      expectV3Near(decomp.translation, Vector3(1.2 - 10.0, 0.3 - 1.5, -2.1 - (-0.5)));
    });

    test('Anchor at 30 deg Y-rotation: POI on angled wall segment maps correctly', () {
      final tb = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, -0.5), 30.0);
      final td = ARMath.buildBlueprintMatrix(Vector3(1.2, 0.3, -2.1), 30.0);
      final correction = ARMath.calculateCorrectionDelta(
          blueprintTransform: tb, driftedTransform: td);

      final poiBlueprint = ARMath.localToGlobalBlueprint(
        anchorBlueprintMatrix: tb,
        localOffset: Vector3(0.3, 0, 0),
      );
      final poiWorldPos = applyMatrix(correction, poiBlueprint);

      // Expected: anchor AR pos + same 0.3 m offset along 30 deg wall
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
  // ─────────────────────────────────────────────────────────────────────────

  group('Corner POI validation — flat anchor (0 deg rotation)', () {

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
      // 8 cm right, 5 cm down drift
      final td = ARMath.buildBlueprintMatrix(Vector3(5.08, 1.45, 0.0), 0.0);
      final correction = ARMath.calculateCorrectionDelta(
          blueprintTransform: tb, driftedTransform: td);

      // TL offset from anchor center: (-0.2, +0.2, 0)
      // Expected TL AR world: (5.08 - 0.2, 1.45 + 0.2, 0.0) = (4.88, 1.65, 0.0)
      final correctedTL = applyMatrix(correction, blueprintCorners['TL']!);
      expectV3Near(correctedTL, Vector3(4.88, 1.65, 0.0), reason: 'TL after correction');

      final correctedBR = applyMatrix(correction, blueprintCorners['BR']!);
      expectV3Near(correctedBR, Vector3(5.28, 1.25, 0.0), reason: 'BR after correction');
    });

    test('No drift => corner AR positions equal blueprint corner positions', () {
      final correction = ARMath.calculateCorrectionDelta(
          blueprintTransform: tb, driftedTransform: tb);

      for (final entry in blueprintCorners.entries) {
        final corrected = applyMatrix(correction, entry.value);
        expectV3Near(corrected, entry.value,
            reason: '${entry.key} must not move when drift=0');
      }
    });

  });

  group('Corner POI validation — rotated anchor (15 deg Y-axis wall segment)', () {

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
      final anchorPos = ARMath.extractTranslation(tb);
      final tr = blueprintCorners['TR']!;
      expect(tr.x, greaterThan(anchorPos.x), reason: 'TR is to the right');
      expect(tr.z, isNot(closeTo(anchorPos.z, 0.0001)),
          reason: 'Rotated wall corner Z must differ from anchor center Z');
    });

    test('Corner POIs survive round-trip: blueprint => detect same orientation => correct => back', () {
      final driftedPos = Vector3(3.1, -0.2, -2.9);
      final td = ARMath.buildBlueprintMatrix(driftedPos, 15.5);
      final correction = ARMath.calculateCorrectionDelta(
          blueprintTransform: tb, driftedTransform: td);

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
  // Note: driftYaw = 0.0 because the simplified drift model only adds a
  // translation offset; adding rotation breaks the uniform-drift assumption.
  // ─────────────────────────────────────────────────────────────────────────

  group('Global drift consistency', () {

    test('Two anchors with the same uniform translation drift give the same correction', () {
      final driftTranslation = Vector3(0.15, -0.03, 0.0);
      // driftYaw = 0.0 (not 2.0) — simplified model: only translate, no extra rotation
      const double driftYaw = 0.0;

      final tbA = ARMath.buildBlueprintMatrix(Vector3(2.0, 1.5, 0.0), 0.0);
      final tdA = ARMath.buildBlueprintMatrix(
          ARMath.extractTranslation(tbA) + driftTranslation, driftYaw);
      final correctionA = ARMath.calculateCorrectionDelta(
          blueprintTransform: tbA, driftedTransform: tdA);

      final tbB = ARMath.buildBlueprintMatrix(Vector3(8.5, 1.5, 0.0), 0.0);
      final tdB = ARMath.buildBlueprintMatrix(
          ARMath.extractTranslation(tbB) + driftTranslation, driftYaw);
      final correctionB = ARMath.calculateCorrectionDelta(
          blueprintTransform: tbB, driftedTransform: tdB);

      final tA = ARMath.extractTranslation(correctionA);
      final tB = ARMath.extractTranslation(correctionB);
      expectV3Near(tA, tB, epsilon: 0.002,
          reason: 'Uniform drift => all anchors give the same correction');
    });

    test('POI farther from any anchor still maps correctly under uniform drift', () {
      final drift = Vector3(0.10, 0.0, 0.0);

      final tb = ARMath.buildBlueprintMatrix(Vector3(2.0, 1.5, 0.0), 0.0);
      final td = ARMath.buildBlueprintMatrix(
          ARMath.extractTranslation(tb) + drift, 0.0);
      final correction = ARMath.calculateCorrectionDelta(
          blueprintTransform: tb, driftedTransform: td);

      final poiBlueprint = Vector3(15.0, 1.5, 0.0);
      final poiWorld = applyMatrix(correction, poiBlueprint);

      expectV3Near(poiWorld, poiBlueprint + drift,
          reason: 'Drift is globally uniform: all POIs shift by the same amount');
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 6 — buildBlueprintMatrix CORRECTNESS
  // ─────────────────────────────────────────────────────────────────────────

  group('buildBlueprintMatrix', () {

    test('0 deg rotation: X-axis offset stays purely in X', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      final point = ARMath.localToGlobalBlueprint(
          anchorBlueprintMatrix: m, localOffset: Vector3(0.3, 0, 0));
      expectV3Near(point, Vector3(5.3, 1.5, 0.0),
          reason: 'No rotation: offset stays in X');
    });

    test('90 deg rotation: X-axis offset becomes Z-axis in global space', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(10.0, 1.5, -1.0), 90.0);
      final point = ARMath.localToGlobalBlueprint(
          anchorBlueprintMatrix: m, localOffset: Vector3(0.3, 0, 0));
      // At 90 deg, local +X maps to global -Z (point.z becomes anchor.z - 0.3)
      expect((point.z - (-1.0)).abs(), closeTo(0.3, 0.01),
          reason: '90 deg rotation: local X maps to global Z axis');
    });

    test('Translation is correct for all rotations', () {
      for (final yaw in [0.0, 15.0, 30.0, 45.0, 90.0]) {
        final pos = Vector3(7.0, 2.0, -0.5);
        final m = ARMath.buildBlueprintMatrix(pos, yaw);
        final extractedPos = ARMath.extractTranslation(m);
        expectV3Near(extractedPos, pos,
            reason: 'Position must survive any yaw rotation');
      }
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 7 — localToGlobalBlueprint
  // ─────────────────────────────────────────────────────────────────────────

  group('localToGlobalBlueprint', () {

    test('Flat anchor: 0.3 m right stays in X', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      final r = ARMath.localToGlobalBlueprint(
          anchorBlueprintMatrix: m, localOffset: Vector3(0.3, 0, 0));
      expectV3Near(r, Vector3(5.3, 1.5, 0.0));
    });

    test('Rotated anchor: 0.3 m right decomposes into X and Z components', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(12.45, 1.35, -0.85), 15.5);
      final r = ARMath.localToGlobalBlueprint(
          anchorBlueprintMatrix: m, localOffset: Vector3(0.3, 0, 0));
      // X: 12.45 + 0.3*cos(15.5)
      // Z: -0.85 - 0.3*sin(15.5)
      expect(r.x, closeTo(12.45 + 0.3 * cos(radians(15.5)), 0.002));
      expect(r.z, closeTo(-0.85 - 0.3 * sin(radians(15.5)), 0.002));
      expect(r.y, closeTo(1.35, 0.001), reason: 'Y is unaffected by Y-rotation');
    });

    test('Y offset stays in Y regardless of wall rotation', () {
      final m = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 30.0);
      final r = ARMath.localToGlobalBlueprint(
          anchorBlueprintMatrix: m, localOffset: Vector3(0, 0.5, 0));
      expectV3Near(r, Vector3(5.0, 2.0, 0.0),
          reason: 'Y offset unaffected by Y-rotation');
    });

  });

}
