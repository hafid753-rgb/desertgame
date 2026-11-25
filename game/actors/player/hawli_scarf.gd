class_name HawliScarf
extends Node3D
## The hawli as a long trailing cloth ribbon (Journey-style scarf, in the
## Mauritanian indigo with gold embroidery). Verlet chain anchored at the
## back of the neck, pushed by the shared Wind field and by the wearer's
## motion, kept out of the robe and above the ground; drawn each frame as a
## flat strip with a pixel-art pattern (hawli_scarf.gdshader).

@export var segments := 18
@export var seg_len := 0.13
@export var width := 0.2
@export var color := Color(0.2, 0.26, 0.55)
var anchor: Node3D          # follows the neck
var body_root: Node3D       # character root (ground height, robe axis)

var _p := PackedVector3Array()
var _o := PackedVector3Array()
var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _acc := 0.0
var _t := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/hawli_scarf.gdshader")
	m.set_shader_parameter("base", color)
	m.set_shader_parameter("length", seg_len * segments)
	_mi.material_override = m
	_mi.extra_cull_margin = 4.0
	add_child(_mi)


func _reset(at: Vector3, back: Vector3) -> void:
	_p.resize(segments + 1)
	_o.resize(segments + 1)
	for i in segments + 1:
		_p[i] = at + back * seg_len * i - Vector3(0, 0.02 * i, 0)
		_o[i] = _p[i]


func _process(delta: float) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var root := anchor.global_position
	var back := anchor.global_transform.basis.z.normalized()
	if _p.size() != segments + 1 or _p[0].distance_to(root) > 3.0:
		_reset(root, back)
	_t += delta
	_acc += minf(delta, 0.1)
	var h := 1.0 / 90.0
	while _acc >= h:
		_acc -= h
		_step(h, root, back)
	_draw()


func _step(h: float, root: Vector3, back: Vector3) -> void:
	var ground := (body_root.global_position.y if body_root else root.y - 1.1) + 0.04
	var axis := body_root.global_position if body_root else root - Vector3(0, 1.0, 0)
	var side := anchor.global_transform.basis.x.normalized()
	for i in range(1, segments + 1):
		var p := _p[i]
		var vel := (p - _o[i]) * 0.985
		_o[i] = p
		var k := float(i) / segments
		# light cloth: weak gravity, buoyant in the wind, flutters at the tail
		var f := Vector3(0, -1.5, 0)
		var w: Vector3 = Wind.wind_at(p)
		f += w * (3.0 + 3.5 * k) + Vector3(0, 1.1 * k, 0)
		f += side * sin(_t * 7.0 - float(i) * 0.65) * 1.6 * k
		f += Vector3(0, cos(_t * 5.3 - float(i) * 0.5), 0) * 0.9 * k
		_p[i] = p + vel + f * h * h
	_p[0] = root
	for it in 4:
		for i in segments:
			var a := _p[i]
			var b := _p[i + 1]
			var d := b - a
			var len := d.length()
			if len < 1e-5:
				continue
			var corr := d * (1.0 - seg_len / len)
			if i == 0:
				_p[i + 1] = b - corr
			else:
				_p[i] = a + corr * 0.5
				_p[i + 1] = b - corr * 0.5
		# stay outside the robe cone and above the sand
		for i in range(1, segments + 1):
			var p := _p[i]
			var rel := Vector2(p.x - axis.x, p.z - axis.z)
			var hgt := p.y - axis.y
			if hgt < root.y - axis.y + 0.1:
				var r := lerpf(0.42, 0.2, clampf(hgt / maxf(root.y - axis.y, 0.1), 0.0, 1.0))
				if rel.length() < r:
					rel = (rel.normalized() if rel.length() > 1e-4 else Vector2(back.x, back.z)) * r
					p.x = axis.x + rel.x
					p.z = axis.z + rel.y
			p.y = maxf(p.y, ground)
			_p[i] = p


func _draw() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var total := seg_len * segments
	var prev_side := anchor.global_transform.basis.x.normalized()
	for i in segments + 1:
		var dir := (_p[mini(i + 1, segments)] - _p[maxi(i - 1, 0)]).normalized()
		# flat ribbon: width roughly horizontal, carried along (parallel
		# transport) so the band twists gently instead of flipping
		var side := (prev_side - dir * prev_side.dot(dir)).normalized()
		if side.length() < 0.1:
			side = prev_side
		side = side.rotated(dir, sin(_t * 4.0 - float(i) * 0.45) * 0.35 * float(i) / segments)
		prev_side = side
		var k := float(i) / segments
		var wdt := width * (1.0 - smoothstep(0.82, 1.0, k) * 0.55)
		var nrm := side.cross(dir).normalized()
		var u := k * total
		_mesh.surface_set_normal(nrm)
		_mesh.surface_set_uv(Vector2(u, 0.0))
		_mesh.surface_add_vertex(_p[i] - side * wdt * 0.5)
		_mesh.surface_set_normal(nrm)
		_mesh.surface_set_uv(Vector2(u, 1.0))
		_mesh.surface_add_vertex(_p[i] + side * wdt * 0.5)
	_mesh.surface_end()
