# Sand v1 (owner "Sand Rendering Master Specification", 2026-11-25)

Shader: `game/world/sand_ripple.gdshader` (rewritten; original code after
John Edwards' GDC 2013 talk and Alan Zucconi's series, no Journey source).

| Spec item | Status |
|---|---|
| Smooth macro dunes, asymmetric, 20-150 m | Horizon ring 62-95 m swells; 10 low in-play dunes (smooth bumps, convex collision) |
| Diffuse: warm albedo, controlled shadow | Zucconi diffuse contrast, pink-peach albedo #DC967A, mauve shadow tone #C58474 |
| Ripple normals, damped on slip faces / damp ground | Warped wind-aligned sinusoid ~0.55 m; damped by steepness and soil_zone; **filtered by pixel footprint** (no zebra aliasing) |
| Broad ocean sheen p 8-32 | p = 6 (broad), strength 0.3, x N.L x shadow; takes the faded glitter energy at distance |
| Rim (1-N.V)^3 | strength 0.3, x N.L x shadow |
| Stable glitter, narrow lobe | 26 grains/m world cells (never time/screen seeded); tangent-plane tilt; pow(M.H, 220); x N.L x shadow; faded when sub-pixel; bloom threshold 1.15 |
| No emission / ALPHA for reflections | Only DIFFUSE_LIGHT / SPECULAR_LIGHT in light() |
| Footprints | Existing boot-print decals on the world texel grid (not yet a signed height/compaction mask) |
| Slide grooves, GPUParticles dust | Not done (CPU dithered puffs + wind sheet remain) |
| Quality presets / device profiling | Not done; software renderer only |
| Debug pass | `debug_spec = 1` shows N.L, N.H, grain visibility as RGB |

Measured on the software renderer (arrival view, NOT device data):
735k primitives, 297 draws, ~320 ms (v2.9.1: 657k, 284, ~280 ms).

Characters in the same round: head scaled to 0.8 (HEAD_SHRINK), daraa
reshaped into a long Journey-style cone (runtime vertex reshape, colours
kept), hawli as a 2.3 m verlet ribbon (`HawliScarf`, indigo with gold
edge lines and lozenge embroidery, wind-driven, kept out of the robe).
