import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../calibration/cubit/calibration_cubit.dart';
import '../../calibration/presentation/calibration_overlay.dart';
import '../../../core/ar/ar_native_view.dart';
import '../cubit/wall_view_cubit.dart';
import '../cubit/wall_view_state.dart';
import 'ar_overlay.dart';
import 'poi_detail_sheet.dart';

// Root screen: a full-screen Stack with the native AR camera view at the base,
// loading/error overlays in the middle, and the status HUD on top.
class WallViewportPage extends StatefulWidget {
  const WallViewportPage({super.key});

  @override
  State<WallViewportPage> createState() => _WallViewportPageState();
}

class _WallViewportPageState extends State<WallViewportPage> {
  @override
  void initState() {
    super.initState();
    // Load JSON config immediately — safe before PlatformView is ready.
    context.read<WallViewCubit>().loadConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocConsumer<WallViewCubit, WallViewState>(
        // Show the POI detail sheet whenever a tapped POI id becomes set.
        listenWhen: (_, current) =>
            current is WallViewReady && current.tappedPOIId != null,
        listener: (context, state) {
          if (state is WallViewReady && state.tappedPOI != null) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => POIDetailSheet(poi: state.tappedPOI!),
            ).whenComplete(() {
              if (context.mounted) {
                context.read<WallViewCubit>().dismissPOIDetail();
              }
            });
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              // Base layer: full-screen native ARCore surface.
              // initializeChannels() fires once the PlatformView is created.
              Positioned.fill(
                child: ARNativeView(
                  onViewCreated: () {
                    debugPrint('[WallViewport] PlatformView onViewCreated fired — calling initializeChannels');
                    context.read<WallViewCubit>().initializeChannels();
                  },
                ),
              ),

              // Loading indicator while config is being read.
              if (state is WallViewLoading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),

              // Error display on session failure.
              if (state is WallViewError)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'AR Error: ${state.message}',
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              // HUD overlay: anchor tracking status chip + gizmo + POI dots.
              if (state is WallViewReady)
                AROverlay(
                  activeAnchorId: state.activeAnchorId,
                  detectedCount: state.detectedAnchorIds.length,
                  overlayData: state.overlayData,
                  anchors: state.anchors,
                  isCalibrating: context.select(
                    (CalibrationCubit cubit) => cubit.state.isCalibrating,
                  ),
                  isCorrectionFrozen: context.select(
                    (CalibrationCubit cubit) => cubit.state.freezeCorrection,
                  ),
                  referenceAnchorId: context.select(
                    (CalibrationCubit cubit) => cubit.state.referenceAnchorId,
                  ),
                  editedAnchorId: context.select(
                    (CalibrationCubit cubit) => cubit.state.editedAnchorId,
                  ),
                  selectedPoiId: context.select(
                    (CalibrationCubit cubit) => cubit.state.selectedPoiId,
                  ),
                  highlightedPoiIds: context.select(
                    (CalibrationCubit cubit) => cubit.highlightedPoiIds(),
                  ),
                  referenceImageOpacity: context.select(
                    (CalibrationCubit cubit) => cubit.state.isCalibrating
                        ? cubit.state.referenceImageOpacity
                        : 0.0,
                  ),
                ),

              if (state is WallViewReady)
                CalibrationOverlay(
                  anchors: state.anchors,
                  pois: state.pois,
                ),
            ],
          );
        },
      ),
    );
  }
}
