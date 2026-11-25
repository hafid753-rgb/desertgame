class_name HawliScarf
extends Node3D
## The hawli as a long trailing cloth ribbon (Journey-style scarf, in the
## Mauritanian indigo with gold embroidery). Verlet chain anchored at the
## back of the neck, pushed by the shared Wind field and by the wearer's
## motion, kept out of the robe and above the ground; drawn each frame as a
## flat strip with a pixel-art pattern (hawli_scarf.gdshader).

@export var segments := 12
@export var seg_len := 0.0975     # 1.17 m (owner: half the earlier 2.3 m)
@export var width := 0.2
@export var color := Color(0.2, 0.26, 0.55)
var anchor: Node3D          # follows the neck
var body_root: Node3D       # character root (ground height, robe axis)
## head collision (chibi head is a big sphere-ish box: keep the ribbon off it)
var head_node: Node3D
var head_radius := 0.25
## the daraa as an elliptic cylinder in the character's frame (half-width,
## half-depth, its centre offset forward, and the shoulder height)
var daraa_rx := 0.47
var daraa_rz := 0.3
var daraa_cz := -0.03
var shoulder_y := 1.1

var _p := PackedVector3Array()
var _o := PackedVector3Array()
var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _acc := 0.0
var _t := 0.0


var trim := Color(1.0, 0.82, 0.36)
var _vertex_colors := false


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


## Use the wearer's own cloth material (same shader, lighting and colour
## handling as the neck wrap); the pattern is carried in vertex colours.
func set_cloth(mat: Material, cloth: Color, trim_color: Color) -> void:
	color = cloth
	trim = trim_color
	_mi.material_override = mat
	_vertex_colors = true
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
		# stay off the head, outside the daraa and above the sand
		var basis := body_root.global_transform.basis.orthonormalized() if body_root else Basis()
		var hc := head_node.global_position if head_node else Vector3(0, -99, 0)
		for i in range(1, segments + 1):
			var p := _p[i]
			var dh := p - hc
			if dh.length() < head_radius:
				p = hc + (dh.normalized() if dh.length() > 1e-4 else back) * head_radius
			var rel := basis.inverse() * (p - axis)
			if rel.y < shoulder_y + 0.03:
				# narrower at the neck, full width from the shoulders down
				var top := smoothstep(shoulder_y - 0.12, shoulder_y + 0.03, rel.y)
				var rx := lerpf(daraa_rx, 0.22, top) + 0.02
				var rz := lerpf(daraa_rz, 0.19, top) + 0.02
				var ex := rel.x / rx
				var ez := (rel.z - daraa_cz) / rz
				var e := sqrt(ex * ex + ez * ez)
				if e < 1.0:
					if e < 1e-3:
						ez = 1.0
						e = 1.0
					rel.x = ex / e * rx
					rel.z = daraa_cz + ez / e * rz
					p = axis + basis * rel
			p.y = maxf(p.y, ground)
			_p[i] = p


func _draw() -> void:
	_mesh.clear_surfaces()
	var total := seg_len * segments
	var prev_side := anchor.global_transform.basis.x.normalized()
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var nrms: Array[Vector3] = []
	for i in segments + 1:
		var dir := (_p[mini(i + 1, segments)] - _p[maxi(i - 1, 0)]).normalized()
		# flat ribbon carried along by parallel transport (gentle twist, no flips)
		var side := (prev_side - dir * prev_side.dot(dir)).normalized()
		if side.length() < 0.1:
			side = prev_side
		side = side.rotated(dir, sin(_t * 4.0 - float(i) * 0.45) * 0.35 * float(i) / segments)
		prev_side = side
		var k := float(i) / segments
		var wdt := width * (1.0 - smoothstep(0.82, 1.0, k) * 0.55)
		lefts.append(_p[i] - side * wdt * 0.5)
		rights.append(_p[i] + side * wdt * 0.5)
		nrms.append(side.cross(dir).normalized())
	if not _vertex_colors:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in segments + 1:
			var u := float(i) / segments * total
			_mesh.surface_set_normal(nrms[i])
			_mesh.surface_set_uv(Vector2(u, 0.0))
			_mesh.surface_add_vertex(lefts[i])
			_mesh.surface_set_normal(nrms[i])
			_mesh.surface_set_uv(Vector2(u, 1.0))
			_mesh.surface_add_vertex(rights[i])
		_mesh.surface_end()
		return
	# cloth material: one plain band, the wrap's own colour
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		_quad(lefts[i], rights[i], lefts[i + 1], rights[i + 1], nrms[i], nrms[i + 1], color)
	_mesh.surface_end()


func _quad(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, n0: Vector3, n1: Vector3, c: Color) -> void:
	for v in [[a0, n0], [b0, n1], [a1, n0], [a1, n0], [b0, n1], [b1, n1]]:
		_mesh.surface_set_color(c)
		_mesh.surface_set_normal(v[1])
		_mesh.surface_add_vertex(v[0])
