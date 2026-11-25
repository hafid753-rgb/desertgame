class_name Vegetation
extends RefCounted
## Builders for pixel-art vegetation (Phase 3): individual grass blades,
## date palms with individual frond leaflets, acacias with individual
## leaflets, shrubs, flowers and rocks. Every visible blade/leaf is its own
## subdivided, deformable 2D surface, GPU-instanced (MultiMesh) and driven by
## the shared Wind field in the shader. Trunks/branches are 3D tubes with
## pixel-aligned UVs (32 px per metre).

const PPM := 32.0
const VEG_SHADER := preload("res://game/shaders/veg_card.gdshader")
const UV_SHADER := preload("res://game/shaders/pixel_uv.gdshader")
const LEAF_SHADER := preload("res://game/shaders/leaf_fall.gdshader")

static var _card_cache: Dictionary = {}


## Subdivided card: width `w`, height `hgt`, `cols` x `rows` quads, root at
## the origin (bottom centre), UV.y = 1 at the root.
static func card(w: float, hgt: float, cols: int, rows: int) -> ArrayMesh:
	var key := "%s_%s_%d_%d" % [w, hgt, cols, rows]
	if _card_cache.has(key):
		return _card_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows:
		for c in cols:
			var pts: Array[Vector2] = [Vector2(c, r), Vector2(c + 1, r), Vector2(c + 1, r + 1), Vector2(c, r + 1)]
			var idx := [0, 1, 2, 0, 2, 3]
			for i in idx:
				var g: Vector2 = pts[i]
				var u := g.x / cols
				var v := 1.0 - g.y / rows
				st.set_normal(Vector3(0, 0, 1))
				st.set_uv(Vector2(u, v))
				st.add_vertex(Vector3((u - 0.5) * w, g.y / rows * hgt, 0.0))
	var m := st.commit()
	_card_cache[key] = m
	return m


static func card_material(tex_path: String, cols: float, rows: float, kind: int, card_h: float,
		bend: float, response: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = VEG_SHADER
	m.set_shader_parameter("tex", load(tex_path))
	m.set_shader_parameter("atlas_cols", cols)
	m.set_shader_parameter("atlas_rows", rows)
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("card_height", card_h)
	m.set_shader_parameter("bend", bend)
	m.set_shader_parameter("response", response)
	return m


## A MultiMesh of cards. items: Array of [Transform3D, cell (0..cells-1), stiffness, along].
static func instances(parent: Node3D, mesh: Mesh, mat: Material, items: Array, cells: int,
		rng: RandomNumberGenerator, vis_end: float = 0.0, shadows: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		mm.set_instance_transform(i, it[0])
		mm.set_instance_custom_data(i, Color(float(it[1]) / float(cells), rng.randf(), float(it[2]), float(it[3])))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 4.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	parent.add_child(mi)
	return mi


## Tapered tube along `spine` (local points) with pixel-aligned UVs:
## u = texels around / tex, v = texels along / tex.
static func tube(spine: PackedVector3Array, r0: float, r1: float, sides: int, tex_px: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := spine.size()
	var along := 0.0
	var rings: Array = []
	var up := Vector3.UP
	for i in n:
		var tdir := (spine[mini(i + 1, n - 1)] - spine[maxi(i - 1, 0)]).normalized()
		var side := tdir.cross(up if absf(tdir.dot(up)) < 0.9 else Vector3.RIGHT).normalized()
		var nrm := side.cross(tdir).normalized()
		var r := lerpf(r0, r1, float(i) / float(n - 1))
		if i > 0:
			along += spine[i].distance_to(spine[i - 1])
		var ring := []
		for k in sides + 1:
			var a := TAU * float(k) / float(sides)
			var dir := side * cos(a) + nrm * sin(a)
			var circ := TAU * r0
			ring.append([spine[i] + dir * r, dir, Vector2(snappedf(float(k) / float(sides) * circ * PPM, 1.0) / tex_px, snappedf(along * PPM, 1.0) / tex_px)])
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			var a: Array = rings[i][k]
			var b: Array = rings[i][k + 1]
			var c: Array = rings[i + 1][k + 1]
			var d: Array = rings[i + 1][k]
			for v in [a, c, b, a, d, c]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.set_color(Color(1, 1, 1))
				st.add_vertex(v[0])
	return st.commit()


static func uv_material(tex_path: String, tint: Color = Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = UV_SHADER
	m.set_shader_parameter("tex", load(tex_path))
	m.set_shader_parameter("tint", tint)
	return m


static func set_sway(mat: ShaderMaterial, root: Vector3, height: float, amount: float) -> void:
	mat.set_shader_parameter("sway_root", root)
	mat.set_shader_parameter("sway_height", height)
	mat.set_shader_parameter("sway_amount", amount)


# --- Plants -----------------------------------------------------------------

## Date palm: curved trunk, crown of arching fronds, each frond carrying
## individual leaflets on both sides. Returns the trunk height.
static func date_palm(parent: Node3D, base: Vector3, height: float, lean: Vector3, rng: RandomNumberGenerator,
		collide: bool = true) -> Node3D:
	var root := Node3D.new()
	root.position = base
	parent.add_child(root)
	var spine := PackedVector3Array()
	for i in 13:
		var t := float(i) / 12.0
		spine.append(Vector3(lean.x * t * t, t * height, lean.z * t * t))
	var trunk_mat := uv_material("res://game/art/pixel/veg_bark_palm.png")
	var gpos := base
	set_sway(trunk_mat, gpos, height, 0.35)
	var trunk := MeshInstance3D.new()
	trunk.mesh = tube(spine, 0.22, 0.16, 10, 32.0)
	trunk.material_override = trunk_mat
	root.add_child(trunk)
	var crown := spine[spine.size() - 1]
	# crown knob
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.45
	sm.radial_segments = 10
	sm.rings = 5
	knob.mesh = sm
	knob.material_override = trunk_mat
	knob.position = crown
	root.add_child(knob)
	# fronds
	var items: Array = []
	var fronds := 13
	for f in fronds:
		var yaw := TAU * float(f) / fronds + rng.randf_range(-0.15, 0.15)
		var rise := rng.randf_range(0.25, 0.75)       # young fronds stand up
		var length := rng.randf_range(2.4, 3.2)
		var dry := f % 5 == 0 and rise < 0.4
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var prev := crown
		var steps := 24
		for s in range(1, steps + 1):
			var t := float(s) / steps
			# arching spine: up then drooping
			var p := crown + dir * t * length + Vector3(0, (rise * 1.6) * t - 1.9 * t * t, 0)
			var tang := (p - prev).normalized()
			prev = p
			if s < 3:
				continue
			var side := tang.cross(Vector3.UP).normalized()
			var leaflet_len := lerpf(0.85, 0.3, t) * (0.9 + 0.2 * sin(float(s) * 1.7))
			for sd in [-1.0, 1.0]:
				# leaflets point outward and slightly forward/down from the rachis
				var out: Vector3 = (side * sd * 0.85 + tang * 0.5 + Vector3(0, -0.55 * t + 0.15, 0)).normalized()
				var nrm := out.cross(tang).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				var basis := Basis(nrm.cross(out).normalized(), out, nrm)
				basis = basis.scaled(Vector3(0.55, leaflet_len, 1.0))
				var cell := 2 if dry else (rng.randi() % 2)
				items.append([Transform3D(basis, p), cell, rng.randf_range(0.8, 1.2), t])
	var lmesh := card(6.0 / PPM, 1.0, 1, 4)
	var lmat := card_material("res://game/art/pixel/veg_palm_leaflet.png", 3.0, 1.0, 2, 1.0, 0.8, 0.7)
	set_sway(lmat, gpos, height, 0.35)
	var mi := instances(root, lmesh, lmat, items, 3, rng, 120.0, true)
	mi.extra_cull_margin = 1.0
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = Combat.LAYER_WORLD
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.26
		shape.height = height
		col.shape = shape
		col.position = Vector3(lean.x * 0.3, height * 0.5, lean.z * 0.3)
		body.add_child(col)
		root.add_child(body)
	return root


## Acacia: forked trunk, spreading branches, flat umbrella canopy of
## individual leaflets in layered clumps.
static func acacia(parent: Node3D, base: Vector3, scale: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = base
	parent.add_child(root)
	var bark := uv_material("res://game/art/pixel/veg_bark_acacia.png")
	var h := 2.2 * scale
	set_sway(bark, base, h * 2.0, 0.08)
	var trunk_spine := PackedVector3Array([Vector3.ZERO, Vector3(0.05, h * 0.5, 0.0), Vector3(0.1, h, 0.05)])
	var trunk := MeshInstance3D.new()
	trunk.mesh = tube(trunk_spine, 0.2 * scale, 0.13 * scale, 9, 32.0)
	trunk.material_override = bark
	root.add_child(trunk)
	var tips: Array[Vector3] = []
	var branches := 5
	for b in branches:
		var yaw := TAU * float(b) / branches + rng.randf_range(-0.3, 0.3)
		var reach := rng.randf_range(1.6, 2.4) * scale
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var sp := PackedVector3Array()
		for i in 7:
			var t := float(i) / 6.0
			sp.append(Vector3(0.1, h, 0.05) + dir * reach * t + Vector3(0, (1.3 * t - 0.25 * t * t) * scale, 0))
		var bm := MeshInstance3D.new()
		bm.mesh = tube(sp, 0.12 * scale, 0.04 * scale, 6, 32.0)
		bm.material_override = bark
		root.add_child(bm)
		tips.append(sp[sp.size() - 1])
		tips.append(sp[4])
	# canopy: an umbrella of feathery sprays. Each spray is a twig line with
	# paired 6x6 pinnae every 3 texels (acacias are bipinnate), in two tiers:
	# a sunlit flat top and a darker underside layer for depth.
	var items: Array = []
	var shed: Array[Vector3] = []
	var canopy_y := h + 1.15 * scale
	var step := 3.0 / PPM
	for tip in tips:
		var centre := Vector3(tip.x, canopy_y + (tip.y - canopy_y) * 0.25, tip.z)
		var rad := rng.randf_range(1.0, 1.4) * scale
		for sp_i in rng.randi_range(30, 40):
			var under := rng.randf() < 0.35
			var a := rng.randf() * TAU
			var r0 := sqrt(rng.randf()) * rad * 0.55
			var start := centre + Vector3(cos(a) * r0, (rng.randf_range(-0.04, 0.12) - (0.22 if under else 0.0)) * scale, sin(a) * r0)
			var ha := a + rng.randf_range(-0.7, 0.7)
			var dir := Vector3(cos(ha), rng.randf_range(-0.1, 0.04), sin(ha)).normalized()
			var length := rng.randf_range(0.3, 0.65) * scale
			var n := maxi(2, int(length / step))
			for k in n:
				var t := float(k) / float(n)
				var pos := start + dir * length * t + Vector3(0, -t * t * 0.06 * scale, 0)
				for side in [-1.0, 1.0]:
					var yaw: float = atan2(dir.x, dir.z) + float(side) * rng.randf_range(1.0, 1.4)
					var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-1.35, -0.85))
					var cell: int
					var roll := rng.randf()
					if roll < 0.05:
						cell = 5 + rng.randi() % 2          # dry
					elif under:
						cell = 3 + rng.randi() % 2          # shaded underside
					else:
						cell = [0, 1, 2, 7][rng.randi() % 4]
					items.append([Transform3D(basis, pos), cell, rng.randf_range(0.8, 1.3), 1.0])
				if rng.randf() < 0.012:
					shed.append(pos)
	var lmesh := card(6.0 / PPM, 6.0 / PPM, 1, 2)
	var lmat := card_material("res://game/art/pixel/veg_leaf_fine.png", 8.0, 1.0, 1, 6.0 / PPM, 0.6, 1.4)
	set_sway(lmat, base, h * 2.0, 0.08)
	instances(root, lmesh, lmat, items, 8, rng, 140.0, true)
	root.set_meta("leaf_count", items.size())
	# shed leaves: dry and green sprays drifting down on the wind
	falling_leaves(root, shed.slice(0, 48), "res://game/art/pixel/veg_leaf_fine.png", 8.0, [5, 6, 5, 6, 0, 7],
		6.0 / PPM, 6.0 / PPM, -base.y, rng, 0.45, 15.0)
	var body := StaticBody3D.new()
	body.collision_layer = Combat.LAYER_WORLD
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.24 * scale
	shape.height = h
	col.shape = shape
	col.position = Vector3(0.05, h * 0.5, 0)
	body.add_child(col)
	root.add_child(body)
	return root


## Leaves that detach, tumble downwind, settle and dissolve (stateless GPU
## loop, see leaf_fall.gdshader). `spawns` are local points in `parent`.
static func falling_leaves(parent: Node3D, spawns: Array, tex_path: String, cols: float, cells: Array,
		w: float, hgt: float, ground_y: float, rng: RandomNumberGenerator, fall_speed: float = 0.5,
		cycle: float = 16.0) -> MultiMeshInstance3D:
	if spawns.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = card(w, hgt, 1, 1)
	mm.instance_count = spawns.size()
	for i in spawns.size():
		mm.set_instance_transform(i, Transform3D(Basis(), spawns[i]))
		mm.set_instance_custom_data(i, Color(float(cells[rng.randi() % cells.size()]) / cols, rng.randf(),
			rng.randf(), rng.randf()))
	var m := ShaderMaterial.new()
	m.shader = LEAF_SHADER
	m.set_shader_parameter("tex", load(tex_path))
	m.set_shader_parameter("atlas_cols", cols)
	m.set_shader_parameter("ground_y", ground_y)
	m.set_shader_parameter("fall_speed", fall_speed)
	m.set_shader_parameter("cycle", cycle)
	m.set_shader_parameter("pivot", hgt * 0.5)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 20, 40))
	mi.visibility_range_end = 60.0
	parent.add_child(mi)
	return mi


## Low thorny shrub: a dome of twig blades and leaflets.
static func shrub_items(center: Vector3, radius: float, rng: RandomNumberGenerator, blades: Array, leaves: Array) -> void:
	for i in rng.randi_range(40, 70):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius * 0.5
		var pos := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var lean := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.7, 0.7))
		blades.append([Transform3D(lean.scaled(Vector3.ONE * rng.randf_range(0.35, 0.6)), pos), 5, rng.randf_range(1.6, 2.4), 0.0])
	for i in rng.randi_range(80, 130):
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		var pos := center + dir * radius * rng.randf_range(0.5, 0.95) * Vector3(1.0, 0.65, 1.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-1.4, -0.3))
		leaves.append([Transform3D(basis, pos), rng.randi() % 6, rng.randf_range(0.9, 1.4), 1.0])
