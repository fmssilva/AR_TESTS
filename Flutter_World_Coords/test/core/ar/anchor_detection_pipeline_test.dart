import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnchorDetectionPipeline phase 2', () {
    test('ignores non FULL_TRACKING detections', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      pipeline.onDetection(
        _RawDetection(
          anchorId: 'A',
          trackingMethod: _TrackingMethod.lastKnownPose,
          pose: const _Pose.translation(1, 2, 3),
          distanceMeters: 1,
        ),
      );

      expect(world.appliedWorldPoses, isEmpty);
      expect(pipeline.visibleAnchorIds, isEmpty);
    });

    test('closes cycle when one anchor reaches 8 samples', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 7; index++) {
        pipeline.onDetection(_full('A', x: 1, distance: 1));
      }

      expect(world.appliedWorldPoses, isEmpty);

      pipeline.onDetection(_full('A', x: 1, distance: 1));

      expect(world.appliedWorldPoses, isEmpty);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 1, distance: 1));
      }

      expect(world.appliedWorldPoses, hasLength(1));
      expect(world.appliedWorldPoses.single.tx, closeTo(1, 1e-6));
      expect(pipeline.sampleCountFor('A'), 0);
    });

    test('only visible anchors with at least 4 samples are eligible', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
      }
      expect(world.appliedWorldPoses, isEmpty);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
      }
      expect(world.lastAppliedWorldPose!.tx, closeTo(0, 1e-6));

      world.clearApplied();

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
        if (index < 3) {
          pipeline.onDetection(_full('B', x: 10, distance: 1));
        }
      }

      expect(world.appliedWorldPoses, hasLength(1));
      expect(world.lastFusionWeights.keys, {'A'});
      expect(world.lastAppliedWorldPose!.tx, closeTo(0, 1e-6));
    });

    test('paused anchor is excluded from cycle even if it kept samples', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 4; index++) {
        pipeline.onDetection(_full('B', x: 10, distance: 1));
      }
      pipeline.onDetection(
        _RawDetection(
          anchorId: 'B',
          trackingMethod: _TrackingMethod.lastKnownPose,
          pose: const _Pose.translation(10, 0, 0),
          distanceMeters: 1,
        ),
      );

      for (var index = 0; index < 16; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
      }

      expect(world.lastFusionWeights.keys, {'A'});
      expect(world.lastAppliedWorldPose!.tx, closeTo(0, 1e-6));
      expect(pipeline.sampleCountFor('B'), 0);
    });

    test('normalizes fusion weights to 1.0', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
        pipeline.onDetection(_full('B', x: 10, distance: 2));
      }

      final weightSum = world.lastFusionWeights.values.fold<double>(0, (sum, value) => sum + value);
      expect(weightSum, closeTo(1, 1e-9));
    });

    test('closer anchor gets larger weight in the closing cycle', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
        pipeline.onDetection(_full('B', x: 10, distance: 2));
      }

      expect(world.lastFusionWeights['A']!, greaterThan(world.lastFusionWeights['B']!));
      expect(world.lastAppliedWorldPose!.tx, closeTo(1.8058748404, 1e-6));
    });

    test('larger batch gets larger weight when distances match', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
        if (index < 4) {
          pipeline.onDetection(_full('B', x: 10, distance: 1));
        }
      }

      expect(world.lastFusionWeights['A']!, greaterThan(world.lastFusionWeights['B']!));
      expect(world.lastAppliedWorldPose!.tx, closeTo(3.3333333333, 1e-6));
    });

    test('keeps last world pose while all anchors are paused', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 16; index++) {
        pipeline.onDetection(_full('A', x: 4, distance: 1));
      }
      expect(world.lastAppliedWorldPose!.tx, closeTo(4, 1e-6));

      pipeline.onDetection(
        _RawDetection(
          anchorId: 'A',
          trackingMethod: _TrackingMethod.lastKnownPose,
          pose: const _Pose.translation(100, 0, 0),
          distanceMeters: 1,
        ),
      );

      expect(world.appliedWorldPoses, hasLength(1));
      expect(world.lastAppliedWorldPose!.tx, closeTo(4, 1e-6));
      expect(pipeline.inHoldMode, isTrue);
    });

    test('drops partial batch on pause before reacquiring', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 4; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 0.5));
      }

      pipeline.onDetection(
        _RawDetection(
          anchorId: 'A',
          trackingMethod: _TrackingMethod.lastKnownPose,
          pose: const _Pose.translation(0, 0, 0),
          distanceMeters: 0.5,
        ),
      );

      expect(pipeline.sampleCountFor('A'), 0);

      for (var index = 0; index < 16; index++) {
        pipeline.onDetection(_full('A', x: 10, distance: 1.4));
      }

      expect(world.lastAppliedWorldPose!.tx, closeTo(10, 1e-6));
      expect(world.appliedWorldPoses, hasLength(1));
    });

    test('requires stable single-anchor bootstrap before first apply', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 10, distance: 1.4));
      }

      expect(world.appliedWorldPoses, isEmpty);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 10, distance: 1.4));
      }

      expect(world.appliedWorldPoses, hasLength(1));
      expect(world.lastAppliedWorldPose!.tx, closeTo(10, 1e-6));
    });

    test('guards large single-anchor jump immediately after hold exit', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
      }
      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
      }
      expect(world.lastAppliedWorldPose!.tx, closeTo(0, 1e-6));

      pipeline.onDetection(
        _RawDetection(
          anchorId: 'A',
          trackingMethod: _TrackingMethod.lastKnownPose,
          pose: const _Pose.translation(0, 0, 0),
          distanceMeters: 1,
        ),
      );

      for (var index = 0; index < 8; index++) {
        pipeline.onDetection(_full('A', x: 10, distance: 1.4));
      }

      expect(world.appliedWorldPoses, hasLength(1));
      expect(world.lastAppliedWorldPose!.tx, closeTo(0, 1e-6));
    });

    test('rejects persistent single-anchor pose far from trusted anchor history', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 16; index++) {
        pipeline.onDetection(_full('A', x: 0, distance: 1));
      }
      expect(world.lastAppliedWorldPose!.tx, closeTo(0, 1e-6));

      pipeline.onDetection(
        _RawDetection(
          anchorId: 'A',
          trackingMethod: _TrackingMethod.lastKnownPose,
          pose: const _Pose.translation(0, 0, 0),
          distanceMeters: 1,
        ),
      );

      for (var cycle = 0; cycle < 4; cycle++) {
        for (var index = 0; index < 8; index++) {
          pipeline.onDetection(_full('A', x: 10, distance: 1.4));
        }
      }

      expect(world.appliedWorldPoses, hasLength(1));
      expect(world.lastAppliedWorldPose!.tx, closeTo(0, 1e-6));
    });

    test('reset clears visible anchors and pending samples', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var index = 0; index < 3; index++) {
        pipeline.onDetection(_full('A', x: 1, distance: 1));
      }
      pipeline.reset();

      expect(pipeline.visibleAnchorIds, isEmpty);
      expect(pipeline.sampleCountFor('A'), 0);

      for (var index = 0; index < 16; index++) {
        pipeline.onDetection(_full('A', x: 2, distance: 1));
      }

      expect(world.lastAppliedWorldPose!.tx, closeTo(2, 1e-6));
    });

    test('averages quaternions with hemisphere correction', () {
      final world = _WorldManagerMirror();
      final pipeline = _AnchorDetectionPipelineMirror(world);

      for (var cycle = 0; cycle < 2; cycle++) {
        for (var index = 0; index < 4; index++) {
          pipeline.onDetection(
            _RawDetection(
              anchorId: 'A',
              trackingMethod: _TrackingMethod.fullTracking,
              pose: const _Pose(0, 0, 0, 0, 0, 0, 1),
              distanceMeters: 1,
            ),
          );
          pipeline.onDetection(
            _RawDetection(
              anchorId: 'A',
              trackingMethod: _TrackingMethod.fullTracking,
              pose: const _Pose(0, 0, 0, 0, 0, 0, -1),
              distanceMeters: 1,
            ),
          );
        }
      }

      final pose = world.lastAppliedWorldPose!;
      final magnitude = math.sqrt(
        pose.qx * pose.qx +
            pose.qy * pose.qy +
            pose.qz * pose.qz +
            pose.qw * pose.qw,
      );
      expect(magnitude, closeTo(1, 1e-6));
      expect(pose.qw.abs(), closeTo(1, 1e-6));
    });
  });
}

_RawDetection _full(String anchorId, {required double x, required double distance}) {
  return _RawDetection(
    anchorId: anchorId,
    trackingMethod: _TrackingMethod.fullTracking,
    pose: _Pose.translation(x, 0, 0),
    distanceMeters: distance,
  );
}

enum _TrackingMethod { fullTracking, lastKnownPose }

class _RawDetection {
  const _RawDetection({
    required this.anchorId,
    required this.trackingMethod,
    required this.pose,
    required this.distanceMeters,
  });

  final String anchorId;
  final _TrackingMethod trackingMethod;
  final _Pose pose;
  final double distanceMeters;
}

class _Pose {
  const _Pose(this.tx, this.ty, this.tz, this.qx, this.qy, this.qz, this.qw);

  const _Pose.translation(double x, double y, double z) : this(x, y, z, 0, 0, 0, 1);

  final double tx;
  final double ty;
  final double tz;
  final double qx;
  final double qy;
  final double qz;
  final double qw;

  _Pose inverse() => _Pose(-tx, -ty, -tz, -qx, -qy, -qz, qw);

  _Pose compose(_Pose other) {
    return _Pose(tx + other.tx, ty + other.ty, tz + other.tz, qx, qy, qz, qw);
  }
}

class _WorldManagerMirror {
  final Map<String, _Pose> _blueprints = <String, _Pose>{
    'A': const _Pose.translation(0, 0, 0),
    'B': const _Pose.translation(0, 0, 0),
  };

  final List<_Pose> appliedWorldPoses = <_Pose>[];
  Map<String, double> lastFusionWeights = <String, double>{};

  bool shouldAcceptRuntimePipelineDetections() => true;

  _Pose? computeCorrectionPose(String anchorId, _Pose driftedPose) {
    final blueprintPose = _blueprints[anchorId];
    if (blueprintPose == null) {
      return null;
    }
    return driftedPose.compose(blueprintPose.inverse());
  }

  void applyWorldPose(_Pose pose, {Map<String, double>? fusionWeights}) {
    appliedWorldPoses.add(pose);
    if (fusionWeights != null) {
      lastFusionWeights = fusionWeights;
    }
  }

  _Pose? get currentCorrectionPose => appliedWorldPoses.isEmpty ? null : appliedWorldPoses.last;

  _Pose? get lastAppliedWorldPose => currentCorrectionPose;

  void clearApplied() {
    appliedWorldPoses.clear();
    lastFusionWeights = <String, double>{};
  }
}

class _AnchorDetectionPipelineMirror {
  _AnchorDetectionPipelineMirror(this.world);

  static const int maxBatchSize = 8;
  static const int minEligibleSamples = 4;
  static const double distanceEpsilonSq = 0.01;
  static const int singleAnchorBootstrapCycles = 2;
  static const int singleAnchorLargeCorrectionStableCycles = 2;
  static const double singleAnchorLargeCorrectionPositionMeters = 0.10;
  static const double singleAnchorLargeCorrectionRotationDegrees = 10;
  static const double singleAnchorTrustedPositionMeters = 0.15;
  static const double singleAnchorTrustedRotationDegrees = 20;

  final _WorldManagerMirror world;
  final Map<String, _AnchorBatchState> _states = <String, _AnchorBatchState>{};
  final Set<String> _visibleAnchorIds = <String>{};
  final Map<String, _Pose> _trustedCorrectionPoseByAnchorId = <String, _Pose>{};
  bool inHoldMode = false;
  int singleAnchorStableCyclesSinceResetOrPause = 0;

  Set<String> get visibleAnchorIds => Set<String>.unmodifiable(_visibleAnchorIds);

  void onDetection(_RawDetection raw) {
    if (!world.shouldAcceptRuntimePipelineDetections()) {
      return;
    }
    if (raw.trackingMethod != _TrackingMethod.fullTracking) {
      onAnchorPaused(raw.anchorId);
      return;
    }

    _visibleAnchorIds.add(raw.anchorId);
    final state = _states.putIfAbsent(raw.anchorId, () => _AnchorBatchState(raw.anchorId));
    state.add(raw.pose, raw.distanceMeters);

    if (inHoldMode && _visibleAnchorIds.isNotEmpty) {
      inHoldMode = false;
    }

    if (state.sampleCount < maxBatchSize) {
      return;
    }

    final eligible = _states.values
        .where((state) => _visibleAnchorIds.contains(state.anchorId) && state.sampleCount >= minEligibleSamples)
        .map((state) => state.toEligible())
        .toList()
      ..sort((left, right) => left.avgDistance.compareTo(right.avgDistance));

    final candidates = <_CorrectionCandidate>[];
    for (final batch in eligible) {
      final correction = world.computeCorrectionPose(batch.anchorId, batch.avgPose);
      if (correction != null) {
        candidates.add(
          _CorrectionCandidate(
            anchorId: batch.anchorId,
            sampleCount: batch.sampleCount,
            avgDistance: batch.avgDistance,
            correctionPose: correction,
          ),
        );
      }
    }

    _clearCycleSamples();
    if (candidates.isEmpty) {
      return;
    }

    final fused = _fuse(candidates);
    final previous = world.currentCorrectionPose;
    final delta = previous == null ? null : _measurePoseDelta(previous, fused.pose);
    final singleAnchor = candidates.length == 1;
    final nextSingleAnchorStableCycles = singleAnchor ? singleAnchorStableCyclesSinceResetOrPause + 1 : 0;
    final trustedSingleAnchorPose = singleAnchor ? _trustedCorrectionPoseByAnchorId[candidates.single.anchorId] : null;
    final trustedSingleAnchorDelta = singleAnchor && trustedSingleAnchorPose != null
      ? _measurePoseDelta(trustedSingleAnchorPose, candidates.single.correctionPose)
      : null;
    final shouldReject = singleAnchor &&
        ((previous == null && nextSingleAnchorStableCycles < singleAnchorBootstrapCycles) ||
        (trustedSingleAnchorDelta != null &&
          (trustedSingleAnchorDelta.positionMeters >= singleAnchorTrustedPositionMeters ||
            trustedSingleAnchorDelta.rotationDegrees >= singleAnchorTrustedRotationDegrees)) ||
            (delta != null &&
                (delta.positionMeters >= singleAnchorLargeCorrectionPositionMeters ||
                    delta.rotationDegrees >= singleAnchorLargeCorrectionRotationDegrees) &&
                nextSingleAnchorStableCycles < singleAnchorLargeCorrectionStableCycles));
    if (shouldReject) {
      singleAnchorStableCyclesSinceResetOrPause = nextSingleAnchorStableCycles;
      return;
    }

    if (singleAnchor) {
      singleAnchorStableCyclesSinceResetOrPause = nextSingleAnchorStableCycles;
    } else {
      singleAnchorStableCyclesSinceResetOrPause = 0;
    }
    for (final candidate in candidates) {
      _trustedCorrectionPoseByAnchorId[candidate.anchorId] = candidate.correctionPose;
    }
    world.applyWorldPose(fused.pose, fusionWeights: fused.weights);
  }

  void onAnchorPaused(String anchorId) {
    _visibleAnchorIds.remove(anchorId);
    _states[anchorId]?.clear();
    if (_visibleAnchorIds.isEmpty) {
      inHoldMode = true;
      singleAnchorStableCyclesSinceResetOrPause = 0;
    }
  }

  void onAnchorLost(String anchorId) {
    _visibleAnchorIds.remove(anchorId);
    _states.remove(anchorId);
    if (_visibleAnchorIds.isEmpty) {
      inHoldMode = true;
    }
  }

  void reset() {
    _visibleAnchorIds.clear();
    _states.clear();
    _trustedCorrectionPoseByAnchorId.clear();
    inHoldMode = false;
    singleAnchorStableCyclesSinceResetOrPause = 0;
  }

  int sampleCountFor(String anchorId) => _states[anchorId]?.sampleCount ?? 0;

  void _clearCycleSamples() {
    final keysToRemove = <String>[];
    _states.forEach((anchorId, state) {
      state.clear();
      if (!_visibleAnchorIds.contains(anchorId)) {
        keysToRemove.add(anchorId);
      }
    });
    for (final anchorId in keysToRemove) {
      _states.remove(anchorId);
    }
  }

  _FusedResult _fuse(List<_CorrectionCandidate> candidates) {
    final rawWeights = candidates
        .map((candidate) {
          final distanceScore = 1 / (candidate.avgDistance * candidate.avgDistance + distanceEpsilonSq);
          final batchScore = candidate.sampleCount / maxBatchSize;
          return distanceScore * batchScore;
        })
        .toList();
    final rawWeightSum = rawWeights.fold<double>(0, (sum, value) => sum + value);
    final normalizedWeights = rawWeights.map((weight) => weight / rawWeightSum).toList();

    if (candidates.length == 1) {
      return _FusedResult(
        pose: candidates.single.correctionPose,
        weights: <String, double>{candidates.single.anchorId: 1},
      );
    }

    final fusedTx = _weightedSum(candidates, normalizedWeights, (candidate) => candidate.correctionPose.tx);
    final fusedTy = _weightedSum(candidates, normalizedWeights, (candidate) => candidate.correctionPose.ty);
    final fusedTz = _weightedSum(candidates, normalizedWeights, (candidate) => candidate.correctionPose.tz);

    final ref = candidates.first.correctionPose;
    var qx = 0.0;
    var qy = 0.0;
    var qz = 0.0;
    var qw = 0.0;
    for (var index = 0; index < candidates.length; index++) {
      final q = candidates[index].correctionPose;
      final dot = q.qx * ref.qx + q.qy * ref.qy + q.qz * ref.qz + q.qw * ref.qw;
      final sign = dot < 0 ? -1.0 : 1.0;
      qx += q.qx * sign * normalizedWeights[index];
      qy += q.qy * sign * normalizedWeights[index];
      qz += q.qz * sign * normalizedWeights[index];
      qw += q.qw * sign * normalizedWeights[index];
    }
    final mag = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
    final pose = mag == 0
        ? _Pose(fusedTx, fusedTy, fusedTz, 0, 0, 0, 1)
        : _Pose(fusedTx, fusedTy, fusedTz, qx / mag, qy / mag, qz / mag, qw / mag);

    return _FusedResult(
      pose: pose,
      weights: <String, double>{
        for (var index = 0; index < candidates.length; index++) candidates[index].anchorId: normalizedWeights[index],
      },
    );
  }

  double _weightedSum(
    List<_CorrectionCandidate> candidates,
    List<double> normalizedWeights,
    double Function(_CorrectionCandidate candidate) pick,
  ) {
    var total = 0.0;
    for (var index = 0; index < candidates.length; index++) {
      total += pick(candidates[index]) * normalizedWeights[index];
    }
    return total;
  }

  _PoseDelta _measurePoseDelta(_Pose previous, _Pose next) {
    final dx = next.tx - previous.tx;
    final dy = next.ty - previous.ty;
    final dz = next.tz - previous.tz;
    final positionMeters = math.sqrt(dx * dx + dy * dy + dz * dz);
    final dot = (previous.qx * next.qx + previous.qy * next.qy + previous.qz * next.qz + previous.qw * next.qw)
        .abs()
        .clamp(0.0, 1.0);
    final rotationDegrees = 2 * math.acos(dot) * 180 / math.pi;
    return _PoseDelta(positionMeters, rotationDegrees);
  }
}

class _PoseDelta {
  const _PoseDelta(this.positionMeters, this.rotationDegrees);

  final double positionMeters;
  final double rotationDegrees;
}

class _AnchorBatchState {
  _AnchorBatchState(this.anchorId);

  final String anchorId;
  final List<_Pose> _poses = <_Pose>[];
  final List<double> _distances = <double>[];

  int get sampleCount => _poses.length;

  void add(_Pose pose, double distanceMeters) {
    _poses.add(pose);
    _distances.add(distanceMeters);
  }

  _EligibleAnchorBatch toEligible() {
    final avgTx = _poses.map((pose) => pose.tx).reduce((a, b) => a + b) / _poses.length;
    final avgTy = _poses.map((pose) => pose.ty).reduce((a, b) => a + b) / _poses.length;
    final avgTz = _poses.map((pose) => pose.tz).reduce((a, b) => a + b) / _poses.length;

    final ref = _poses.first;
    var qx = 0.0;
    var qy = 0.0;
    var qz = 0.0;
    var qw = 0.0;
    for (final pose in _poses) {
      final dot = pose.qx * ref.qx + pose.qy * ref.qy + pose.qz * ref.qz + pose.qw * ref.qw;
      final sign = dot < 0 ? -1.0 : 1.0;
      qx += pose.qx * sign;
      qy += pose.qy * sign;
      qz += pose.qz * sign;
      qw += pose.qw * sign;
    }
    final mag = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
    final avgPose = mag == 0
        ? _Pose(avgTx, avgTy, avgTz, 0, 0, 0, 1)
        : _Pose(avgTx, avgTy, avgTz, qx / mag, qy / mag, qz / mag, qw / mag);
    final avgDistance = _distances.reduce((a, b) => a + b) / _distances.length;

    return _EligibleAnchorBatch(
      anchorId: anchorId,
      sampleCount: sampleCount,
      avgDistance: avgDistance,
      avgPose: avgPose,
    );
  }

  void clear() {
    _poses.clear();
    _distances.clear();
  }
}

class _EligibleAnchorBatch {
  const _EligibleAnchorBatch({
    required this.anchorId,
    required this.sampleCount,
    required this.avgDistance,
    required this.avgPose,
  });

  final String anchorId;
  final int sampleCount;
  final double avgDistance;
  final _Pose avgPose;
}

class _CorrectionCandidate {
  const _CorrectionCandidate({
    required this.anchorId,
    required this.sampleCount,
    required this.avgDistance,
    required this.correctionPose,
  });

  final String anchorId;
  final int sampleCount;
  final double avgDistance;
  final _Pose correctionPose;
}

class _FusedResult {
  const _FusedResult({required this.pose, required this.weights});

  final _Pose pose;
  final Map<String, double> weights;
}
