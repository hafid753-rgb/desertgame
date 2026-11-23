extends Node
## Character lineup render: godot --path . res://tools/portrait.tscn
## Saves user://shots/lineup.png and user://shots/jinn_close.png

func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.74, 0.56)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.85, 0.8)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.78, 0.64, 0.45)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var x := -2.4
	for id in ["cat", "fennec", "lizard"]:
		var m := CreatureModel.new()
		root.add_child(m)
		m.build(Species.get_data(id))
		m.position = Vector3(x, 0, 0)
		m.rotation.y = PI + 0.35
		x += 1.6
	var j := Jinn.new()
	j.ai_enabled = false
	j.position = Vector3(2.6, 0, -0.4)
	j.rotation.y = PI + 0.25
	root.add_child(j)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.position = Vector3(0, 1.6, 7.2)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	for i in 30:
		await get_tree().process_frame
	await _shot("lineup")
	cam.position = Vector3(2.0, 1.55, 1.8)
	cam.look_at(Vector3(2.6, 1.2, -0.4))
	for i in 5:
		await get_tree().process_frame
	await _shot("jinn_close")
	cam.position = Vector3(-2.9, 1.25, 1.6)
	cam.look_at(Vector3(-2.4, 0.9, 0))
	for i in 5:
		await get_tree().process_frame
	await _shot("cat_close")
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	var path := "user://shots/%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
