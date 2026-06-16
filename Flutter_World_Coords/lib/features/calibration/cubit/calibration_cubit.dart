import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math_64.dart';
import '../../../core/ar/ar_session_bridge.dart';
import '../../../core/ar/models/anchor_blueprint.dart';
import '../../../core/ar/models/poi_model.dart';
import '../../../core/logging/file_logger.dart';
import 'calibration_state.dart';

class CalibrationCubit extends Cubit<CalibrationState> {
  CalibrationCubit({required ARSessionBridge bridge})
      : _bridge = bridge,
        super(const CalibrationState());

  final ARSessionBridge _bridge;
  Map<String, AnchorBlueprint> _anchorsById = const {};
  Map<String, POIModel> _poisById = const {};

  // Synchronize loaded config with the calibration feature.
  void syncConfig({
    required List<AnchorBlueprint> anchors,
    required List<POIModel> pois,
  }) {
    _anchorsById = {for (final anchor in anchors) anchor.id: anchor};
    _poisById = {for (final poi in pois) poi.id: poi};
    FileLogger.log(
      '[CALIBRATION_SYNC] anchors=${anchors.length} pois=${pois.length}',
    );

    final referenceAnchorId = state.referenceAnchorId;
    final editedAnchorId = state.editedAnchorId;
    final selectedPoiId = state.selectedPoiId;
    emit(state.copyWith(
      clearReferenceAnchor:
        referenceAnchorId != null && !_anchorsById.containsKey(referenceAnchorId),
      clearEditedAnchor:
        editedAnchorId != null && !_anchorsById.containsKey(editedAnchorId),
      clearSelectedPoi:
          selectedPoiId != null && !_poisById.containsKey(selectedPoiId),
    ));
  }

  // Toggle calibration mode on/off.
  Future<void> toggleCalibration() async {
    final nextValue = !state.isCalibrating;
    emit(state.copyWith(
      isCalibrating: nextValue,
      freezeCorrection: nextValue ? state.freezeCorrection : false,
      clearReferenceAnchor: !nextValue,
      clearEditedAnchor: !nextValue,
      clearSelectedPoi: !nextValue,
      clearLastAdjustmentLog: !nextValue,
    ));
    await FileLogger.log(
      '[CALIBRATION_MODE] enabled=$nextValue reference_anchor=${state.referenceAnchorId} edited_anchor=${state.editedAnchorId} selected_poi=${state.selectedPoiId}',
    );
    await _pushCalibrationViewState();
  }

  // Freeze/unfreeze the currently solved world correction so the user can move
  // the camera without the world frame continuing to drift.
  Future<void> toggleFreezeCorrection() async {
    final nextValue = !state.freezeCorrection;
    emit(state.copyWith(freezeCorrection: nextValue));
    await FileLogger.log('[CALIBRATION_FREEZE] enabled=$nextValue reference_anchor=${state.referenceAnchorId}');
    await _pushCalibrationViewState();
  }

  // Select one reference anchor and lock native correction to it.
  Future<void> selectReferenceAnchor(String anchorId) async {
    assert(_anchorsById.containsKey(anchorId));
    final clearEditedAnchor = state.editedAnchorId == anchorId;
    emit(state.copyWith(
      referenceAnchorId: anchorId,
      clearEditedAnchor: clearEditedAnchor,
    ));
    await FileLogger.log(
      '[CALIBRATION_SELECT_REFERENCE] id=$anchorId related_pois=${_poisById.values.where((poi) => poi.nearestAnchorId == anchorId).length} cleared_edited=$clearEditedAnchor',
    );
    await _pushCalibrationViewState();
  }

  // Select one anchor to edit while the reference anchor keeps the world stable.
  Future<void> selectEditedAnchor(String anchorId) async {
    assert(_anchorsById.containsKey(anchorId));
    final referenceAnchorId = state.referenceAnchorId;
    if (referenceAnchorId == null) {
      await FileLogger.log(
        '[CALIBRATION_SELECT_EDIT_ANCHOR_REJECTED] id=$anchorId reason=missing_reference',
      );
      return;
    }
    if (referenceAnchorId == anchorId) {
      await FileLogger.log(
        '[CALIBRATION_SELECT_EDIT_ANCHOR_REJECTED] id=$anchorId reason=matches_reference',
      );
      return;
    }
    emit(state.copyWith(
      editedAnchorId: anchorId,
      clearSelectedPoi: true,
    ));
    await FileLogger.log(
      '[CALIBRATION_SELECT_EDIT_ANCHOR] id=$anchorId reference_anchor=$referenceAnchorId',
    );
    await _pushCalibrationViewState();
  }

  // Select one POI for Flutter-side highlighting and movement.
  Future<void> selectPoi(String poiId) async {
    assert(_poisById.containsKey(poiId));
    final poi = _poisById[poiId]!;
    final referenceAnchorId = state.referenceAnchorId;
    if (referenceAnchorId == null) {
      await FileLogger.log(
        '[CALIBRATION_SELECT_POI_REJECTED] id=$poiId reason=missing_reference nearest_anchor=${poi.nearestAnchorId}',
      );
      return;
    }
    emit(state.copyWith(
      referenceAnchorId: referenceAnchorId,
      selectedPoiId: poiId,
      clearEditedAnchor: true,
    ));
    await FileLogger.log(
      '[CALIBRATION_SELECT_POI] id=$poiId reference_anchor=$referenceAnchorId',
    );
    await _pushCalibrationViewState();
  }

  // Control whether anchor reference images are overlaid and at what opacity.
  Future<void> setReferenceImageOpacity(double opacity) async {
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    emit(state.copyWith(
      showReferenceImage: clampedOpacity > 0.0,
      referenceImageOpacity: clampedOpacity,
    ));
    await FileLogger.log(
      '[CALIBRATION_REF_IMAGE] show=${clampedOpacity > 0.0} opacity=${_f(clampedOpacity)}',
    );
    await _pushCalibrationViewState();
  }

  // Resolve which POIs should be highlighted for the current calibration context.
  Set<String> highlightedPoiIds() {
    if (state.selectedPoiId != null) {
      return {state.selectedPoiId!};
    }
    final anchorId = state.editedAnchorId ?? state.referenceAnchorId;
    if (anchorId == null) {
      return const {};
    }
    return _poisById.values
        .where((poi) => poi.nearestAnchorId == anchorId)
        .map((poi) => poi.id)
        .toSet();
  }

  // Adjust one anchor in blueprint-space meters.
  Future<void> nudgeAnchorTranslation({
    required String anchorId,
    required Vector3 delta,
  }) async {
    final current = state.anchorTranslationDeltas[anchorId] ?? Vector3.zero();
    final updatedDeltas = Map<String, Vector3>.from(state.anchorTranslationDeltas)
      ..[anchorId] = (Vector3.copy(current)..add(delta));
    emit(state.copyWith(anchorTranslationDeltas: updatedDeltas));

    final updatedAnchor = adjustedAnchorById(anchorId);
    assert(updatedAnchor != null);
    final role = _anchorRole(anchorId);
    await FileLogger.log(
      '[CALIBRATION_NUDGE_ANCHOR_XYZ] role=$role id=$anchorId dx=${_f(delta.x)} dy=${_f(delta.y)} dz=${_f(delta.z)} -> x=${_f(updatedAnchor!.blueprintPosition.x)} y=${_f(updatedAnchor.blueprintPosition.y)} z=${_f(updatedAnchor.blueprintPosition.z)} freeze=${state.freezeCorrection}',
    );
    await _bridge.updateAnchorBlueprint(
      id: anchorId,
      x: updatedAnchor.blueprintPosition.x,
      y: updatedAnchor.blueprintPosition.y,
      z: updatedAnchor.blueprintPosition.z,
      yawDegrees: updatedAnchor.blueprintYawDegrees,
      physicalWidthMeters: updatedAnchor.physicalWidthMeters,
    );
  }

  // Adjust one anchor yaw in blueprint-space degrees.
  Future<void> nudgeAnchorYaw({
    required String anchorId,
    required double deltaDegrees,
  }) async {
    final current = state.anchorYawDeltas[anchorId] ?? 0.0;
    final updatedYawDeltas = Map<String, double>.from(state.anchorYawDeltas)
      ..[anchorId] = current + deltaDegrees;
    emit(state.copyWith(anchorYawDeltas: updatedYawDeltas));

    final updatedAnchor = adjustedAnchorById(anchorId);
    assert(updatedAnchor != null);
    final role = _anchorRole(anchorId);
    await FileLogger.log(
      '[CALIBRATION_NUDGE_ANCHOR_YAW] role=$role id=$anchorId delta=${_f(deltaDegrees)} -> yaw=${_f(updatedAnchor!.blueprintYawDegrees)} freeze=${state.freezeCorrection}',
    );
    await _bridge.updateAnchorBlueprint(
      id: anchorId,
      x: updatedAnchor.blueprintPosition.x,
      y: updatedAnchor.blueprintPosition.y,
      z: updatedAnchor.blueprintPosition.z,
      yawDegrees: updatedAnchor.blueprintYawDegrees,
      physicalWidthMeters: updatedAnchor.physicalWidthMeters,
    );
  }

  // Adjust one anchor width in meters while preserving the image aspect ratio.
  Future<void> nudgeAnchorWidth({
    required String anchorId,
    required double deltaMeters,
  }) async {
    final current = state.anchorWidthDeltas[anchorId] ?? 0.0;
    final original = _anchorsById[anchorId];
    assert(original != null);
    final minWidthDelta = 0.05 - original!.physicalWidthMeters;
    final updatedWidthDeltas = Map<String, double>.from(state.anchorWidthDeltas)
      ..[anchorId] = (current + deltaMeters).clamp(minWidthDelta, 10.0);
    emit(state.copyWith(anchorWidthDeltas: updatedWidthDeltas));

    final updatedAnchor = adjustedAnchorById(anchorId);
    assert(updatedAnchor != null);
    final role = _anchorRole(anchorId);
    await FileLogger.log(
      '[CALIBRATION_NUDGE_ANCHOR_WIDTH] role=$role id=$anchorId delta=${_f(deltaMeters)} -> width=${_f(updatedAnchor!.physicalWidthMeters)} freeze=${state.freezeCorrection}',
    );
    await _bridge.updateAnchorBlueprint(
      id: anchorId,
      x: updatedAnchor.blueprintPosition.x,
      y: updatedAnchor.blueprintPosition.y,
      z: updatedAnchor.blueprintPosition.z,
      yawDegrees: updatedAnchor.blueprintYawDegrees,
      physicalWidthMeters: updatedAnchor.physicalWidthMeters,
    );
  }

  // Adjust one POI in blueprint-space meters.
  Future<void> nudgePoiTranslation({
    required String poiId,
    required Vector3 delta,
  }) async {
    final current = state.poiTranslationDeltas[poiId] ?? Vector3.zero();
    final updatedDeltas = Map<String, Vector3>.from(state.poiTranslationDeltas)
      ..[poiId] = (Vector3.copy(current)..add(delta));
    emit(state.copyWith(poiTranslationDeltas: updatedDeltas));

    final updatedPosition = adjustedPoiPositionById(poiId);
    assert(updatedPosition != null);
    await FileLogger.log(
      '[CALIBRATION_NUDGE_POI_XYZ] id=$poiId nearest_anchor=${_poisById[poiId]!.nearestAnchorId} reference_anchor=${state.referenceAnchorId} dx=${_f(delta.x)} dy=${_f(delta.y)} dz=${_f(delta.z)} -> x=${_f(updatedPosition!.x)} y=${_f(updatedPosition.y)} z=${_f(updatedPosition.z)} freeze=${state.freezeCorrection}',
    );
    await _bridge.updatePOIBlueprint(
      id: poiId,
      x: updatedPosition.x,
      y: updatedPosition.y,
      z: updatedPosition.z,
    );
  }

  // Build a plain-text adjustment log that is easy to capture from flutter run.
  String buildAdjustmentLog() {
    final lines = <String>['[CALIBRATION_ADJUSTMENTS_BEGIN]'];
    for (final anchorId in _anchorsById.keys) {
      final updatedAnchor = adjustedAnchorById(anchorId);
      final hasTranslation = state.anchorTranslationDeltas.containsKey(anchorId);
      final hasYaw = state.anchorYawDeltas.containsKey(anchorId);
      final hasWidth = state.anchorWidthDeltas.containsKey(anchorId);
      if (updatedAnchor == null || (!hasTranslation && !hasYaw && !hasWidth)) continue;
      lines.add(
        '[CALIBRATION_ANCHOR] id=${updatedAnchor.id} x=${_f(updatedAnchor.blueprintPosition.x)} y=${_f(updatedAnchor.blueprintPosition.y)} z=${_f(updatedAnchor.blueprintPosition.z)} yaw=${_f(updatedAnchor.blueprintYawDegrees)} width=${_f(updatedAnchor.physicalWidthMeters)}',
      );
    }

    for (final poiId in _poisById.keys) {
      final updatedPosition = adjustedPoiPositionById(poiId);
      if (updatedPosition == null || !state.poiTranslationDeltas.containsKey(poiId)) {
        continue;
      }
      lines.add(
        '[CALIBRATION_POI] id=$poiId ref_anchor=${_poisById[poiId]!.nearestAnchorId} x=${_f(updatedPosition.x)} y=${_f(updatedPosition.y)} z=${_f(updatedPosition.z)}',
      );
    }
    if (lines.length == 1) {
      lines.add('[CALIBRATION_ADJUSTMENTS_EMPTY]');
    }
    lines.add('[CALIBRATION_ADJUSTMENTS_END]');
    return lines.join('\n');
  }

  // Build a single-line JSON patch that can be pasted into config files by id.
  String buildAdjustmentJsonLine() {
    final anchors = <Map<String, Object?>>[];
    for (final anchorId in _anchorsById.keys) {
      final updatedAnchor = adjustedAnchorById(anchorId);
      final hasTranslation = state.anchorTranslationDeltas.containsKey(anchorId);
      final hasYaw = state.anchorYawDeltas.containsKey(anchorId);
      final hasWidth = state.anchorWidthDeltas.containsKey(anchorId);
      if (updatedAnchor == null || (!hasTranslation && !hasYaw && !hasWidth)) {
        continue;
      }
      anchors.add({
        'id': updatedAnchor.id,
        'image_asset_name': updatedAnchor.imageAssetName,
        'physical_width_meters': _round(updatedAnchor.physicalWidthMeters),
        'blueprint_position': {
          'x': _round(updatedAnchor.blueprintPosition.x),
          'y': _round(updatedAnchor.blueprintPosition.y),
          'z': _round(updatedAnchor.blueprintPosition.z),
        },
        'blueprint_yaw_degrees': _round(updatedAnchor.blueprintYawDegrees),
      });
    }

    final pois = <Map<String, Object?>>[];
    for (final poiId in _poisById.keys) {
      final original = _poisById[poiId];
      final updatedPosition = adjustedPoiPositionById(poiId);
      if (original == null ||
          updatedPosition == null ||
          !state.poiTranslationDeltas.containsKey(poiId)) {
        continue;
      }
      pois.add({
        'id': original.id,
        'label': original.label,
        'description': original.description,
        'icon_name': original.iconName,
        'nearest_anchor_id': original.nearestAnchorId,
        'blueprint_position': {
          'x': _round(updatedPosition.x),
          'y': _round(updatedPosition.y),
          'z': _round(updatedPosition.z),
        },
      });
    }

    return jsonEncode({
      'anchors': anchors,
      'pois': pois,
    });
  }

  // Log the current final adjustments in plain text for terminal capture.
  Future<void> logAdjustments() async {
    final logText = buildAdjustmentLog();
    emit(state.copyWith(lastAdjustmentLog: logText));
    await FileLogger.log('[CALIBRATION_EXPORT] requested');
    await FileLogger.log('[CALIBRATION_JSON] ${buildAdjustmentJsonLine()}');
    await FileLogger.log(logText);
  }

  // Read one anchor with all active deltas applied.
  AnchorBlueprint? adjustedAnchorById(String anchorId) {
    final original = _anchorsById[anchorId];
    if (original == null) return null;
    final translationDelta =
        state.anchorTranslationDeltas[anchorId] ?? Vector3.zero();
    final updatedPosition = Vector3.copy(original.blueprintPosition)
      ..add(translationDelta);
    final updatedYaw =
        original.blueprintYawDegrees + (state.anchorYawDeltas[anchorId] ?? 0.0);
    final updatedWidth = original.physicalWidthMeters +
        (state.anchorWidthDeltas[anchorId] ?? 0.0);
    return AnchorBlueprint(
      id: original.id,
      imageAssetName: original.imageAssetName,
      physicalWidthMeters: updatedWidth,
      blueprintPosition: updatedPosition,
      blueprintYawDegrees: updatedYaw,
    );
  }

  // Read one POI position with all active deltas applied.
  Vector3? adjustedPoiPositionById(String poiId) {
    final original = _poisById[poiId];
    if (original == null) return null;
    final translationDelta = state.poiTranslationDeltas[poiId] ?? Vector3.zero();
    return Vector3.copy(original.blueprintPosition)..add(translationDelta);
  }

  // Push the current calibration view state down to native.
  Future<void> _pushCalibrationViewState() async {
    await FileLogger.log(
      '[CALIBRATION_VIEW_STATE] enabled=${state.isCalibrating} frozen=${state.freezeCorrection} reference_anchor=${state.referenceAnchorId} edited_anchor=${state.editedAnchorId} selected_poi=${state.selectedPoiId} show_reference_image=${state.showReferenceImage} opacity=${_f(state.referenceImageOpacity)}',
    );
    await _bridge.setCalibrationViewState(
      enabled: state.isCalibrating,
      referenceAnchorId: state.referenceAnchorId,
      editedAnchorId: state.editedAnchorId,
      showReferenceImage: state.showReferenceImage,
      referenceImageOpacity: state.referenceImageOpacity,
      freezeCorrection: state.freezeCorrection,
    );
  }

  String _anchorRole(String anchorId) {
    if (state.referenceAnchorId == anchorId) {
      return 'reference_world';
    }
    if (state.editedAnchorId == anchorId) {
      return 'edited_local';
    }
    return 'unscoped';
  }

  static String _f(double value) => value.toStringAsFixed(4);

  static double _round(double value) => double.parse(value.toStringAsFixed(4));
}