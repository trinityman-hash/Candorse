# Candorse

A video editor built inside a 3D world. Godot 4, mobile-first.

Video and image layers are textured quads placed in real 3D space — so you
can push a camera through the layer stack for real parallax, build 3D
environments around footage, deform the video mesh itself, and drop true 3D
models into the same lit scene as your clips.

**Status:** scaffolding only. See `docs/architecture.md` for the full brief
and `docs/PHASE0_STATUS.md` for what's implemented vs. still open. The
riskiest technical bet (mobile hardware video decode inside Godot) has not
yet been validated on real devices — that's the required next step before
any UI work continues.

## Structure
See `docs/architecture.md` §5 for the full repo layout and rationale.

## Build order
See `docs/architecture.md` §6. Phase 0 (decode pipeline proof) must pass
before Phase 1 (flat editor parity) starts.
