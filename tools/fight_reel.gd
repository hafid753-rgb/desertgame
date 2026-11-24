extends Node
## Records the cat fighting a jinn in the real game (AI on, real combat):
##   godot --path . --write-movie /tmp/fight.avi --fixed-fps 30 res://tools/fight_reel.tscn
## A small bot locks on, closes in, strings combos, charges heavies and
## dodges every telegraph.

var main: Node3D
var p: Player
var t := 0.0
var next_tap := 0.0
var dodge_cd := 0.0
var heavy_until := -1.0
var taps := 0
var dead_at := -1.0
var release_queue: Array = []
var side_cam := false
var _cam_pos := Vector3.ZERO


## Side-on fight camera: perpendicular to the cat-jinn line, framing both.
func _process(delta: float) -> void:
	if not side_cam or p == null:
		return
	var cam: Camera3D = main.camera_rig.camera
	var a := p.global_position
	var b := a + p.global_transform.basis * Vector3(0, 0, -2.0)
	if main.jinn != null and is_instance_valid(main.jinn) and not main.jinn.is_dead():
		b = main.jinn.global_position
	var mid := (a + b) * 0.5
	var line := Combat.flat(b - a)
	if line.length() < 0.1:
		line = Vector3(0, 0, -1)
	var perp := Vector3(-line.z, 0, line.x).normalized()
	# stay on the open (courtyard-centre) side so walls never block the shot
	if Combat.flat(mid + perp * 3.6).length() > Combat.flat(mid - perp * 3.6).length() + 1.5:
		perp = -perp
	var want := mid + perp * 3.6 + Vector3(0, 1.35, 0) - line.normalized() * 0.6
	_cam_pos = want if _cam_pos == Vector3.ZERO else _cam_pos.lerp(want, 1.0 - exp(-3.0 * delta))
	cam.global_position = _cam_pos
	cam.look_at(mid + Vector3(0, 0.8, 0))


func _ready() -> void:
	process_priority = 1000  # run after the camera rig, then override the view
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	p = main.player
	p.global_position = Vector3(0, 0.1, 7)
	p.reset_physics_interpolation()
	if OS.get_cmdline_user_args().has("close"):
		side_cam = true
		main.hud.visible = false


func _tap(action: String, hold: float = 0.06) -> void:
	GameInput.press(action)
	release_queue.append([t + hold, action])


func _physics_process(delta: float) -> void:
	t += delta
	for r in release_queue.duplicate():
		if t >= float(r[0]):
			GameInput.release(str(r[1]))
			release_queue.erase(r)
	if main.jinn_kills > 0 or (main.jinn != null and is_instance_valid(main.jinn) and main.jinn.is_dead()):
		if dead_at < 0.0:
			dead_at = t
			p.emote("thumbs_up", 2.0)
		GameInput.touch_move = Vector2.ZERO
		if t - dead_at > 3.2:
			get_tree().quit()
		return
	var j: Jinn = main.jinn
	if side_cam and j != null and is_instance_valid(j) and not j.has_meta("reel_hp"):
		j.set_meta("reel_hp", true)
		j.hp = 150.0
	if t < 1.2 or j == null or not is_instance_valid(j):
		GameInput.touch_move = Vector2.ZERO
		return
	if t > 40.0:
		get_tree().quit()
		return
	if p.lock_target == null and t > 1.4:
		p.toggle_lock()
	dodge_cd -= delta
	var d := Combat.flat(j.global_position - p.global_position).length()
	var js := j.state_name()
	if js == "TELEGRAPH" and d < 5.0 and dodge_cd <= 0.0:
		# step sideways out of the burst
		GameInput.touch_move = Vector2(1.0 if int(t) % 2 == 0 else -1.0, 0.3)
		_tap("dodge")
		dodge_cd = 1.0
		return
	if t < heavy_until:
		GameInput.touch_move = Vector2.ZERO
		return
	if d > 2.0:
		GameInput.touch_move = Vector2(0, -1)
		return
	GameInput.touch_move = Vector2.ZERO
	if p.stamina < 30.0:
		# breathe: step back and let stamina refill
		GameInput.touch_move = Vector2(0.0, 0.6) if d < 3.2 else Vector2.ZERO
		return
	if t >= next_tap:
		taps += 1
		if taps % 5 == 0:
			_tap("attack", 0.9)       # hold = heavy
			heavy_until = t + 1.3
			next_tap = t + 1.5
		else:
			_tap("attack")
			next_tap = t + (0.32 if taps % 5 != 4 else 0.7)
