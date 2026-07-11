# Color Engine Status (Module E, color/grading slice)

Per the repo's own standard (brief §7: "resolve early and document, not
defer"), this tracks what's real vs. still open in color grading.

## What's here
- `shaders/video_compositor.gdshader` — real DaVinci-style Lift/Gamma/
  Gain wheels (`lift`/`gamma`/`gain` uniforms), Brightness/Contrast/
  Saturation, a generic color matrix, per-channel tone curves, and a
  Vignette, applied in that order, ahead of the LUT blend. LUT sampling
  remaps through `lut_domain_min`/`lut_domain_max` instead of assuming a
  0..1 domain, so LUTs with a non-default DOMAIN_MIN/MAX grade correctly.
- `scripts/color/lut_loader.gd` — a real `.cube` parser (Adobe/DaVinci
  standard format). Builds a `Texture3D` directly from parsed data — no
  placeholder/identity fallback on a bad file; malformed input returns
  `null` with a specific `push_error()`, never fabricated data. LUT_1D
  cubes are explicitly rejected (not silently misread as 3D).
- `scripts/color/hsl_curves.gd` — Master/Red/Green/Blue tone curves,
  each a real Godot `Curve` resource a UI curve-editor widget can bind
  to directly. Composition order matches DaVinci/Photoshop: Master
  evaluated first, then the per-channel curve on that result. Baked
  CPU-side (only when a point actually changes) into a single 256x1
  RGB8 lookup texture. `is_identity()` lets untouched tracks pay zero
  extra GPU cost, same "opt-in, zero cost when unused" shape as
  `chroma_key.gdshader`.
- `scripts/color/color_grade_state.gd` — holds one track's grade
  (wheels, brightness/contrast/saturation, vignette, matrix, curves,
  LUT) and pushes it onto a `ShaderMaterial`. Now also has `clone()` /
  `copy_from()` / `equals()` — full independent-copy, in-place-restore,
  and no-op-diff primitives, added specifically so grading edits can be
  snapshotted for undo without a class-per-command wrapper (see below).
- `assets/luts/identity.cube` — a real, hand-verified 2×2×2 identity LUT
  for testing the loader end-to-end.
- **UI wiring (new).** `Track.color_grade` (timeline_data.gd) is now a
  real field, lazily created via `TimelineData.get_or_create_color_grade`.
  `VideoTrackMesh` applies it to its material on every `track_changed`
  (`_apply_color_grade`), so a grade sticks whether it arrived via a
  live drag or an undo/redo restore. `scripts/ui/color_grade_panel.gd`
  is a slider-based grading panel (Lift/Gamma/Gain per RGB channel,
  brightness/contrast/saturation, vignette, LUT load/clear/mix) opened
  via a "Grade" button on each video/overlay/sticker track row in
  `timeline_ui.gd`. Every shader parameter has a 1:1 slider here — this
  is explicitly sliders, not a graphical circular color wheel; a real
  wheel is a separate custom-drawn Control (puck hit-testing, 2D
  hue/luma math) and stays open below.
  - Undo model: **one entry per grading session**, not per slider tick.
    `TimelineData.begin_color_grade_edit(track_id)` snapshots the grade
    when the panel opens; `commit_color_grade_edit(track_id)` diffs
    against that baseline when it closes (via Done or re-clicking
    Grade) and pushes a single undo/redo command — matching how every
    NLE treats "adjusted the grade" as one user action. A session that
    changes nothing pushes nothing (`ColorGradeState.equals`).
    Live-drag frames go through `notify_color_grade_changed()`, which
    re-emits `track_changed` without touching the undo stack — the same
    pattern `TimelineData.set_playhead()` already uses for continuous
    input.

## What's NOT here yet (documented, not deferred silently)
- **Graphical color wheel widget.** Lift/Gamma/Gain are RGB sliders,
  not a circular puck-drag wheel. Same parameter set either way.
- **Automated tests for the curve-baking or undo-session math.** No
  test runner (e.g. GUT) is wired in yet, for any module.
- **Sharpness slider.** Needs a `texel_size` uniform tangled up with the
  still-undecided Module B decode route.
- **Curve editor screen.** `HSLCurves`'s point API
  (`add_point`/`move_point`/`remove_point`) is shaped for a drag-to-edit
  widget; no UI drives it yet.
- **LUT preset library / device-storage import flow.** LUT loading is a
  raw file-picker only; `assets/luts/` still holds just the identity
  test LUT.
- **Grading through an active clip transition.**
  `transition_crossfade.gdshader` has its own uniform set
  (texture_out/texture_in/blend) and does not grade yet —
  `VideoTrackMesh._apply_color_grade` explicitly no-ops while
  `_in_transition` rather than silently applying to the wrong material.
