extends Node3D
## Front and back lineup of the three masks on the child (for review).
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("E9D2BC")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("D9A88A")
	e.ambient_light_energy = 0.72
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("FFE3C4")
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(28), 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("DCB08E")
	floor.material_override = fm
	add_child(floor)
	var models := []
	var i := 0
	for id in ["cat", "fennec", "rabbit"]:
		var m := CreatureModel.new()
		add_child(m)
		m.build(Species.get_data(id))
		m.position = Vector3((i - 1) * 1.15, 0, 0)
		models.append(m)
		i += 1
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 38.0
	for side in ["front", "back"]:
		var z := -4.4 if side == "front" else 4.4
		cam.position = Vector3(0, 1.15, z)
		cam.look_at(Vector3(0, 0.8, 0))
		for f in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/lineup_%s.png" % side)
	get_tree().quit()
