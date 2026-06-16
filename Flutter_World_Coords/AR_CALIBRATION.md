# AR Calibration

## Purpose

This feature adds an on-site calibration workflow for AR wall deployments so anchors and POIs can be adjusted live while standing in front of the wall, then exported back into config JSON. The wall model is fully 3D, so calibration must support:

- `x`: lateral movement along the wall
- `y`: vertical movement on the wall
- `z`: forward/back offset from the wall plane
- `yaw`: rotation around the wall normal

The main goal is to keep the world frame stable while allowing precise local fitting of anchors and POIs.

## Final Architecture

The final implementation uses a split calibration model:

- `Reference anchor`: the anchor that defines world correction
- `Edited anchor`: a different anchor that can be adjusted locally without moving the world
- `POI selection`: edits POI blueprint coordinates locally, also without moving the world

This is the final "Option 2" workflow because the earlier single-anchor model mixed two responsibilities:

- choosing the anchor used to align the world
- choosing the anchor currently being edited

Separating those roles fixed the main usability and correctness issue.

## Core World-Alignment Model

The native side keeps one corrected world root. All axes, anchors, and POIs are shown relative to that corrected root.

The correction is based on the tracked pose of the reference image versus its configured blueprint pose:

`correctionPose = driftedPose.compose(blueprintPose.inverse())`

That means:

- changing the reference anchor blueprint changes the world correction
- changing a non-reference anchor blueprint must not reapply world correction
- changing a POI must never reapply world correction

This distinction became the controlling rule for the final implementation.

## User Workflow

The implemented calibration workflow is:

1. Enter calibration mode.
2. Choose a reference anchor in the `Ref` tab.
3. Optionally freeze correction.
4. Adjust the reference anchor to align the whole world to the real wall.
5. Switch to `Anchors` and adjust other anchors locally.
6. Switch to `POIs` and adjust POIs locally.
7. Export the final values from logs.
8. Copy those values back into `anchor_blueprint.json` and `poi_config.json`.

This matches on-site usage better than editing raw JSON blindly.

## Flutter Side

### State and Control

The Flutter calibration feature is centered in `lib/features/calibration/`.

Key pieces:

- `CalibrationCubit`: owns calibration state, selections, nudges, export logs, and bridge calls
- `CalibrationState`: stores calibration mode, freeze state, reference anchor, edited anchor, selected POI, image overlay controls, and accumulated adjustments
- `CalibrationPanel`: the compact transparent UI with `Ref`, `Anchors`, and `POIs` tabs
- `CalibrationOverlay`: mounts the calibration UI above the AR viewport

Important final state fields include:

- `referenceAnchorId`
- `editedAnchorId`
- `selectedPoiId`
- `freezeCorrection`
- `referenceImageOpacity`
- per-anchor translation/yaw/width deltas
- per-POI translation deltas

### Bridge Contract

The Flutter-to-native contract lives in `lib/core/ar/ar_session_bridge.dart`.

Important methods:

- `setCalibrationViewState(...)`
- `updateAnchorBlueprint(...)`
- `updatePOIBlueprint(...)`

The final `setCalibrationViewState` payload includes both `referenceAnchorId` and `editedAnchorId`, which was necessary for the split world-vs-local behavior.

## Native Side

The native implementation is centered in:

- `NativeARViewController.kt`
- `WorldCoordinateManager.kt`
- `CalibrationRenderer.kt`

Responsibilities:

- `WorldCoordinateManager`: correction math, lock state, freeze state, current corrected world transform
- `NativeARViewController`: method-channel handling, blueprint updates, correction reapply policy, overlay payload generation, debug logs
- `CalibrationRenderer`: tracked anchor border/reference-image state for overlay rendering

## Final Behavior Rules

The final update behavior is:

- Reference anchor update: `updates_world=true`
- Edited anchor update: `updates_world=false`
- POI update: `world_correction_unchanged=true`

This was the most important functional fix. Earlier in the work, local edits could feel like they were still moving the whole world. The final implementation prevents that by only reapplying correction when the updated anchor is the selected reference anchor.

## Overlay and Visualization

The visual feedback is drawn mostly in Flutter in `ar_overlay.dart`, based on native projection data.

Implemented overlay features:

- anchor borders for detected anchors
- optional reference image overlay per anchor
- opacity control for the reference image
- highlighted reference anchor and edited anchor
- highlighted selected POI and related POIs
- wall-distance feedback coloring
- origin and axis visualization

Important native-to-Flutter payload support added in `overlay_data.dart`:

- origin wall distance
- POI wall distance
- per-corner wall distance for each anchor quad

That allowed the overlay to communicate whether points were close to the expected wall plane.

## 3D Wall-Specific Solutions

Several implementation details were required specifically because this is a wall-aligned 3D calibration problem, not a flat 2D image editor.

### 1. Correct plane interpretation

ARCore image local space was the source of several early rendering mistakes. The important fact is:

- the augmented image plane lives in local `X/Z`
- local `+Y` is the image normal

This mattered for border orientation, image overlay orientation, and wall-distance interpretation.

### 2. Z is a real calibration dimension

The calibration tool had to support `z` edits for both anchors and POIs because real installations are not perfectly flush. The tool therefore treats `z` as a first-class coordinate in:

- live nudges
- export logs
- config files
- wall-distance diagnostics

### 3. Yaw is part of local fitting

Yaw adjustment was implemented for anchors so rotated content can be matched to the real wall orientation without changing the correction source unless that anchor is the reference anchor.

### 4. Physical width matters

Anchor width editing and bitmap aspect-ratio-aware rendering were added so the visual border/image size reflects real image dimensions instead of a fixed placeholder rectangle.

## Major Debugging Steps and Fixes

### World-vs-local ambiguity

Problem:

- using one selected anchor for both lock and edit caused local adjustments to behave like world adjustments

Fix:

- split `referenceAnchorId` from `editedAnchorId`
- restrict world correction reapply to reference-anchor updates only

### POI stability

Problem:

- POI edits needed a stable correction source while editing

Fix:

- POIs remain tied to `nearest_anchor_id`
- POI updates mutate only POI blueprint coordinates
- reference anchor remains the world lock source

### Border and image rendering

Problems encountered:

- borders missing
- reference image not visible
- wrong orientation
- clipping when partially off screen
- stale async cleanup issues

Fixes implemented:

- corrected image-plane basis/orientation
- fixed border-node cleanup behavior
- used unclipped projection for partially visible geometry
- synchronized image loading and quad drawing more carefully

### Wall-plane feedback quality

Problem:

- one color per edge was too coarse and often misleading

Fix:

- interpolate wall depth along each edge and draw many short segments
- this gives a practical pseudo per-pixel depth cue without expensive native geometry sampling

### Freeze semantics

Problem:

- it was unclear when the world should keep following live tracking and when it should hold steady

Fix:

- explicit freeze/unfreeze control in calibration state and native correction manager
- freeze is especially useful during reference-anchor alignment

## Logging and Export

The final workflow relies on plain text tagged logs instead of separate JSON artifact files.

Important log groups include:

- `CALIBRATION_SELECT_REFERENCE`
- `CALIBRATION_SELECT_EDIT_ANCHOR`
- `CALIBRATION_SELECT_POI`
- `CALIBRATION_NUDGE_ANCHOR_XYZ`
- `CALIBRATION_NUDGE_ANCHOR_YAW`
- `CALIBRATION_NUDGE_POI_XYZ`
- `CALIBRATION_ANCHOR_UPDATE`
- `CALIBRATION_POI_UPDATE`
- `CALIBRATION_JSON`
- `CALIBRATION_ADJUSTMENTS_BEGIN/END`

These logs were essential both for debugging and for confirming final exported values before updating config files.

## Tests and Validation

Validation was done repeatedly during implementation with:

- focused widget/unit tests
- `flutter analyze`
- `flutter build apk --debug`
- direct log review from `_out.txt`

The final implementation was validated by checking that:

- reference-anchor edits logged `updates_world=true`
- edited-anchor edits logged `updates_world=false`
- POI edits logged `world_correction_unchanged=true`
- exported JSON matched the final adjustment lines

## Final Outcome

The calibration feature now supports live, on-site adjustment of:

- the world reference anchor
- additional anchors
- POIs
- z offsets
- anchor yaw
- anchor width
- reference image opacity

It also provides:

- stable separation between world calibration and local fitting
- visual wall-distance feedback
- exportable config values
- a workflow suited to repeated visits to the real wall

## Remaining Notes

The calibration path is working, but a few practical limits remain outside the core feature:

- ARCore runtime noise still appears in logs and is normal unless it causes visible drift
- calibration quality still depends on reliable image tracking at the site
- future improvements could include faster export/apply UX or richer visual diagnostics, but the core calibration architecture is in place and working
