import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../../../core/ar/models/anchor_blueprint.dart';
import '../../../core/ar/models/poi_model.dart';
import '../../../core/logging/file_logger.dart';
import '../cubit/calibration_cubit.dart';
import '../cubit/calibration_state.dart';
import 'widgets/increment_control_row.dart';

enum _CalibrationTab { reference, anchors, pois }

class CalibrationPanel extends StatefulWidget {
  const CalibrationPanel({
    super.key,
    required this.anchors,
    required this.pois,
  });

  final List<AnchorBlueprint> anchors;
  final List<POIModel> pois;

  @override
  State<CalibrationPanel> createState() => _CalibrationPanelState();
}

class _CalibrationPanelState extends State<CalibrationPanel> {
  _CalibrationTab _tab = _CalibrationTab.reference;

  // Build the calibration side panel.
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalibrationCubit, CalibrationState>(
      builder: (context, state) {
        final cubit = context.read<CalibrationCubit>();

        return Container(
          width: 290,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x884FC3F7), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Calibration',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              _OpacitySelector(
                selectedOpacity: state.referenceImageOpacity,
                onSelected: cubit.setReferenceImageOpacity,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: cubit.toggleFreezeCorrection,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: state.freezeCorrection
                            ? const Color(0x2234C759)
                            : Colors.transparent,
                        side: BorderSide(
                          color: state.freezeCorrection
                              ? const Color(0xFF34C759)
                              : Colors.white24,
                        ),
                        foregroundColor: state.freezeCorrection
                            ? const Color(0xFF34C759)
                            : Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        state.freezeCorrection
                            ? 'Unfreeze correction'
                            : 'Freeze correction',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _tabButton(
                      label: 'Ref',
                      isSelected: _tab == _CalibrationTab.reference,
                      onPressed: () {
                        FileLogger.log('[CALIBRATION_TAB] reference');
                        setState(() => _tab = _CalibrationTab.reference);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _tabButton(
                      label: 'Anchors',
                      isSelected: _tab == _CalibrationTab.anchors,
                      onPressed: () {
                        FileLogger.log('[CALIBRATION_TAB] anchors');
                        setState(() => _tab = _CalibrationTab.anchors);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _tabButton(
                      label: 'POIs',
                      isSelected: _tab == _CalibrationTab.pois,
                      onPressed: () {
                        FileLogger.log('[CALIBRATION_TAB] pois');
                        setState(() => _tab = _CalibrationTab.pois);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: switch (_tab) {
                  _CalibrationTab.reference => _ReferenceAnchorList(anchors: widget.anchors),
                  _CalibrationTab.anchors => _EditableAnchorList(anchors: widget.anchors),
                  _CalibrationTab.pois => _PoiList(pois: widget.pois),
                },
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: SingleChildScrollView(
                  child: switch (_tab) {
                    _CalibrationTab.reference => _ReferenceAnchorControls(cubit: cubit, state: state),
                    _CalibrationTab.anchors => _AnchorControls(cubit: cubit, state: state),
                    _CalibrationTab.pois => _PoiControls(cubit: cubit, state: state),
                  },
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: state.hasChanges ? cubit.logAdjustments : null,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Colors.white24),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Log adjustments'),
              ),
              if (state.lastAdjustmentLog != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.lastAdjustmentLog!,
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReferenceAnchorList extends StatelessWidget {
  const _ReferenceAnchorList({required this.anchors});

  final List<AnchorBlueprint> anchors;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalibrationCubit, CalibrationState>(
      builder: (context, state) {
        final cubit = context.read<CalibrationCubit>();
        return ListView.separated(
          itemCount: anchors.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final anchor = anchors[index];
            final isSelected = state.referenceAnchorId == anchor.id;
            return OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: isSelected ? const Color(0xFF34C759) : Colors.white24,
                ),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onPressed: () => cubit.selectReferenceAnchor(anchor.id),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(anchor.id, style: const TextStyle(fontSize: 12)),
              ),
            );
          },
        );
      },
    );
  }
}

class _EditableAnchorList extends StatelessWidget {
  const _EditableAnchorList({required this.anchors});

  final List<AnchorBlueprint> anchors;

  // Build the selectable anchor list.
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalibrationCubit, CalibrationState>(
      builder: (context, state) {
        final cubit = context.read<CalibrationCubit>();
        return ListView.separated(
          itemCount: anchors.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final anchor = anchors[index];
            final isReference = state.referenceAnchorId == anchor.id;
            final isSelected = state.editedAnchorId == anchor.id;
            return OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: isReference
                      ? const Color(0xFF34C759)
                      : isSelected
                          ? const Color(0xFF4FC3F7)
                          : Colors.white24,
                ),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onPressed: isReference ? null : () => cubit.selectEditedAnchor(anchor.id),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${anchor.id}${isReference ? ' | ref locked' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PoiList extends StatelessWidget {
  const _PoiList({required this.pois});

  final List<POIModel> pois;

  // Build the selectable POI list.
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalibrationCubit, CalibrationState>(
      builder: (context, state) {
        final cubit = context.read<CalibrationCubit>();
        return ListView.separated(
          itemCount: pois.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final poi = pois[index];
            final isSelected = state.selectedPoiId == poi.id;
            return OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: isSelected ? const Color(0xFFEF5350) : Colors.white24,
                ),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onPressed: state.referenceAnchorId == null
                  ? null
                  : () {
                      cubit.selectPoi(poi.id);
                    },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${poi.id} | ${poi.label}', style: const TextStyle(fontSize: 12)),
              ),
            );
          },
        );
      },
    );
  }
}

class _AnchorControls extends StatelessWidget {
  const _AnchorControls({required this.cubit, required this.state});

  final CalibrationCubit cubit;
  final CalibrationState state;

  // Build the anchor adjustment controls.
  @override
  Widget build(BuildContext context) {
    if (state.referenceAnchorId == null) {
      return const Text(
        'Select a reference anchor first, then choose an anchor to fit against that locked world.',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      );
    }

    final anchorId = state.editedAnchorId;
    if (anchorId == null) {
      return const Text(
        'Select an anchor to fit while the reference anchor keeps the world stable.',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      );
    }

    final anchor = cubit.adjustedAnchorById(anchorId)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(anchor.id, style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 8),
        _vectorControls(
          position: anchor.blueprintPosition,
          onDelta: (delta) => cubit.nudgeAnchorTranslation(anchorId: anchorId, delta: delta),
        ),
        const SizedBox(height: 10),
        IncrementControlRow(
          label: 'Yaw',
          valueLabel: anchor.blueprintYawDegrees.toStringAsFixed(2),
          decrements: [
            _stepButton(label: '-5', onPressed: () => cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: -5.0)),
            _stepButton(label: '-1', onPressed: () => cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: -1.0)),
          ],
          increments: [
            _stepButton(label: '+1', onPressed: () => cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: 1.0)),
            _stepButton(label: '+5', onPressed: () => cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: 5.0)),
          ],
        ),
        const SizedBox(height: 10),
        IncrementControlRow(
          label: 'Width',
          valueLabel: anchor.physicalWidthMeters.toStringAsFixed(3),
          decrements: [
            _stepButton(label: '-5', onPressed: () => cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: -0.05)),
            _stepButton(label: '-1', onPressed: () => cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: -0.01)),
          ],
          increments: [
            _stepButton(label: '+1', onPressed: () => cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: 0.01)),
            _stepButton(label: '+5', onPressed: () => cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: 0.05)),
          ],
        ),
      ],
    );
  }
}

class _ReferenceAnchorControls extends StatelessWidget {
  const _ReferenceAnchorControls({required this.cubit, required this.state});

  final CalibrationCubit cubit;
  final CalibrationState state;

  @override
  Widget build(BuildContext context) {
    final anchorId = state.referenceAnchorId;
    if (anchorId == null) {
      return const Text(
        'Select the anchor that should define the corrected world frame. Freeze correction after tracking settles, then switch to Anchors or POIs to edit within that stable world.',
        style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.35),
      );
    }

    final anchor = cubit.adjustedAnchorById(anchorId)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(anchor.id, style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 8),
        const Text(
          'Reference anchor drives the solved world frame. These controls intentionally move the world correction. Use Anchors and POIs for local edits that should not move the world origin.',
          style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.35),
        ),
        const SizedBox(height: 10),
        _vectorControls(
          position: anchor.blueprintPosition,
          onDelta: (delta) => cubit.nudgeAnchorTranslation(anchorId: anchorId, delta: delta),
        ),
        const SizedBox(height: 10),
        IncrementControlRow(
          label: 'Yaw',
          valueLabel: anchor.blueprintYawDegrees.toStringAsFixed(2),
          decrements: [
            _stepButton(label: '-5', onPressed: () => cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: -5.0)),
            _stepButton(label: '-1', onPressed: () => cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: -1.0)),
          ],
          increments: [
            _stepButton(label: '+1', onPressed: () => cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: 1.0)),
            _stepButton(label: '+5', onPressed: () => cubit.nudgeAnchorYaw(anchorId: anchorId, deltaDegrees: 5.0)),
          ],
        ),
        const SizedBox(height: 10),
        IncrementControlRow(
          label: 'Width',
          valueLabel: anchor.physicalWidthMeters.toStringAsFixed(3),
          decrements: [
            _stepButton(label: '-5', onPressed: () => cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: -0.05)),
            _stepButton(label: '-1', onPressed: () => cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: -0.01)),
          ],
          increments: [
            _stepButton(label: '+1', onPressed: () => cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: 0.01)),
            _stepButton(label: '+5', onPressed: () => cubit.nudgeAnchorWidth(anchorId: anchorId, deltaMeters: 0.05)),
          ],
        ),
      ],
    );
  }
}

class _PoiControls extends StatelessWidget {
  const _PoiControls({required this.cubit, required this.state});

  final CalibrationCubit cubit;
  final CalibrationState state;

  // Build the POI adjustment controls.
  @override
  Widget build(BuildContext context) {
    if (state.referenceAnchorId == null) {
      return const Text(
        'Select a reference anchor first so POIs are adjusted inside a stable corrected world.',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      );
    }

    final poiId = state.selectedPoiId;
    if (poiId == null) {
      return const Text(
        'Select a POI to move its blueprint position.',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      );
    }

    final position = cubit.adjustedPoiPositionById(poiId)!;
    return _vectorControls(
      position: position,
      onDelta: (delta) => cubit.nudgePoiTranslation(poiId: poiId, delta: delta),
    );
  }
}

Widget _vectorControls({
  required Vector3 position,
  required Future<void> Function(Vector3 delta) onDelta,
}) {
  return Column(
    children: [
      IncrementControlRow(
        label: 'X',
        valueLabel: position.x.toStringAsFixed(3),
        decrements: [
          _stepButton(label: '-5', onPressed: () => onDelta(Vector3(-0.05, 0, 0))),
          _stepButton(label: '-1', onPressed: () => onDelta(Vector3(-0.01, 0, 0))),
        ],
        increments: [
          _stepButton(label: '+1', onPressed: () => onDelta(Vector3(0.01, 0, 0))),
          _stepButton(label: '+5', onPressed: () => onDelta(Vector3(0.05, 0, 0))),
        ],
      ),
      const SizedBox(height: 8),
      IncrementControlRow(
        label: 'Y',
        valueLabel: position.y.toStringAsFixed(3),
        decrements: [
          _stepButton(label: '-5', onPressed: () => onDelta(Vector3(0, -0.05, 0))),
          _stepButton(label: '-1', onPressed: () => onDelta(Vector3(0, -0.01, 0))),
        ],
        increments: [
          _stepButton(label: '+1', onPressed: () => onDelta(Vector3(0, 0.01, 0))),
          _stepButton(label: '+5', onPressed: () => onDelta(Vector3(0, 0.05, 0))),
        ],
      ),
      const SizedBox(height: 8),
      IncrementControlRow(
        label: 'Z',
        valueLabel: position.z.toStringAsFixed(3),
        decrements: [
          _stepButton(label: '-5', onPressed: () => onDelta(Vector3(0, 0, -0.05))),
          _stepButton(label: '-1', onPressed: () => onDelta(Vector3(0, 0, -0.01))),
        ],
        increments: [
          _stepButton(label: '+1', onPressed: () => onDelta(Vector3(0, 0, 0.01))),
          _stepButton(label: '+5', onPressed: () => onDelta(Vector3(0, 0, 0.05))),
        ],
      ),
    ],
  );
}

Widget _stepButton({required String label, required VoidCallback onPressed}) {
  return OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(label),
  );
}

Widget _tabButton({
  required String label,
  required bool isSelected,
  required VoidCallback onPressed,
}) {
  return OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      backgroundColor: isSelected ? const Color(0x224FC3F7) : Colors.transparent,
      foregroundColor: isSelected ? const Color(0xFF4FC3F7) : Colors.white,
      side: BorderSide(
        color: isSelected ? const Color(0xFF4FC3F7) : Colors.white24,
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    child: Text(label),
  );
}

class _OpacitySelector extends StatelessWidget {
  const _OpacitySelector({
    required this.selectedOpacity,
    required this.onSelected,
  });

  final double selectedOpacity;
  final Future<void> Function(double opacity) onSelected;

  @override
  Widget build(BuildContext context) {
    const options = <double>[0.0, 0.25, 0.5, 0.75, 1.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Anchor overlay',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((opacity) {
            final isSelected = (selectedOpacity - opacity).abs() < 0.001;
            final label = '${(opacity * 100).round()}%';
            return OutlinedButton(
              onPressed: () => onSelected(opacity),
              style: OutlinedButton.styleFrom(
                backgroundColor:
                    isSelected ? const Color(0x224FC3F7) : Colors.transparent,
                foregroundColor:
                    isSelected ? const Color(0xFF4FC3F7) : Colors.white,
                side: BorderSide(
                  color: isSelected ? const Color(0xFF4FC3F7) : Colors.white24,
                ),
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(label),
            );
          }).toList(),
        ),
      ],
    );
  }
}