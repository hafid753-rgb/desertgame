extends Node
## Gameplay showcase clips in the real game (High quality):
##   godot --path . --write-movie /tmp/walk.avi --fixed-fps 30 res://tools/showcase.tscn -- seg=walk
## seg = walk | run | jump | water. (Fighting: tools/fight_reel.tscn -- close)
## Writes stills to user://shots/show_<seg>_<n>.png along the way.

var main: Node3D
var p: Player
var t := 0.0
var seg := "walk"
var shots_at: Array[float] = [2.0, 4.0]
var _shot_i := 0
var _release := -1.0
const OASIS := Vector3(-32, 0, -4)


func _ready() -> void:
	Settings.quality = 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seg="):
			seg = a.substr(4)
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	main.hud.visible = false
	p = main.player
	var start := {"walk": OASIS + Vector3(16, 0.05, 12), "run": OASIS + Vector3(20, 0.05, -10),
		"jump": OASIS + Vector3(16, 0.05, -14), "water": OASIS + Vector3(8.5, 0.05, 1.0),
		"surf": Vector3(-28.5, 8.3, 46.0)}
	var yaw := {"walk": 0.6, "run": 2.2, "jump": 1.2, "water": PI * 0.5, "surf": -PI * 0.5}
	p.global_position = start.get(seg, start["walk"])
	p.rotation.y = yaw.get(seg, 0.0)
	p.reset_physics_interpolation()
	main.camera_rig.yaw = p.rotation.y
	main.camera_rig.pitch = -0.22
	if seg == "water":
		shots_at = [2.2, 3.6, 5.5]
	if seg == "surf":
		shots_at = [1.6, 2.6, 3.6, 4.4, 5.2, 6.4]
		main.camera_rig.distance = 6.0


func _physics_process(delta: float) -> void:
	t += delta
	if _release > 0.0 and t >= _release:
		GameInput.release("jump")
		_release = -1.0
	var mv := Vector2.ZERO
	match seg:
		"walk":
			mv = Vector2(sin(t * 0.5) * 0.25, -0.42) if t > 0.6 and t < 7.0 else Vector2.ZERO
			main.camera_rig.yaw = lerp_angle(main.camera_rig.yaw, p.rotation.y + sin(t * 0.4) * 0.9, delta * 1.5)
		"run":
			mv = Vector2(sin(t * 0.6) * 0.35, -1.0) if t > 0.5 and t < 7.0 else Vector2.ZERO
		"jump":
			mv = Vector2(0, -0.7) if t > 0.5 and t < 7.5 else Vector2.ZERO
			if t > 1.0 and fmod(t, 1.3) < delta and t < 7.0:
				GameInput.press("jump")
				_release = t + 0.25
		"surf":
			mv = Vector2(sin(t * 1.3) * 0.25, -1.0) if t > 0.4 and t < 9.0 else Vector2.ZERO
			main.camera_rig.yaw = -PI * 0.5
			if int(t * 10.0) % 5 == 0 and fmod(t, 0.5) < delta:
				print("t %.1f state %s pos %s vel %.1f" % [t, p.state_name(), p.global_position.snapped(Vector3.ONE * 0.1), p.velocity.length()])
		"water":
			if t > 0.6 and t < 2.4:
				mv = Vector2(0, -0.55)
			elif t > 3.0 and t < 4.8:
				mv = Vector2(0.6, -0.2)
			elif t > 5.6 and t < 6.6:
				mv = Vector2(0, 0.6)
			main.camera_rig.pitch = lerpf(main.camera_rig.pitch, -0.35, delta)
	GameInput.touch_move = mv
	if _shot_i < shots_at.size() and t >= shots_at[_shot_i]:
		_shot_i += 1
		_save(_shot_i)
	if t > (10.0 if seg == "surf" else 8.0):
		get_tree().quit()


func _save(n: int) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	get_viewport().get_texture().get_image().save_png("user://shots/show_%s_%d.png" % [seg, n])
