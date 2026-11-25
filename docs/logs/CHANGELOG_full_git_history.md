## be298b6  2026-11-23 08:44:18 +0000
The Room: touch combat prototype (Cat vs shadow jinn)

- Player controller: combo, heavy, dodge/block/parry, stamina, sprint
- Hold-Special element charge (3 tiers): wind/fire attack, mobility, defense
- Shadow jinn AI with three telegraphed attacks, stagger, burn
- Orbit camera with lock-on, multi-touch HUD, species switch
- Per-second perf CSV logger, 30 headless combat tests
- Android export preset, GitHub Actions test + APK build

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 4705d84  2026-11-23 08:55:02 +0000
v0.2: climbing, daraa glide, outdoor area, sound, hit-stop, pause menu

- Jump, wall climb with species climb speed and stamina, mantle, leap/drop
- Wind glide with the daraa; fall damage when not gliding
- Walkable courtyard walls, open gate, dunes, 10 m pillar, 20 m mesa
  (only the Lizard tops it in one climb: measured 15.5 / 16.8 / 20 m)
- Generated original SFX incl. a distinct sound per jinn telegraph
- Hit-stop and camera shake, pause menu with left-handed layout,
  button size, sound, overlay toggle and session stats
- 45 headless tests (combat, traversal, species, menu)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## ed147b0  2026-11-23 09:04:50 +0000
v0.3: real character models with toon shading

- Blender-built (bpy 5.3) Cat, Fennec, Lizard in daraa robes with embroidered
  pockets, takouba sword, leather shield, masked shadow jinn with claws
- Vertex-coloured parts, ~6k faces per species, floating hands/feet kept
- Toon shader (cel band, cool shadows, rim, spec) + outline adapted from
  GDQuest godot-shaders (MIT); double-sided cloth for the daraa sail
- Jinn arms pose per telegraphed attack; mask fades on banish
- tools/portrait.tscn renders a character lineup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 05858fb  2026-11-23 09:10:34 +0000
v0.3.1: character polish

- Crisp embroidery and jinn mask markings as geometry projected onto
  the surface (no textures), V-neck trim, pocket with diamond chain
- Daraa sleeves, soft skirt folds; paws with fingers, pads, lizard claws
- Cheek blush and fur tufts; fennec blaze and inner-ear tuft
- Separate eyes and ears: blinking, ear twitch, ears flatten when hit or gliding
- ~8.6k tris per species, ~6.8k for the jinn

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 66baf9d  2026-11-23 09:26:26 +0000
v0.4: adventurer proportions and a real daraa

- ~1.75 m characters, head ~1/6 of height, almond eyes with irises and
  slit/round pupils, brow ridge, cheek ruff, dark cat ear tips
- Daraa rebuilt as a lofted robe from shoulders to shins with drape folds,
  gold hem, cinched leather belt with brass buckle, chest pocket, V-neck
- Connected limbs: sleeves and sirwal trousers stretched to the animated
  hands and feet; leather sandals
- Glide sail spreads from the shoulders; jinn scaled up 1.25x
- Player capsule 1.75 m, camera raised; ~9-10k tris per species

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## b907b96  2026-11-23 10:37:35 +0000
Import external v0.4 fork (4 elements, physics props, spirit veil, sand shader, lock diamond)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## e91650b  2026-11-23 10:38:54 +0000
Merge fork gameplay onto v0.4 characters

Keeps v0.4 proportions/daraa/limbs; adds the fork's Water/Ice + Earth
elements, physics props, spirit veil and lock-on marker. Sand ripples
toned down (0.045) and kept outside; packed-earth courtyard floor;
props moved clear of the ruined wall. 61/61 tests.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## f4a7fe6  2026-11-24 02:52:52 +0000
v0.5: haunted village, Jinn King, conquest and restoration loop

- Aïn Sirra: greybox Saharan village east of the courtyard, houses,
  well, ruined mosque; violet haze while haunted
- Jinn King (2.1x, crown): bigger swipe/burst/lunge plus summon and
  slam; rages at 50% (faster tells, more summons); guards leash to
  their territory
- Defeat the King -> village claimed (once, from the environment),
  survivors kneel and can be recruited as Guard/Merchant/Builder
- Salvage brick piles, rebuild the mosque (10 bricks) with a
  Chinguetti-style minaret and ostrich-egg finials
- WorldState: single-writer world record, event log, user://world.json;
  ACT button with prompts, boss bar, bricks counter, reset in pause menu
- MeshBatcher merges static geometry: village 355 -> 207 draw calls
- 29 new village tests (90 total)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## b90abd2  2026-11-24 02:59:47 +0000
v0.6: boxy Rayman-style characters with five hand poses

- All character parts rebuilt from rounded boxes (bevelled cubes):
  heads, brows, eyes, ears, tail segments, chunky leather boots
- Floating paws back (limb tubes removed), 1.6x bigger, five poses per
  hand: open, fist, grip, thumbs_up, peace, chosen from player state
- Sword and shield drawn near jinn / in fights, sheathed on the back
  after 5 s of calm; emotes sheathe to gesture
- Thumbs-up on banishing a jinn, peace on claiming a village or
  switching species
- Rectangular aghar-style shield with projected pattern; boxier robe
- ~9.5k visible tris per species; combat 145 draw calls
- 9 new hand-pose tests (99 total)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## ddee787  2026-11-24 03:03:53 +0000
v0.6.1: smoke jinn, enchantment rule

- Jinn are smoke: rising wisps, glowing white dot eyes, golden rings
  that flare to the attack colour and spin faster on tells; mask and
  ribbon veil retired; King gets five rings; villagers turquoise rings
- Only Water- or Earth-enchanted blades and spells harm jinn; steel,
  Wind and Fire pass through ('immune'); Wind still pushes; Fire is
  kept for props and future PvP
- Sword glows with its enchantment; hint when steel passes through
- Player starts on Water

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## d7550d3  2026-11-24 03:32:21 +0000
v0.8: chibi sculpt pass, shell fur, Mauritanian species, daraa + hawli, takoba

- Proportions: big head (~1/3 height), stocky body, chunky boots under sarouel
  cuffs, mitten hands at the hips; limbs stay disconnected
- Species: Saharan sand cat, fennec, dabb (Uromastyx dispar)
- Daraa with pipe folds fanned from the shoulders, wavy thick hem, hanging
  sleeves, crisp V-neck and five-sided embroidered pocket
- Hawli neck wrap with knot and fringed tails; tagelmust turban
- Takoba with fullers, langets, wrapped grip, disc pommel; tooled scabbard
- Shell fur (fur_shell.gdshader) on cat/fennec heads, tails, paws; culled at 14 m
- Baked vertex AO + curvature; 3-band toon light, rim masked by light

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 901831f  2026-11-24 03:43:08 +0000
v0.9: vinyl-toy style, rabbit replaces lizard, '> <' closed eyes

- Smooth mochi heads (superellipsoid), tall glossy oval eyes, tiny nose,
  crisp face patches; sand cat keeps green eyes, cheek streaks, brow stripes
- Fennec: broad ears with rounded tips; rabbit = desert hare, long black-tipped
  ears, pale eye rings, cotton tail
- EyesClosed part: chevrons swapped in on blink, hit-stun and death
- Shell fur disabled for this style (pipeline kept); glossier highlight

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 4ef77dd  2026-11-24 03:51:07 +0000
v0.9.1: flocked fur finish on the vinyl characters

- Shell fur on cat, fennec and rabbit (heads, ears, tails, paws), built from a
  coarse head copy (~3.5k faces per shell, 8 shells); culled beyond 14 m
- Eyes and printed markings stay bald and crisp
- CharacterArt.fur_enabled switches between vinyl and flocked finishes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## fce155f  2026-11-24 04:04:03 +0000
v1.0: Nintendo-style storybook look, clean A-line daraa

- Lighting: wrapped diffuse with a soft cel step, light lavender shadows,
  warm soft rim; per-material presets (skin satin, fabric velvet sheen,
  glossy eyes, leather boots); thin warm outlines
- Faces: cheek blush, smooth decal markings, fused mitten hands
- Daraa: wide A-line boubou, few large soft folds, wavy hem with a rolled gold
  edge, gold sleeve seams, embroidered yoke, V slit and chest pocket; brighter
  bazin palettes (sky blue, white, royal indigo)
- Tagelmust turbans with a domed crown and crossing wraps; indigo hawli
- Fur kept as an option (CharacterArt.fur_enabled), off by default

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 4069bd4  2026-11-24 04:10:41 +0000
v1.1: aghar shield, sculpted takoba and scabbard, chibi hand targets

- Tuareg-style aghar: curved pale hide, leather rim, painted cross, lozenges,
  zigzag bands, brass boss
- Takoba: spiral-wrapped grip, brass ferrules, disc pommel; one-piece tooled
  sheath with painted bands, brass throat and diamond chape
- Hand targets remapped for chibi proportions (no clipping into the head on
  emotes, charge, climb, mantle)
- portrait tool: gear sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## b4edf55  2026-11-24 04:15:39 +0000
v1.2: mouths, bazin damask, soft shadows, richer daraa embroidery

- 'ω' mouths (hare gets a philtrum line), on open and closed eye sets
- Fabric shader: tone-on-tone bazin damask, quieter rim and sheen
- Softer sun shadows (shadow_blur 2.5)
- Daraa: lozenge chains along the V, back neck arch and medallion
- Aghar back: leather with grip strap and crossing thongs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 150ef65  2026-11-24 04:25:44 +0000
v1.3: squash & stretch and a bouncy walk

- Spring-driven squash & stretch: stretch on take-off and swings, squash on
  landing and hits, soft idle breathing; fixed sub-steps keep it stable at
  low frame rates (caught a blow-up at ~10 fps)
- Hoppy walk bob and head tilt
- Tests: take-off stretch, landing squash, settle, 10 fps stability
- portrait tool: squash strip

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## dda305b  2026-11-24 04:30:54 +0000
v1.4: Nintendo mittens

- Hands rebuilt as soft rounded mitts: flat mitten with grooves (open), ball
  fist, grip, chunky thumb, two-finger peace; soft rounded palm pad

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 3069c06  2026-11-24 04:34:02 +0000
v1.4.1: clean white bazin, matte cotton hawli/turbans

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 23dc604  2026-11-24 04:39:14 +0000
v1.5: Journey-style sand (after Alan Zucconi's series)

- Diffuse contrast (N.y*0.3, 4x Lambert, shadow->terrain lerp)
- Sand grain normals (nlerp), slope-blended shallow/steep wind ripples
- Rim + ocean specular combined with max(); rare stable glitter
- Procedural, no textures; warmer storybook sand palette

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 3e7d4c5  2026-11-24 20:57:23 +0000
v2.0: skeletal animation + movement weight

- Characters ride a keyframe-animated skeleton (KayKit Rig_Medium, CC0,
  76 hand-made clips; game/art/rig). Arms/legs stay invisible: mittens and
  boots float but move with real animation. ArmSpread modifier keeps the
  hands clear of the daraa.
- Attacks scrub their clip from gameplay progress so the blade connects on
  the hit frame; heavy charge holds the overhead wind-up (anticipation)
- Robe hangs from a spring at the neck, tail on a spring; sand dust on
  landings, skids and running footsteps
- Ground momentum: acceleration/braking, skid on reversals, landing lag
- tools/motion_reel: deterministic movie-maker reel for judging motion
- Tests: rig loads, attack swings the hand, robe orientation (89 pass)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## fb454e9  2026-11-24 21:01:04 +0000
v2.1: ear springs, head hop, twitch/flatten through the spring

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 3a8349f  2026-11-24 21:06:47 +0000
tools: fight_reel (bot plays the real game vs a jinn, movie-maker recording)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 111f53e  2026-11-24 21:08:50 +0000
fight_reel: close camera option

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 313e890  2026-11-24 21:30:58 +0000
v2.2: exaggerated combat - big sweeps, reaching stab, lunging footwork

- Combo: diagonal sweep, reaching stab (range 3.2), spinning sweep finisher
  (360 arc); heavy: two-handed overhead chop. Impact frames measured per
  clip (peak hand speed) and mapped onto wind-up/active/recovery, so the
  follow-through plays instead of freezing
- Exaggerate modifier amplifies spine/chest/sword-arm rotation past the
  clip during attacks; ArmSpread adds reach on the stab
- Lunge footwork on the floating boots: front foot steps in, back foot
  plants on the ground, body drives forward and down
- Additive sword trail ribbon (tinted when enchanted)
- fight_reel: side-on fight camera (close mode)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 00f12d9  2026-11-24 21:54:53 +0000
v2.3: ICO-style shadow jinn - punches, fireballs, 2 s vanish

- Body: skeletal shadow (KayKit hooded rig, CC0) reshaped by
  ShadowProportions (long thin limbs, stretched torso/neck, small head,
  hunch, cocked head) and rendered by shadow_being.gdshader: unlit black,
  frayed noise-cut silhouette, boiling vertices, edge-only warning glow
- Black smoke from head/chest/hips/hands, shadow pool underfoot, white eyes
  that flare to the attack colour; golden rings kept as tells
- Attacks: hook punch (swipe), dashing punch (lunge), smoke burst, thrown
  homing fireball, vanish (2 s intangible, pool opens behind the player
  0.5 s before an ambush kick). Clips scrubbed to measured impact frames,
  Exaggerate modifier on every strike
- Jinn King keeps its crown on the head bone
- tools/jinn_reel: attack showcase; tests for fireball, vanish, ambush (97)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 8813e0d  2026-11-24 22:05:53 +0000
Phase 0-1: research ledger + pixel-art rendering lab (courtyard)

- docs/RESEARCH_LEDGER.md: every repo in the brief with commit, licence,
  files, reuse status (studied / adapted / not used)
- Checkpoint tag v2.3-pre-pixel; baseline/after captures + perf CSVs in
  docs/pixel_lab
- Pixel texture families (tools/pixel/gen_textures.py -> game/art/pixel)
- pixel_common/pixel_world shaders: 32 px/m texel grid, palette ramp
- PixelRender: ~270-line world render, nearest upscale, native HUD,
  unsnapped camera; depth-edge pass (adapted, MIT)
- Sand, characters, jinn moved onto the texel grid; gloss removed
- Palette lighting: warm sun, lavender ambient, warm haze

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## ca0488f  2026-11-24 22:26:27 +0000
Oasis lab: full-res pixel art, shared wind, individual grass/leaves, pond

- Pixel look moved fully into assets at full resolution (low-res layer off)
- Wind autoload + wind.gdshaderinc: gust fronts, turbulence, response,
  plant sway, player parting; CPU mirror for particles
- veg_card shader: subdivided individual cards, h^2 bend, flutter,
  ordered-dither camera fade
- Vegetation builders: date palms (individual leaflets), acacia, shrubs,
  flowers; pixel-UV trunks
- Oasis: lobed pixel-art pond (dithered depth, ripples, foam, glints),
  damp shore, ~7.7k grass blades in 6 m chunks, rocks
- Courtyard palms replaced; palette contrast/haze retuned
- docs/oasis/ART_NOTES.md, ledger updated, oasis_shots tool

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 5cea799  2026-11-25 01:25:46 +0000
Oasis life: wind-blown dithered dust, footprints, wading ripples, falling leaves, finer acacias

- wind_dust.gdshader + WindDust: drift sheet of dithered streaks moving
  downwind and thickening under gust fronts, airborne grains; follows the
  player, masked off the pond and past the ground edge
- dust_dither.gdshader: footstep/landing puffs and water spray as world-texel
  discs with ordered-dither transparency (bayer4 in pixel_common)
- GroundFX + footprint.gdshader: boot prints every 0.5 m, resampled onto the
  sand's 32 px/m grid at any heading, eroded by wind over ~40 s
- Oasis wading: splash on entry, 8 expanding crest/trough ripple rings,
  lapping foam ring at the legs
- leaf_fall.gdshader: acacias shed leaves that tumble downwind, settle and
  slide in gusts (stateless GPU loop)
- Acacia canopy rebuilt from bipinnate sprays (6x6 pinnae), lit top and
  shaded underside tiers
- Docs: Garbage Country comparison from press/store descriptions, perf probe

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 0167b9d  2026-11-25 01:27:51 +0000
Art notes: Noio's own 3D pixel-art rules vs Hafid, reflection gap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 371ef0d  2026-11-25 01:44:28 +0000
Pond planar reflection (Noio's below-camera technique), pixel-dithered

- WaterReflection: mirrored camera renders the REFLECT layer (palms,
  acacias, player) into a full-res transparent SubViewport; skipped when
  the pond is off-screen or far
- pixel_water: samples it at the mirrored screen UV, ripple wobble, water
  tint, ordered dither on world texels; sky keeps the stylised band
- Oasis.reflections toggle; cost measured in ART_NOTES

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 2159f48  2026-11-25 03:58:21 +0000
Saharan palette + Garbage Country comparison pass

- Owner photo palette: terracotta sand, rust shadows, cream haze; warm
  ambient, low golden sun, depth fog into the haze
- Sand: two-scale tonal patches with dithered borders, painted pebbles,
  damp earth + moss around the oasis (global soil_zone)
- DuneHorizon: ring of large slip-face dunes beyond the play area
- Ground scatter (dead twig bushes, golden tufts), reeds in the shallows
- Date palms: rigid leaf-base planes in helical rows, date bunches
- Foliage: olive tint, leaf/grass translucency; golden grass palette
- docs/oasis/GARBAGE_COUNTRY_COMPARISON.md + before/after frames

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 5c8961f  2026-11-25 04:13:19 +0000
Low wide smooth dunes; slight cel shading on characters and vegetation

- DuneHorizon: no tall dunes; long smooth asymmetric swells (95 m / 62 m
  wavelengths), 1.6-6 m high, rounded crests and troughs
- In-play dunes: elongated smooth bumps along the wind meeting the floor
  tangentially (were squashed spheres); collision rebuilt from the mesh
- Characters: toon band 0.22 -> 0.1 softness, toon amount 0.95
- Vegetation: two-tone cel step on cards, normals lean less to world up

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## ce46b52  2026-11-25 04:23:27 +0000
Lower contrast to the owner's soft reference: peach-tan sand, gentle shadows

- Sand D9864F with soft shadow BC6E42; weaker tonal patches, fewer pebbles
- Lighter shadow ramps for world, vegetation cel and characters
- Ambient 0.72, contrast 0.94, saturation 0.86, lavender-grey sky top
- Softer soil/moss, dust and footprint colours

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## a3787bb  2026-11-25 04:44:27 +0000
Journey-inspired sand, smaller head, Journey-style daraa, hawli ribbon

- sand_ripple.gdshader rewritten per the owner's sand spec: smooth macro
  shading (Zucconi diffuse contrast), footprint-filtered wind ripples,
  broad ocean sheen, crest rim, stable world-anchored glitter faded when
  sub-pixel, all x N.L x shadow; pink-peach palette; subtle glow
- Four more long low dunes in the open desert
- Wind sand sheet lit like the ground (no grey patches); dust/prints recoloured
- Characters: head x0.8, daraa reshaped into a long flared cone, HawliScarf
  verlet ribbon (indigo + gold embroidery) driven by Wind
- docs/sand/SAND_NOTES.md

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## b457132  2026-11-25 05:05:09 +0000
Stylized shadows, atmospheric light, sun + pixel lens flare, Journey sheen, tucked arms

- Shadows: crisp tinted band (attenuation mapped through a narrow step in
  sand, character, vegetation and world shaders), shadow blur 0.45
- Atmosphere: fog sun scatter, low ground haze, sky affect 0.55 so the sun
  disc shows; sun disc + wide halo in the procedural sky; stronger glow
- LensFlare: pixel-art glare, rays and ghost chain when the sun is on
  screen and unobstructed (physics ray; world boundary ignored)
- Sand: Journey silky sheen lobe + grazing skylight sheen
- Hawli ribbon takes the neck wrap's own vertex colour
- Arms: mittens x0.82, closer in; ArmSpread.tuck pulls arms in and damps
  the swing while walking/running
- Wind grains fade near the lens

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 795f41a  2026-11-25 06:18:13 +0000
Sand surfing + glide + face veil, sand interaction mask, realistic flare, tech-demo cinematics

- SURF state: auto when running downhill on >13 deg sand; shield under the
  boots, lean into turns, dust plume, groove; lips launch into an automatic
  daraa glide; jump/dodge to step off
- SlideDune: steep surfing dune with kicker lip (trimesh collision) north
  of the courtyard (replaces three small dunes)
- Tagelmust face veil (hawli cloth) pulled up while surfing/gliding
- Hawli ribbon: same material/colour as the neck wrap, ~1.2 m, plain cloth
- SandInteraction: signed height/compaction mask (256^2 over 16 m) for
  footprint dents with rims, dodge grooves, landing craters; shader-side
  age fade; GroundFX forwards prints on sand
- Lens flare rebuilt as an analytic full-screen shader (glare, spikes,
  chromatic halo, hex ghosts with dispersion, anamorphic streak)
- Phase 4/7: pixel-dithered Fx and fireball flames; village on pixel
  materials; graphics quality presets (pause menu)
- tools/cinematic.gd (tech-demo camera moves incl. fight), tools/showcase.gd

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 5cb2935  2026-11-25 06:35:09 +0000
Glide pass: shield board under the feet, shrink-wrapped face veil, daraa sail in rig mode, warm dust plume

- Shield laid flat (disc normal up, long axis along travel), x2.3, under the boots
- Veil fitted to the real head surface per height band/angle (no
  floating band), stops below the eyes; hawli cloth colour
- Daraa sail opens wide during GLIDE (was only on the pre-rig path)
- Surf plume in warm sand colours
- cinematic shots: surfclose, glideclose, board

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 5509441  2026-11-25 06:53:47 +0000
Daraa as cloth everywhere, epic surfing dune and fast glide

- robe_cloth.gdshaderinc: daraa body deforms like hanging cloth (wind
  field + gusts, spring-lagged velocity so the hem trails/swings past,
  travelling hem flutter, heavy-hem hang); shared by toon_robe and a
  matching outline_robe hull; fold normals from the Jacobian
- Glide sail (toon_cloth, CLOTH_WIND): droop, billow, streaming trailing
  edge, roll with turns and gusts
- Surfing dune 74 m / 12 m crest with a taller kicker; real kickers pop the
  rider higher; launched glides keep their speed (32 m glides)
- cinematic shots: epic (4-camera cut), robe

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## e58af7c  2026-11-25 08:28:59 +0000
Children in poncho daraas wearing animal masks with abilities

- ChildBuild: child skull + hood (poncho cloth), species head flattened
  into a lacquered mask with hollow eyes (ears ride on it), daraa reshaped
  into a poncho, thin capsule limbs on the arm/leg bones, small skin
  hands, smaller boots; tail/hawli/veil off; masks do not blink
- Mask ribbon tied at the back of the head (per-mask colour)
- Mask abilities: cat double jump, rabbit high jump (+80 %), fennec long
  cheap glide + faster sand surfing; HUD/menu say Mask
- tools/mask_lineup, cinematic shots front and masks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 5d3564a  2026-11-25 08:30:24 +0000
Revert "Children in poncho daraas wearing animal masks with abilities"

Owner asked to revert; back to the v3.4.0 animal characters.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## ae9127f  2026-11-25 08:32:26 +0000
Version 3.4.1 (code 35) after the mask revert

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 8f89344  2026-11-25 09:35:30 +0000
Version 3.5.0 (code 36): authentic daraa from a flat pattern and Blender drape

One folded rectangle with open lateral openings, lower side seams, open hem,
neck V, embroidered chest band and pocket, bazin damask pixel texture.
Wearing configurations (draped, gather L/R, gather both) and the glide
spread as blend shapes; runtime springs, arm support, GPU wind, hand and
leg collision proxies, LOD1. Research, assumptions and validation in
docs/garment/DARAA.md.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 5fc8fac  2026-11-25 10:04:46 +0000
Version 3.5.1 (code 37): hands only when used; daraa showcase; media, logs and APK

Floating hands pop in for combat and emotes and are hidden while walking,
running, climbing and gliding (hand collision proxies off while hidden).
Daraa showcase cinematic (tools/cinematic.tscn -- shot=showcase). All
session videos and stills under media/, APK under releases/, logs and
media index under docs/logs/.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## ce7ab35  2026-11-25 10:07:13 +0000
Initial commit


## 908fb78  2026-11-25 10:07:13 +0000
Initial commit


## a48534a  2026-11-25 10:08:04 +0000
Merge GitHub repo initial commit (keep the game's README)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## a2b6b64  2026-11-25 10:21:47 +0000
Version 3.5.2 (code 38): head 20% smaller, simple babouches, smoother daraa

HEAD_SHRINK 0.8 -> 0.64 with the head lowered into the neckline; simple
leather babouche feet replace the bulky boots and sirwal cuffs; Taubin
smoothing of the daraa drape and shape keys; showcase re-shot; logs,
media and APK updated.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 2d8108b  2026-11-25 10:24:51 +0000
Store binaries as plain git blobs (Git LFS uploads are blocked from the build session)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 857d12a  2026-11-25 10:25:12 +0000
Add the 3.5.2 debug APK

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## fdda0e6  2026-11-25 10:25:26 +0000
Merge GitHub initial commit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## cc18598  2026-11-25 11:06:43 +0000
Version 3.5.3 (code 39): character pass — daraa proportions and self-clipping, hawli, feet

Daraa narrowed (W 1.32) with lower gathers; sim thickness, single Taubin
pass, z-independent wind/flutter phases, smaller spring caps and a thinner
outline stop the cloth clipping through itself. Chin rests on the yoke;
the neck hawli rides the neck pivot and its ribbon collides with the head
and the daraa. Yellow belgha babouches; green daraa for the rabbit.
Activity reels (showcase, water, surf+glide, fight, oasis walk), logs, APK.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 228ca87  2026-11-25 11:38:01 +0000
Desert driving test (top-down) + daraa anti-clipping work in progress

game/drive/: separate prototype in the Hafid desert. Original voxel 80s
sedan built in code, arcade slip handling with handbrake drifts, raycast
ride, pond spray and ripples, soft-sand pit (wheels spin, car digs in,
stuck); shared tyre grooves, grass parting and oasis splash. Teaser via
'-- teaser'. Video in media/videos/desert_driving_teaser.mp4.

Daraa: rig weights now position-based (layers move together), garment
build uses softer config pins + higher collision quality (test build:
0-3 self-intersections vs 65-140); check_intersections.py added. The
shipped daraa.glb is not rebuilt yet.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

## 56717f1  2026-11-25 11:41:31 +0000
Move the desert driving prototype to its own repository

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FJKj7YND72GBSTHM8TTJ61

