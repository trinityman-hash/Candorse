# How to Run the Phase 0 Decode Stress Test

This is the one gate the brief says not to skip (`docs/architecture.md` §6).
Flat-editor work (Phase 1) doesn't strictly depend on it, but don't ship
past Phase 2 without running this on real devices.

## 1. Install Godot
Godot 4.2 or later, standard editor build, from godotengine.org. If you
want to test on-device (you should — desktop numbers don't predict mobile
decode performance), also grab the export templates for your target OS
version from the same download page.

## 2. Open the project
Open `project.godot` (repo root) in the Godot editor.

## 3. Get test footage into a decodable format
Godot's built-in `VideoStreamPlayer` only natively reads Theora (`.ogv`).
Convert 3 short clips (10-30s each, so they meaningfully overlap):

```bash
ffmpeg -i clip1.mp4 -c:v libtheora -c:a libvorbis test_media/clip1.ogv
ffmpeg -i clip2.mp4 -c:v libtheora -c:a libvorbis test_media/clip2.ogv
ffmpeg -i clip3.mp4 -c:v libtheora -c:a libvorbis test_media/clip3.ogv
```

Create `res://test_media/` in the project and drop the 3 `.ogv` files there.

## 4. Build the test scene
- New Scene → root node type `Node`.
- Attach `scripts/export/decode_stress_test.gd` to the root.
- Add 3 `VideoStreamPlayer` children.
- For each, set `stream` (Inspector) to one of the 3 `.ogv` files.
- Select the root node, in the Inspector drag all 3 `VideoStreamPlayer`
  nodes into the `video_players` array exported by the script.
- Save as `scenes/tests/phase0_stress_test.tscn`.

## 5. Run it
F6 to run the current scene. Watch the Output panel. Every 60 frames you'll
see a line like:

```
[Phase0] tracks=3 avg_frame_ms=15.87 avg_fps=63.0 worst_frame_ms=18.20
```

## 6. Run it on real hardware (the part that actually matters)
Desktop editor performance will not tell you anything meaningful about
mobile GPU/decode behavior. To test for real:
- Project → Export → add an Android or iOS export preset.
- Connect your device via USB with debugging enabled.
- Use the one-click deploy button (top-right of the editor, device icon)
  to build and run directly on the connected device.
- Watch the same log via `adb logcat` (Android) or the Xcode console (iOS)
  while the scene plays.

## 7. Interpret the result
Per `decode_stress_test.gd`'s built-in interpretation guide:
- **avg_fps consistently ≥ 58** with all 3 tracks playing: route (2),
  FFmpeg/`ImageTexture.update()`, is viable for v1 — proceed to Phase 1/2
  with confidence.
- **Frequent worst_frame_ms spikes above ~33ms, or avg_fps well under 60**:
  route (2) isn't enough on this hardware tier. Evaluate route (1), the
  GDExtension platform-decoder bridge (`native/ios/`, `native/android/`),
  before building more UI on an unstable foundation — this is the
  brief's explicit stop-and-rethink gate.

Document whichever result you get (and which route you choose) in
`docs/PHASE0_STATUS.md` so it isn't re-litigated later.
