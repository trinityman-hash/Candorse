# Android Decode Bridge (route 1, GDExtension — only build if Phase 0 route 2 fails)

Mirrors `native/ios/README.md`. If needed, this is where a MediaCodec-based
GDExtension bridge would live:

- Decode via `MediaCodec` on a background thread/looper.
- Output surface texture -> OpenGL/Vulkan texture Godot can sample.
- Render thread only ever consumes an already-decoded frame.

Not implemented yet — do not start this until Phase 0 proves it's necessary.
