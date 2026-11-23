class_name CreatureModel
extends Node3D
## Placeholder Rayman-style creature: rounded body, floating hands and feet,
## no limbs to skin. Built from primitives so it costs ~18 draw calls and needs
## no imported art. Replace with the artist's rigged model later; keep the
## same animate() contract so player.gd does not change.

var hand_r: Node3D
var hand_l: Node3D
var foot_r: Node3D
var foot_l: Node3D
var body: MeshInstance3D
var head: Node3D
var tail: Node3D
var sword: MeshInstance3D
var element_glow: MeshInstance3D

var _mats: Array[StandardMaterial3D] = []
var _glow_mat: StandardMaterial3D
var _walk_phase := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE


func build(data: Dictionary) -> void:
	var fur: Color = data["fur"]
	var accent: Color = data["accent"]
	body = _mesh(_sphere(0.34, 0.78), Vector3(0, 0.62, 0), fur, self)
	_mesh(_sphere(0.2, 0.4), Vector3(0, 0.6, -0.2), accent, self)  # belly
	head = Node3D.new()
	head.position = Vector3(0, 1.12, 0)
	add_child(head)
	_mesh(_sphere(0.33, 0.6), Vector3.ZERO, fur, head)
	_mesh(_sphere(0.15, 0.2), Vector3(0, -0.08, -0.26), accent, head)  # muzzle
	for side in [-1.0, 1.0]:
		var eye := _mesh(_sphere(0.055, 0.11), Vector3(0.12 * side, 0.05, -0.28), Color(0.08, 0.05, 0.1), head)
		eye.scale = Vector3(1, 1.4, 1)
		match str(data["ears"]):
			"pointed":
				var ear := _mesh(_cone(0.1, 0.24), Vector3(0.17 * side, 0.3, 0), fur, head)
				ear.rotation = Vector3(0, 0, -0.35 * side)
			"large":
				var ear2 := _mesh(_cone(0.16, 0.42), Vector3(0.2 * side, 0.36, 0.02), fur, head)
				ear2.rotation = Vector3(0, 0, -0.5 * side)
				ear2.scale = Vector3(1, 1, 0.4)
	tail = Node3D.new()
	tail.position = Vector3(0, 0.45, 0.3)
	add_child(tail)
	var tail_mesh := _mesh(_capsule(0.07, 0.6), Vector3(0, 0.25, 0.08), fur, tail)
	tail_mesh.rotation = Vector3(0.6, 0, 0)

	hand_r = _pivot(Vector3(0.45, 0.62, -0.08))
	hand_l = _pivot(Vector3(-0.45, 0.62, -0.08))
	foot_r = _pivot(Vector3(0.17, 0.09, 0))
	foot_l = _pivot(Vector3(-0.17, 0.09, 0))
	for h in [hand_r, hand_l]:
		_mesh(_sphere(0.1, 0.2), Vector3.ZERO, accent, h)
	for f in [foot_r, foot_l]:
		var fm := _mesh(_sphere(0.11, 0.16), Vector3(0, 0, -0.04), accent, f)
		fm.scale = Vector3(1, 0.8, 1.35)
	sword = _mesh(_box(Vector3(0.06, 0.05, 0.85)), Vector3(0, 0, -0.5), Color(0.85, 0.87, 0.9), hand_r)
	_mesh(_box(Vector3(0.22, 0.05, 0.06)), Vector3(0, 0, -0.08), Color(0.55, 0.38, 0.2), hand_r)  # guard
	var shield := _mesh(_cylinder(0.26, 0.05), Vector3(-0.05, 0, -0.05), Color(0.55, 0.32, 0.16), hand_l)
	shield.rotation = Vector3(0, 0, PI / 2)
	element_glow = _mesh(_sphere(0.16, 0.32), Vector3(0, 0, 0), Color(1, 1, 1, 0.0), hand_r)
	_glow_mat = element_glow.material_override as StandardMaterial3D
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	element_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func flash(color: Color, amount: float = 1.0) -> void:
	_flash = amount
	_flash_color = color


## info keys: move (0..1), state (String), t (0..1 progress in state),
## combo (int), charge (0..3 float), element_color (Color), guarding (bool)
func animate(delta: float, info: Dictionary) -> void:
	var move: float = info.get("move", 0.0)
	var state: String = info.get("state", "MOVE")
	var t: float = info.get("t", 0.0)
	var charge: float = info.get("charge", 0.0)
	var ecol: Color = info.get("element_color", Color.WHITE)

	_walk_phase += delta * (4.0 + 10.0 * move)
	var bob := sin(_walk_phase * 2.0) * 0.04 * move
	body.position.y = 0.62 + bob
	head.position.y = 1.12 + bob * 1.3 + sin(_walk_phase) * 0.01
	tail.rotation.y = sin(_walk_phase * 0.7) * 0.35

	var step := sin(_walk_phase) * 0.22 * move
	var fr := Vector3(0.17, 0.09 + maxf(0.0, sin(_walk_phase)) * 0.12 * move, -step)
	var fl := Vector3(-0.17, 0.09 + maxf(0.0, -sin(_walk_phase)) * 0.12 * move, step)
	var hr := Vector3(0.45, 0.62 + bob, -0.08 + step * 0.6)
	var hl := Vector3(-0.45, 0.62 + bob, -0.08 - step * 0.6)
	var hr_rot := Vector3.ZERO
	var hl_rot := Vector3.ZERO

	match state:
		"ATTACK", "HEAVY":
			var combo: int = info.get("combo", 0)
			var side := 1.0 if combo % 2 == 0 else -1.0
			var swing := clampf(t * 1.8, 0.0, 1.0)
			hr = Vector3(lerpf(0.55 * side, -0.35 * side, swing), 0.8, -0.35)
			hr_rot = Vector3(-0.3, lerpf(1.2 * side, -1.4 * side, swing), 0)
			if state == "HEAVY":
				hr = Vector3(0.3, lerpf(1.4, 0.4, swing), -0.4)
				hr_rot = Vector3(lerpf(1.2, -1.3, swing), 0, 0)
		"HEAVY_CHARGE":
			hr = Vector3(0.35, 1.4, 0.05)
			hr_rot = Vector3(1.3, 0, 0)
		"GUARD", "DEFENSE":
			hl = Vector3(-0.15, 0.75, -0.42)
			hl_rot = Vector3(0, -0.4, 0)
		"DODGE", "MOBILITY":
			body.position.y = 0.45
			head.position.y = 0.9
		"CAST":
			hr = Vector3(0.2, 0.85, -0.55)
			hl = Vector3(-0.2, 0.85, -0.55)
		"HITSTUN":
			head.position.z = 0.08
	if charge > 0.0:
		hr = hr.lerp(Vector3(0.3, 0.95, -0.25), 0.6)

	var k := 1.0 - exp(-20.0 * delta)
	hand_r.position = hand_r.position.lerp(hr, k)
	hand_l.position = hand_l.position.lerp(hl, k)
	foot_r.position = foot_r.position.lerp(fr, k)
	foot_l.position = foot_l.position.lerp(fl, k)
	hand_r.rotation = hand_r.rotation.lerp(hr_rot, k)
	hand_l.rotation = hand_l.rotation.lerp(hl_rot, k)

	var glow_a := clampf(charge / 3.0, 0.0, 1.0) * 0.8
	_glow_mat.albedo_color = Color(ecol.r, ecol.g, ecol.b, glow_a)
	element_glow.scale = Vector3.ONE * (0.6 + charge * 0.5)

	_flash = maxf(0.0, _flash - delta * 6.0)
	for m in _mats:
		m.emission_enabled = _flash > 0.01
		m.emission = _flash_color
		m.emission_energy_multiplier = _flash * 1.5


func _pivot(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n


func _mesh(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	_mats.append(m)
	parent.add_child(mi)
	return mi


func _sphere(r: float, h: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = 16
	s.rings = 8
	return s


func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


func _cylinder(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	return c


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 4
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
