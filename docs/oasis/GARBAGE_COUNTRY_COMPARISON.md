# Hafid oasis vs Garbage Country (frame comparison, 2026-11-25)

References: 4 Garbage Country screenshots and an owner photo of Saharan dunes
(colour target), all supplied by the owner. Kept for comparison only; no
pixels from them are used in the game. Sheet:
`docs/oasis/compare/` (cmp_*_before / cmp_*_after, framed like the
references: high three-quarter camera).

## What Garbage Country does (observed in the screenshots)
| Trait | Observation |
|---|---|
| Value range | Mid-tone heavy; strong but soft shadows; nothing near white except foam |
| Ground | Chunky texels in 3-4 flat tones, large patches whose edges dither; pebbles painted in as 2-4 texel clusters; tyre tracks |
| Ground scatter | Dark dead twig bushes, small golden grass tufts, agaves (smooth low-poly), all sparse and clumped |
| Grass | Short golden clumps with a dark base, high contrast against dark ground |
| Water | Teal with darker patches; bright broken white foam along shores and on chop; reeds standing in water |
| Dust | Big puffs: solid core, checkerboard-dithered edge, two tones |
| Atmosphere | Strong warm aerial haze from mid distance; flat hazy sky |
| Shadows | Long, cool purple-brown, soft edged (low sun) |

## Owner colour target (photo)
Sampled: sky/haze #F2D8BF / #F0D1B5, near sand #CE7341 lit, #DF8048 crest,
shadows #C16B3E (warm rust, not purple), far dunes #E1A77F. Overrides the
spec's purple shadow (#79758C) and GC's cool shadows: shadows stay warm.

## Hafid before (v2.7) -> after (v2.8)
| Gap found | Change |
|---|---|
| Washed out, pale, almost no value range | Warm ambient #D9A88A at 0.6 (was lavender 0.75), rust shadow ramp, saturation/contrast retuned |
| Flat pale sand, pixel texture invisible at distance | Terracotta sand #D27A48, rust shadow #A4552F, 2-scale tonal patches in flat tones with ordered-dither borders, painted pebbles (sand_ripple) |
| Oasis ground identical to open desert | Damp earth + moss patches around the oasis (global `soil_zone`) |
| Open sand empty | Dead twig bushes (crossed pixel cards) + golden tufts, clumped by noise, outside the oasis |
| Grass pale beige | Golden ochre palette (#C99A45) |
| Pond without reeds | Rust rush clumps in the shallows, reflected in the water |
| Low sun missing, weak shadows | Sun at 33 deg elevation, #FFE3C4: long shadows, modelled dunes |
| Visible floor edge, empty horizon | DuneHorizon: ring of large wind-shaped dunes (slip faces, sharp crests) beyond the play area, smooth far-sand material, depth fog 18-240 m into cream haze |
| Lime-green foliage | Olive foliage tint under warm light; leaf/grass translucency |
| Palm trunks were a texture only (spec) | Individual leaf-base planes ("boots") in staggered helical rows, rigid to the trunk; date bunches |

## Deliberately not copied
- GC's purple/cool shadow temperature (owner photo wins: warm rust).
- GC's chunkier ground texel (~16 px/m estimated): Hafid keeps 32 px/m on
  everything so characters and world share one pixel size.
- Post-industrial props, cliffs, agaves (not Saharan).

## Still different / next
- GC foam is bolder (thick broken white bands, foam on open water).
- GC dust puffs are much larger (vehicle scale); Hafid's are sized to a cat.
- No tyre-track equivalent beyond boot prints; no sliding trails on dune slopes.
- Far dunes are smooth-shaded geometry; no impostor/LOD yet.

## Cost (software renderer, arrival view, NOT device data)
v2.7: 525k primitives, 233 draws, ~260 ms. v2.8: 657k, 284 draws, ~280 ms.
Main additions: horizon ring (40k tris), boots (~1.5k cards), scatter and reeds.
