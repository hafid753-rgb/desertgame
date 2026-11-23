class_name Courtyard
extends StaticBody3D
## Greybox arena: an abandoned Saharan courtyard, 24 x 24 m, mud-brick walls
## (walkable on top) with triangular merlons, an open gate, a well and palms.
## Outside the gate: dunes, a ruined wall, a 10 m pillar and a 20 m mesa.
## Climb budgets on a full bar: Cat ~15.5 m, Fennec ~17 m, Lizard ~19 m, plus
## ~2.5 m of mantle reach, so only the Lizard tops the mesa in one go. Built from primitives so the artist's
## modular kit can replace it without touching gameplay.

const MUD := Color(0.7, 0.47, 0.3)
const MUD_DARK := Color(0.62, 0.41, 0.26)
const SAND := Color(0.74, 0.6, 0.41)
const STONE := Color(0.58, 0.5, 0.42)
const PALM := Color(0.36, 0.5, 0.22)
const WOOD := Color(0.42, 0.28, 0.16)
const HALF := 12.0
const WALL_H := 3.6
const WALL_T := 1.6
const BOUND := 58.0
const MESA_H := 20.0

var _materials: Dictionary = {}
var _sand_shader: Shader = preload("res://game/world/sand_ripple.gdshader")


func _ready() -> void:
	collision_layer = Combat.LAYER_WORLD
	collision_mask = 0
	# Floor (extends far so the camera never sees the void; fog hides the edge).
	_box(Vector3(BOUND * 2 + 10, 1, BOUND * 2 + 10), Vector3(0, -0.5, 0), SAND)
	# Packed-earth floor inside the walls (no dune ripples indoors).
	_box(Vector3(HALF * 2, 0.04, HALF * 2), Vector3(0, 0.0, 0), Color(0.7, 0.55, 0.38), false)
	# Walls, thick enough to walk along the top, with a gate gap on the south side.
	_box(Vector3(HALF * 2 + WALL_T, WALL_H, WALL_T), Vector3(0, WALL_H / 2, -HALF), MUD)
	_box(Vector3(WALL_T, WALL_H, HALF * 2 + WALL_T), Vector3(-HALF, WALL_H / 2, 0), MUD)
	_box(Vector3(WALL_T, WALL_H, HALF * 2 + WALL_T), Vector3(HALF, WALL_H / 2, 0), MUD)
	_box(Vector3(HALF - 1.6, WALL_H, WALL_T), Vector3(-(HALF + 1.6) / 2, WALL_H / 2, HALF), MUD)
	_box(Vector3(HALF - 1.6, WALL_H, WALL_T), Vector3((HALF + 1.6) / 2, WALL_H / 2, HALF), MUD)
	# Open gate: two pillars and a lintel (the door has rotted away).
	_box(Vector3(4.2, 1.0, WALL_T + 0.3), Vector3(0, WALL_H + 0.2, HALF), MUD_DARK)
	_box(Vector3(0.6, WALL_H + 0.7, WALL_T + 0.3), Vector3(-1.9, (WALL_H + 0.7) / 2, HALF), MUD_DARK)
	_box(Vector3(0.6, WALL_H + 0.7, WALL_T + 0.3), Vector3(1.9, (WALL_H + 0.7) / 2, HALF), MUD_DARK)
	_box(Vector3(1.2, 0.15, 2.4), Vector3(2.8, 0.4, HALF + 1.6), WOOD, false)  # fallen door plank
	# Corner towers.
	for x in [-HALF, HALF]:
		for z in [-HALF, HALF]:
			_box(Vector3(2.4, WALL_H + 1.6, 2.4), Vector3(x, (WALL_H + 1.6) / 2, z), MUD_DARK)
	_merlons()
	# Well in the centre-north, palms, a stone bench, broken pots.
	_cylinder(1.0, 0.8, Vector3(0, 0.4, -5), STONE)
	_cylinder(0.75, 0.82, Vector3(0, 0.42, -5), Color(0.1, 0.08, 0.07), false)
	_palm(Vector3(-7.5, 0, -7.5), 0.15)
	_palm(Vector3(8, 0, 6.5), -0.12)
	_box(Vector3(3, 0.5, 0.8), Vector3(-9.5, 0.25, 2), STONE)
	for p in [Vector3(9.5, 0, -9), Vector3(10.2, 0, -8.2), Vector3(-10, 0, 9.5)]:
		_cylinder(0.32, 0.7, p + Vector3(0, 0.35, 0), Color(0.68, 0.4, 0.25))
	_outside()
	_spawn_physics_props()


func _outside() -> void:
	# Climbing practice: ruined wall, pillar, mesa.
	_box(Vector3(6, 2.2, 0.8), Vector3(5, 1.1, 20), MUD_DARK)
	_box(Vector3(3, 10, 3), Vector3(12, 5, 25), STONE)
	_box(Vector3(9, MESA_H, 9), Vector3(-17, MESA_H / 2, 31), Color(0.66, 0.46, 0.32))
	_sign("Pillar 10 m", Vector3(12, 2.5, 22.3))
	_sign("Mesa 20 m — only the Lizard makes it in one climb", Vector3(-17, 2.5, 25.0))
	_palm(Vector3(-13, MESA_H, 31), 0.05)  # a lone palm on the mesa as a goal
	# Dunes.
	for d in [
		[Vector3(18, 0, 40), Vector3(9, 2.2, 6)], [Vector3(-2, 0, 44), Vector3(12, 3.0, 7)],
		[Vector3(-30, 0, 12), Vector3(7, 2.0, 10)], [Vector3(30, 0, -8), Vector3(8, 2.6, 12)],
		[Vector3(0, 0, -34), Vector3(14, 3.2, 8)], [Vector3(-28, 0, -26), Vector3(9, 2.4, 9)],
	]:
		_dune(d[0], d[1])
	# Invisible boundary.
	for side in [Vector3(BOUND, 0, 0), Vector3(-BOUND, 0, 0), Vector3(0, 0, BOUND), Vector3(0, 0, -BOUND)]:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1, 40, BOUND * 2) if side.x != 0.0 else Vector3(BOUND * 2, 40, 1)
		col.shape = shape
		col.position = side + Vector3(0, 20, 0)
		add_child(col)


func _dune(center: Vector3, size: Vector3) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.scale = size
	mi.position = center
	mi.material_override = _sand_mat(Color(0.8, 0.65, 0.44))
	add_child(mi)
	var pts := PackedVector3Array()
	for v in sm.get_mesh_arrays()[Mesh.ARRAY_VERTEX]:
		if v.y >= -0.05:
			pts.append(v * size)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = center
	add_child(col)


func _sign(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.outline_size = 10
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	add_child(l)


func _merlons() -> void:
	# One MultiMesh for every merlon: one draw call instead of ~90.
	var prism := PrismMesh.new()
	prism.size = Vector3(0.7, 0.7, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = prism
	var xforms: Array[Transform3D] = []
	var step := 1.2
	var count := int(HALF * 2 / step)
	for i in count + 1:
		var t := -HALF + i * step
		var o := WALL_T * 0.5 - 0.15  # on the outer edge, leaving a walkway
		xforms.append(Transform3D(Basis.from_scale(Vector3(1, 1, 0.3)), Vector3(t, WALL_H + 0.35, -HALF - o)))
		xforms.append(Transform3D(Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3(1, 1, 0.3)), Vector3(-HALF - o, WALL_H + 0.35, t)))
		xforms.append(Transform3D(Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3(1, 1, 0.3)), Vector3(HALF + o, WALL_H + 0.35, t)))
		if absf(t) > 2.4:
			xforms.append(Transform3D(Basis.from_scale(Vector3(1, 1, 0.3)), Vector3(t, WALL_H + 0.35, HALF + o)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat(MUD)
	add_child(mmi)


func _palm(base: Vector3, lean: float) -> void:
	var trunk := Node3D.new()
	trunk.position = base
	trunk.rotation = Vector3(lean, 0, lean * 0.5)
	add_child(trunk)
	var m := CylinderMesh.new()
	m.top_radius = 0.16
	m.bottom_radius = 0.26
	m.height = 5.0
	m.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat(WOOD)
	mi.position = Vector3(0, 2.5, 0)
	trunk.add_child(mi)
	var leaf := BoxMesh.new()
	leaf.size = Vector3(0.5, 0.06, 2.6)
	for i in 7:
		var l := MeshInstance3D.new()
		l.mesh = leaf
		l.material_override = _mat(PALM)
		var a := i * TAU / 7.0
		l.position = Vector3(sin(a) * 1.1, 5.0, cos(a) * 1.1)
		l.rotation = Vector3(0.45, a, 0)
		trunk.add_child(l)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.28
	shape.height = 5.0
	col.shape = shape
	col.position = base + Vector3(0, 2.5, 0)
	add_child(col)


func _box(size: Vector3, pos: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _sand_mat(color) if color == SAND else _mat(color)
	mi.position = pos
	add_child(mi)
	if collide:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = pos
		add_child(col)


func _cylinder(radius: float, h: float, pos: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = h
	mesh.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	add_child(mi)
	if collide:
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = h
		col.shape = shape
		col.position = pos
		add_child(col)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	_materials[key] = m
	return m

## One cached material per sand tint; shared by all dune meshes.
func _sand_mat(tint: Color) -> ShaderMaterial:
	var key := "sand_" + tint.to_html()
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = _sand_shader
	m.set_shader_parameter("sand_color", tint)
	_materials[key] = m
	return m

## Three interactable objects at the southern gate, away from combat tests.
## Wind pushes, fire ignites wooden crates, ice stops motion.
func _spawn_physics_props() -> void:
	for item in [
		{"at": Vector3(-4.0, 1.0, 17.0), "wood": true},
		{"at": Vector3(-5.8, 1.0, 17.6), "wood": true},
		{"at": Vector3(-7.6, 1.0, 18.2), "wood": false},
	]:
		var prop := ElementalProp.new()
		prop.wooden = item["wood"]
		prop.position = item["at"]
		add_child(prop)
