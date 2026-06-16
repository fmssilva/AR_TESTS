import '../../../core/ar/models/overlay_data.dart';
import '../../../core/ar/models/anchor_blueprint.dart';
import '../../../core/ar/models/poi_model.dart';

// All possible states of the AR wall view session.
sealed class WallViewState {
  const WallViewState();
}

// Initial state: config files are loading and native view is being set up.
class WallViewLoading extends WallViewState {
  const WallViewLoading();
}

// Session is active. Holds all live tracking data for the UI to render.
class WallViewReady extends WallViewState {
  final List<AnchorBlueprint> anchors;
  final List<POIModel> pois;

  // Most recently detected anchor id - drives the status chip label.
  final String? activeAnchorId;

  // All anchors detected at least once this session - drives "X anchors found" counter.
  final Set<String> detectedAnchorIds;

  // Set when the user taps a POI billboard; cleared after sheet is dismissed.
  final String? tappedPOIId;

  // Latest 2D screen positions for the overlay painter (null before first detection).
  final OverlayData? overlayData;

  const WallViewReady({
    required this.anchors,
    required this.pois,
    this.activeAnchorId,
    this.detectedAnchorIds = const {},
    this.tappedPOIId,
    this.overlayData,
  });

  // Resolve the full POI data for the currently tapped node.
  POIModel? get tappedPOI =>
      tappedPOIId == null ? null : pois.firstWhere((p) => p.id == tappedPOIId);

  WallViewReady copyWith({
    String? activeAnchorId,
    Set<String>? detectedAnchorIds,
    String? tappedPOIId,
    bool clearTappedPOI = false,
    OverlayData? overlayData,
  }) {
    return WallViewReady(
      anchors: anchors,
      pois: pois,
      activeAnchorId: activeAnchorId ?? this.activeAnchorId,
      detectedAnchorIds: detectedAnchorIds ?? this.detectedAnchorIds,
      tappedPOIId: clearTappedPOI ? null : (tappedPOIId ?? this.tappedPOIId),
      overlayData: overlayData ?? this.overlayData,
    );
  }
}

// Session failed - shows error message to the user.
class WallViewError extends WallViewState {
  final String message;
  const WallViewError(this.message);
}
