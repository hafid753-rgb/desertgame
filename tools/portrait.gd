extends Node
## Character lineup render: godot --path . res://tools/portrait.tscn
## Saves user://shots/lineup.png and user://shots/jinn_close.png

var models: Array[CreatureModel] = []


func _process(delta: float) -> void:
	for m in models:
		m.animate(delta, {"move": 0.0, "state": "MOVE"})


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
	root.add_child(sun)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.62, 0.9)
	sm.sky_horizon_color = Color(0.9, 0.86, 0.78)
	sm.ground_horizon_color = Color(0.86, 0.74, 0.56)
	sm.ground_bottom_color = Color(0.7, 0.56, 0.4)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_white = 1.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.6, 0.48, 0.34)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var x := -2.4
	for id in ["cat", "fennec", "rabbit"]:
		var m := CreatureModel.new()
		models.append(m)
		root.add_child(m)
		m.build(Species.get_data(id))
		m.position = Vector3(x, 0, 0)
		m.rotation.y = PI + 0.35
		m.set_armed(true)
		x += 1.6
	var j := Jinn.new()
	j.ai_enabled = false
	j.position = Vector3(2.6, 0, -0.4)
	j.rotation.y = PI + 0.25
	root.add_child(j)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.position = Vector3(0, 1.5, 8.2)
	cam.look_at(Vector3(0, 1.05, 0))
	cam.current = true
	for i in 30:
		await get_tree().process_frame
	await _shot("lineup")
	cam.position = Vector3(1.6, 1.9, 2.6)
	cam.look_at(Vector3(2.6, 1.5, -0.4))
	for i in 5:
		await get_tree().process_frame
	await _shot("jinn_close")
	cam.position = Vector3(-2.7, 1.45, 2.2)
	cam.look_at(Vector3(-2.35, 1.2, 0))
	for i in 5:
		await get_tree().process_frame
	await _shot("cat_close")
	# Faces, open and closed ("> <").
	cam.position = Vector3(-0.8, 1.4, 4.4)
	cam.look_at(Vector3(-0.8, 1.2, 0))
	for i in 5:
		await get_tree().process_frame
	await _shot("faces")
	for m in models:
		m._blink_t = 30.0
		m._blink_in = 30.0
	for i in 5:
		await get_tree().process_frame
	await _shot("faces_closed")
	for m in models:
		m._blink_t = 0.0
		m._blink_in = 3.0
	# Squash & stretch strip on the cat: take-off, mid-air, landing, settle.
	var cat0: CreatureModel = models[0]
	models.erase(cat0)
	cat0.set_armed(false)
	cam.position = Vector3(-2.4, 1.1, 3.4)
	cam.look_at(Vector3(-2.4, 0.95, 0))
	var seq := [["AIR", 6, "sq_takeoff"], ["AIR", 30, "sq_air"], ["MOVE", 6, "sq_land"], ["MOVE", 60, "sq_settle"]]
	for step in seq:
		for i in int(step[1]):
			cat0.animate(1.0 / 60.0, {"state": step[0], "move": 0.0})
			await get_tree().process_frame
		await _shot(str(step[2]))
	models.insert(0, cat0)
	cat0.set_armed(true)
	# Gear sheet: shield face-on, takoba and scabbard.
	var gear := CharacterArt.load_parts("res://game/art/characters/equipment.glb")
	var gear_root := Node3D.new()
	root.add_child(gear_root)
	gear_root.position = Vector3(0, 5, 20)
	var gm := CharacterArt.toon_material(Color(0.2, 0.12, 0.08), 0.006, "leather")
	var placed := {"Shield": Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-0.35, 0, 0)),
		"Sword": Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.08, -0.3, 0)),
		"Scabbard": Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.36, -0.3, 0))}
	for k in placed:
		var mi: MeshInstance3D = gear[k]
		mi.material_override = gm
		gear_root.add_child(mi)
		mi.transform = placed[k]
	cam.position = gear_root.position + Vector3(0.05, 0.1, 2.0)
	cam.look_at(gear_root.position + Vector3(0.05, 0.05, 0))
	for i in 5:
		await get_tree().process_frame
	await _shot("gear")
	gear_root.queue_free()
	# Emotes on the lineup.
	models[1].emote("thumbs_up", 5.0)
	models[2].emote("peace", 5.0)
	cam.position = Vector3(0, 1.5, 8.2)
	cam.look_at(Vector3(0, 1.05, 0))
	for i in 20:
		await get_tree().process_frame
	await _shot("lineup_emotes")
	# Hand pose close-ups: freeze the cat and show each pose.
	var cat := models[0]
	models.erase(cat)
	cat.set_armed(false)
	var hand := cat.hand_r
	hand.rotation = Vector3.ZERO
	var fwd := -cat.global_transform.basis.z
	cam.position = hand.global_position + fwd * 0.55 + Vector3(0, 0.3, 0) + cat.global_transform.basis.x * 0.25
	cam.look_at(hand.global_position)
	for pose in CreatureModel.POSES:
		cat.set_hand_pose("r", pose)
		hand.rotation = Vector3(PI / 2, 0, 0) if pose == "peace" else Vector3.ZERO
		for i in 3:
			await get_tree().process_frame
		await _shot("hand_" + pose)
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	var path := "user://shots/%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
