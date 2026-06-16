# AR Wall — Tracking Robustness Improvements
## Post-MVP Enhancement Plan, Ordered by Impact

> **Apply this after the basic system works.** Each improvement is independent and can be shipped individually. Do them in order — earlier items give the highest ROI.

---

## Critical Review of the Submitted Notes

The notes correctly identify the right concepts but get several key details wrong.

**Frame batching:** The notes suggest a fixed-size batch (e.g., 20 frames) and then averaging. This is **wrong** for a walking user — the anchor is only visible for 1–3 seconds. A 20-frame buffer at 60fps = 333ms of lag before you act. Use **EMA (Exponential Moving Average)** instead. EMA gives you continuous averaging with no buffering lag. The only good use of a fixed batch is on **first detection** — wait for 5 consistent frames before accepting an anchor's first correction.

**Outlier rejection:** The notes mention IQR filtering, which requires storing all samples to compute quartiles. Use a **velocity gate** instead: if the proposed correction delta moved more than a threshold (e.g., 15 cm) from the previous accepted correction in a single frame, reject that frame. Simple, stateless, works in a render loop.

**Multi-anchor fusion:** "Average all visible anchors" is naive — an anchor 4 m away is much less reliable than one 0.5 m away. Use **inverse-distance-squared weighting**. Weight of anchor i = 1/d²ᵢ. Normalize all weights to sum to 1. This automatically de-weights far anchors.

**Gradient descent / momentum:** This is a creative idea but the right framing is **EMA with velocity prediction** — track the rate of change of the correction and add a damped momentum term. This reduces lag during slow continuous drift without introducing oscillation.

---

## The Correction Pipeline (Full Architecture)

Every anchor update goes through this pipeline in order, in the native render thread:

```
Raw detected transform (per frame, per anchor)
         │
         ▼
[1] FIRST-DETECTION SETTLE BUFFER (5 frames, per anchor)
         │  Rejected until 5 consistent frames seen
         ▼
[2] VELOCITY GATE (outlier rejection)
         │  Reject if |Δcorrection| > 15 cm in one frame
         ▼
[3] DEAD ZONE (threshold gate)
         │  Skip if |Δcorrection| < 4 mm (noise floor)
         ▼
[4] CONFIDENCE SCORE (per anchor, per frame)
         │  Weight = f(distance, trackingQuality, imageArea)
         ▼
[5] MULTI-ANCHOR FUSION (if 2+ anchors visible)
         │  Inverse-distance-squared weighted average of corrections
         ▼
[6] EMA SMOOTHER (adaptive alpha)
         │  α = fast (0.25) when camera still, slow (0.08) when moving
         ▼
[7] APPLY TO worldRootNode (via SCNTransaction / SceneView animator)
```

---

## Improvements in Priority Order

---

### #1 — EMA on the World Root Correction
**Impact: Highest. Eliminates jitter immediately.**

The current plan uses `SCNTransaction.animationDuration = 0.75` which is a fixed-duration linear animation, not true EMA. The problem: if a new correction arrives before the animation ends, the old one is cancelled and a new animation starts — causing stuttering. Replace with a per-frame EMA update in the `renderer(_:updateAtTime:)` delegate method.

**`ios/Runner/AR/WorldCoordinateManager.swift` — full replacement:**

```swift
import SceneKit
import ARKit

class WorldCoordinateManager {
    let worldRootNode: SCNNode

    // Blueprint data: anchorId → true physical transform
    private var blueprintTransforms: [String: simd_float4x4] = [:]

    // Proximity tracking
    private var visibleAnchors: [String: AnchorObservation] = [:]

    // EMA state — the smoothed current correction
    private var smoothedTranslation: SIMD3<Float> = .zero
    private var smoothedRotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var hasFirstCorrection = false

    // Adaptive EMA alphas
    // Higher alpha = faster response (less smoothing)
    // Lower alpha = more smoothing (slower response)
    private let alphaFast: Float = 0.25   // camera is still
    private let alphaSlow: Float = 0.08   // camera is moving
    private var currentAlpha: Float = 0.15

    // Velocity gate: reject if correction jumps more than this in 1 frame
    private let maxCorrectionJumpMeters: Float = 0.15

    // Dead zone: ignore corrections smaller than this
    private let deadZoneMeters: Float = 0.004   // 4 mm

    init(worldRootNode: SCNNode) {
        self.worldRootNode = worldRootNode
    }

    func registerBlueprints(anchors: [AnchorBlueprintNative]) {
        for anchor in anchors {
            blueprintTransforms[anchor.id] = anchor.blueprintTransform
        }
    }

    // Called every frame by renderer(_:updateAtTime:)
    func updateSmoothing(cameraAngularVelocity: Float) {
        guard hasFirstCorrection else { return }

        // Adapt alpha to camera motion
        // High angular velocity → camera moving → use slow alpha to avoid lag-induced jitter
        currentAlpha = cameraAngularVelocity > 0.3 ? alphaSlow : alphaFast

        // Apply EMA to worldRootNode transform (decompose → EMA → recompose)
        let targetTranslation = smoothedTranslation
        let targetRotation = smoothedRotation

        let currentT = worldRootNode.simdTransform.columns.3
        let currentTranslation = SIMD3<Float>(currentT.x, currentT.y, currentT.z)
        let currentRotation = simd_quatf(worldRootNode.simdTransform)

        let newTranslation = mix(currentTranslation, targetTranslation, t: currentAlpha)
        let newRotation = simd_slerp(currentRotation, targetRotation, t: currentAlpha)

        var newTransform = simd_matrix4x4(newRotation)
        newTransform.columns.3 = SIMD4<Float>(newTranslation.x, newTranslation.y, newTranslation.z, 1)

        // Direct assignment — no SCNTransaction. EMA IS the animation.
        worldRootNode.simdTransform = newTransform

        if !worldRootNode.isHidden {
            worldRootNode.opacity = 1
        }
    }

    // Called when an anchor is detected or updated
    func proposeCorrection(
        anchorId: String,
        driftedTransform: simd_float4x4,
        cameraDistance: Float,
        isTracked: Bool
    ) {
        guard isTracked, let blueprint = blueprintTransforms[anchorId] else { return }

        // Correction: M = T_drifted × T_blueprint⁻¹
        let correction = driftedTransform * blueprint.inverse

        var observation = visibleAnchors[anchorId] ?? AnchorObservation(anchorId: anchorId)
        observation.addSample(correction: correction, distance: cameraDistance)
        visibleAnchors[anchorId] = observation

        // Only act once the settle buffer is full
        guard observation.isSettled else { return }

        // Fuse all visible settled anchors
        let fused = fuseVisibleAnchors()

        // Velocity gate
        if hasFirstCorrection {
            let proposedT = SIMD3<Float>(fused.columns.3.x, fused.columns.3.y, fused.columns.3.z)
            let delta = simd_length(proposedT - smoothedTranslation)
            if delta > maxCorrectionJumpMeters {
                // Outlier — log and skip
                return
            }
            // Dead zone
            if delta < deadZoneMeters { return }
        }

        // Decompose fused correction into translation + quaternion
        let fusedQ = simd_quatf(fused)
        let fusedT = SIMD3<Float>(fused.columns.3.x, fused.columns.3.y, fused.columns.3.z)

        if !hasFirstCorrection {
            // Snap to first correction immediately (no lerp on first fix)
            smoothedTranslation = fusedT
            smoothedRotation = fusedQ
            hasFirstCorrection = true
            worldRootNode.isHidden = false
        } else {
            // Update the EMA target (updateSmoothing() will lerp toward this each frame)
            smoothedTranslation = fusedT
            smoothedRotation = fusedQ
        }
    }

    func anchorLost(_ anchorId: String) {
        visibleAnchors.removeValue(forKey: anchorId)
    }

    // MARK: - Private

    /// Fuses all settled visible anchors using inverse-distance-squared weighting.
    private func fuseVisibleAnchors() -> simd_float4x4 {
        let settled = visibleAnchors.values.filter { $0.isSettled }
        guard !settled.isEmpty else {
            return matrix_identity_float4x4
        }
        guard settled.count > 1 else {
            return settled.first!.smoothedCorrection
        }

        // Compute weights: w_i = 1 / d²_i
        let weights = settled.map { 1.0 / max($0.currentDistance * $0.currentDistance, 0.01) }
        let totalWeight = weights.reduce(0, +)
        let normalizedWeights = weights.map { Float($0 / totalWeight) }

        // Weighted average of translations
        var fusedTranslation = SIMD3<Float>.zero
        for (i, obs) in settled.enumerated() {
            let t = obs.smoothedCorrection.columns.3
            fusedTranslation += normalizedWeights[i] * SIMD3<Float>(t.x, t.y, t.z)
        }

        // Weighted average of rotations via quaternion slerp chain
        var fusedRotation = simd_quatf(settled[0].smoothedCorrection)
        var accumulatedWeight = normalizedWeights[0]
        for i in 1..<settled.count {
            let qi = simd_quatf(settled[i].smoothedCorrection)
            let t = normalizedWeights[i] / (accumulatedWeight + normalizedWeights[i])
            fusedRotation = simd_slerp(fusedRotation, qi, t: t)
            accumulatedWeight += normalizedWeights[i]
        }

        var result = simd_matrix4x4(fusedRotation)
        result.columns.3 = SIMD4<Float>(fusedTranslation.x, fusedTranslation.y, fusedTranslation.z, 1)
        return result
    }
}

// MARK: - AnchorObservation

/// Tracks the per-anchor settle buffer and running stats.
struct AnchorObservation {
    let anchorId: String
    private(set) var currentDistance: Float = Float.greatestFiniteMagnitude
    private(set) var smoothedCorrection: simd_float4x4 = matrix_identity_float4x4
    private var sampleCount: Int = 0
    private let settleCount: Int = 5       // Frames required before first use

    // Internal EMA for per-anchor smoothing before fusion
    private let anchorEMAAlpha: Float = 0.4

    var isSettled: Bool { sampleCount >= settleCount }

    mutating func addSample(correction: simd_float4x4, distance: Float) {
        currentDistance = distance
        if sampleCount == 0 {
            smoothedCorrection = correction
        } else {
            // EMA on translation
            let prevT = smoothedCorrection.columns.3
            let newT = correction.columns.3
            let emaT = mix(
                SIMD3<Float>(prevT.x, prevT.y, prevT.z),
                SIMD3<Float>(newT.x, newT.y, newT.z),
                t: anchorEMAAlpha
            )
            // EMA on rotation
            let prevQ = simd_quatf(smoothedCorrection)
            let newQ = simd_quatf(correction)
            let emaQ = simd_slerp(prevQ, newQ, t: anchorEMAAlpha)

            var result = simd_matrix4x4(emaQ)
            result.columns.3 = SIMD4<Float>(emaT.x, emaT.y, emaT.z, 1)
            smoothedCorrection = result
        }
        sampleCount += 1
    }
}
```

**Wire `updateSmoothing` into the render loop in `NativeARViewController.swift`:**

```swift
// Add this delegate method:
func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    let angularVelocity = sceneView.session.currentFrame?.camera.eulerAngles ?? .zero
    // Use magnitude of euler angle rates as proxy for camera motion
    let motionMagnitude = simd_length(angularVelocity)
    worldCoordinateManager.updateSmoothing(cameraAngularVelocity: motionMagnitude)
}
```

---

### #2 — Settle Buffer on First Detection
**Impact: High. Eliminates the "snap on first detection" jitter.**

Already included in `AnchorObservation.settleCount = 5` above. The anchor won't contribute to corrections until 5 consistent frames have been seen. No additional code needed.

**Tuning guide:**
- `settleCount = 3` — fast but may accept a noisy first reading
- `settleCount = 5` — recommended (83ms at 60fps, imperceptible)
- `settleCount = 10` — very stable, but 167ms before first correction fires

---

### #3 — Dead Zone + Velocity Gate
**Impact: High. Eliminates micro-jitter and single-frame spikes.**

Already included in `WorldCoordinateManager` above as `deadZoneMeters = 0.004` and `maxCorrectionJumpMeters = 0.15`.

**Tuning guide:**
- Dead zone `4 mm` — anything smaller is measurement noise on a 40cm printed image
- Velocity gate `15 cm` — a single-frame jump of 15cm is physically impossible for a static wall anchor; almost certainly a bad tracking frame
- For rough/textured surfaces, raise the velocity gate to `25 cm`

---

### #4 — Multi-Anchor Inverse-Distance-Squared Fusion
**Impact: High. Removes the abrupt "anchor switch" transition artefact.**

Already included in `fuseVisibleAnchors()` above. When 2+ anchors are visible, their corrections are blended by inverse-distance-squared.

**Why inverse-distance-squared and not inverse-distance?**
- Inverse-distance (1/d): the far anchor still has meaningful weight at 3–4× the distance
- Inverse-distance-squared (1/d²): the far anchor's weight drops to near-zero at 2× the distance
- For AR tracking, the relationship between distance and measurement error is approximately quadratic (pose error scales with d²), so 1/d² is physically motivated

**Transition example at equal distance:**
- Anchor A at 1.0 m, weight = 1/1² = 1.0
- Anchor B at 1.0 m, weight = 1/1² = 1.0
- Fused = 50%A + 50%B (equal blend)

**As user walks toward B:**
- Anchor A at 2.0 m, weight = 1/4 = 0.25
- Anchor B at 0.8 m, weight = 1/0.64 = 1.56
- Fused ≈ 14%A + 86%B (B dominates)

---

### #5 — Adaptive EMA Alpha Based on Camera Motion
**Impact: Medium. Reduces lag when stationary, reduces jitter when moving.**

Already included in `updateSmoothing(cameraAngularVelocity:)` above.

The key insight from AR tracking research: when the camera is **stationary**, you want a slow (low) alpha so the system accumulates many samples and converges to a stable estimate. When the camera is **moving fast**, you want a high alpha so the system responds quickly and doesn't lag behind.

**Tuning:**
```
cameraAngularVelocity < 0.1 rad/s  →  alpha = 0.08   (very smooth, slow)
cameraAngularVelocity 0.1–0.3      →  alpha = 0.15   (balanced)
cameraAngularVelocity > 0.3 rad/s  →  alpha = 0.25   (responsive, less smooth)
```

---

### #6 — Anchor Confidence Score (Weighted by Quality, Not Just Distance)
**Impact: Medium. Anchors at grazing angles and far away are less accurate.**

Extend `AnchorObservation` to track a per-anchor confidence factor that combines:
- Distance (1/d²) — already done
- Camera angle to anchor normal (cosine of angle)
- Image area in pixels (larger = more accurate pose)

```swift
// In NativeARViewController.renderer(_:didUpdate:for:)
func anchorConfidence(imageAnchor: ARImageAnchor) -> Float {
    guard let frame = sceneView.session.currentFrame else { return 1.0 }

    // Factor 1: distance
    let anchorPos = imageAnchor.transform.columns.3
    let cameraPos = frame.camera.transform.columns.3
    let dist = simd_length(SIMD3<Float>(anchorPos.x, anchorPos.y, anchorPos.z)
                         - SIMD3<Float>(cameraPos.x, cameraPos.y, cameraPos.z))
    let distanceFactor = 1.0 / max(dist * dist, 0.01)

    // Factor 2: angle (dot product of camera forward and anchor normal)
    let anchorNormal = SIMD3<Float>(imageAnchor.transform.columns.2.x,
                                    imageAnchor.transform.columns.2.y,
                                    imageAnchor.transform.columns.2.z)
    let cameraForward = -SIMD3<Float>(frame.camera.transform.columns.2.x,
                                       frame.camera.transform.columns.2.y,
                                       frame.camera.transform.columns.2.z)
    let angleFactor = max(0, simd_dot(simd_normalize(anchorNormal),
                                       simd_normalize(cameraForward)))

    return distanceFactor * angleFactor
}
```

Use this confidence as the weight instead of raw 1/d² in `fuseVisibleAnchors()`.

---

### #7 — Anchor Lock-In After Stability
**Impact: Medium. After N stable readings, treat the anchor as a reliable reference.**

Once an anchor has been seen many times with consistent corrections (low variance), lock it: stop updating its blueprint contribution and use it as a high-confidence fixed reference.

```swift
// Add to AnchorObservation:
private var recentTranslations: [SIMD3<Float>] = []
private let lockInSampleCount = 30   // ~500ms at 60fps
private let lockInVarianceThreshold: Float = 0.0001  // 1 cm² variance = 1cm std dev

var isLockedIn: Bool = false

mutating func attemptLockIn() {
    guard !isLockedIn, recentTranslations.count >= lockInSampleCount else { return }
    let mean = recentTranslations.reduce(.zero, +) / Float(recentTranslations.count)
    let variance = recentTranslations.map { simd_length_squared($0 - mean) }.reduce(0, +)
                   / Float(recentTranslations.count)
    if variance < lockInVarianceThreshold {
        isLockedIn = true
        // Log that this anchor is now a trusted reference
    }
}
```

When locked in, `proposeCorrection` skips the settle buffer and applies the correction with maximum weight.

---

### #8 — Android Mirror
**Impact: Required for parity. Apply the same logic in Kotlin.**

In `WorldCoordinateManager.kt`, replace the current `applyCorrection` method with the same pipeline: `AnchorObservation` settle buffer → velocity gate → dead zone → inverse-distance-squared fusion → EMA target update.

The SceneView library's `Node.worldPosition` setter already applies a smooth animator, so set a short duration (100ms) and update the target each frame:

```kotlin
// Called from ArSceneView.onSessionUpdated every frame:
fun updateSmoothing(cameraAngularVelocity: Float) {
    if (!hasFirstCorrection) return
    val alpha = if (cameraAngularVelocity > 0.3f) alphaFast else alphaSlow

    // Lerp current worldRootNode position toward target
    val current = worldRootNode.worldPosition
    val target = smoothedTarget
    worldRootNode.worldPosition = Vector3(
        current.x + (target.x - current.x) * alpha,
        current.y + (target.y - current.y) * alpha,
        current.z + (target.z - current.z) * alpha,
    )
}
```

---

## Dart Test Suite

All logic is in native, so the Dart tests focus on the math that IS in Dart, plus integration tests that mock the native channel and verify the full pipeline.

### `test/core/ar/tracking_improvements_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ar_wall_app/core/ar/utils/ar_math.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: simulate N frames of EMA convergence on the Dart side
// (mirrors what the native EMA does, lets us verify alpha tuning)
// ─────────────────────────────────────────────────────────────────────────────

Vector3 simulateEMA({
  required List<Vector3> samples,
  required double alpha,
}) {
  var current = samples.first;
  for (final sample in samples.skip(1)) {
    current = ARMath.lerpVector3(current, sample, alpha);
  }
  return current;
}

Vector3 addNoise(Vector3 v, double noiseMagnitude, int seed) {
  // Deterministic pseudo-noise using seed
  final n = (seed * 6364136223846793005 + 1442695040888963407) % 1000;
  final noise = (n / 1000.0 - 0.5) * 2.0 * noiseMagnitude;
  return Vector3(v.x + noise, v.y + noise * 0.7, v.z + noise * 0.3);
}

void main() {

  // ─────────────────────────────────────────────────────────────────────────
  // 1. EMA CONVERGENCE
  // ─────────────────────────────────────────────────────────────────────────

  group('EMA convergence', () {

    test('alpha=0.15: converges to true value within 30 frames with noise', () {
      const double alpha = 0.15;
      const double noiseMeters = 0.008; // 8mm noise per frame
      final trueValue = Vector3(10.0, 1.5, 0.0);

      // Generate 30 noisy samples centered on the true value
      final samples = List.generate(30, (i) => addNoise(trueValue, noiseMeters, i));
      final result = simulateEMA(samples: samples, alpha: alpha);

      expect((result - trueValue).length, lessThan(0.015),
          reason: 'EMA with alpha=0.15 must converge within 15mm after 30 frames');
    });

    test('alpha=0.25 (fast): converges faster but has more residual noise', () {
      const double alphaFast = 0.25;
      const double alphaSlow = 0.08;
      const double noise = 0.01;
      final trueValue = Vector3(5.0, 1.5, 0.0);
      final samples = List.generate(20, (i) => addNoise(trueValue, noise, i));

      final fastResult = simulateEMA(samples: samples, alpha: alphaFast);
      final slowResult = simulateEMA(samples: samples, alpha: alphaSlow);

      // Fast converges closer in 20 frames
      expect((fastResult - trueValue).length,
          lessThan((slowResult - trueValue).length + 0.005),
          reason: 'Fast alpha converges in fewer frames');
    });

    test('alpha=0: never updates (frozen)', () {
      final samples = [Vector3(0, 0, 0), Vector3(10, 10, 10), Vector3(5, 5, 5)];
      final result = simulateEMA(samples: samples, alpha: 0.0);
      expect(result.x, closeTo(0.0, 0.001), reason: 'alpha=0 means never update');
    });

    test('alpha=1: instantly snaps (no smoothing)', () {
      final samples = [Vector3(0, 0, 0), Vector3(10, 10, 10)];
      final result = simulateEMA(samples: samples, alpha: 1.0);
      expect(result.x, closeTo(10.0, 0.001), reason: 'alpha=1 means instant snap');
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. VELOCITY GATE (outlier rejection)
  // ─────────────────────────────────────────────────────────────────────────

  group('Velocity gate outlier rejection', () {

    const double velocityThreshold = 0.15; // 15 cm

    bool velocityGateRejects(Vector3 previous, Vector3 proposed) {
      return (proposed - previous).length > velocityThreshold;
    }

    test('Normal correction (3cm) passes gate', () {
      final prev = Vector3(9.97, 1.50, 0.0);
      final next = Vector3(9.94, 1.51, 0.0);
      expect(velocityGateRejects(prev, next), isFalse);
    });

    test('Large jump (50cm) is rejected', () {
      final prev = Vector3(10.0, 1.5, 0.0);
      final outlier = Vector3(10.5, 1.5, 0.0);
      expect(velocityGateRejects(prev, outlier), isTrue);
    });

    test('Exactly at threshold: accepted', () {
      final prev = Vector3(10.0, 1.5, 0.0);
      final borderline = Vector3(10.15, 1.5, 0.0);
      expect(velocityGateRejects(prev, borderline), isFalse,
          reason: 'Exactly at threshold should pass (exclusive gate)');
    });

    test('Just over threshold: rejected', () {
      final prev = Vector3(10.0, 1.5, 0.0);
      final justOver = Vector3(10.151, 1.5, 0.0);
      expect(velocityGateRejects(prev, justOver), isTrue);
    });

    test('EMA output is stable after one outlier injection', () {
      // Simulate: 10 good frames, 1 outlier, 10 more good frames
      const double alpha = 0.15;
      const double noise = 0.005;
      final trueValue = Vector3(10.0, 1.5, 0.0);

      var current = trueValue;
      final log = <double>[];

      for (int i = 0; i < 21; i++) {
        final raw = i == 10
            ? Vector3(10.5, 1.5, 0.0)  // outlier at frame 10
            : addNoise(trueValue, noise, i);

        // Apply velocity gate
        final isOutlier = (raw - current).length > velocityThreshold;
        if (!isOutlier) {
          current = ARMath.lerpVector3(current, raw, alpha);
        }
        log.add(current.x);
      }

      // After the outlier frame, deviation should be <5mm
      final deviationAfterOutlier = (log[11] - trueValue.x).abs();
      expect(deviationAfterOutlier, lessThan(0.05),
          reason: 'Outlier rejection must keep EMA within 5cm of true value');
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. DEAD ZONE
  // ─────────────────────────────────────────────────────────────────────────

  group('Dead zone', () {

    const double deadZone = 0.004; // 4mm

    bool deadZoneBlocks(Vector3 current, Vector3 proposed) {
      return (proposed - current).length < deadZone;
    }

    test('2mm correction is blocked', () {
      expect(deadZoneBlocks(Vector3(10.0, 1.5, 0.0), Vector3(10.002, 1.5, 0.0)), isTrue);
    });

    test('5mm correction passes', () {
      expect(deadZoneBlocks(Vector3(10.0, 1.5, 0.0), Vector3(10.005, 1.5, 0.0)), isFalse);
    });

    test('Dead zone prevents EMA drift from sub-mm noise', () {
      // 30 frames of <3mm noise — EMA output should barely move
      var current = Vector3(10.0, 1.5, 0.0);
      const double alpha = 0.15;

      for (int i = 0; i < 30; i++) {
        final noisy = addNoise(current, 0.002, i); // 2mm noise
        if (!deadZoneBlocks(current, noisy)) {
          current = ARMath.lerpVector3(current, noisy, alpha);
        }
      }
      expect((current - Vector3(10.0, 1.5, 0.0)).length, lessThan(0.005),
          reason: 'Dead zone must prevent drift from sub-mm noise');
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. MULTI-ANCHOR INVERSE-DISTANCE-SQUARED FUSION
  // ─────────────────────────────────────────────────────────────────────────

  group('Multi-anchor fusion', () {

    // Simulate weighted average of two correction translations
    Vector3 fuseTwo({
      required Vector3 corrA, required double distA,
      required Vector3 corrB, required double distB,
    }) {
      final wA = 1.0 / (distA * distA);
      final wB = 1.0 / (distB * distB);
      final total = wA + wB;
      return (corrA * wA + corrB * wB) / total;
    }

    test('Equal distance: result is midpoint of two corrections', () {
      final corrA = Vector3(-8.0, -1.5, -1.0);
      final corrB = Vector3(-8.1, -1.5, -1.0); // 10cm disagreement
      final fused = fuseTwo(corrA: corrA, distA: 1.0, corrB: corrB, distB: 1.0);
      expect(fused.x, closeTo(-8.05, 0.001), reason: 'Equal distance → midpoint');
    });

    test('Closer anchor dominates: 2:1 distance ratio', () {
      final corrA = Vector3(-8.0, -1.5, -1.0); // anchor A, close
      final corrB = Vector3(-8.2, -1.5, -1.0); // anchor B, far, 20cm disagreement
      // distA=0.5m, distB=1.0m → wA = 4, wB = 1
      final fused = fuseTwo(corrA: corrA, distA: 0.5, corrB: corrB, distB: 1.0);
      // Expected: 4/5 × (-8.0) + 1/5 × (-8.2) = -8.04
      expect(fused.x, closeTo(-8.04, 0.002),
          reason: 'Closer anchor must dominate the fusion result');
    });

    test('Single anchor: weight is 100% (result equals that correction)', () {
      final corrA = Vector3(-8.0, -1.5, -1.0);
      final fused = fuseTwo(corrA: corrA, distA: 1.0, corrB: corrA, distB: 1.0);
      expect(fused.x, closeTo(-8.0, 0.001));
    });

    test('Very far anchor (5m vs 0.5m) contributes less than 1%', () {
      final corrA = Vector3(-8.0, -1.5, -1.0);
      final corrB = Vector3(-9.0, -1.5, -1.0); // 1m disagreement
      // wA = 1/0.25 = 4.0, wB = 1/25 = 0.04
      final fused = fuseTwo(corrA: corrA, distA: 0.5, corrB: corrB, distB: 5.0);
      // Expected ≈ -8.01 (far anchor barely moves the result)
      expect(fused.x, closeTo(-8.0, 0.02),
          reason: 'Very far anchor should contribute less than 2%');
    });

    test('Fusion result is always between the two input corrections', () {
      final corrA = Vector3(-7.5, -1.0, 0.0);
      final corrB = Vector3(-9.0, -2.0, 0.0);
      for (final distRatio in [0.5, 1.0, 1.5, 2.0, 3.0]) {
        final fused = fuseTwo(corrA: corrA, distA: 1.0, corrB: corrB, distB: distRatio);
        expect(fused.x, greaterThanOrEqualTo(-9.0));
        expect(fused.x, lessThanOrEqualTo(-7.5));
      }
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. SETTLE BUFFER
  // ─────────────────────────────────────────────────────────────────────────

  group('Settle buffer', () {

    test('Anchor does not contribute before settleCount frames', () {
      const int settleCount = 5;
      int samplesAccepted = 0;
      int samplesReceived = 0;

      // Simulate per-frame arrival
      for (int i = 0; i < 10; i++) {
        samplesReceived++;
        if (samplesReceived >= settleCount) {
          samplesAccepted++;
        }
      }
      expect(samplesAccepted, equals(6)); // frames 5..10 inclusive
      expect(samplesAccepted, isNot(equals(10)));
    });

    test('First correction snaps immediately (no EMA lag on initial fix)', () {
      // Simulate: snap on first valid correction, then EMA kicks in
      Vector3? current;
      const double alpha = 0.15;
      final trueValue = Vector3(10.0, 1.5, 0.0);
      final samples = List.generate(10, (i) => addNoise(trueValue, 0.005, i));

      for (int i = 0; i < samples.length; i++) {
        if (current == null) {
          current = samples[i]; // Snap on first
        } else {
          current = ARMath.lerpVector3(current!, samples[i], alpha);
        }
      }
      // After snap+EMA, must be close to truth
      expect((current! - trueValue).length, lessThan(0.02));
    });

  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. PIPELINE INTEGRATION — corner POI validation with full pipeline
  // ─────────────────────────────────────────────────────────────────────────

  group('Full pipeline integration', () {

    Vector3 applyMatrix(Matrix4 m, Vector3 v) {
      final r = m * Vector4(v.x, v.y, v.z, 1.0);
      return Vector3(r.x, r.y, r.z);
    }

    test('Corner POIs survive EMA pipeline with noisy anchor detections', () {
      final anchorBlueprint = ARMath.buildBlueprintMatrix(Vector3(5.0, 1.5, 0.0), 0.0);
      final corners = ARMath.computeAnchorCorners(
        anchorBlueprintMatrix: anchorBlueprint,
        physicalWidthMeters: 0.4,
        physicalHeightMeters: 0.4,
      );

      // Simulate: true drift is (−8.0, −1.5, 0.0), but each frame has 5mm noise
      const int numFrames = 30;
      const double alpha = 0.15;
      const double noise = 0.005;
      final trueDriftedPos = Vector3(5.0 - 8.0, 1.5 - 1.5, 0.0);

      // EMA over the correction matrices
      Matrix4 currentCorrection = Matrix4.identity();
      bool hasFirst = false;
      Vector3? smoothedT;

      for (int i = 0; i < numFrames; i++) {
        final noisyDriftedPos = addNoise(trueDriftedPos, noise, i);
        final drifted = ARMath.buildBlueprintMatrix(noisyDriftedPos, 0.0);
        final rawCorrection = ARMath.calculateCorrectionDelta(
          blueprintTransform: anchorBlueprint,
          driftedTransform: drifted,
        );

        final rawT = ARMath.extractTranslation(rawCorrection);

        if (!hasFirst) {
          smoothedT = rawT;
          hasFirst = true;
        } else {
          smoothedT = ARMath.lerpVector3(smoothedT!, rawT, alpha);
        }
      }

      // Build final correction from smoothed translation
      final finalCorrection = Matrix4.identity()..setTranslation(smoothedT!);

      // Apply to all 4 corners
      for (final entry in corners.entries) {
        final corrected = applyMatrix(finalCorrection, entry.value);
        // Expected: corner blueprint pos + true drift
        final expected = entry.value + trueDriftedPos - Vector3(5.0, 1.5, 0.0);
        // Wait, expected = blueprint_corner_pos translated by drift correction
        // Actually: corner_ar_world = blueprint_corner_pos + (drifted_anchor - blueprint_anchor)
        final anchorBlueprintPos = ARMath.extractTranslation(anchorBlueprint);
        final expectedPos = entry.value + (trueDriftedPos - anchorBlueprintPos);
        expect((corrected - expectedPos).length, lessThan(0.012),
            reason: '${entry.key}: EMA pipeline must place corner within 12mm of truth');
      }
    });

  });

}
```

---

## Tuning Parameters Summary

| Parameter | Recommended | Range | Effect of increasing |
|---|---|---|---|
| `settleCount` | 5 frames | 3–10 | More stable first fix, but slower |
| `deadZoneMeters` | 0.004 m (4mm) | 2–10mm | Quieter, but slower to react to real drift |
| `maxCorrectionJumpMeters` | 0.15 m (15cm) | 5–30cm | Fewer outliers accepted, but may reject fast real corrections |
| `alphaFast` (still camera) | 0.25 | 0.1–0.5 | Faster convergence, more noise |
| `alphaSlow` (moving camera) | 0.08 | 0.03–0.2 | Smoother, more lag |
| `anchorEMAAlpha` | 0.4 | 0.2–0.6 | Per-anchor smoothing before fusion |
| `lockInSampleCount` | 30 frames | 15–60 | Faster lock-in, but may lock on bad reading |
| `lockInVarianceThreshold` | 0.0001 m² | 0.00005–0.001 | Stricter lock-in condition |

---

## Implementation Order for the Agent

Execute in this exact order. Each step can be verified independently.

1. **Implement `AnchorObservation` struct** in Swift — settle buffer + per-anchor EMA
2. **Implement `fuseVisibleAnchors()`** in `WorldCoordinateManager` — inverse-distance-squared
3. **Add `proposeCorrection()`** — velocity gate + dead zone + dispatch to fusion
4. **Wire `updateSmoothing()` into `renderer(_:updateAtTime:)`** — per-frame EMA on worldRootNode
5. **Run Dart test suite** — `flutter test test/core/ar/tracking_improvements_test.dart`
6. **Mirror changes in Kotlin** `WorldCoordinateManager.kt`
7. **On-device validation** with the corner-POI debug overlay (verify corners stay locked)
8. **Tune alphas and thresholds** using the log file output
9. **Add anchor lock-in** after the core pipeline is stable
10. **Add confidence score (angle factor)** last — it's an optimisation, not a fix

---

## On-Device Validation Checklist

- [ ] Walk toward a single anchor: POIs fade in smoothly (no snap) within 1 second
- [ ] Hold camera still at 0.5m from anchor: POIs must not drift or jitter visibly
- [ ] Wave camera fast past the anchor: no "phantom" POI positions after camera settles
- [ ] Walk the 23m wall: POIs stay on the wall with no visible jump when switching anchors
- [ ] Introduce a bad-tracking frame (cover camera briefly): no position spike after uncovering
- [ ] Two anchors simultaneously visible: POIs blend smoothly between the two corrections
- [ ] Check log file: drift deltas must decrease over the first 30 seconds of a session
