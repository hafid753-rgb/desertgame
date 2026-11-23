class_name Courtyard
extends StaticBody3D
## Greybox arena: an abandoned Saharan courtyard, 24 x 24 m, mud-brick walls
## with triangular merlons, a gate, a well and two palms. Built from boxes so
## it can be replaced by the artist's modular kit without touching gameplay.

const MUD := Color(0.7, 0.47, 0.3)
const MUD_DARK := Color(0.62, 0.41, 0.26)
const SAND := Color(0.74, 0.6, 0.41)
const STONE := Color(0.58, 0.5, 0.42)
const PALM := Color(0.36, 0.5, 0.22)
const WOOD := Color(0.42, 0.28, 0.16)
const HALF := 12.0
const WALL_H := 3.6

var _materials: Dictionary = {}


func _ready() -> void:
	collision_layer = Combat.LAYER_WORLD
	collision_mask = 0
	# Floor (extends beyond the walls so the camera never sees the void).
	_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0), SAND)
	# Walls with a gate gap on the south side.
	_box(Vector3(HALF * 2 + 1, WALL_H, 1), Vector3(0, WALL_H / 2, -HALF), MUD)
	_box(Vector3(1, WALL_H, HALF * 2 + 1), Vector3(-HALF, WALL_H / 2, 0), MUD)
	_box(Vector3(1, WALL_H, HALF * 2 + 1), Vector3(HALF, WALL_H / 2, 0), MUD)
	_box(Vector3(HALF - 1.6, WALL_H, 1), Vector3(-(HALF + 1.6) / 2, WALL_H / 2, HALF), MUD)
	_box(Vector3(HALF - 1.6, WALL_H, 1), Vector3((HALF + 1.6) / 2, WALL_H / 2, HALF), MUD)
	# Gate frame and a closed wooden door (decorative studs).
	_box(Vector3(4.2, 1.0, 1.3), Vector3(0, WALL_H + 0.2, HALF), MUD_DARK)
	_box(Vector3(0.6, WALL_H + 0.7, 1.3), Vector3(-1.9, (WALL_H + 0.7) / 2, HALF), MUD_DARK)
	_box(Vector3(0.6, WALL_H + 0.7, 1.3), Vector3(1.9, (WALL_H + 0.7) / 2, HALF), MUD_DARK)
	_box(Vector3(3.2, WALL_H - 0.4, 0.2), Vector3(0, (WALL_H - 0.4) / 2, HALF + 0.3), WOOD)
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
		xforms.append(Transform3D(Basis(), Vector3(t, WALL_H + 0.35, -HALF)))
		xforms.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-HALF, WALL_H + 0.35, t)))
		xforms.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(HALF, WALL_H + 0.35, t)))
		if absf(t) > 2.4:
			xforms.append(Transform3D(Basis(), Vector3(t, WALL_H + 0.35, HALF)))
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
	mi.material_override = _mat(color)
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
