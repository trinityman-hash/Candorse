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
- `scripts/color/hsl_curves.gd` — **new.** Master/Red/Green/Blue tone
  curves, each a real Godot `Curve` resource a UI curve-editor widget
  can bind to directly. Composition order matches DaVinci/Photoshop:
  Master evaluated first, then the per-channel curve on that result.
  Baked CPU-side (only when a point actually changes — not per frame)
  into a single 256x1 RGB8 lookup texture; the shader does three cheap
  `texture2D` fetches per pixel instead of evaluating a spline per
  pixel. `is_identity()` lets `ColorGradeState` leave
  `hsl_curves_enabled = false` (a static shader branch) whenever the
  curves haven't been touched, so untouched tracks pay zero extra GPU
  cost — same "opt-in, zero cost when unused" shape as
  `chroma_key.gdshader`. Anchor points (x=0, x=1) on every channel are
  permanently protected from deletion so `sample_baked()` never
  extrapolates flat past a missing domain edge; `reset_channel()` /
  `reset_all()` restore identity instead.
- `scripts/color/color_grade_state.gd` — holds one clip's/track's grade
  (wheels, brightness/contrast/saturation, vignette, matrix, curves,
  LUT) and pushes it onto a `ShaderMaterial`. Doesn't know about
  TimelineData or undo/redo by design — same separation Module A
  already uses elsewhere (data model vs. node/material, single source
  of truth).
- `assets/luts/identity.cube` — a real, hand-verified 2×2×2 identity LUT
  (no-op grade) for testing the loader end-to-end without needing a
  third-party LUT file.

## What's NOT here yet (documented, not deferred silently)
- **Automated tests for the curve-baking math.** `hsl_curves.gd`'s
  `bake()` is straightforward (256-sample `Curve.sample_baked` calls
  composed in a fixed order) but has no regression coverage yet — the
  repo has no test runner/addon (e.g. GUT) wired in at all yet, for any
  module. Adding one is worth doing as its own pass rather than
  bootstrapping test infra as a side effect of this change.
- **Sharpness slider.** Needs neighbor-texel sampling (unsharp mask),
  which needs a `texel_size` uniform derived from the actual decoded
  frame resolution — tangled up with whichever decode route Module B
  settles on (frame dimensions available at different points depending
  on route), so it's cleaner to land after that decision than to guess
  at plumbing now.
- **UI**: no color-wheel widgets, curve editor screen, or LUT-picker
  screen yet — `ColorGradeState`/`HSLCurves` are the data/shader layer
  those will drive. `HSLCurves`'s point API
  (`add_point`/`move_point`/`remove_point`) is already shaped for a
  drag-to-edit curve widget: `move_point` returns the point's new index
  since dragging a point's x-offset can re-sort Curve's internal point
  list, which a UI needs to track the "currently dragged" point
  correctly across the gesture.
- **LUT preset library / import flow**: `assets/luts/` currently holds
  only the identity test LUT. A real preset pack and an in-app "import
  .cube from device storage" flow are separate, larger pieces of work.
