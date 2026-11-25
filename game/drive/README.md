# Desert driving test (separate prototype)

This is a top-down driving test set in the Hafid desert. It uses the same
courtyard, oasis, dunes, Journey-style sand, wind, dust, light and lens
flare as the main game.

Run it:
- `godot --path . res://game/drive/drive_test.tscn` to drive it yourself.
  Arrow keys or the touch stick steer and accelerate; Space is the
  handbrake.
- `... -- teaser` runs the scripted teaser: drifts, the oasis pond, then
  stuck in soft sand.

## Files
- `voxel_car.gd` is an original boxy 1980s sedan made of 0.1 m voxels. It
  is built in code and carries no brand marks.
- `desert_car.gd` is the arcade handling:
  - Slip model: engine force along the heading, lateral grip, and a
    handbrake drift.
  - Raycast ride over the dunes and slopes.
  - Water: drag, spray and ripples on the pond.
  - Soft-sand pits: the wheels spin, the car digs in and gets stuck.
  - It joins the "player" group, so the tyre grooves, grass parting and
    oasis splash come from the game's shared systems.
- `drive_test.gd` builds the world, the top-down chase camera, and the
  teaser autopilot (pure pursuit along a smoothed route).
