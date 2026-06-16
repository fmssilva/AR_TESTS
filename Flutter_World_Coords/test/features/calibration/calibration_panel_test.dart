import 'package:ar_wall_app/core/ar/ar_session_bridge.dart';
import 'package:ar_wall_app/core/ar/models/anchor_blueprint.dart';
import 'package:ar_wall_app/core/ar/models/poi_model.dart';
import 'package:ar_wall_app/features/calibration/cubit/calibration_cubit.dart';
import 'package:ar_wall_app/features/calibration/presentation/calibration_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

class _FakeARSessionBridge extends ARSessionBridge {
  @override
  Future<void> setCalibrationViewState({
    required bool enabled,
    String? referenceAnchorId,
    String? editedAnchorId,
    bool showReferenceImage = false,
    double referenceImageOpacity = 0.0,
    bool freezeCorrection = false,
  }) async {}

  @override
  Future<void> updateAnchorBlueprint({
    required String id,
    required double x,
    required double y,
    required double z,
    required double yawDegrees,
    double? physicalWidthMeters,
  }) async {}

  @override
  Future<void> updatePOIBlueprint({
    required String id,
    required double x,
    required double y,
    required double z,
  }) async {}
}

void main() {
  testWidgets('CalibrationPanel selects anchors and switches to POIs tab',
      (tester) async {
    final cubit = CalibrationCubit(bridge: _FakeARSessionBridge());
    final anchors = [
      AnchorBlueprint(
        id: 'anchor_01',
        imageAssetName: 'anchor_01',
        physicalWidthMeters: 1.0,
        blueprintPosition: Vector3.zero(),
        blueprintYawDegrees: 0.0,
      ),
      AnchorBlueprint(
        id: 'anchor_02',
        imageAssetName: 'anchor_02',
        physicalWidthMeters: 0.8,
        blueprintPosition: Vector3(1, 0, 0),
        blueprintYawDegrees: 15.0,
      ),
    ];
    final pois = [
      POIModel(
        id: 'poi_01',
        label: 'POI One',
        description: 'Test POI',
        blueprintPosition: Vector3.zero(),
        iconName: 'poi',
        nearestAnchorId: 'anchor_01',
      ),
    ];
    cubit.syncConfig(anchors: anchors, pois: pois);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: CalibrationPanel(anchors: anchors, pois: pois),
          ),
        ),
      ),
    );

    expect(find.text('Calibration'), findsOneWidget);
    expect(find.text('anchor_01'), findsOneWidget);
    expect(find.text('Freeze correction'), findsOneWidget);

    await tester.tap(find.text('Ref'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('anchor_01'));
    await tester.pump();

    expect(cubit.state.referenceAnchorId, 'anchor_01');
    expect(find.text('Yaw'), findsOneWidget);

    await tester.tap(find.text('Anchors'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('anchor_02'));
    await tester.pump();

    expect(cubit.state.editedAnchorId, 'anchor_02');

    await tester.tap(find.text('POIs'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.textContaining('poi_01'), findsOneWidget);

    await cubit.close();
  });
}