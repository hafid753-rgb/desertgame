# ADR 0001 — Engine, renderer and code structure

**Status:** accepted, 2026-11-23

## Decision

- Godot **4.6.3-stable**, GDScript only. Re-evaluate moving to 4.7.x at the end of Phase 2.
- Renderer: **Mobile** (Vulkan). Phones without Vulkan fall back to Compatibility (OpenGL ES 3); the prototype was verified to render in Compatibility.
- Physics: built-in **Jolt** (Godot 4.4+). Not the godot-jolt extension (maintenance mode).
- No addons yet. The camera, state machines and touch HUD are hand-written (~2,300 lines) so the prototype has zero third-party risk. Phantom Camera, LimboAI and netfox are candidates once a need is proven.
- One input path: every device writes timestamped events into `GameInput`; gameplay consumes them once per physics tick.
- Combat rules live in plain scripts with no rendering calls in their decisions, so the same code can run on a headless server in Phase 3.

## Consequences

- Placeholder art is built from primitives in code. When the artist's models arrive, replace `CreatureModel` while keeping its `build()` / `animate()` contract.
- Tests drive `GameInput` the same way the HUD does; keep them passing in CI.
