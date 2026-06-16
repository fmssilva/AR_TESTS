# AR Stability Previous Implementation — Full Record

Status recorded: 2026-06-16. Deleted in favour of a simpler baseline.

This document is a complete record of the stability/smoothing pipeline that was
built, iterated, and ultimately removed. The code is preserved here for reference
in case any individual idea is worth re-introducing later, one at a time and only
after the simpler baseline is proven stable on device.

---

## 1. Why It Was Built

The original direct-apply path (compute correction → apply immediately to
worldRootNode) produced visible jitter because:

- ARCore VIO takes ~15 s to stabilize after session start.
- Brief FULL_TRACKING bursts at the edge of a detection field produce
  geometrically bad poses ("Quad not convex" in ARCore tracking.cc).
- Two anchors detected simultaneously could produce conflicting corrections
  applied in alternating frames.
- RANSAC failures during fast phone movement inject corrections 9–11 m off.

The pipeline attempted to absorb all of these problems at once.

---

## 2. Pipeline Architecture

The full pipeline lived in `AnchorCorrectionPipeline.kt` plus hooks in
`WorldCoordinateManager.kt` and `NativeARViewController.kt`.

### 2.1 Stage Overview

```
Raw ARCore detection (FULL_TRACKING only)
  │
  ▼
[1] Per-anchor settle buffer
      – first 5 frames per anchor are counted; the anchor is not yet eligible
        for fusion.
  │
  ▼
[2] Per-anchor EMA (alpha = 0.4)
      – each anchor smooths its own raw correction stream before fusing.
      – EMA update was ONLY applied when consecutiveFTFrames >= settleCount
        (the "EMA freeze during unreliable bursts" rule added last).
  │
  ▼
[3] Multi-anchor fusion
      – inverse-distance-squared weighted blend of all settled anchors.
      – changed to use isReliable instead of isSettled in last iteration.
  │
  ▼
[4] Rate-limiter (MAX_JUMP_METERS = 0.15 m per frame)
      – if fused correction is > 0.15 m from current target, step toward it
        instead of snapping; this was supposed to make large corrections
        animate smoothly.
      – if rate-limiter fires for > 30 consecutive frames → RATE_LIMIT_RESET:
        clear all observations and re-settle.
  │
  ▼
[4c] Plausibility filter (MAX_PLAUSIBLE_CORRECTION_METERS = 6.0 m)
      – reject corrections whose translation magnitude exceeds 6 m (RANSAC
        failures inject 9–11 m garbage values).
  │
  ▼
[5] Dead zone (DEAD_ZONE_METERS = 0.004 m = 4 mm)
      – skip updates smaller than 4 mm to suppress sub-pixel jitter.
  │
  ▼
[6] Global EMA tick (ALPHA_SLOW = 0.15, ALPHA_FAST = 0.60)
      – every render frame, worldRootNode was lerped toward smoothedTarget.
      – alpha was switched based on camera angular velocity:
          angular_vel > 0.15 rad/s → ALPHA_FAST (responsive during panning).
          otherwise             → ALPHA_SLOW (stable when still).
  │
  ▼
worldRootNode pose updated every frame
```

### 2.2 AnchorObservation (per-anchor state)

Fields:
- `settleCount = 5` — frames before first contribution.
- `emaAlpha = 0.4f` — per-anchor EMA speed.
- `sampleCount: Int` — total frames seen (ever).
- `consecutiveFTFrames: Int` — frames in the current FULL_TRACKING burst.
- `smoothedCorrection: Pose?` — EMA-smoothed correction (null until first reliable burst).
- `currentDistance: Float` — latest camera distance.
- `settleLogged: Boolean` — log guard.

Properties:
- `isSettled: Boolean = sampleCount >= settleCount`
- `isReliable: Boolean = isSettled && consecutiveFTFrames >= settleCount`

Key method — `addSample(rawCorrection, distance): String?`:
- Increments `sampleCount` and `consecutiveFTFrames`.
- **Only updates EMA when `consecutiveFTFrames >= settleCount`** (last rule added).
  This was added because brief 1–4 frame edge-of-view re-acquisitions with
  alpha=0.4 can shift the EMA 78% toward the wrong value in just 3 frames.
- Returns a log string on SETTLED / first-observe / RELIABLE transitions.

`onPause()`:
- Resets `consecutiveFTFrames = 0` (called on LAST_KNOWN_POSE).
- EMA value is preserved — NOT cleared.

### 2.3 AnchorCorrectionPipeline (global state)

Fields:
- `observations: MutableMap<String, AnchorObservation>` — one entry per anchor.
- `smoothedTarget: Pose?` — the goal the global EMA lerps toward.
- `hasFirstCorrection: Boolean`
- `deadZoneLogCount: Int`
- `consecutiveRateLimitFrames: Int`

Key constants (companion object):
```
MAX_JUMP_METERS                  = 0.15 f   // rate-limiter cap
MAX_CONSECUTIVE_RATE_LIMIT_FRAMES = 30       // resets pipeline after 30 frames
MAX_PLAUSIBLE_CORRECTION_METERS  = 6.0 f    // RANSAC-garbage filter
DEAD_ZONE_METERS                 = 0.004 f  // 4 mm sub-noise gate
ALPHA_SLOW                       = 0.15 f   // global EMA, camera still
ALPHA_FAST                       = 0.60 f   // global EMA, camera moving
MOTION_THRESHOLD_RAD_S           = 0.15 f   // switching threshold
```

Key methods:
- `propose(anchorId, rawCorrectionPose, cameraDistance): Boolean`
  Full pipeline: addSample → isSettled check → fuseSettledAnchors → plausibility →
  dead zone → rate-limiter (or FIRST_CORRECTION snap).
- `tick(currentPose, cameraAngularVelocity): Pose?`
  Advance global EMA toward smoothedTarget.
- `anchorPaused(anchorId)` — calls obs.onPause(); keeps observation.
- `anchorLost(anchorId)` — removes observation from map (STOPPED only).
- `reset()` — clears everything (calibration override).
- `fuseSettledAnchors(): Pose?` (private)
  Filter to `isReliable && smoothedCorrection != null`, then
  inverse-distance-squared weighted blend.
- `diagnosticLine(alpha): String` — throttled tick log.

### 2.4 WorldCoordinateManager additions

Fields added for the pipeline:
- `correctionPipeline: AnchorCorrectionPipeline`
- `currentSmoothedPose: Pose?` — EMA origin for tick().
- `tickLogCount: Int`
- `inHoldMode: Boolean`

Methods added:
- `proposeCorrection(anchorId, driftedPose, cameraDistance)`:
  Computes `correctionPose = driftedPose.compose(blueprintPose.inverse())`,
  calls `correctionPipeline.propose()`.
  Blocked entirely when `calibrationAnchorLockId != null`.
- `tickSmoothing(cameraAngularVelocity: Float)`:
  Called every render frame. If no active anchors → HOLD mode (no update).
  Otherwise → `correctionPipeline.tick()` → `setWorldRootPose(smoothed)`.
- `anchorPaused(anchorId)` — removes from visibleAnchors, calls pipeline.anchorPaused.
- `anchorLost(anchorId)` — removes from visibleAnchors, calls pipeline.anchorLost.

### 2.5 NativeARViewController additions

- `prevCameraQuaternion: FloatArray?` — last frame camera rotation.
- `prevFrameTimestamp: Long` — last frame timestamp (ns).
- Per-frame: angular velocity = `2 * acos(|dot(q_prev, q_curr)|) / dt`.
- `worldCoordinateManager.tickSmoothing(angularVelocityRadS)` called every frame.
- LAST_KNOWN_POSE branch in `handleAnchorTracked`: calls `anchorPaused` instead of
  `anchorLost`.
- STOPPED branch (outer when): still calls `anchorLost`.

---

## 3. Bugs Encountered And Fixes Applied (Chronological)

### 3.1 Velocity gate locked on bad VIO-init correction

**Problem**: The original velocity gate rejected any correction more than 0.15 m from
the last accepted value. When ARCore VIO initializes badly, the first accepted
correction could be 0.5–2 m off. The gate then permanently blocked all future
(correct) updates.

**Fix**: Replaced hard rejection with a rate-limiter that steps toward the new value
by MAX_JUMP per frame instead of rejecting.

### 3.2 RANSAC failures injecting 9–11 m corrections

**Problem**: During fast phone movement or VIO restart, ARCore RANSAC failures
produced corrections 9–11 m from the real value. These passed the rate-limiter
(after 30+ steps × 0.15 m = 4.5 m), walking the world to the wrong position.

**Fix**: Plausibility filter: reject any correction whose translation magnitude
exceeds 6 m.

### 3.3 Consecutive rate-limit reset

**Problem**: If the plausibility filter let through a wrong value, the rate-limiter
would keep stepping toward it for 30+ frames before giving up, moving the world
to an intermediate wrong position.

**Fix**: If the rate-limiter fires for more than MAX_CONSECUTIVE_RATE_LIMIT_FRAMES
(30), clear all observations and re-settle from scratch.

### 3.4 anchorLost on LAST_KNOWN_POSE destroying EMA

**Problem**: When `handleAnchorTracked` received a LAST_KNOWN_POSE tracking method,
the original code called `anchorLost()`, destroying the per-anchor observation.
When FULL_TRACKING resumed (often 1–3 frames later at the anchor edge), a fresh
observation was created and went through a 5-frame settle on edge-view data.
Each edge burst produced a different settled value. The rate-limiter would step
toward each new value, causing POI positions to drift and jump.

**Evidence in logs**:
```
[TRACKING] FULL_TRACKING -> LAST_KNOWN_POSE
[PIPELINE] anchor_lost id=... remaining=0
[TRACKING] LAST_KNOWN_POSE -> FULL_TRACKING  (1 frame later)
[PIPELINE] SETTLED correction=(bad_value)
[PIPELINE] rate_limit delta=0.2m  (starts moving worldRootNode)
[TRACKING] FULL_TRACKING -> LAST_KNOWN_POSE  (drops out again after 1 frame)
```

**Fix**: Call `anchorPaused()` (resets `consecutiveFTFrames` only) instead of
`anchorLost()` for LAST_KNOWN_POSE. Only STOPPED fires `anchorLost`.

### 3.5 EMA corrupted by brief FULL_TRACKING re-acquisitions

**Problem**: Even after fix 3.4, the per-anchor EMA was still being updated
during brief 1–4 frame FULL_TRACKING bursts between LAST_KNOWN_POSE periods.
With alpha=0.4, three bad edge-view frames shift the EMA 78% toward the wrong
value. Observed in logs: two consecutive 5-frame RELIABLE bursts from the same
anchor, same physical location, gave corrections differing by 0.95 m because
brief edge bursts had corrupted the EMA in between.

**Fix**: Only update the EMA when `consecutiveFTFrames >= settleCount`. During
the first 4 frames of any new burst, count frames but freeze the EMA value.

### 3.6 Log spam from anchorLost on LAST_KNOWN_POSE (cosmetic)

**Problem**: Logs flooded with "anchor_lost" every frame for LAST_KNOWN_POSE.

**Fix**: Only log when the observation was actually in the map (cosmetic guard).

### 3.7 Calibration mode affected by pipeline

**Problem**: When calibration was active, pipeline EMA corrections were still
moving worldRootNode via tickSmoothing.

**Fix**: `proposeCorrection()` returns early when `calibrationAnchorLockId != null`.

---

## 4. Dart Test Suite (correction_pipeline_test.dart)

18 tests covering:
- EMA convergence with noise (alpha 0.15 → within 15 mm after 30 frames).
- Fast vs slow alpha convergence rate.
- Alpha=0 freezes, alpha=1 snaps.
- Velocity gate: 3 cm passes, 20 cm rejects.
- Outlier sequence: 5 good + 1 outlier → gate rejects outlier.
- Dead zone: 3 mm below threshold, 5 mm above.
- Multi-anchor fusion: closer anchor dominates, equal distance gives midpoint,
  single anchor returns its own correction unchanged.

---

## 5. Root Problems That Were Never Solved

Despite all the above fixes, the pipeline was still producing bad results in the
following scenario documented in the final session log (`_out.txt`, 2026-06-16):

With two anchors detected:
1. One anchor at ~0.5 m (good reading, RELIABLE burst, EMA = (0.415, 0.030, -0.165)).
2. That anchor drops to LAST_KNOWN_POSE, then brief re-acquisitions corrupted EMA.
3. Second RELIABLE burst same anchor: EMA = (0.973, 0.197, -0.897) — 0.95 m off.
4. Rate-limiter fires 7+ consecutive steps, moving world to wrong intermediate position.
5. Second anchor (TOP_RIGHT) was never reaching isReliable because it was bouncing
   FULL_TRACKING ↔ LAST_KNOWN_POSE every 1–2 frames continuously.

**Root issue**: ARCore at anchor-detection edges produces genuinely bad pose
estimates ("Quad is not convex. Cancel tracking."). No amount of EMA freezing or
isReliable gating can help when the 5-frame reliable burst itself contains ARCore
geometrically bad poses. The complexity added to the pipeline (EMA + rate-limiter +
isReliable + EMA freeze) was fighting symptoms of an underlying ARCore data quality
problem that no Kotlin filter can fully compensate for.

---

## 6. Decision To Revert

The pipeline was removed and replaced with a much simpler baseline:

- **FULL_TRACKING filter only**: reject all LAST_KNOWN_POSE frames.
- **Best anchor (1-hot)**: at any time, only the single closest-distance anchor
  contributes to corrections.
- **5-frame batch average**: collect 5 consecutive FULL_TRACKING frames from the
  best anchor, then apply the mean as a single correction to worldRootNode.
  The world only updates when a complete batch is ready (~5–10 frames when stable,
  never when tracking is unstable).
- **Calibration bypass**: when calibration lock is active, the batch filter is
  bypassed entirely (same as before).

This baseline is deterministic, testable, and produces a stable world position
because the world only ever moves to a mean of 5 actual good detections, never
to an EMA that was corrupted by edge-view noise.

Stability features can be re-added one at a time only after the baseline is
proven to produce correct positions on device.
