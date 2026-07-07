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
- `scripts/timeline/timeline_data.gd` — minimal Track/Clip data model +
  autoload singleton, command-stack stub for undo/redo (Module A).
- `scripts/export/decode_stress_test.gd` — the actual Phase 0 test harness:
  loads N overlapping video tracks via `VideoStreamPlayback`/`ImageTexture`
  and logs frame times, so you can see immediately whether route (2) from
  Module B (FFmpeg/ImageTexture.update()) holds 60fps with 3 overlapping
  clips on your target devices.
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
Open this in Godot 4.2+, add 3 real video files under `res://test_media/`,
run `decode_stress_test.gd` on a mid-range Android device and an iPhone, and
record actual frame times. If it holds 60fps, proceed to Phase 1. If not,
the brief says: stop and rethink the architecture before building UI — don't
skip that gate.
