# Hafid v0.4 — Combat + spectral jinn + interactive environment

## What changed

1. **Ico-like spirit rendering** — original procedural spectral skirt (8 translucent ribbons / one mesh), softly wobbling ghost shell, attack-specific silhouette tints, and dissolve-on-death. Original models remain; no extracted ICO meshes, textures, audio, or code were copied.
2. **Zelda-style focus indicator** — an unobtrusive 2D projected lock-on diamond. Existing target-follow camera, parry, dodge, counters and climb/glide controller retained unchanged.
3. **Journey-like sand lighting** — procedural world-space ripple material applied to terrain floor and dunes. No additional texture files or runtime sand simulation.
4. **Physics/element experiment** — two wooden crates + a stone near the southern gate. Wind pushes, fire ignites wood, water extinguishes and chills, and earth launches nearby props. Scripted as an explicit simulation interface that can later move to the server.
5. **Regression checks** — three physics property tests and one spirit silhouette test added to existing headless combat tests.

## Source references (research only)

- Ico matching PS2 decompilation: https://github.com/nathanialf/ico
- Ico PC/mobile port: https://github.com/nathanialf/ico-pc
- Zelda Ocarina of Time decompilation: https://github.com/zeldaret/oot
- Zelda Breath of the Wild decompilation: https://github.com/zeldaret/botw
- Adventure Mode Godot template: https://github.com/EasterEggProductions/adventure-mode-godot

These repositories were reviewed as references to explain behavior and implementation patterns. **No decompiled or recompiled game code was included** in the project: the PS2/N64 engines and proprietary animations are not drop-in dependencies for Godot. Respect `docs/adr/0002-no-decomp-code.md`.

## Scope limitations

- Single-player greybox prototype; not a 100-player MMO or persistent world.
- No authentic Ico shadow meshes/animations; visual direction is original and inspired by shadow-spirit silhouettes.
- Elements interact with test objects only, not terrain or entire buildings.
- Existing mobile controls unchanged. The hold-Special traversal vs charging conflict is still unresolved.
- The jinn remains a single encounter with three telegraphed moves; new body visual and tells do not constitute new enemy AI.
- Godot runtime wasn't available in this environment. Changes are static-inspected but require Godot import, headless tests and device performance verification.

## Recommended verification

```bash
godot --headless --path . --import
godot --headless --path . res://tests/combat_test.tscn
godot --path .
```

Open the game and check the jinn's smoky veil and focus diamond; move outside the gate to experiment with props. Check that opaque + transparent meshes render in the Godot 4 Mobile renderer, including on Android devices.
