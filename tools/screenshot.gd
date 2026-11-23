extends Node
## Renders review screenshots: godot --path . res://tools/screenshot.tscn
## Output: user://shots/*.png (paths printed).

var main: Node3D
var p: Player


func _ready() -> void:
	Juice.enabled_hitstop = false
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	await _wait(20)
	p = main.player
	main.jinn.ai_enabled = false

	# 1. Combat: lock-on + telegraph.
	main.jinn.global_position = Vector3(0.5, 0, 0.5)
	p.global_position = Vector3(0, 0.05, 4)
	p.reset_physics_interpolation()
	await _wait(20)
	p.toggle_lock()
	main.jinn.force_attack("burst")
	await _wait(30)
	await _shot("01_combat_lock_telegraph")
	p.toggle_lock()

	# 2. Outside: look at the mesa and pillar from beyond the gate.
	main.jinn.global_position = Vector3(-6, 0, -6)
	p.global_position = Vector3(-6, 0.05, 15)
	p.rotation.y = 2.54
	main.camera_rig.yaw = 2.54
	main.camera_rig.pitch = -0.05
	p.reset_physics_interpolation()
	await _wait(40)
	await _shot("02_outside_mesa_pillar")

	# 3. Climbing the pillar.
	p.global_position = Vector3(12, 0.05, 22.6)
	p.rotation.y = PI
	main.camera_rig.yaw = PI
	main.camera_rig.pitch = -0.05
	p.reset_physics_interpolation()
	await _wait(5)
	GameInput.touch_move = Vector2(0.25, -1)
	await _wait(60)
	main.camera_rig.yaw = PI * 0.75
	await _wait(10)
	await _shot("03_climbing_pillar")
	GameInput.touch_move = Vector2.ZERO

	# 4. Gliding with the daraa.
	p.global_position = Vector3(20, 9, 8)
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	main.camera_rig.yaw = 0.4
	main.camera_rig.pitch = -0.2
	p.reset_physics_interpolation()
	await _wait(8)
	GameInput.press("special")
	await _wait(3)
	GameInput.release("special")
	GameInput.touch_move = Vector2(0, -1)
	await _wait(40)
	await _shot("04_glide_daraa")
	GameInput.touch_move = Vector2.ZERO

	# 5. Pause menu.
	main.hud.set_paused(true)
	await _wait(3)
	await _shot("05_pause_menu")
	main.hud.set_paused(false)
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	var img := get_viewport().get_texture().get_image()
	var path := "user://shots/%s.png" % name
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
