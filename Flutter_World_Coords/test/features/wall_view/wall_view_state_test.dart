import 'package:ar_wall_app/core/ar/models/overlay_data.dart';
import 'package:ar_wall_app/core/ar/models/anchor_blueprint.dart';
import 'package:ar_wall_app/core/ar/models/poi_model.dart';
import 'package:ar_wall_app/features/wall_view/cubit/wall_view_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('WallViewReady.copyWith preserves or replaces overlay data as expected', () {
    const overlay = OverlayData(
      originX: 0.5,
      originY: 0.5,
      originVisible: true,
      axisXx: 0.6,
      axisXy: 0.5,
      axisXVisible: true,
      axisYx: 0.5,
      axisYy: 0.4,
      axisYVisible: true,
      axisZx: 0.5,
      axisZy: 0.6,
      axisZVisible: true,
      pois: [
        POIScreenPos(id: 'BL', label: 'BL', x: 0.4, y: 0.7),
      ],
      anchors: [],
    );

    final state = WallViewReady(
      anchors: [
        AnchorBlueprint(
          id: 'anchor_01',
          imageAssetName: 'anchor_01',
          physicalWidthMeters: 1.0,
          blueprintPosition: Vector3.zero(),
          blueprintYawDegrees: 0.0,
        ),
      ],
      pois: [
        POIModel(
          id: 'BL',
          label: 'BL',
          description: 'Bottom left',
          blueprintPosition: Vector3.zero(),
          iconName: 'BL',
          nearestAnchorId: 'anchor_01',
        ),
      ],
      overlayData: overlay,
    );

    final unchanged = state.copyWith();
    final replaced = state.copyWith(
      overlayData: const OverlayData(
        originX: double.nan,
        originY: double.nan,
        originVisible: false,
        axisXx: double.nan,
        axisXy: double.nan,
        axisXVisible: false,
        axisYx: double.nan,
        axisYy: double.nan,
        axisYVisible: false,
        axisZx: double.nan,
        axisZy: double.nan,
        axisZVisible: false,
        pois: [],
        anchors: [],
      ),
    );

    expect(unchanged.overlayData, same(state.overlayData));
    expect(replaced.overlayData?.pois, isEmpty);
    expect(replaced.pois, same(state.pois));
  });
}