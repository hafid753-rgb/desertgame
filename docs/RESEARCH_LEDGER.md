# Hafid — repository research ledger

Inspected 2026-11-24 (shallow clones, commit = HEAD at inspection).
"Studied" = read for technique only, no code copied. "Adapted" = technique
re-implemented in Hafid's own code with credit. Nothing here is "integrated
unchanged" unless stated. No proprietary game assets, ROM data or
decompiled code were imported.

## Project baseline (Phase 0)
- Engine: Godot 4.6.3 (project.godot `config/features = 4.6, Mobile`).
- Renderer: Mobile (`rendering_method="mobile"`); headless/xvfb captures fall
  back to a software Vulkan device, so captured frame times are NOT device
  figures — they are only for before/after comparison on the same machine.
- Checkpoint: git tag `v2.3-pre-pixel` (commit aee94a5).
- Baseline captures: docs/pixel_lab/before/*.png, perf_baseline.csv
  (100–175 draw calls, 75–118k primitives, 82–83 MB static memory).
- Tests at checkpoint: combat 97/97, village 29/29.
- Existing systems preserved: Player state machine (MOVE, ATTACK,
  HEAVY_CHARGE, GUARD, DODGE, CAST, MOBILITY, DEFENSE, HITSTUN, DEAD, AIR,
  CLIMB, MANTLE, GLIDE), elements (Wind/Fire/Water/Earth), lock-on,
  CameraRig, GameInput event queue, TouchHud, WorldState save, Village loop,
  Jinn / JinnKing / VillagerJinn AI, MeshBatcher, Juice (hit-stop, shake).
- Species: cat, fennec, rabbit (the brief lists "lizard"; the project
  replaced it with a rabbit on the owner's request on 2026-11-24 and keeps
  the lizard's stats — flagged, not changed).

## Pixel-art rendering
| Repo | Commit | License | Relevant files | Status | Notes |
|---|---|---|---|---|---|
| github.com/noio/Pixel-Unwrapper | 5665e5c | MIT | Blender add-on (texel-aligned UV unwrap) | Studied | Principle used: fixed world texel density + texel-aligned mapping. Hafid meshes are procedural with vertex colour and no UVs, so density is enforced in-shader (world/object-space texel grid) instead of by unwrapping. |
| github.com/astrellon/godot-3d-pixel-art | ee08bef | MIT (code); sprites credited to third parties | materials/isometric_atlas.gdshader, camera/main_camera.gd | Studied | Screen-space atlas sampling and texel-snapped camera assume an orthographic camera. Hafid's third-person perspective camera can't use either; the brief also forbids snapping gameplay movement. |
| github.com/leopeltola/Godot-3d-pixelart-demo | 6118473 | MIT | pixelart_stylizer.gdshader | Adapted | Depth-difference edge darkening re-implemented in game/shaders/pixel_post.gdshader. Its normal-edge highlights need `hint_normal_roughness_texture` (Forward+ only), so Mobile uses a depth-only variant. |
| github.com/gdquest-demos/godot-shaders | 158a490 | MIT code / CC-BY-NC-SA art | various | Studied | Art is non-commercial: none used. |

## Vegetation (Phase 3 — oasis lab built, see docs/oasis/ART_NOTES.md)
| Repo | Commit | License | Status | Notes |
|---|---|---|---|---|
| 2Retr0/GodotGrass | 3785bec | MIT | Studied | Compute-based; heavier than Mobile budget. Hafid uses MultiMesh cards + vertex bend instead. |
| DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo | 7486b9b | MIT code / art separate | Adapted (idea) | Character displacement re-implemented as `player_push()` in game/shaders/wind.gdshaderinc (single player position, not their 64-entry array). No code or art copied. |
| TheMIU/Stylized-Fluffy-Tree-Shader | d1909e8 | **No license file** | Studied only | Cannot reuse code. |
| FaRu85/Godot-Foliage | e5af6d7 | MIT | Studied | |
| Ladvien/pixy_terrain | b53fef2 | **No license file** | Studied only | |
| HungryProton/scatter | 7198cc0 | MIT | Studied | Candidate for Phase 3 distribution. |
| mlaass/dynamic-2d-grass | 4484522 | MIT code / art separate | Studied | |

## Sand
| Repo / source | Commit | License | Status | Notes |
|---|---|---|---|---|
| alanzucconi.com Journey sand series parts 1–6 | — | article | Adapted (v1.5) | game/world/sand_ripple.gdshader: diffuse contrast, grain nlerp, slope ripples, rim/ocean max(), glitter. |
| AtwoodDeng/JourneySand | f793aab | **CC BY-SA 4.0** | Studied only | Share-alike: no code copied. |
| Exyde/Journey-Sand-Shader | 05dab56 | **No license file** | Studied only | |
| Flynsarmy/gd-snow-project | 72af9dd | see repo | Studied | Trail-mask approach for Phase 2 footprints. |
| GDC 1017742 "Sand Rendering in Journey" | — | talk | Studied | |

## ICO creatures
| Repo | Commit | License | Status | Notes |
|---|---|---|---|---|
| nathanialf/ico, nathanialf/ico-pc | 5ebb9a4, 5396fcf | MIT (decomp code) — underlying game data proprietary | Studied only | No code, data or assets used. |
| odevpedro/ico-reconstruction | 44f0e9a | **No license file** | Studied only | |

## Gameplay / controllers / tools (not used in Phase 0–1)
adventure-mode-godot 42d9c96 (custom), g4-climb-n-glide d11dbb2 (MIT),
phantom-camera 7945af6 (MIT), limboai d25f876 (MIT),
godot-gameplay-abilities 6d1ce71 (MIT), Godot-Trail3D 299b361 (MIT),
Terrain3D 69699ff (MIT), mobile_controls 614b7c9 (MIT),
libsm64-godot dff8695 (MIT, needs a user-supplied SM64 ROM — **will not be
used**). zeldaret/oot, zeldaret/botw, Shipwright, Zelda64Recomp,
n64decomp/sm64, libsm64: decompilations of proprietary games — **not
cloned, not used**; design references only.

## Previously integrated assets
| Asset | Source | License | Use |
|---|---|---|---|
| KayKit Character Pack: Adventurers 1.0 | github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | CC0 | Rig_Medium skeleton + 76 clips (player rig, game/art/rig/hafid_rig.glb); hooded rogue mesh as the shadow jinn base (shadow.glb). Licence copy: game/art/rig/KAYKIT_LICENSE.txt |

## Round 2026-11-25 (owner environment spec)
| Reference | Status | Notes |
|---|---|---|
| Garbage Country screenshots (owner-supplied) | Studied | Frame comparison in docs/oasis/GARBAGE_COUNTRY_COMPARISON.md; no assets used |
| Owner Sahara photo | Studied | Palette target sampled; no pixels used |
| HungryProton/scatter (Proton Scatter) | Not integrated | Scatter done with in-house noise-clumped placement (Oasis._build_scatter) |
| TheMIU/Stylized-Fluffy-Tree-Shader | Not integrated | Spec lists it as shading reference only; individual leaves kept |
| Garbage Country trailer (YouTube d4S9pdUVML8) | Not viewed | No video access from the build workspace |

## Round 2026-11-25 (daraa reconstruction) — see docs/garment/DARAA.md
| Repo / reference | Commit | License | Status | Notes |
|---|---|---|---|---|
| maria-korosteleva/GarmentCode | d449629 | MIT | Format followed | Pattern JSON layout only; no code copied |
| opensew-2 | 86b4322 | GPL-3 | Studied only | |
| blender_clothing_tools | 776370c | GPL-3 | Studied only | |
| blender-seams-to-sewing-pattern | 919d031 | GPL | Studied only | |
| freesewing | 8a8de5a2 | MIT | Studied only | |
| godot-jigglebones | e861ae9 | MIT | Studied only | Springs written in-house |
| bpy (Blender 5.3 module) | pip | GPL | Tool | Drape/shape keys/GLB export; output is project data |
| democraticac.de, FIT boubou, textilevaluechain, custom-qamis, mauritania-travel, UCSC boubou, ami.mr | — | — | Text references | Construction facts; no images used |
| Two YouTube daraa videos | — | — | Not viewed | Rate-limited |
