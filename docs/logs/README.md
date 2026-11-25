# Hafid — work log and media index

Everything produced in this build session lives here, in `media/` and in
`releases/`.

- `CHANGELOG_full_git_history.md`: every commit with its full message, oldest
  first. It is the authoritative change log.
- `tests_v3.5.1.txt`, `tests_v3.5.2.txt`, `tests_v3.5.3.txt`: gameplay test results (combat 97/97, village 29/29).
- `perf_daraa_v3.5.0.txt`: daraa vs old robe frame cost, measured with the
  software renderer only (not on a phone).
- `render_showcase_v3.5.1.txt`: engine log of the showcase render.
- `../RESEARCH_LEDGER.md`: every repository and reference, with licence and
  integration status.
- `../garment/DARAA.md`: daraa research, construction, assumptions and
  validation.
- `../oasis/`: oasis and environment notes, plus the Garbage Country
  comparison.
- `../sand/`: Journey-style sand rendering notes.

## Rounds (latest first)

| Version | What changed | Media |
|---|---|---|
| 3.5.3 (code 39) | Daraa proportions (narrower, lower gathers), anti-self-clipping, hawli on the neck with head/daraa collision, chin on the yoke, yellow belgha feet, green rabbit daraa; full activity reels | videos/hafid_showcase.mp4, hafid_water.mp4, hafid_surf_glide.mp4, hafid_fight.mp4, hafid_oasis_walk.mp4 |
| 3.5.2 (code 38) | Head 20% smaller (lowered into the neckline); simple leather babouches replace the bulky boots and sirwal cuffs; daraa folds Taubin-smoothed (no crumple noise); showcase re-shot | videos/daraa_showcase_v3.5.2.mp4, stills/daraa_closeup_v3.5.2.png |
| 3.5.1 (code 37) | Floating hands appear only in combat or emotes; daraa showcase cinematic | videos/daraa_showcase.mp4 |
| 3.5.0 (code 36) | Authentic daraa built from a flat pattern and Blender drape: 3 wearing configurations plus glide spread, runtime springs and collision, LOD | videos/daraa_in_game.mp4, stills/daraa_*.png |
| 3.4.1 (code 35) | Little Nightmares children with masks, then reverted at the owner's request | videos/hafid-mask-children.mp4 (reverted design) |
| 3.4.x | Robe cloth deformation (wind, lag, hang); epic ramp and fast glide | videos/hafid-epic-glide.mp4, hafid-epic-ramp.mp4 |
| 3.3.x | Sand surfing on the shield, dust plume, daraa glide, face veil; tech-demo cinematics and fight | videos/hafid-sand-surf-glide.mp4, hafid-tech-demo.mp4, hafid-fight-cinematic.mp4 |
| 3.2.x | Realistic lens flare; walk, run, jump and water clips | videos/hafid-walk.mp4, hafid-run.mp4, hafid-jump.mp4, hafid-water.mp4 |
| 3.1.x | Journey sand spec, smaller head, hawli ribbon, stylised shadows, sun flare | videos/sand-scarf.mp4, stills/sand-character-sheet.png, sun-light-sheet.png |
| 3.0.x | Saharan palette, low wide dunes, cel shading, lower contrast | videos/oasis-saharan.mp4, stills/dunes-cel-sheet.png, low-contrast-sheet.png |
| 2.8–2.9 | Oasis: pond, desert grass, palms, reflections, wind | videos/oasis-wind.mp4, oasis-life.mp4, stills/oasis-*.png |
| earlier | Phase 1 pixel world, characters, cat vs jinn | videos/cat-vs-jinn*.mp4, stills/phase1-*.png, v0.*.png |

## Open items
- On-device profiling: no phone frame rate has been measured or claimed.
- Daraa measurements are estimates; validation photos have been requested
  (see DARAA.md §3).
- The YouTube references (Garbage Country trailer, two daraa videos) could
  not be viewed from the build workspace.
## media/ listing
    media/stills:
    daraa_blender_drape.png
    daraa_closeup.png
    daraa_pattern_texture_blue.png
    daraa_silhouette.png
    daraa_species.png
    daraa_views.png
    dunes-cel-sheet.png
    hafid-mask-lineup.png
    hafid-showcase-stills.png
    hands_sheet.png
    low-contrast-sheet.png
    oasis-life-sheet.png
    oasis-reflection.png
    oasis-sheet.png
    oasis-vs-references.png
    phase1-before-after.png
    phase1-detail.png
    phase1-texture-families.png
    sand-character-sheet.png
    sun-light-sheet.png
    the-room-screenshot.png
    v0.2-screens.png
    v0.3-characters.png
    v0.3.1-characters.png
    v0.4-characters.png
    v0.6-boxy-characters.png
    v0.7-wip.png
    v0.8-chibi-sculpt.png
    v0.8-fur-chibi.png
    v0.9-vinyl.png
    v0.9.1-fur.png
    v1.0-storybook.png
    v1.1-sheet.png
    v1.2-sheet.png
    v1.3-squash.png
    v1.4-sheet.png
    v1.4.1-lineup.png
    v1.5-sand.png
    
    media/videos:
    cat-vs-jinn-close.mp4
    cat-vs-jinn.mp4
    daraa_in_game.mp4
    daraa_showcase.mp4
    hafid-epic-glide.mp4
    hafid-epic-ramp.mp4
    hafid-fight-cinematic.mp4
    hafid-jump.mp4
    hafid-mask-children.mp4
    hafid-run.mp4
    hafid-sand-surf-glide.mp4
    hafid-tech-demo.mp4
    hafid-walk.mp4
    hafid-water.mp4
    oasis-life.mp4
    oasis-saharan.mp4
    oasis-wind.mp4
    sand-scarf.mp4
    v2.0-motion-reel.mp4
    v2.1-motion-reel.mp4
    v2.2-cat-vs-jinn.mp4
    v2.2-combo-closeup.mp4
    v2.3-cat-vs-shadow.mp4
    v2.3-jinn-attacks.mp4
