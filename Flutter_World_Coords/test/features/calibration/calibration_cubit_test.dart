import 'package:ar_wall_app/core/ar/ar_session_bridge.dart';
import 'package:ar_wall_app/core/ar/models/anchor_blueprint.dart';
import 'package:ar_wall_app/core/ar/models/poi_model.dart';
import 'package:ar_wall_app/features/calibration/cubit/calibration_cubit.dart';
import 'package:ar_wall_app/features/calibration/cubit/calibration_state.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

class _FakeARSessionBridge extends ARSessionBridge {
  final List<Map<String, Object?>> calibrationViewCalls = [];
  final List<Map<String, Object?>> anchorUpdateCalls = [];
  final List<Map<String, Object?>> poiUpdateCalls = [];

  @override
  Future<void> setCalibrationViewState({
    required bool enabled,
    String? referenceAnchorId,
    String? editedAnchorId,
    bool showReferenceImage = false,
    double referenceImageOpacity = 0.0,
    bool freezeCorrection = false,
  }) async {
    calibrationViewCalls.add({
      'enabled': enabled,
      'referenceAnchorId': referenceAnchorId,
      'editedAnchorId': editedAnchorId,
      'showReferenceImage': showReferenceImage,
      'referenceImageOpacity': referenceImageOpacity,
      'freezeCorrection': freezeCorrection,
    });
  }

  @override
  Future<void> updateAnchorBlueprint({
    required String id,
    required double x,
    required double y,
    required double z,
    required double yawDegrees,
    double? physicalWidthMeters,
  }) async {
    anchorUpdateCalls.add({
      'id': id,
      'x': x,
      'y': y,
      'z': z,
      'yawDegrees': yawDegrees,
      'physicalWidthMeters': physicalWidthMeters,
    });
  }

  @override
  Future<void> updatePOIBlueprint({
    required String id,
    required double x,
    required double y,
    required double z,
  }) async {
    poiUpdateCalls.add({
      'id': id,
      'x': x,
      'y': y,
      'z': z,
    });
  }
}

void main() {
  late _FakeARSessionBridge bridge;
  late CalibrationCubit cubit;
  const anchorId = 'anchor_01';
  const editedAnchorId = 'anchor_02';
  const poiId = 'poi_01';

  final anchors = [
    AnchorBlueprint(
      id: anchorId,
      imageAssetName: 'anchor_01',
      physicalWidthMeters: 1.0,
      blueprintPosition: Vector3(1.0, 2.0, 3.0),
      blueprintYawDegrees: 90.0,
    ),
    AnchorBlueprint(
      id: editedAnchorId,
      imageAssetName: editedAnchorId,
      physicalWidthMeters: 0.75,
      blueprintPosition: Vector3(4.0, 5.0, 6.0),
      blueprintYawDegrees: 15.0,
    ),
  ];
  final pois = [
    POIModel(
      id: poiId,
      label: 'POI',
      description: 'Test POI',
      blueprintPosition: Vector3(0.5, 0.6, 0.7),
      iconName: 'POI',
      nearestAnchorId: anchorId,
    ),
  ];

  setUp(() {
    bridge = _FakeARSessionBridge();
    cubit = CalibrationCubit(bridge: bridge)
      ..syncConfig(anchors: anchors, pois: pois);
  });

  tearDown(() async {
    await cubit.close();
  });

  blocTest<CalibrationCubit, CalibrationState>(
    'toggleCalibration emits enabled state and pushes view state',
    build: () => cubit,
    act: (cubit) => cubit.toggleCalibration(),
    expect: () => [isA<CalibrationState>().having((s) => s.isCalibrating, 'isCalibrating', isTrue)],
    verify: (_) {
      expect(bridge.calibrationViewCalls.single['enabled'], isTrue);
    },
  );

  blocTest<CalibrationCubit, CalibrationState>(
    'toggleFreezeCorrection pushes frozen state to native view state',
    build: () => cubit,
    seed: () => const CalibrationState(isCalibrating: true),
    act: (cubit) => cubit.toggleFreezeCorrection(),
    expect: () => [
      isA<CalibrationState>().having((s) => s.freezeCorrection, 'freezeCorrection', isTrue),
    ],
    verify: (_) {
      expect(bridge.calibrationViewCalls.single['freezeCorrection'], isTrue);
    },
  );

  blocTest<CalibrationCubit, CalibrationState>(
    'selectReferenceAnchor locks one anchor in native view state',
    build: () => cubit,
    seed: () => const CalibrationState(isCalibrating: true),
    act: (cubit) => cubit.selectReferenceAnchor(anchorId),
    expect: () => [
      isA<CalibrationState>()
          .having((s) => s.referenceAnchorId, 'referenceAnchorId', anchorId)
          .having((s) => s.selectedPoiId, 'selectedPoiId', isNull),
    ],
    verify: (_) {
      expect(bridge.calibrationViewCalls.single['referenceAnchorId'], anchorId);
    },
  );

  blocTest<CalibrationCubit, CalibrationState>(
    'selectEditedAnchor keeps a separate editable anchor target',
    build: () => cubit,
    seed: () => const CalibrationState(isCalibrating: true, referenceAnchorId: anchorId),
    act: (cubit) => cubit.selectEditedAnchor(editedAnchorId),
    expect: () => [
      isA<CalibrationState>()
          .having((s) => s.referenceAnchorId, 'referenceAnchorId', anchorId)
          .having((s) => s.editedAnchorId, 'editedAnchorId', editedAnchorId),
    ],
    verify: (_) {
      expect(bridge.calibrationViewCalls.single['editedAnchorId'], editedAnchorId);
    },
  );

  test('selectEditedAnchor rejects reusing the reference anchor', () async {
    await cubit.toggleCalibration();
    await cubit.selectReferenceAnchor(anchorId);
    bridge.calibrationViewCalls.clear();

    await cubit.selectEditedAnchor(anchorId);

    expect(cubit.state.editedAnchorId, isNull);
    expect(bridge.calibrationViewCalls, isEmpty);
  });

  test('nudgeAnchorTranslation sends adjusted blueprint coordinates', () async {
    await cubit.nudgeAnchorTranslation(
      anchorId: anchorId,
      delta: Vector3(0.1, -0.2, 0.3),
    );

    final call = bridge.anchorUpdateCalls.single;
    expect(call['id'], anchorId);
    expect(call['x'], closeTo(1.1, 0.0001));
    expect(call['y'], closeTo(1.8, 0.0001));
    expect(call['z'], closeTo(3.3, 0.0001));
    expect(call['yawDegrees'], 90.0);
    expect(call['physicalWidthMeters'], 1.0);
  });

  test('nudgePoiTranslation sends adjusted blueprint coordinates', () async {
    await cubit.nudgePoiTranslation(
      poiId: poiId,
      delta: Vector3(-0.1, 0.2, 0.05),
    );

    final call = bridge.poiUpdateCalls.single;
    expect(call['id'], poiId);
    expect(call['x'], closeTo(0.4, 0.0001));
    expect(call['y'], closeTo(0.8, 0.0001));
    expect(call['z'], closeTo(0.75, 0.0001));
  });

  test('selectPoi keeps the existing reference anchor and selects the POI', () async {
    await cubit.toggleCalibration();
    await cubit.selectReferenceAnchor(anchorId);
    bridge.calibrationViewCalls.clear();

    await cubit.selectPoi(poiId);

    expect(cubit.state.selectedPoiId, poiId);
    expect(cubit.state.referenceAnchorId, anchorId);
    expect(bridge.calibrationViewCalls.single['referenceAnchorId'], anchorId);
  });

  test('selectPoi rejects selection before a reference anchor exists', () async {
    await cubit.selectPoi(poiId);

    expect(cubit.state.selectedPoiId, isNull);
    expect(cubit.state.referenceAnchorId, isNull);
    expect(bridge.calibrationViewCalls, isEmpty);
  });

  test('buildAdjustmentLog includes tagged anchor and POI lines', () async {
    await cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: 5.0);
    await cubit.nudgePoiTranslation(
      poiId: poiId,
      delta: Vector3(0.0, 0.1, 0.0),
    );

    final logText = cubit.buildAdjustmentLog();

    expect(logText, contains('[CALIBRATION_ADJUSTMENTS_BEGIN]'));
    expect(logText, contains('[CALIBRATION_ANCHOR] id=$anchorId'));
    expect(logText, contains('yaw=95.0000'));
    expect(logText, contains('width=1.0000'));
    expect(logText, contains('[CALIBRATION_POI] id=$poiId'));
    expect(logText, contains('[CALIBRATION_ADJUSTMENTS_END]'));
  });

  test('nudgeAnchorWidth sends adjusted width for border and export updates', () async {
    await cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: 0.05);

    final call = bridge.anchorUpdateCalls.single;
    expect(call['physicalWidthMeters'], closeTo(1.05, 0.0001));
  });

  test('buildAdjustmentJsonLine emits copyable config-shaped payload', () async {
    await cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: 0.05);
    await cubit.nudgePoiTranslation(
      poiId: poiId,
      delta: Vector3(0.0, 0.1, 0.0),
    );

    final jsonLine = cubit.buildAdjustmentJsonLine();

    expect(jsonLine, contains('"anchors"'));
    expect(jsonLine, contains('"physical_width_meters":1.05'));
    expect(jsonLine, contains('"pois"'));
    expect(jsonLine, contains('"nearest_anchor_id":"$anchorId"'));
  });
}