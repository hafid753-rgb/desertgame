# Daraa reconstruction (v3.5.0)

The generic blue robe is replaced by a daraa built the way the garment is
made: a flat sewing pattern, sewn and draped with Blender cloth, then rigged
for runtime. This file covers the research, how each part of the garment is
translated, the assumptions that still need checking against real garments,
the pipeline, the runtime and the validation.

## 1. What a daraa is made of (research)

| Component | What the sources say | Source |
|---|---|---|
| Body cloth | Very wide, ankle-length. An adult garment uses about 10 m of cloth; a 5-year-old's about 3 m | democraticac.de |
| Construction | Boubou family: one large rectangle, usually about 150 cm wide, folded in half with a neck opening at the centre | FIT fashion history (boubou); UCSC boubou page |
| Sides | Deep vents on both sides; "two large opened sleeves" on the sides; the sleeves are open from the armpit to the lower torso | democraticac.de; textilevaluechain (Drâa); UCSC |
| Sleeve handling | The wide sleeves are pushed, folded or rolled up onto the shoulders while walking, working or in summer | democraticac.de; custom-qamis; mauritania-travel |
| Neckline | Deep V neck, embroidered round the neckline | UCSC; ami.mr |
| Pocket | A large front pocket at the base of the neck opening, slightly left of the chest, with ornate yellow-thread designs (triangular/rectangular). Side pockets are also mentioned | democraticac.de; UCSC; custom-qamis; mauritania-travel |
| Embroidery | Central to the garment; gold/yellow and white thread; every tailor has his own mark | textilevaluechain; ami.mr |
| Fabric | Bazin (damask cotton, stiff and lustrous) or plain cotton | custom-qamis; mauritania-travel |
| Colours | White, blue (sky to indigo), green | democraticac.de; mauritania-travel |
| Worn with | Serwal (trousers) and a hawli/turban | democraticac.de |

There is a conflict: democraticac.de calls the daraa both "wide sleeves" and
"sleeveless". Both descriptions fit one rectangle whose overhang beyond the
shoulders hangs open, and that is how it is modelled here.

## 2. Translation: component → implementation

| Component | Implementation |
|---|---|
| One folded rectangle, no shoulder seam | `daraa_pattern.py`: one panel W × 2L, fold line at the shoulders; the mesh is one continuous grid (front, fold, back) |
| Broad, shoulder-supported | W = 1.50 character units (about 2.2 m adult equivalent at REAL_SCALE 1.45). The yoke (\|x\| < 0.2, \|s\| < 0.2) is pinned to the shoulders during the drape |
| Large lateral openings | The side edges stay unsewn from the fold down to 68% of the length. They hang over hidden arm-support proxies, like sleeves on a real wearer's arms |
| Lower side seams, open hem | Sewing springs join front to back over the lowest 32% of each side edge; after the drape the seam pairs are snapped together. The hem stays open |
| Neck opening | Elliptical cut on the fold, 0.26 deep at the front (V to the chest) and 0.06 at the back |
| Embroidered neckline and chest band | Texture: gold/white rings following the cut, toothed band, and a column down from the V (the part that shows below the hawli knot). Front only |
| Large chest pocket | Patch pocket in the GarmentCode JSON; embroidered pentagon in the texture, slightly to the wearer's left (−x), with an open top hem and a cast shadow |
| Bazin damask | 8-px woven lozenges, tone on tone (lighter on dark cloth, darker on white) |
| Natural folds | Come from the Blender cloth drape (bending stiffness 3 for stiff bazin, self-collision), not from sculpting |
| Sleeves onto the shoulders | Wearing configurations simulated in Blender by lifting the lower part of the opening onto the shoulder, along a waypoint path round the arm (shape keys GatherL, GatherR, GatherBoth) |
| Colourways | cat: royal blue · fennec: white · rabbit: navy (the species' existing robe colours) |

## 3. Assumptions — to validate against real garments

No published Mauritanian daraa cutting pattern with measurements was found.
These numbers are reasoned estimates:

1. **Width-to-length ratio.** W 1.50 × L 1.22 at character scale. The sources
   give total yardage (about 10 m) and the boubou's 150 cm loom width, not a
   finished daraa width. Adult daraas look wider than 2 m; check against a
   real garment laid flat.
2. **Seam height.** The lower 32% of each side is sewn. UCSC says the
   opening runs "from the armpit to the lower torso"; the hip-level end is
   an estimate.
3. **Neck depth.** The V reaches the upper chest (0.26 of 1.22). Photos show
   variation by tailor.
4. **Pocket.** One large front patch pocket, about 0.17 × 0.20 units,
   pentagonal with the point down. Real pockets vary (rectangular,
   triangular). The side pockets mentioned by custom-qamis and
   mauritania-travel are **not modelled**.
5. **Gathering gesture.** Interpreted as lifting the lower end of the
   opening onto the shoulder or upper arm. The exact way the cloth is
   folded and rolled is not documented in the text sources; the two video
   references could not be viewed (YouTube was rate-limited).
6. **Embroidery motifs.** Generic gold lozenge/tooth bands, not a specific
   tailor's mark.

**Validation request:** a photo of a real daraa laid flat (front and back)
with its width, length and seam height, plus one photo of each way of
wearing it (sleeves down, one side up, both up), would confirm or correct
points 1–5.

## 4. Pipeline (all scripted, reproducible)

```
tools/garment/daraa_pattern.py      flat pattern -> daraa_specification.json (GarmentCode-style, cm)
tools/garment/gen_daraa_textures.py pixel textures on the pattern UVs (64 texels/unit), 3 colourways
tools/garment/build_daraa.py        bpy 5.3: sew + drape on body proxies, 3 configs + Spread, GLB
tools/garment/plot_daraa.py         orthographic views of every shape key (quick check)
```

- `python3 tools/garment/build_daraa.py --res 0.03` writes
  `game/art/garment/daraa.glb` (LOD0: 4,149 vertices, 4,002 quads) and
  `tools/garment/daraa_source.blend`.
- `--res 0.08 --out game/art/garment/daraa_lod1.glb` writes LOD1 (580
  vertices) from the same pattern.
- Coordinates: Godot model space (y up, front −z), converted to Blender as
  (x, −z, y).
- Collision proxies: torso and shoulder ellipsoids, hidden arm capsules
  (shoulder to just short of the floating hand's idle rest), a leg capsule
  and the ground.
- The UVs are the flat pattern itself: each texel is a fixed 1/64 unit of
  cloth everywhere, so density is consistent and the UVs never move.
- The garment is 64 texels/unit, 2× the 32 px/m world grid. This is a
  deliberate deviation so the embroidery stays legible at character scale.

## 5. Runtime (`game/actors/player/daraa_garment.gd`, `game/shaders/daraa*.gd*`)

- **Wearing configurations.** Blend shapes cross-faded over about 0.45 s.
  There are no mesh swaps:
  - draped while exploring;
  - right side gathered while armed or in combat (frees the sword arm);
  - both sides gathered while climbing or mantling;
  - Spread while gliding (the daraa's own sides become the sail; the
    separate wing meshes are hidden).

  The configuration is presentation only. Movement, combat, stamina,
  physics, camera and abilities are unchanged.
- **Invisible garment skeleton.** Packed in vertex COLOR from the pattern:
  - r: left side chain;
  - g: right side chain;
  - b: freedom (0 on the yoke, 1 at the hem);
  - a: front or back.

  The CPU runs damped springs for the two side chains and the hem, driven by:
  - travel lag;
  - acceleration kick;
  - turn swing;
  - rising and falling lift;
  - landing drop.

  Hidden arm support: a raised or reaching floating hand carries its side
  up and out. The hands themselves are never driven by the cloth.
- **GPU wind.** The shared Wind field, weighted by freedom: shoulders still,
  hems free. Flutter grows with speed and gusts, and the sides are sheltered
  when spread.
- **Collision proxies** (shader push-out, model space):
  - hand spheres;
  - boot+sirwal capsules (the cloth is pushed outward from the body axis,
    so a striding leg carries the front panel ahead of it);
  - the invisible legs.
- **LOD.** LOD0 within 16 m, LOD1 beyond (visibility ranges). Both share the
  material and blend weights.
- **Shading.** Toon light ramp, double-sided. The inside is plain darker
  cloth, so the embroidery shows on the front only. The outline hull uses
  the same deformation.

## 5b. Hands only when used (v3.5.1)

The floating hands appear only when they're needed:
- combat states, or the sword drawn;
- emotes (thumbs up and peace are hand gestures).

They're hidden while idle, walking, running, jumping, climbing, gliding and
surfing. They pop in on a spring with a small overshoot and shrink away in
about 0.15 s. The animation still drives them while hidden; only scale and
visibility change. While they're hidden, the daraa's hand collision proxies
are switched off.
`CreatureModel.hands_wanted()` / `_update_hand_visibility()`.

## 6. Validation

| Check | Output |
|---|---|
| Front / side / back × draped, gather L, gather R, gather both, glide spread | `tools/daraa_views.tscn -- mode=views` → shots/daraa_views.png |
| Silhouette without colour | `mode=silhouette` → shots/daraa_silhouette.png |
| Species colourways + close-up | `mode=species` → shots/daraa_species.png, daraa_closeup.png |
| Walk, run, jump, dodge, combat, climb, glide in the real game | `tools/cinematic.tscn -- shot=daraa` (video) |
| Gameplay unchanged | tests/combat_test 97/97, tests/village_test 29/29 |
| Cost | `tools/daraa_perf.tscn [-- no_daraa]` |

**Performance.** Measured with the software OpenGL renderer (llvmpipe), not
a phone:
- Daraa: 262 ms mean frame.
- Old robe: 257–259 ms.
- So the daraa adds about 3–6 ms (1–2%). Primitives fall by about 23k
  (597k vs 620k), because the old robe mesh was denser.

On-device profiling is still outstanding. No frame rate is claimed.

## 7. Repositories (licences checked, inspected only — none vendored)

| Repo | Commit | Licence | Use |
|---|---|---|---|
| maria-korosteleva/GarmentCode | d449629 | MIT | Pattern JSON layout (panels / edges / stitches) followed for daraa_specification.json; no code used |
| opensew-2 | 86b4322 | GPL-3 | Inspected; not used (GPL) |
| blender_clothing_tools | 776370c | GPL-3 | Inspected; not used |
| blender-seams-to-sewing-pattern | 919d031 | GPL | Inspected; not used |
| freesewing | 8a8de5a2 | MIT | Inspected (parametric pattern ideas); no code used |
| godot-jigglebones | e861ae9 | MIT | Inspected; springs written in-house (DaraaGarment) |

Blender cloth runs through the `bpy` 5.3 Python module (GPL tool; its
output is our data).
