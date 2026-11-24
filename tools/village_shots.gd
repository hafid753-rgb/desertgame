extends Node
## Renders the village in each stage: godot --path . res://tools/village_shots.tscn

var main: Node3D

func _ready() -> void:
	Juice.enabled_hitstop = false
	WorldState.use_path("user://shots_world.json", true)
	main = preload("res://game/main.tscn").instantiate()
	main.jinn_enabled = false
	add_child(main)
	await _wait(10)
	var v: Village = main.village
	var p: Player = main.player
	var cam: CameraRig = main.camera_rig
	p.global_position = v.global_position + Vector3(0, 0.05, 11)
	p.rotation.y = 0.0
	cam.yaw = 0.0
	cam.pitch = -0.18
	p.reset_physics_interpolation()
	v.king.ai_enabled = false
	for m in v.minions:
		m.ai_enabled = false
	await _wait(90)
	await _shot("v1_haunted_king")
	v.king.force_attack("summon")
	await _wait(40)
	await _shot("v2_king_summon")
	v.king.take_damage({"amount": 99999.0, "stagger": 2, "from": p.global_position})
	await _wait(120)
	await _shot("v3_claimed_kneeling")
	WorldState.data["player"]["bricks"] = 10
	v.rebuild_mosque()
	await _wait(150)
	p.global_position = v.global_position + Vector3(-2, 0.05, 6)
	cam.yaw = -0.25
	cam.pitch = -0.05
	p.reset_physics_interpolation()
	await _wait(40)
	await _shot("v4_mosque_rebuilt")
	WorldState.use_path("user://world.json")
	get_tree().quit()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	var path := "user://shots/%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
