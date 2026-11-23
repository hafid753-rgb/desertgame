# Hafid — The Room

First playable prototype of **Hafid**, a Mauritanian fantasy action RPG.
Two questions: **is touch combat fun, and does climbing and gliding feel good, on a cheap Android phone?**

A greybox Saharan courtyard with walkable walls, the Cat (switchable to Fennec and
Lizard), and one shadow jinn with three telegraphed attacks that respawns 3 s after
it is banished. Outside the open gate: dunes, a ruined wall, a 10 m pillar, and a
20 m mesa that only the Lizard can climb in one go.

## Run it

- **Phone:** install `hafid-the-room.apk` (Android 7.0 or newer; allow "install unknown apps").
- **PC:** open this folder in Godot **4.6.3** and press F5.
- **Tests:** `godot --headless --path . --fixed-fps 60 res://tests/combat_test.tscn` (45 checks: combat, traversal, species, menu; exit code 0 = pass).
- **Sounds:** `python3 tools/gen_sfx.py` regenerates `game/audio/*.wav` (original, procedurally generated).
- **Screenshots:** `godot --path . res://tools/screenshot.tscn` → `user://shots/`.

## Controls

| Touch | Keyboard / mouse | Gamepad | Action |
| --- | --- | --- | --- |
| Left side: floating joystick | WASD | Left stick | Move (push fully for 0.5 s = sprint) |
| Right side: swipe | Right-mouse drag | Right stick | Camera |
| Tap a jinn on screen / LOCK | Tab | LB | Lock-on (Q / R3 cycles) |
| ATK tap | J / left click | X | Combo (3 hits) |
| ATK hold | hold J | hold X | Heavy strike on release |
| DGE tap | K / Space | B | Dodge (direction of stick; backstep if neutral) |
| DGE hold | hold K | hold B | Block. Starting the block ≤150 ms before a hit = **PARRY** |
| SPC hold | hold L / Shift | RB | Charge element: tier I 0.35 s, II 0.8 s, III 1.4 s |
| SPC held + ATK | | | Elemental attack (Wind gust or Fire strike) |
| SPC held + DGE | | | Elemental mobility (wind dash / fire burst) |
| DGE held + tap SPC | | | Elemental defense (wind deflect / fire riposte) |
| ELM (top right) | E | Y | Switch Wind ↔ Fire (out of combat) |
| JMP | Space | A | Jump. On a wall: LEAP off |
| Push into a wall | push W into a wall | push stick | Climb (uses stamina; reach the top to mantle) |
| DGE while climbing | | | DROP (let go) |
| SPC tap in the air | | | Open the daraa and glide; tap again (or JMP) to close |
| Tap species label | 1 | Back | Cat → Fennec → Lizard |
| II (top right) | Esc / P | Start | Pause: left-handed layout, button size, sound, session stats |

Release SPC without pressing anything = cancel, no stamina cost.
Falling faster than 17 m/s (about a 6 m drop) hurts; glide to land safely.

## Species

| | Cat | Fennec | Lizard |
| --- | --- | --- | --- |
| Run speed | 1.15× | 1.0× | 0.9× |
| Climb speed | 1.3× | 1.0× | 0.8× |
| Stamina | 70 | 100 | 140 |
| Height climbed on a full bar (measured in tests) | 15.5 m | 16.8 m | 20 m mesa topped |
Parry or perfect dodge = 1 s counter window (x1.5 damage); a staggered jinn takes x1.25.

## Reading the jinn

| Eyes | Attack | Telegraph | Answer |
| --- | --- | --- | --- |
| Orange + rising whine | Swipe (arc in front) | 0.6 s | Parry, or dodge sideways |
| Red + pulsing growl | Lunge (dashes at you) | 0.9 s, pulls back | Dodge late for a perfect dodge |
| Violet + swelling ring + deep rumble | Smoke burst (3.4 m ring) | 1.2 s | Get out, or dodge through it |

Each attack has its own sound, so it can be read by ear as well as by colour.

## Layout

```
game/
  autoload/   game_input.gd (one input path for touch/keys/pad), perf_logger.gd (CSV per second),
              juice.gd (sound, hit-stop, shake), settings.gd (saved options)
  audio/      generated placeholder sound effects
  actors/     player/ (rules, species, placeholder model)  jinn/ (AI, smoke shader)
  camera/     orbit + lock-on rig
  combat/     shared rules (Combat), effects (Fx)
  input/      touch HUD
  world/      greybox courtyard
tests/        headless combat acceptance tests
tools/        screenshot capture
docs/         ADRs, playtest protocol
```

Combat rules sit in `player.gd` / `jinn.gd` with no rendering dependencies,
so they can move to a headless server in Phase 3.

## Performance log

Every second the game appends a row to `user://perf_<timestamp>.csv`
(FPS, p95/p99 frame time, draw calls, memory, input-to-action latency).
On Android that is `/data/data/dev.overcode.hafid/files/`; the same numbers show live at the bottom of the screen.

## Status

Prototype v0.2. Placeholder art and generated sounds. No networking, terrain streaming,
village or Jinn King yet. Traversal modes besides the wind glide (ice board, fire shoes,
sand wave) come later.
