extends Node
## Showcase of every jinn attack in the real game (player idle, side camera):
##   godot --path . --write-movie /tmp/jinn.avi --fixed-fps 30 res://tools/jinn_reel.tscn

const SEQ := [[1.2, "fireball"], [4.0, "swipe"], [6.4, "lunge"], [9.0, "fireball"], [11.4, "vanish"], [16.0, "burst"], [19.5, ""]]

var main: Node3D
var p: Player
var t := 0.0
var i := 0
var _cam_pos := Vector3.ZERO


func _ready() -> void:
	process_priority = 1000
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	p = main.player
	main.hud.visible = false
	p.global_position = Vector3(0, 0.1, 4)
	p.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	t += delta
	var j: Jinn = main.jinn
	if j == null or not is_instance_valid(j):
		return
	j.ai_enabled = false
	p.hp = p.max_hp  # keep the cat standing for the whole showcase
	if i < SEQ.size() and t >= float(SEQ[i][0]):
		var name: String = SEQ[i][1]
		i += 1
		if name == "":
			get_tree().quit()
			return
		# reposition for the move: far for fireballs, close for melee
		var d := 7.5 if name == "fireball" else (4.6 if name == "lunge" else 2.2)
		if name != "vanish":
			j.global_position = p.global_position + Vector3(0, 0, -d)
		j.force_attack(name)


func _process(delta: float) -> void:
	var cam: Camera3D = main.camera_rig.camera
	var j: Jinn = main.jinn
	var a := p.global_position
	var b := a + Vector3(0, 0, -3)
	if j != null and is_instance_valid(j) and not j.hidden:
		b = j.global_position
	var mid := (a + b) * 0.5
	var want := mid + Vector3(5.2, 1.5, 0.6)
	_cam_pos = want if _cam_pos == Vector3.ZERO else _cam_pos.lerp(want, 1.0 - exp(-2.5 * delta))
	cam.global_position = _cam_pos
	cam.look_at(mid + Vector3(0, 1.0, 0))
