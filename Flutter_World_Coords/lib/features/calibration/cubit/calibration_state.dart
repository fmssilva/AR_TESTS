import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

@immutable
class CalibrationState {
  final bool isCalibrating;
  final bool freezeCorrection;
  final String? referenceAnchorId;
  final String? editedAnchorId;
  final String? selectedPoiId;
  final Map<String, Vector3> anchorTranslationDeltas;
  final Map<String, double> anchorYawDeltas;
  final Map<String, double> anchorWidthDeltas;
  final Map<String, Vector3> poiTranslationDeltas;
  final bool showReferenceImage;
  final double referenceImageOpacity;
  final String? lastAdjustmentLog;

  const CalibrationState({
    this.isCalibrating = false,
    this.freezeCorrection = false,
    this.referenceAnchorId,
    this.editedAnchorId,
    this.selectedPoiId,
    this.anchorTranslationDeltas = const {},
    this.anchorYawDeltas = const {},
    this.anchorWidthDeltas = const {},
    this.poiTranslationDeltas = const {},
    this.showReferenceImage = false,
    this.referenceImageOpacity = 0.0,
    this.lastAdjustmentLog,
  });

  bool get hasChanges =>
      anchorTranslationDeltas.isNotEmpty ||
      anchorYawDeltas.isNotEmpty ||
      anchorWidthDeltas.isNotEmpty ||
      poiTranslationDeltas.isNotEmpty;

  CalibrationState copyWith({
    bool? isCalibrating,
    bool? freezeCorrection,
    String? referenceAnchorId,
    String? editedAnchorId,
    String? selectedPoiId,
    bool clearReferenceAnchor = false,
    bool clearEditedAnchor = false,
    bool clearSelectedPoi = false,
    Map<String, Vector3>? anchorTranslationDeltas,
    Map<String, double>? anchorYawDeltas,
    Map<String, double>? anchorWidthDeltas,
    Map<String, Vector3>? poiTranslationDeltas,
    bool? showReferenceImage,
    double? referenceImageOpacity,
    String? lastAdjustmentLog,
    bool clearLastAdjustmentLog = false,
  }) {
    return CalibrationState(
      isCalibrating: isCalibrating ?? this.isCalibrating,
      freezeCorrection: freezeCorrection ?? this.freezeCorrection,
      referenceAnchorId:
        clearReferenceAnchor ? null : (referenceAnchorId ?? this.referenceAnchorId),
      editedAnchorId:
        clearEditedAnchor ? null : (editedAnchorId ?? this.editedAnchorId),
      selectedPoiId: clearSelectedPoi ? null : (selectedPoiId ?? this.selectedPoiId),
      anchorTranslationDeltas:
          anchorTranslationDeltas ?? this.anchorTranslationDeltas,
      anchorYawDeltas: anchorYawDeltas ?? this.anchorYawDeltas,
        anchorWidthDeltas: anchorWidthDeltas ?? this.anchorWidthDeltas,
      poiTranslationDeltas: poiTranslationDeltas ?? this.poiTranslationDeltas,
      showReferenceImage: showReferenceImage ?? this.showReferenceImage,
      referenceImageOpacity:
          referenceImageOpacity ?? this.referenceImageOpacity,
      lastAdjustmentLog: clearLastAdjustmentLog
          ? null
          : (lastAdjustmentLog ?? this.lastAdjustmentLog),
    );
  }
}