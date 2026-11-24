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


func _ready() -> void:
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	p = main.player
	p.global_position = Vector3(0, 0.1, 7)
	p.reset_physics_interpolation()


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
