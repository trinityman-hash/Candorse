# iOS Decode Bridge (route 1, GDExtension — only build if Phase 0 route 2 fails)

If `decode_stress_test.gd` shows route (2), FFmpeg + `ImageTexture.update()`,
can't hold 60fps on target iPhones, this is where an AVFoundation-based
GDExtension bridge would live.

Expected surface:
- Decode `AVAssetReader` output on a background queue.
- Write decoded `CVPixelBuffer` into a Metal texture Godot can sample
  (`Texture2DRHI` / equivalent import path for 4.x).
- Never touch the render thread except to hand off an already-decoded frame.

Not implemented yet — do not start this until Phase 0 proves it's necessary.
