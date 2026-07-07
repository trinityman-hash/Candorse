# SPATIAL VIDEO EDITOR — MASTER BRIEF
### "A video editor built inside a 3D world" — Godot 4, mobile-first

---

## 1. PRODUCT VISION

Every mainstream mobile editor (CapCut, InShot, DaVinci mobile) treats the timeline as a flat
2D stack: clips are rectangles, overlays are rectangles, effects are shaders applied to
rectangles. This product rejects that assumption.

**Core bet:** if video and image layers are just textured quads *placed in real 3D space*,
then a user can do everything a flat editor does, PLUS:
- move a virtual camera through the layer stack for real parallax (multiplane camera, the
  technique behind Disney's original multiplane camera and every AE "3D camera + 2D layers"
  title sequence)
- build actual 3D environments (lights, geometry, fog, particles) *around* footage, so the
  footage becomes one element in a living scene instead of the whole picture
- deform the video mesh itself (curl, curve, ripple, page-peel) because it's real geometry,
  not a texture composited by a 2D layer engine
- drop true 3D models (product shots, low-poly characters, text extrusions) into the same
  coordinate space as footage, lit by the same lights, so 2D and 3D content blend natively

**Positioning:** "CapCut for editing speed, Blender for compositing depth." Not a Blender
clone — a *video editor* whose compositing layer happens to be a real 3D scene graph.

**Honest scope boundary (stated up front so it doesn't get re-litigated mid-build):**
The camera roams *in front of and around* the layer stack within a bounded volume, not
"anywhere including behind." Video quads are single-sided textured planes — there is
nothing to see from behind. Roam mode is scoped to a frustum/bounding-box the user works
inside, not unrestricted flight.

---

## 2. ARCHITECTURAL PILLARS

1. **The Stage** — `SubViewport` containing the entire timeline as a live 3D scene.
   Tracks are quads (or subdivided grids for curvable tracks) at incrementing Z depths.
2. **Dual Camera** — `Camera3D` that smoothly interpolates between:
   - EDIT mode: orthographic, locked, flat — this is what 95% of editing happens in.
   - ROAM mode: perspective, touch-driven spectator movement, bounded to a working volume.
3. **Environment as a first-class layer** — lights, fog, particles, and modeled geometry
   are not "effects," they're scene nodes that sit alongside video quads and affect them
   (real shadows, real lighting falloff) via the standard Godot renderer.
4. **Runtime modeling** — `SurfaceTool`/`ArrayMesh` lets users generate simple 3D primitives
   at runtime (extruded text, primitives, simple paths) without leaving the app or hitting
   an "export to Blender" round trip.
5. **Shader-driven compositing** — alpha blending, color grading, curving/displacement, and
   transitions all live in shaders so the mobile GPU carries the cost, not the CPU.

---

## 3. CORRECTIONS TO THE ORIGINAL PITCH (carry these into implementation)

| Original assumption | Reality | Correction |
|---|---|---|
| Occlusion culling skips covered tracks | Alpha-blended layers can't use early-Z / occlusion culling — transparency forces back-to-front draw order | Budget for full per-track fragment cost on blended tracks; only apply occlusion logic to fully opaque background tracks |
| "Fly anywhere, including behind clips" | Quads are single-sided; behind = blank | Roam mode bounded to a frustum in front of the stack; document this as a hard UX constraint, not a bug |
| Quads = the performance bottleneck | 4-vertex quads are free for any mobile GPU | The real bottleneck is **video decode → GPU texture upload** per frame per visible track. This must be solved before anything else, see Module B |
| Curving works the same for video and static images | Video textures update every frame; re-evaluating a displacement shader against a streaming texture is real cost | Gate "fancy geometry" (subdivided/curved mesh) to foreground/hero tracks only; background tracks stay flat 1×1 quads by default |

---

## 4. MODULE BREAKDOWN (for the coding agent)

### Module A — Timeline & Scene Graph Core
- Track = data model (clip list, in/out points, transform, z-depth, "flat vs curvable" flag)
  driving a corresponding `video_track_mesh.gd` node.
- Multi-track: video, audio (no mesh, drives audio bus only), overlay/graphics, text, sticker.
- Trim, split, ripple-delete, drag-reorder — mutate the data model, scene nodes rebuild
  from it. Never let UI drag directly mutate mesh transforms; single source of truth is
  the timeline data model.
- Undo/redo: command-pattern stack (min. 30 steps), operating on the data model, not nodes.
- Snap-to-grid / magnetic timeline: snap thresholds computed in timeline-seconds, not pixels.

### Module B — Media Decode Pipeline (**highest technical risk — build first, prototype before anything else**)
- Godot does not have a first-class mobile hardware video decode path out of the box.
  Two viable routes, pick one early and document why:
  1. **GDExtension bridging to platform decoders** (AVFoundation on iOS, MediaCodec on
     Android) that write decoded frames into a `Texture2DRHI`/`ImageTexture` Godot can
     sample. Higher effort, best performance, true hardware decode.
  2. **Native FFmpeg-based frame extraction** running off the render thread, feeding
     `ImageTexture.update()` per frame. Lower effort, higher CPU cost, easier to ship v1.
- Whichever is chosen: decode must run on a background thread/isolate; the render thread
  only ever consumes an already-decoded frame. This is the single biggest determinant of
  whether "60Hz mobile preview" is true or marketing copy — validate with a 3-track
  overlapping-clip stress test before building anything else on top.
- Frame cache/lookahead strategy for scrubbing (decode ahead of playhead, discard behind).

### Module C — Camera System
- `timeline_camera.gd`: extends `Camera3D`. Orthographic↔Perspective interpolation via
  `Camera3D.set(fov/size)` tween, not a hard cut.
- Roam movement relative to `global_transform.basis` (forward/back/strafe/up-down), fed by
  mobile touch vectors (twin virtual joystick or drag-to-orbit — pick one, twin-stick is
  more precise for cinematic moves, drag-to-orbit is more mobile-native/discoverable).
- Bounding volume clamp so roam mode can't clip behind the stack.

### Module D — Environment & Runtime Modeling
- `runtime_modeler.gd`: `SurfaceTool`-based primitive generator (cube, extruded text/path,
  simple polygon) with a real-shadow-casting default material.
- Lighting rig presets (key/fill/rim) as draggable `Light3D` nodes users can place, color,
  and animate on the timeline like any other layer.
- Particle/fog nodes as optional environment layers — animated independent of video content,
  this is the mechanism behind "surroundings become the animation" from the brief.

### Module E — Shader Pipeline
- `video_compositor.gdshader`: premultiplied-alpha compositing, 4×4 color matrix for
  grading/LUT, `.cube` LUT sampling via 3D texture.
- Curving/displacement: grid-subdivided quads (parametrize subdivision count per track),
  vertex-shader bend functions (cylinder wrap, page-curl, ripple/noise UV displacement).
  This one shader family underlies: photo-curl transitions, screen-in-screen tilt, water/
  heat distortion, and pseudo-parallax from a luminance-based fake depth map.
- Chroma key as a separate fragment shader pass (basic spill suppression, not full keyer).
- Transitions implemented as either (a) shader crossfade between two sampled tracks or
  (b) geometry transitions (the page-curl case) — keep these as separate systems, don't
  force transitions to be pure shaders when the visual requires real geometry motion.

### Module F — Audio Engine
- Per-track volume envelope (keyframed, not just a single fader).
- Waveform generation for timeline display (precompute once per import, cache result).
- Fade in/out per clip, audio detach from video, voiceover recording, beat-marker detection
  (basic onset detection is enough for v1 — don't over-invest in beat-matching accuracy).

### Module G — Text, Graphics, Keyframing
- Kinetic text presets and text-on-path reuse the Module D extrusion pipeline (text is
  just runtime-modeled geometry with a font-to-mesh step).
- Generic keyframe system (position/scale/rotation/opacity) that any layer type (video,
  text, 3D object, light) can subscribe to — build this once, generically, not per-layer-type.

### Module H — Export
- Resolution/FPS/format matrix (480p–4K, 24/30/60fps, H.264/H.265).
- Render-to-texture the `SubViewport` at target resolution/fps, feed frames to the same
  native encode path chosen in Module B (symmetry: whatever decodes footage in should
  encode the result out).
- Background export (don't block UI thread), progress callback, direct share intents.

### Module I — UI/UX: keeping "3D mode" from becoming a mess
- Default state is always EDIT mode (orthographic, flat) — ROAM and environment-building
  are opt-in modes entered deliberately, not the default editing surface.
- Two clearly separated surfaces: **Timeline/Trim UI** (2D, familiar, CapCut-like) and
  **Scene/Roam UI** (3D, entered via an explicit "enter scene" affordance). Never blend
  both control schemes on screen simultaneously.
- Every 3D-only feature (lighting placement, environment modeling, roam camera) should
  have a "snap back to flat" one-tap reset, so a user who doesn't want the 3D depth of
  this product can ignore it entirely and it still behaves like a normal editor.

---

## 5. REPO STRUCTURE

```
/
├── project.godot
├── addons/
│   └── decode_bridge/        # GDExtension: platform video decode/encode bridge
├── scenes/
│   ├── editor_main.tscn
│   ├── timeline_stage.tscn   # SubViewport + track root
│   └── ui/
├── scripts/
│   ├── camera/timeline_camera.gd
│   ├── tracks/video_track_mesh.gd
│   ├── modeling/runtime_modeler.gd
│   ├── timeline/ (data model, undo/redo, command stack)
│   ├── audio/ (mixer, waveform, beat detect)
│   └── export/ (render-to-texture pipeline)
├── shaders/
│   ├── video_compositor.gdshader
│   ├── displacement_curve.gdshader
│   └── chroma_key.gdshader
├── assets/luts/
├── native/
│   ├── ios/ (AVFoundation bridge, Swift)
│   └── android/ (MediaCodec bridge, Kotlin)
├── tests/
└── docs/architecture.md
```

---

## 6. PHASED BUILD ORDER

Doing this in the "right" order matters more than doing all of it — each phase should be a
working, testable app, not a stub.

1. **Phase 0 (prove the risky bet):** Module B decode pipeline only. Three overlapping
   video tracks, hardware-decoded, rendered onto quads at stable 60fps on a mid-range
   Android device and an iPhone. If this fails, the whole architecture needs rethinking
   before any UI is built.
2. **Phase 1 (flat editor parity):** Modules A + F + G basics + H, in EDIT/orthographic
   mode only. This alone should already function as a legitimate, shippable flat editor.
3. **Phase 2 (the differentiator):** Module C roam camera + Module D environment/modeling,
   gated behind the "enter scene" UI affordance from Module I.
4. **Phase 3 (the shader showcase):** Module E curving/displacement, transitions, LUT
   grading, chroma key.
5. **Phase 4 (polish/scale):** keyframe generalization across all layer types, beat sync,
   4K export, accessibility pass, CI/testing hardening.

---

## 7. OPEN DECISIONS THE CODING AGENT MUST RESOLVE EARLY (and document, not defer)

- GDExtension bridge vs. native FFmpeg decode (Module B) — pick one before Phase 1 starts.
- Roam input scheme: twin-stick vs. drag-to-orbit.
- Subdivision granularity default for "curvable" tracks (perf vs. curve smoothness tradeoff).
- Whether chroma key is a v1 feature or deferred to Phase 4 — it's a genuinely different
  shader complexity class from simple compositing and shouldn't be assumed "basic."

---

**Bottom line:** the differentiator is real (3D-space compositing + environment-building
around footage), the risk is real too (mobile hardware video decode inside Godot is the
one part of this that could kill the whole timeline), and the build order above puts that
risk first instead of last.
