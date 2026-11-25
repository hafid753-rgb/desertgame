class_name Courtyard
extends StaticBody3D
## Greybox arena: an abandoned Saharan courtyard, 24 x 24 m, mud-brick walls
## (walkable on top) with triangular merlons, an open gate, a well and palms.
## Outside the gate: dunes, a ruined wall, a 10 m pillar and a 20 m mesa.
## Climb budgets on a full bar: Cat ~15.5 m, Fennec ~17 m, Rabbit ~19 m, plus
## ~2.5 m of mantle reach, so only the Rabbit tops the mesa in one go. Built from primitives so the artist's
## modular kit can replace it without touching gameplay.

const MUD := Color(0.7, 0.47, 0.3)
const MUD_DARK := Color(0.62, 0.41, 0.26)
const SAND := Color(0.84, 0.64, 0.42)
const STONE := Color(0.58, 0.5, 0.42)
const PALM := Color(0.36, 0.5, 0.22)
const WOOD := Color(0.42, 0.28, 0.16)
const HALF := 12.0
const WALL_H := 3.6
const WALL_T := 1.6
const BOUND := 58.0
const MESA_H := 20.0

var _materials: Dictionary = {}
var _batch := MeshBatcher.new()
const DUNE := Color(0.88, 0.67, 0.44)
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
	_batch.build(func(c: Color) -> Material: return _sand_mat(c) if (c == SAND or c == DUNE) else _mat(c))
	_spawn_physics_props()


func _outside() -> void:
	# Climbing practice: ruined wall, pillar, mesa.
	_box(Vector3(6, 2.2, 0.8), Vector3(5, 1.1, 20), MUD_DARK)
	_box(Vector3(3, 10, 3), Vector3(12, 5, 25), STONE)
	_box(Vector3(9, MESA_H, 9), Vector3(-17, MESA_H / 2, 31), Color(0.66, 0.46, 0.32))
	_sign("Pillar 10 m", Vector3(12, 2.5, 22.3))
	_sign("Mesa 20 m — only the Rabbit makes it in one climb", Vector3(-17, 2.5, 25.0))
	_palm(Vector3(-13, MESA_H, 31), 0.05)  # a lone palm on the mesa as a goal
	# Dunes.
	for d in [
		
		[Vector3(-30, 0, 12), Vector3(7, 2.0, 10)], [Vector3(34, 0, -40), Vector3(8, 2.6, 12)],
		[Vector3(0, 0, -34), Vector3(14, 3.2, 8)], [Vector3(-28, 0, -26), Vector3(9, 2.4, 9)],
		# long low swells in the open desert (sand spec: flowing macro dunes)
		[Vector3(10, 0, -50), Vector3(16, 2.2, 9)],
		[Vector3(-50, 0, -40), Vector3(12, 1.8, 7)], [Vector3(48, 0, 44), Vector3(12, 1.8, 7)],
	]:
		_dune(d[0], d[1])
	# The surfing dune (shield sand-surfing, owner request): climb the back
	# from the west, surf east down the slip face, launch off the lip.
	var slide := SlideDune.new()
	slide.material = _sand_mat(SAND)
	slide.position = Vector3(-14.0, 0.0, 46.0)
	add_child(slide)
	# Invisible boundary.
	for side in [Vector3(BOUND, 0, 0), Vector3(-BOUND, 0, 0), Vector3(0, 0, BOUND), Vector3(0, 0, -BOUND)]:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1, 40, BOUND * 2) if side.x != 0.0 else Vector3(BOUND * 2, 40, 1)
		col.shape = shape
		col.position = side + Vector3(0, 20, 0)
		add_child(col)


## Low, long dune: a smooth bump (height (1 - r^2)^2, so it meets the floor
## tangentially) stretched along the prevailing wind, with a slightly steeper
## lee side. Uses the shared sand material; convex collision as before.
func _dune(center: Vector3, size: Vector3) -> void:
	var length := maxf(size.x, size.z) * 1.7
	var width := minf(size.x, size.z) * 1.15
	var height := size.y * 0.6
	var yaw := atan2(0.38, 0.92)            # along the wind (sand_ripple wind_dir)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 40
	var nv := 20
	var pts := PackedVector3Array()
	for i in nu + 1:
		for j in nv + 1:
			var u := float(i) / nu * 2.0 - 1.0
			var v := float(j) / nv * 2.0 - 1.0
			var uu := u * (1.15 if u > 0.0 else 0.9)   # lee side steeper
			var r2 := clampf(uu * uu + v * v, 0.0, 1.0)
			var hgt := height * (1.0 - r2) * (1.0 - r2)
			var p := Vector3(u * length, hgt - 0.02, v * width).rotated(Vector3.UP, yaw)
			st.add_vertex(p)
			if hgt > 0.05:
				pts.append(p)
	for i in nu:
		for j in nv:
			var a0 := i * (nv + 1) + j
			var b0 := a0 + 1
			var c0 := a0 + nv + 1
			var d0 := c0 + 1
			for k in [a0, c0, b0, b0, c0, d0]:   # front face up (see DuneHorizon)
				st.add_index(k)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	mi.material_override = _sand_mat(SAND)
	add_child(mi)
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


## Date palm (pixel-art trunk, individual frond leaflets, wind sway).
func _palm(base: Vector3, lean: float) -> void:
	if _palm_rng == null:
		_palm_rng = RandomNumberGenerator.new()
		_palm_rng.seed = 21
	Vegetation.date_palm(self, base, 5.0, Vector3(lean * 6.0, 0, lean * 3.0), _palm_rng)


func _box(size: Vector3, pos: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch.add(mesh, Transform3D(Basis(), pos), color, self)
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
	_batch.add(mesh, Transform3D(Basis(), pos), color, self)
	if collide:
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = h
		col.shape = shape
		col.position = pos
		add_child(col)


## Pixel-art surface families (Phase 1): architecture and props use the
## shared texel-grid shader; anything not mapped keeps a plain material.
var _palm_rng: RandomNumberGenerator
const PIXEL_SHADER := preload("res://game/shaders/pixel_world.gdshader")
const PIXEL_FAMILIES := {
	"mud": ["res://game/art/pixel/sandstone_128.png", 128.0, Color(1.0, 0.97, 0.94)],
	"mud_dark": ["res://game/art/pixel/sandstone_128.png", 128.0, Color(0.88, 0.82, 0.78)],
	"stone": ["res://game/art/pixel/sandstone_128.png", 128.0, Color(0.82, 0.8, 0.82)],
	"mesa": ["res://game/art/pixel/sandstone_128.png", 128.0, Color(0.95, 0.78, 0.66)],
	"floor": ["res://game/art/pixel/earth_128.png", 128.0, Color(1.0, 0.95, 0.9)],
	"wood": ["res://game/art/pixel/wood_64.png", 64.0, Color(1.0, 1.0, 1.0)],
}


func _family(color: Color) -> String:
	if color == MUD:
		return "mud"
	if color == MUD_DARK:
		return "mud_dark"
	if color == STONE:
		return "stone"
	if color == WOOD:
		return "wood"
	if color.is_equal_approx(Color(0.66, 0.46, 0.32)):
		return "mesa"
	if color.is_equal_approx(Color(0.7, 0.55, 0.38)):
		return "floor"
	return ""


func _mat(color: Color) -> Material:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var fam := _family(color)
	if fam != "":
		var f: Array = PIXEL_FAMILIES[fam]
		var pm := ShaderMaterial.new()
		pm.shader = PIXEL_SHADER
		pm.set_shader_parameter("tex", load(f[0]))
		pm.set_shader_parameter("tex_size", f[1])
		pm.set_shader_parameter("tint", f[2])
		_materials[key] = pm
		return pm
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
	# Journey-inspired sand (owner sand spec + references): pink-peach
	# albedo, soft mauve shadow tone, broad sheen, crest rim, stable glitter
	var sand := Color("DC967A")
	m.set_shader_parameter("sand_color", sand * (tint / SAND) if tint != SAND else sand)
	m.set_shader_parameter("shadow_color", Color("C58474"))
	m.set_shader_parameter("sand_tex", load("res://game/art/pixel/sand_128.png"))
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
