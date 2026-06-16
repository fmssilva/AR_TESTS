import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/ar/models/anchor_blueprint.dart';
import '../../../core/ar/models/poi_model.dart';
import '../cubit/calibration_cubit.dart';
import '../cubit/calibration_state.dart';
import 'calibration_panel.dart';

class CalibrationOverlay extends StatefulWidget {
  const CalibrationOverlay({
    super.key,
    required this.anchors,
    required this.pois,
  });

  final List<AnchorBlueprint> anchors;
  final List<POIModel> pois;

  @override
  State<CalibrationOverlay> createState() => _CalibrationOverlayState();
}

class _CalibrationOverlayState extends State<CalibrationOverlay> {
  @override
  void initState() {
    super.initState();
    _syncConfig();
  }

  @override
  void didUpdateWidget(covariant CalibrationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.anchors, widget.anchors) ||
        !listEquals(oldWidget.pois, widget.pois)) {
      _syncConfig();
    }
  }

  void _syncConfig() {
    context.read<CalibrationCubit>().syncConfig(
          anchors: widget.anchors,
          pois: widget.pois,
        );
  }

  // Build the top-most calibration overlay shown only in debug builds.
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<CalibrationCubit, CalibrationState>(
      builder: (context, state) {
        final cubit = context.read<CalibrationCubit>();
        return Stack(
          children: [
            Positioned(
              top: 56,
              right: 16,
              child: OutlinedButton(
                onPressed: cubit.toggleCalibration,
                style: OutlinedButton.styleFrom(
                  backgroundColor: state.isCalibrating
                      ? const Color(0x224FC3F7)
                      : Colors.transparent,
                  foregroundColor:
                      state.isCalibrating ? const Color(0xFF4FC3F7) : Colors.white,
                  side: BorderSide(
                    color: state.isCalibrating
                        ? const Color(0xFF4FC3F7)
                        : Colors.white24,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(state.isCalibrating ? 'Close calibration' : 'Calibrate'),
              ),
            ),
            if (state.isCalibrating)
              Positioned(
                top: 108,
                right: 8,
                bottom: 24,
                child: CalibrationPanel(
                  anchors: widget.anchors,
                  pois: widget.pois,
                ),
              ),
          ],
        );
      },
    );
  }
}