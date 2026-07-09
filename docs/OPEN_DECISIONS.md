# Open Decisions (brief §7) — Resolutions

The brief lists four open decisions the coding agent must resolve early
and document, not defer. Status as of this commit:

## 1. GDExtension bridge vs. native FFmpeg decode (Module B)
**Not yet resolved — still blocking.** This requires the Phase 0 stress
test to actually run on real Android/iPhone hardware first; there is no
responsible way to pick route (1) or (2) from simulated numbers alone.
See `docs/PHASE0_STATUS.md` and `docs/HOW_TO_RUN_PHASE0.md`. Everything
built so far (timeline, UI, camera, keyframes, environment) is
deliberately decode-route-agnostic so this decision doesn't force a
rewrite once made.

## 2. Roam input scheme: twin-stick vs. drag-to-orbit
**Not yet resolved.** `timeline_camera.gd`'s `_handle_roam_input()`
currently has a desktop keyboard fallback (arrow keys) for development
testing only — neither touch scheme is implemented. This is a real UX
decision that benefits from testing both on an actual touchscreen rather
than guessing; deferring the choice itself is reasonable, but the
placeholder should not be mistaken for either final scheme.

## 3. Subdivision granularity default for curvable tracks
**Resolved: `subdivisions = 1` by default, opt-in per track.**
`video_track_mesh.gd` only subdivides when a track's `curvable` flag is
true (per §3's correction: background tracks stay flat 1×1 quads). No
default subdivision count has been tuned against real curve-smoothness-
vs-perf tradeoffs yet — `subdivisions: int = 1` is a placeholder that
produces a flat quad even when `curvable = true` until someone picks a
real number (8? 16?) against an actual curved-track visual test. Tracked
here so it isn't mistaken for a deliberate final value.

## 4. Chroma key: v1 feature or deferred to Phase 4
**Resolved: built now, explicitly scoped as "basic."**
`shaders/chroma_key.gdshader` implements YCbCr-chroma-distance keying
with single-band edge feathering and a simple spill-suppression pass
(desaturates the dominant key-colored channel on edge pixels only). This
is deliberately NOT a full keyer — no light wrap, no multi-sample despill,
no per-pixel edge refinement beyond one smoothstep. It's a separate
shader pass from `video_compositor.gdshader` (per Module E), applied only
to tracks that opt in, so plain video/overlay tracks pay zero extra GPU
cost. If real green-screen footage testing shows this basic version isn't
enough, upgrading it is a contained shader change — it was not "assumed
basic" by skipping the harder cases, they're just not implemented yet.
