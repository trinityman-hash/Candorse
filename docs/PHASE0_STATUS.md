# Phase 0 Status — Decode Pipeline Risk Validation

Per `docs/architecture.md` §6, Phase 0 must be proven before any UI work starts.
This scaffold gives you the skeleton to run that proof — it does NOT claim the
proof is done. You still need to run this on real Android/iOS hardware.

## What's here
- Repo structure matching the brief's Module layout (§5).
- `project.godot` — mobile-render-mode Godot 4 project, portrait, boots to
  `editor_main.tscn`.
- `scripts/tracks/video_track_mesh.gd` — quad mesh node driven by a Track
  resource, NOT by direct transform edits (per Module A: single source of
  truth is the data model).
- `scripts/timeline/timeline_data.gd` — Track/Clip data model + autoload
  singleton with a real command-pattern undo/redo stack (add/remove track,
  add/remove/ripple-delete/trim/split clip — all invertible, min. 30 steps).
- `scripts/export/decode_stress_test.gd` — the Phase 0 test harness.
  **Fixed 2026-07-08:** the original version only timed
  `VideoStreamPlayer._process()`, which measures Theora decode + the
  player's own 2D draw — it never touched the 3D quad/shader pipeline the
  app actually uses, so a passing result would have been a false pass. It
  now pulls each player's `get_video_texture()` and pushes it through
  `VideoTrackMesh.update_frame_texture()` every frame — the real call path
  — and reports `avg_upload_ms` (GPU upload cost alone) separately from
  overall frame time, so you can tell decode cost apart from upload cost.
- `scenes/tests/phase0_stress_test.tscn` — ready-to-wire scene for the
  harness above (camera + light + 3 `VideoStreamPlayer` slots). You still
  need to drop in real `.ogv` test media per
  `docs/HOW_TO_RUN_PHASE0.md`.
- `shaders/video_compositor.gdshader` — premultiplied-alpha compositor stub.
- `shaders/displacement_curve.gdshader` — vertex-bend stub (cylinder wrap
  only for now; page-curl/ripple are TODO, gated to Phase 3 per §6).
- `native/ios/`, `native/android/` — empty, with README stubs describing
  what a GDExtension bridge would need to expose if you outgrow route (2).

## What's NOT here yet (by design — later phases)
- Roam camera (Module C) — Phase 2.
- Environment/runtime modeling (Module D) — Phase 2.
- Chroma key, transitions, LUT grading (Module E full) — Phase 3.
- Any native Swift/Kotlin decode bridge code — only stub after Phase 0
  proves whether you even need route (1) over route (2).

## Immediate next step for you
Open this in Godot 4.2+, follow `docs/HOW_TO_RUN_PHASE0.md` to add 3 real
`.ogv` test files and wire `scenes/tests/phase0_stress_test.tscn`, then run
it on a mid-range Android device and an iPhone. Watch both `avg_fps` and
`avg_upload_ms` in the log. If it holds 60fps with upload cost a small
fraction of the frame budget, proceed to Phase 1. If not, the brief says:
stop and rethink the architecture before building UI — don't skip that gate.
