# Phase 1 — pixel-art rendering lab (courtyard scene)

Status: **awaiting approval** before rolling the pipeline out world-wide
(brief §32: "Do not redesign the entire world before the visual pipeline is
approved").

## What was built
| System (brief §29) | Implementation |
|---|---|
| PixelMaterialLibrary | `game/shaders/pixel_common.gdshaderinc` (32 px/m world texel grid, dominant-axis sampling, palette light ramp), `game/shaders/pixel_world.gdshader` (architecture/ground/props). Courtyard surface families in `Courtyard.PIXEL_FAMILIES`. |
| Pixel texture families | `tools/pixel/gen_textures.py` → `game/art/pixel/` (sand, sandstone, earth, wood, fur/fabric/leather detail, jinn shadow). Palette-limited, clustered, orphan pixels removed; imported lossless with mipmaps, sampled nearest. |
| CharacterVisuals | Toon shader gains object-space pixel detail (fur / bazin weave / leather); gloss, sheen and damask removed per §4 "avoid artificial gloss". |
| SandMaterial | Journey sand (v1.5) now evaluated on the texel grid: pixel-art base texture, per-texel ripples and grain, single-texel glitter that depends on view + light and is reduced in shadow. |
| JinnVisuals | Charcoal/purple pixel-cluster body (#302C3D); fraying edge and dissolve cut whole texels. |
| Render layer | `game/render/pixel_render.gd`: world rendered at ~270 lines (integer scale), nearest upscale; HUD native; game camera never snapped (sub-camera copies it). Root viewport stops drawing 3D. |
| Edges | `game/shaders/pixel_edges.gdshader`, depth-only edge darkening (adapted from Godot-3d-pixelart-demo, MIT; normal edges need Forward+). |
| Lighting | Palette: sun #F1DDB6, lavender ambient #82788D, warm haze with aerial perspective, saturation 0.9. |

## Measurements (same machine, software Vulkan under xvfb — NOT device data)
| | before (v2.3) | after |
|---|---|---|
| mean fps over screenshot tour | 15.0 | 29.1 |
| mean frame time | 65.8 ms | 34.1 ms |
| p95 frame time | 86.5 ms | 43.9 ms |
| draw calls (logger) | 118 | 130 |
| static memory | 82.8 MB | 83.0 MB |
The faster frame time comes from rendering 3D at ~1/9 of the pixels. The
logger's primitive count is no longer comparable (3D now renders in a
SubViewport the logger does not sample). Device profiling is still required.

## Tests
combat 97/97, village 29/29 (gameplay unchanged).

## Known limitations / next
- 3D sign text (Label3D) is unreadable at 270 lines — move signs to HUD or
  render them at native resolution (Phase 7).
- Palm, crates, village buildings still use pre-pixel materials (Phase 3 / 7).
- Character meshes keep vertex-colour regions; a true pixel atlas with
  pixel-aligned UVs needs the UV-unwrapped character rebuild (Phase 5).
- Smoke/dust/fire are not yet sprite-sheet pixel effects (Phase 4).
- Perspective camera: distant texels can swim slightly while moving; this is
  the accepted trade-off for not snapping gameplay.
