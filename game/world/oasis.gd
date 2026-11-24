class_name Oasis
extends Node3D
## A small desert oasis outside the courtyard (Phase 3 lab): an irregular
## pond with pixel-art water, damp earth shore, dense green grass at the
## water's edge thinning into dry tussocks, date palms, an acacia, thorny
## shrubs, flowers and rocks. Every blade and leaf is an individual
## deformable pixel-art card moved by the shared Wind field.

const PPM := 32.0
@export var pond_radius := 4.6
@export var area_radius := 15.0
@export var seed_value := 7

var rng := RandomNumberGenerator.new()
var shore: PackedVector2Array = PackedVector2Array()
var grass_count := 0
var leaf_count := 0


func _ready() -> void:
	rng.seed = seed_value
	_build_shore_outline()
	_build_pond()
	_build_shore_ring()
	_build_grass_and_flowers()
	Vegetation.date_palm(self, Vector3(-2.2, 0, -4.9), 6.2, Vector3(-0.9, 0, -0.5), rng)
	Vegetation.date_palm(self, Vector3(4.3, 0, -2.8), 5.1, Vector3(1.1, 0, -0.2), rng)
	Vegetation.date_palm(self, Vector3(1.6, 0, 5.2), 4.4, Vector3(0.3, 0, 1.0), rng)
	Vegetation.date_palm(self, Vector3(-5.6, 0, 2.4), 3.4, Vector3(-0.5, 0, 0.6), rng)
	Vegetation.acacia(self, Vector3(-10.5, 0, -6.5), 1.15, rng)
	Vegetation.acacia(self, Vector3(9.5, 0, 8.0), 0.9, rng)
	_build_shrubs()
	_build_rocks()


## Radius of the pond at angle a (irregular, lobed).
func _r_at(a: float) -> float:
	return pond_radius * (1.0 + 0.16 * sin(a * 2.0 + 0.7) + 0.09 * sin(a * 5.0 + 2.1) + 0.05 * sin(a * 9.0))


func _build_shore_outline() -> void:
	for i in 96:
		var a := TAU * float(i) / 96.0
		shore.append(Vector2(cos(a), sin(a)) * _r_at(a))


## Distance (m) from a point to the shoreline; negative inside the water.
func shore_distance(p: Vector2) -> float:
	var a := atan2(p.y, p.x)
	return p.length() - _r_at(a)


func _build_pond() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	for i in 96:
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		for r in rings:
			var t0 := float(r) / rings
			var t1 := float(r + 1) / rings
			var p := [
				Vector2(cos(a0), sin(a0)) * _r_at(a0) * (1.0 - t0), Vector2(cos(a1), sin(a1)) * _r_at(a1) * (1.0 - t0),
				Vector2(cos(a1), sin(a1)) * _r_at(a1) * (1.0 - t1), Vector2(cos(a0), sin(a0)) * _r_at(a0) * (1.0 - t1)]
			var d := [t0, t0, t1, t1]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_color(Color(pow(d[k], 0.8), 0, 0))
				st.add_vertex(Vector3(p[k].x, 0.05, p[k].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/pixel_water.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Damp earth band around the water (pixel earth texture, darker when wet).
func _build_shore_ring() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 96:
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		var w0 := 1.0 + 0.45 * sin(a0 * 3.0 + 1.0)
		var w1 := 1.0 + 0.45 * sin(a1 * 3.0 + 1.0)
		var q := [
			Vector2(cos(a0), sin(a0)) * (_r_at(a0) - 0.2), Vector2(cos(a1), sin(a1)) * (_r_at(a1) - 0.2),
			Vector2(cos(a1), sin(a1)) * (_r_at(a1) + w1), Vector2(cos(a0), sin(a0)) * (_r_at(a0) + w0)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q[k].x, 0.025, q[k].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/pixel_world.gdshader")
	m.set_shader_parameter("tex", load("res://game/art/pixel/sand_128.png"))
	m.set_shader_parameter("tex_size", 128.0)
	m.set_shader_parameter("tint", Color(0.62, 0.56, 0.44))  # damp sand
	mi.material_override = m
	add_child(mi)


## Grass density falls off with distance from the water; clumps from noise.
func _build_grass_and_flowers() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.22
	var chunk := 6.0
	var chunks: Dictionary = {}
	var flowers: Array = []
	var step := 0.16
	var x := -area_radius
	while x <= area_radius:
		var z := -area_radius
		while z <= area_radius:
			var p := Vector2(x + rng.randf_range(-step, step) * 0.5, z + rng.randf_range(-step, step) * 0.5)
			var sd := shore_distance(p)
			z += step
			if sd < 0.05 or p.length() > area_radius:
				continue
			var near := 1.0 - smoothstep(0.0, 3.2, sd)                     # lush band
			var clump := smoothstep(0.15, 0.55, noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5)
			var far := 1.0 - smoothstep(area_radius * 0.6, area_radius, p.length())
			var density := maxf(near * 0.95, clump * far * 0.55)
			if rng.randf() > density:
				continue
			var green := rng.randf() < near * 0.9 + 0.05
			var col := rng.randi() % 6
			var cell := col + (6 if green else 0)
			var h := rng.randf_range(0.5, 0.8) * (1.15 if green else 0.9)
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.18, 0.18))
			var key := Vector2i(floori(p.x / chunk), floori(p.y / chunk))
			if not chunks.has(key):
				chunks[key] = []
			(chunks[key] as Array).append([Transform3D(basis.scaled(Vector3(h, h, h)), Vector3(p.x, 0.0, p.y)),
				cell, rng.randf_range(0.7, 1.4), 0.0])
			if sd > 0.6 and sd < 5.0 and rng.randf() < 0.012:
				flowers.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 0.6), Vector3(p.x, 0, p.y)),
					rng.randi() % 2, 1.0, 0.0])
		x += step
	var mesh := Vegetation.card(0.5, 1.0, 2, 8)
	var mat := Vegetation.card_material("res://game/art/pixel/veg_grass.png", 6.0, 2.0, 0, 1.0, 0.9, 1.0)
	for key in chunks:
		var items: Array = chunks[key]
		grass_count += items.size()
		Vegetation.instances(self, mesh, mat, items, 12, rng, 55.0, false)
	var fmesh := Vegetation.card(0.5, 0.5, 1, 4)
	var fmat := Vegetation.card_material("res://game/art/pixel/veg_flower.png", 2.0, 1.0, 0, 0.5, 0.7, 1.1)
	Vegetation.instances(self, fmesh, fmat, flowers, 2, rng, 45.0, false)


func _build_shrubs() -> void:
	var blades: Array = []
	var leaves: Array = []
	for c in [Vector3(-8.5, 0, 4.0), Vector3(7.5, 0, -6.5), Vector3(-3.5, 0, 9.5), Vector3(11.5, 0, 1.5), Vector3(-12, 0, -1)]:
		Vegetation.shrub_items(c, rng.randf_range(0.7, 1.1), rng, blades, leaves)
	var bmat := Vegetation.card_material("res://game/art/pixel/veg_grass.png", 6.0, 2.0, 0, 1.0, 0.4, 0.8)
	bmat.set_shader_parameter("tint", Color(0.62, 0.52, 0.42))
	Vegetation.instances(self, Vegetation.card(0.5, 1.0, 2, 8), bmat, blades, 12, rng, 70.0, false)
	var lmat := Vegetation.card_material("res://game/art/pixel/veg_leaf.png", 6.0, 1.0, 1, 0.25, 0.5, 1.4)
	lmat.set_shader_parameter("tint", Color(0.85, 0.85, 0.8))
	Vegetation.instances(self, Vegetation.card(0.25, 0.25, 1, 2), lmat, leaves, 6, rng, 70.0, true)
	leaf_count += leaves.size()


func _build_rocks() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/pixel_world.gdshader")
	m.set_shader_parameter("tex", load("res://game/art/pixel/sandstone_128.png"))
	m.set_shader_parameter("tex_size", 128.0)
	m.set_shader_parameter("tint", Color(0.82, 0.76, 0.72))
	for i in 9:
		var a := rng.randf() * TAU
		var r := _r_at(a) + rng.randf_range(0.1, 1.6)
		if i > 5:
			r = rng.randf_range(6.0, 12.0)
		var s := rng.randf_range(0.35, 0.8) * (1.6 if i > 5 else 1.0)
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.3
		sm.radial_segments = 7
		sm.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = m
		mi.position = Vector3(cos(a) * r, s * 0.15, sin(a) * r)
		mi.scale = Vector3(s * rng.randf_range(0.9, 1.4), s * 0.6, s)
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)
