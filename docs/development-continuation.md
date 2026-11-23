# Hafid v0.3 — change log and verification status

## Changes

- Extended `Combat.Element` to WIND, FIRE, WATER (ice), EARTH.
- Water/Ice attacks apply a timed movement slow to the jinn, overriding burn.
- Water/Ice elemental defense absorbs a frontal attack and chills the attacker.
- Earth attacks heal the player rather than directly damage a target.
- Earth elemental defense heals slightly and reduces the next frontal hit by 50%.
- Temporary mobile-friendly ice-slide and earth sand-wave movement bursts.
- Added five elemental acceptance tests and a four-element switching test.

## Boundaries and open design questions

- The current `Special` long-press charges attacks. The proposed equipment-dependent
  **hold Special while walking to travel** conflicts with this gesture. Do not
  silently invent timing rules: resolve it with a dedicated input playtest.
- No actual ski board, fire shoes, earth terrain deformation, water surfaces,
  healing allies, elemental damage-type input on enemy attacks or status VFX.
- Ice movement slow affects NPC locomotion, not animation or telegraph time.
- No player inventory or physics synchronization; not a multiplayer build.
- Fire/wind values are intentionally unchanged to preserve existing balancing.

## Checks

Static inspection completed. Godot 4.6.3 executable is unavailable in the
current environment, so `tests/combat_test.tscn` and Android export could not
be executed. **Do not claim the new tests pass until run in Godot.**

Run:

```sh
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 res://tests/combat_test.tscn
```

Then test real mobile touch input, species switching, shader compatibility,
and FPS on low-end Android hardware. Do not commit until green.
