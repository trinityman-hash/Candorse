# Color Engine Status (Module E, color/grading slice)

Per the repo's own standard (brief §7: "resolve early and document, not
defer"), this tracks what's real vs. still open in color grading.

## What's here
- `shaders/video_compositor.gdshader` — extended with real DaVinci-style
  Lift/Gamma/Gain wheels (`lift`/`gamma`/`gain` uniforms), Brightness/
  Contrast/Saturation, and a Vignette, applied in that order, ahead of
  the pre-existing generic color matrix and LUT blend. LUT sampling now
  remaps through `lut_domain_min`/`lut_domain_max` instead of assuming a
  0..1 domain, so LUTs with a non-default DOMAIN_MIN/MAX grade correctly.
- `scripts/color/lut_loader.gd` — a real `.cube` parser (Adobe/DaVinci
  standard format). Builds a `Texture3D` directly from parsed data — no
  placeholder/identity fallback on a bad file; malformed input returns
  `null` with a specific `push_error()`, never fabricated data. LUT_1D
  cubes are explicitly rejected (not silently misread as 3D).
- `scripts/color/color_grade_state.gd` — holds one clip's/track's grade
  (wheels, brightness/contrast/saturation, vignette, matrix, LUT) and
  pushes it onto a `ShaderMaterial`. Doesn't know about TimelineData or
  undo/redo by design — same separation Module A already uses elsewhere
  (data model vs. node/material, single source of truth).
- `assets/luts/identity.cube` — a real, hand-verified 2×2×2 identity LUT
  (no-op grade) for testing the loader end-to-end without needing a
  third-party LUT file.

## What's NOT here yet (documented, not deferred silently)
- **HSL curves per channel** (brief Module E / feature list). Needs
  either per-channel `Curve` resources baked to lookup textures and
  sampled in-shader, or an equivalent GPU-side spline evaluation — real
  work, deserves its own pass rather than being bolted onto this one.
- **Sharpness slider.** Needs neighbor-texel sampling (unsharp mask),
  which needs a `texel_size` uniform derived from the actual decoded
  frame resolution — tangled up with whichever decode route Module B
  settles on (frame dimensions available at different points depending
  on route), so it's cleaner to land after that decision than to guess
  at plumbing now.
- **UI**: no color-wheel widgets, curve editors, or LUT-picker screen
  yet — `ColorGradeState` is the data/shader layer those will drive.
  Follows the same order-of-operations as the rest of this repo: data
  model and rendering first, UI wiring after.
- **LUT preset library / import flow**: `assets/luts/` currently holds
  only the identity test LUT. A real preset pack and an in-app "import
  .cube from device storage" flow are separate, larger pieces of work.
