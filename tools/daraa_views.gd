extends Node
## Daraa validation renders (docs/garment/DARAA.md):
##   xvfb-run godot --path . res://tools/daraa_views.tscn -- mode=views
## modes: views (rest + 3 wearing configs + glide spread x front/side/back),
##        silhouette (same grid, black on white), species (cat/fennec/rabbit)
## Output: user://shots/daraa_<mode>.png

var mode := "views"
var model: CreatureModel
var cam := Camera3D.new()
var state := "MOVE"
var floor_mi := MeshInstance3D.new()
var env := Environment.new()
const CELL := Vector2i(300, 380)


func _process(delta: float) -> void:
	if model:
		model.animate(delta, {"move": 0.0, "state": state, "vel": Vector3.ZERO})


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="):
			mode = a.substr(5)
	var root := Node3D.new()
	add_child(root)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(35), 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.92, 0.82)
	sun.shadow_enabled = true
	root.add_child(sun)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.78, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.68, 0.58)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.82, 0.6, 0.46)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	add_child(cam)
	cam.fov = 30
	cam.current = true
	if mode == "silhouette":
		env.background_color = Color(1, 0, 1)
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		floor_mi.visible = false
	if mode == "probe":
		await _probe(root)
	elif mode == "species":
		await _species(root)
	else:
		await _grid(root)
	get_tree().quit()


func _spawn(root: Node3D, id: String, x: float) -> CreatureModel:
	var m := CreatureModel.new()
	root.add_child(m)
	m.build(Species.get_data(id))
	m.position = Vector3(x, 0, 0)
	m.rotation.y = PI
	return m


func _grid(root: Node3D) -> void:
	model = _spawn(root, "cat", 0.0)
	var configs := [["Draped", 0, "MOVE"], ["Gather L", 1, "MOVE"], ["Gather R", 2, "MOVE"], ["Gather both", 3, "MOVE"], ["Glide spread", 0, "GLIDE"]]
	var views := [["front", 0.0], ["side", PI / 2], ["back", PI]]
	var sheet := Image.create(CELL.x * configs.size(), CELL.y * views.size(), false, Image.FORMAT_RGB8)
	for ci in configs.size():
		var c: Array = configs[ci]
		model.garment.wear_override = c[1]
		state = c[2]
		for i in 50:
			await get_tree().process_frame
		for vi in views.size():
			var a: float = views[vi][1]
			cam.position = Vector3(sin(a) * 6.2, 1.0, cos(a) * 6.2)
			cam.look_at(Vector3(0, 0.72, 0))
			for i in 4:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var w := img.get_width()
			var h := img.get_height()
			var crop := img.get_region(Rect2i(w / 2 - h * CELL.x / CELL.y / 2, 0, h * CELL.x / CELL.y, h))
			crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
			if mode == "silhouette":
				_to_silhouette(crop)
			sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, CELL), Vector2i(ci * CELL.x, vi * CELL.y))
	_save(sheet, "daraa_" + mode)


func _to_silhouette(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var bg := c.r > 0.8 and c.b > 0.8 and c.g < 0.3
			img.set_pixel(x, y, Color.WHITE if bg else Color.BLACK)


func _species(root: Node3D) -> void:
	var ms: Array[CreatureModel] = []
	var x := -1.5
	for id in ["cat", "fennec", "rabbit"]:
		ms.append(_spawn(root, id, x))
		x += 1.5
	model = null
	for i in 60:
		for m in ms:
			m.animate(1.0 / 60.0, {"move": 0.0, "state": "MOVE", "vel": Vector3.ZERO})
		await get_tree().process_frame
	cam.position = Vector3(0, 1.1, 8.6)
	cam.look_at(Vector3(0, 0.72, 0))
	for i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	_save(img, "daraa_species")
	cam.fov = 18
	cam.position = Vector3(-1.5, 1.05, 4.2)
	cam.look_at(Vector3(-1.5, 0.82, 0))
	for i in 4:
		await get_tree().process_frame
	_save(get_viewport().get_texture().get_image(), "daraa_closeup")


func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s.png" % name)
	print("saved ", name)


func _probe(root: Node3D) -> void:
	model = _spawn(root, "cat", 0.0)
	for st in [["MOVE", 0.0], ["MOVE", 1.0], ["CLIMB", 0.0], ["ATTACK", 0.0]]:
		state = st[0]
		for i in 60:
			await get_tree().process_frame
		var inv := model.global_transform.affine_inverse()
		var sk := model.skel
		var ua := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("upperarm.l"))).origin
		print(st, " R ", inv * model.hand_r.global_position, " L ", inv * model.hand_l.global_position, " upperarm.l ", inv * ua)
