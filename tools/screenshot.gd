extends Node
## Renders the room to PNGs for review: godot --path . res://tools/screenshot.tscn
## Output: user://shots/*.png (path printed).

var main: Node3D

func _ready() -> void:
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	for i in 20:
		await get_tree().process_frame
	main.jinn.ai_enabled = false
	main.jinn.global_position = Vector3(0.5, 0, 2.5)
	main.player.global_position = Vector3(0, 0.05, 6)
	main.player.reset_physics_interpolation()
	for i in 30:
		await get_tree().process_frame
	await _shot("01_overview")
	main.jinn.global_position = Vector3(0.5, 0, 0.5)
	main.player.toggle_lock()
	GameInput.press("special")
	for i in 40:
		await get_tree().process_frame
	main.jinn.force_attack("burst")
	for i in 25:
		await get_tree().process_frame
	await _shot("02_lock_telegraph_charge")
	GameInput.release("special")
	GameInput.press("attack")
	for i in 6:
		await get_tree().process_frame
	GameInput.release("attack")
	for i in 4:
		await get_tree().process_frame
	await _shot("03_attack")
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	var img := get_viewport().get_texture().get_image()
	var path := "user://shots/%s.png" % name
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
