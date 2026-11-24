# Oasis (Phase 3 lab) — art notes vs Garbage Country & peers

## Direction (owner, 2026-11-24)
Pixel art is a stylistic choice of the assets: **full resolution, full
polycount**. The Phase 1 low-res render layer is now off by default
(`Main.pixel_render_enabled = false`); it remains available as an option.

## What we take from Garbage Country / Noio
Source: Noio's Pixel-Unwrapper README (github.com/noio/Pixel-Unwrapper,
5665e5c): pixel-art 3D "looks best when pixels align with edges on models"
and "pixels are roughly the same size across the model".
- One texel density everywhere: 32 px/m (sand, water, earth, trunks via
  pixel-aligned UVs, blades/leaves sized from their sprite pixels).
- Simple, readable 3D forms carrying hand-made pixel textures; nearest
  sampling; no texture smoothing, no gloss, no heavy outlines.
- Vegetation as many small flat pixel cards in 3D (Cloud Gardens / Garbage
  Country foliage), each moving on its own.
Not available here: I could not view Garbage Country footage from this
workspace (no video/image access), so comparisons are against Noio's
documented principles and the brief, not frame-matched.

## Peers used as reference
- Journey: sand diffuse contrast, ripples, glitter (Zucconi series).
- Tunic: composition — clear landmark (palm grove + pond) framed by dunes,
  readable from the gameplay camera.
- Dylearn 3D pixel-art grass (MIT): character displacement idea (ours uses
  the player position global; theirs a 64-entry array).

## What was built
- `Wind` autoload + `wind.gdshaderinc` global uniforms: base breeze, gust
  fronts travelling downwind, turbulence, per-material response, sheltering
  hook, whole-plant sway; CPU `Wind.wind_at()` mirrors the shader.
- `veg_card.gdshader`: individual subdivided cards (blades 2x8 quads,
  leaflets 1x4, leaves 1x2), root fixed, h^2 bend, tip flutter, elastic by
  construction (stateless field), player parting, atlas per instance,
  4x4 ordered-dither camera fade, palette light ramp.
- `Vegetation`: date palm (pixel-UV trunk, 13 arching fronds, individual
  leaflets, dry fronds), acacia (forked branches, umbrella canopy of
  individual leaflets), thorny shrubs, flowers, MultiMesh chunks (6 m) with
  visibility ranges.
- `Oasis`: lobed pond with pixel water (dithered depth bands, wind ripples,
  foam lip, single-texel glints), damp shore, grass density from water
  distance + noise clumps (~7.7k blades), 4 palms, 2 acacias, 5 shrubs,
  9 rocks. Courtyard palms replaced by the new palms.
- Sprites: `tools/pixel/gen_vegetation.py` (editable source).

## Measured (software Vulkan under xvfb, full resolution, NOT device data)
Screenshot tour incl. courtyard: 12 fps mean, 79 ms mean frame,
158 draw calls, 144k primitives. Device profiling still required; the grass
chunk visibility range (55 m) and blade density are the first knobs.

## Known gaps
- Acacia leaflets read as chunky clumps at mid distance; needs smaller
  leaflet sprites or impostor cards at range.
- No falling leaves, dust, footprints yet (Phases 2 and 4).
- Pond is walk-through (no splash/ripple from the player yet).
