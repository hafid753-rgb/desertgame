class_name Jinn
extends CharacterBody3D
## Ordinary shadow jinn. Three readable, telegraphed attacks:
##   swipe  (orange eyes, 0.6 s): close arc in front
##   lunge  (red eyes, 0.9 s): dash at the player
##   burst  (violet eyes, 1.2 s): ring of smoke around itself
## Facing locks at 70% of the telegraph so the player can read and react.

signal defeated(jinn: Jinn)
signal health_changed(hp: float, max_hp: float)

enum S { IDLE, CHASE, CIRCLE, TELEGRAPH, ATTACK, RECOVER, STAGGER, DEAD }

const ATTACKS := {
	"swipe": {"telegraph": 0.6, "active": 0.15, "recovery": 0.6, "damage": 14.0, "range": 2.4, "arc": 120.0,
		"color": Color(1.0, 0.6, 0.1), "stun": 0.35, "knockback": 3.0},
	"lunge": {"telegraph": 0.9, "active": 0.35, "recovery": 0.9, "damage": 20.0, "range": 1.4, "arc": 360.0,
		"color": Color(1.0, 0.12, 0.1), "stun": 0.5, "knockback": 6.0, "dash_speed": 14.0},
	"burst": {"telegraph": 1.2, "active": 0.2, "recovery": 1.0, "damage": 24.0, "range": 3.4, "arc": 360.0,
		"color": Color(0.75, 0.35, 1.0), "stun": 0.6, "knockback": 7.0},
}
const CHASE_SPEED := 3.2
const CIRCLE_SPEED := 2.0
const STAGGER_PARRIED := 1.4

@export var ai_enabled: bool = true
@export var max_hp: float = 160.0

var hp: float = 160.0
var radius: float = 0.6
var state: int = S.IDLE
var state_time: float = 0.0
var current: String = ""
var attack_hit_done: bool = false
var last_result: String = ""
var target: Player
var circle_dir: float = 1.0
var circle_time: float = 1.0
var stagger_time: float = 0.0
var knock_velocity: Vector3 = Vector3.ZERO
var burn_time: float = 0.0
var burn_tick: float = 0.0
var chill_time: float = 0.0
var chill_multiplier: float = 1.0
var fx_parent: Node
var damage_taken_total: float = 0.0

var _smoke_mat: ShaderMaterial
var _veil_mat: ShaderMaterial
var _veil: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _visual: Node3D
var _flash: float = 0.0
var _rng := RandomNumberGenerator.new()
var _arm_r: Node3D
var _arm_l: Node3D
var _mask: MeshInstance3D
var _mask_mat: ShaderMaterial
var _recent: Array[String] = []


func _ready() -> void:
	add_to_group("jinn")
	hp = max_hp
	collision_layer = Combat.LAYER_JINN
	collision_mask = Combat.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	_build_visual()
	if fx_parent == null:
		fx_parent = get_parent()
	_rng.seed = hash(get_instance_id())


func is_dead() -> bool:
	return state == S.DEAD


func state_name() -> String:
	return S.keys()[state]


## Start an attack immediately (used by tests and scripted encounters).
func force_attack(name: String) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Player
	_face(Combat.flat(target.global_position - global_position), 1.0)
	_begin_telegraph(name)


## Water slows movement without changing telegraph durations. Server-friendly
## numeric status effect; no physical particle simulation required.
func apply_chill(seconds: float, speed_multiplier: float = 0.6) -> void:
	chill_time = maxf(chill_time, seconds)
	chill_multiplier = minf(chill_multiplier, speed_multiplier)


func take_damage(info: Dictionary) -> void:
	if state == S.DEAD:
		return
	var amount: float = info.get("amount", 0.0)
	var element: int = info.get("element", Combat.Element.NONE)
	var stagger: int = info.get("stagger", 0)
	if element == Combat.Element.FIRE:
		amount *= 1.3
		burn_time = 3.0
	elif element == Combat.Element.WATER:
		# Water extinguishes burn and reduces movement temporarily.
		burn_time = 0.0
		apply_chill(float(info.get("chill_seconds", 2.0)), 0.6)
	if state == S.STAGGER:
		amount *= 1.25
	hp = maxf(0.0, hp - amount)
	damage_taken_total += amount
	health_changed.emit(hp, max_hp)
	_flash = 1.0
	var from: Vector3 = info.get("from", global_position)
	var push := Combat.flat(global_position - from).normalized()
	var knock: float = info.get("knockback", 1.5)
	knock_velocity = push * knock
	var col := Color(1, 1, 1)
	if element == Combat.Element.FIRE:
		col = Color(1, 0.55, 0.2)
	elif element == Combat.Element.WIND:
		col = Color(0.6, 0.95, 1.0)
	elif element == Combat.Element.WATER:
		col = Combat.ELEMENT_COLORS[Combat.Element.WATER]
	if info.get("counter", false):
		col = Color(1, 0.95, 0.4)
	Fx.popup(fx_parent, global_position + Vector3(0, 2.3, 0), str(roundi(amount)), col, 72 if amount >= 25 else 56)
	if hp <= 0.0:
		_die()
		return
	# Light hits do not interrupt attacks; stagger >= 2, or wind stagger >= 1
	# during a telegraph, does.
	var interrupts := stagger >= 2 or (stagger >= 1 and (state == S.TELEGRAPH and element == Combat.Element.WIND or state == S.RECOVER or state == S.CIRCLE))
	if interrupts:
		_stagger(0.6 + 0.15 * stagger)


func _physics_process(delta: float) -> void:
	state_time += delta
	if chill_time > 0.0:
		chill_time = maxf(0.0, chill_time - delta)
		if chill_time <= 0.0:
			chill_multiplier = 1.0
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Player
	_tick_burn(delta)
	var h := Vector3.ZERO
	match state:
		S.IDLE:
			if ai_enabled and target and not target.is_dead():
				_enter(S.CHASE)
		S.CHASE:
			h = _tick_chase(delta)
		S.CIRCLE:
			h = _tick_circle(delta)
		S.TELEGRAPH:
			h = _tick_telegraph(delta)
		S.ATTACK:
			h = _tick_attack(delta)
		S.RECOVER:
			var rec: float = ATTACKS[current]["recovery"]
			if state_time >= rec:
				_enter(S.CIRCLE if ai_enabled else S.IDLE)
		S.STAGGER:
			if state_time >= stagger_time:
				_enter(S.CIRCLE if ai_enabled else S.IDLE)
		S.DEAD:
			_smoke_mat.set_shader_parameter("dissolve", clampf(state_time / 1.2, 0.0, 1.0))
			if _veil_mat:
				_veil_mat.set_shader_parameter("dissolve", clampf(state_time / 0.85, 0.0, 1.0))
			if _mask:
				_mask.scale = Vector3.ONE * maxf(0.01, 1.0 - state_time / 1.0)
			if state_time > 1.3:
				defeated.emit(self)
				queue_free()
			return
	knock_velocity = knock_velocity.lerp(Vector3.ZERO, 1.0 - exp(-7.0 * delta))
	velocity = h + knock_velocity
	velocity.y = 0.0
	move_and_slide()
	_separate_from_player()
	_animate(delta)


func _enter(s: int) -> void:
	state = s
	state_time = 0.0
	_ring.visible = s == S.TELEGRAPH
	if s == S.CIRCLE:
		circle_time = _rng.randf_range(0.8, 1.8)
		circle_dir = -1.0 if _rng.randf() < 0.5 else 1.0
	if s != S.TELEGRAPH and s != S.ATTACK:
		_eye_mat.albedo_color = Color(0.95, 0.9, 0.7)


func _tick_chase(delta: float) -> Vector3:
	if target == null or target.is_dead():
		_enter(S.IDLE)
		return Vector3.ZERO
	var to := Combat.flat(target.global_position - global_position)
	_face(to, 1.0 - exp(-6.0 * delta))
	if to.length() < 3.2:
		_enter(S.CIRCLE)
		return Vector3.ZERO
	return to.normalized() * CHASE_SPEED * chill_multiplier


func _tick_circle(delta: float) -> Vector3:
	if target == null or target.is_dead():
		_enter(S.IDLE)
		return Vector3.ZERO
	var to := Combat.flat(target.global_position - global_position)
	var dist := to.length()
	_face(to, 1.0 - exp(-8.0 * delta))
	var tangent := Vector3(-to.z, 0, to.x).normalized() * circle_dir
	var radial := 0.0
	if dist > 3.4:
		radial = 1.0
	elif dist < 2.6:
		radial = -0.7
	var h := (tangent + to.normalized() * radial).normalized() * CIRCLE_SPEED * chill_multiplier
	if dist > 6.0:
		_enter(S.CHASE)
	elif state_time >= circle_time and ai_enabled:
		_begin_telegraph(_choose_attack(dist))
	return h


## Range decides the options; never the same attack three times in a row,
## so the player has to read the telegraph instead of memorising a rhythm.
func _choose_attack(dist: float) -> String:
	var pick: String
	if dist > 3.6:
		pick = "lunge"
	elif dist < 2.0:
		pick = "burst" if _rng.randf() < 0.55 else "swipe"
	else:
		pick = "swipe" if _rng.randf() < 0.6 else "burst"
	if _recent.size() >= 2 and _recent[-1] == pick and _recent[-2] == pick:
		pick = "burst" if pick == "swipe" else "swipe"
	_recent.append(pick)
	if _recent.size() > 3:
		_recent.pop_front()
	return pick


func _begin_telegraph(name: String) -> void:
	current = name
	attack_hit_done = false
	last_result = ""
	_enter(S.TELEGRAPH)
	var col: Color = ATTACKS[name]["color"]
	_eye_mat.albedo_color = col
	_smoke_mat.set_shader_parameter("warning_color", col)
	Juice.play("tel_" + name, global_position)
	_ring_mat.albedo_color = Color(col, 0.35)


func _tick_telegraph(delta: float) -> Vector3:
	var atk: Dictionary = ATTACKS[current]
	var tel: float = atk["telegraph"]
	var p := clampf(state_time / tel, 0.0, 1.0)
	if p < 0.7 and target:
		_face(Combat.flat(target.global_position - global_position), 1.0 - exp(-10.0 * delta))
	var r: float = atk["range"]
	if current == "lunge":
		r = 1.2
	_ring.scale = Vector3(r * p, 1, r * p)
	_ring_mat.albedo_color.a = 0.2 + 0.5 * p
	var h := Vector3.ZERO
	if current == "lunge":
		h = -_forward() * 0.8 * (1.0 - p)  # pull back
	if state_time >= tel:
		_enter(S.ATTACK)
		_eye_mat.albedo_color = Color(1, 1, 1)
	return h


func _tick_attack(_delta: float) -> Vector3:
	var atk: Dictionary = ATTACKS[current]
	var active: float = atk["active"]
	var h := Vector3.ZERO
	match current:
		"swipe":
			if not attack_hit_done:
				attack_hit_done = true
				Fx.burst(fx_parent, global_position + _forward() * 1.3 + Vector3(0, 1.0, 0), Color(0.2, 0.1, 0.3, 0.7), 1.4, 0.2, Vector3(1.5, 0.4, 1))
				_try_hit(atk)
		"lunge":
			var dash: float = atk["dash_speed"] * chill_multiplier
			h = _forward() * dash
			if not attack_hit_done:
				_try_hit(atk)
		"burst":
			if not attack_hit_done:
				attack_hit_done = true
				Fx.ring(fx_parent, global_position, Color(0.5, 0.25, 0.8, 0.7), float(atk["range"]))
				_try_hit(atk)
	if state_time >= active:
		_enter(S.RECOVER)
	return h


func _try_hit(atk: Dictionary) -> void:
	if target == null or target.is_dead():
		return
	if not Combat.in_arc(global_position, _forward(), target.global_position, float(atk["range"]) + 0.4, float(atk["arc"])):
		return
	attack_hit_done = true
	last_result = target.receive_attack(atk, self)
	match last_result:
		"parried":
			_stagger(STAGGER_PARRIED)
			knock_velocity = -_forward() * 4.0
		"deflected":
			_stagger(0.6)
			knock_velocity = -_forward() * 5.0
		"perfect_dodge":
			pass


func _stagger(duration: float) -> void:
	stagger_time = duration
	_enter(S.STAGGER)
	_eye_mat.albedo_color = Color(0.35, 0.3, 0.4)


func _die() -> void:
	_enter(S.DEAD)
	Juice.play("banish", global_position)
	Juice.shake(0.3)
	collision_layer = 0
	_eye_mat.albedo_color = Color(0.2, 0.2, 0.2)
	Fx.burst(fx_parent, global_position + Vector3(0, 1.0, 0), Color(0.3, 0.15, 0.45, 0.8), 2.2, 0.8)


func _tick_burn(delta: float) -> void:
	if burn_time <= 0.0 or state == S.DEAD:
		_smoke_mat.set_shader_parameter("burn", 0.0)
		return
	burn_time -= delta
	burn_tick += delta
	_smoke_mat.set_shader_parameter("burn", 0.8)
	if burn_tick >= 1.0:
		burn_tick = 0.0
		hp = maxf(0.0, hp - 3.0)
		damage_taken_total += 3.0
		health_changed.emit(hp, max_hp)
		Fx.popup(fx_parent, global_position + Vector3(0, 2.1, 0), "3", Color(1, 0.5, 0.2), 44)
		if hp <= 0.0:
			_die()


func _separate_from_player() -> void:
	if target == null:
		return
	var to := Combat.flat(global_position - target.global_position)
	var min_d := radius + 0.45
	if to.length() < min_d and to.length() > 0.001:
		global_position += to.normalized() * (min_d - to.length())


func _forward() -> Vector3:
	return Combat.flat(-global_transform.basis.z).normalized()


func _face(dir: Vector3, weight: float) -> void:
	if dir.length() < 0.05:
		return
	rotation.y = lerp_angle(rotation.y, Combat.yaw_for(dir), weight)


func _animate(delta: float) -> void:
	var tel_p := 0.0
	if state == S.TELEGRAPH:
		tel_p = clampf(state_time / float(ATTACKS[current]["telegraph"]), 0.0, 1.0)
	var hover := 0.35 + sin(Time.get_ticks_msec() * 0.003 + get_instance_id()) * 0.08
	_visual.position.y = hover
	var swell := 1.0 + tel_p * 0.18
	if state == S.TELEGRAPH and current == "burst":
		swell = 1.0 + tel_p * 0.4
	if state == S.STAGGER:
		_visual.rotation.z = sin(state_time * 20.0) * 0.12
	else:
		_visual.rotation.z = 0.0
	_visual.scale = _visual.scale.lerp(Vector3(swell, 1.0 / sqrt(swell), swell), 1.0 - exp(-12.0 * delta))
	# Arms read the attack: swipe winds one claw back, burst spreads both,
	# lunge sweeps both behind. Idle: slow drifting sway.
	var t_ms := Time.get_ticks_msec() * 0.002
	var ar := Vector3(sin(t_ms) * 0.12, 0, 0.1 + sin(t_ms * 1.3) * 0.08)
	var al := Vector3(sin(t_ms + 1.0) * 0.12, 0, -0.1 - sin(t_ms * 1.1) * 0.08)
	if state == S.TELEGRAPH:
		match current:
			"swipe":
				ar = Vector3(-1.2 * tel_p, -0.8 * tel_p, 0.9 * tel_p)
			"burst":
				ar = Vector3(0, 0, 1.3 * tel_p)
				al = Vector3(0, 0, -1.3 * tel_p)
			"lunge":
				ar = Vector3(0.9 * tel_p, 0, 0.3)
				al = Vector3(0.9 * tel_p, 0, -0.3)
	elif state == S.ATTACK and current == "swipe":
		ar = Vector3(0.9, 1.0, 0.2)
	elif state == S.STAGGER:
		ar = Vector3(0.6, 0, 0.9)
		al = Vector3(0.6, 0, -0.9)
	var k := 1.0 - exp(-14.0 * delta)
	if _arm_r:
		_arm_r.rotation = _arm_r.rotation.lerp(ar, k)
	if _arm_l:
		_arm_l.rotation = _arm_l.rotation.lerp(al, k)

	_flash = maxf(0.0, _flash - delta * 6.0)
	_smoke_mat.set_shader_parameter("flash", _flash * 0.8)
	_smoke_mat.set_shader_parameter("warning", tel_p * 0.40)
	if _veil_mat:
		_veil_mat.set_shader_parameter("agitation", tel_p * 1.5 if state == S.TELEGRAPH else 0.0)
	if _mask_mat:
		_mask_mat.set_shader_parameter("flash", _flash * 0.6)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = preload("res://game/actors/jinn/jinn_smoke.gdshader")
	var parts := CharacterArt.load_parts("res://game/art/characters/jinn.glb")
	for n in ["Body", "ArmR", "ArmL"]:
		if parts.has(n):
			var mi: MeshInstance3D = parts[n]
			mi.material_override = _smoke_mat
			_visual.add_child(mi)
	_arm_r = parts.get("ArmR")
	_arm_l = parts.get("ArmL")
	# Eight tapering smoke ribbons add Ico-like, dissolving silhouettes without
	# reusing any Sony assets. One mesh / one transparent draw surface.
	_veil = _build_spirit_veil()
	_visual.add_child(_veil)
	if parts.has("Mask"):
		_mask = parts["Mask"]
		_mask_mat = CharacterArt.toon_material(Color(0.05, 0.03, 0.06), 0.008)
		_mask.material_override = _mask_mat
		_visual.add_child(_mask)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(0.95, 0.9, 0.7)
	var eye := SphereMesh.new()
	eye.radius = 0.05
	eye.height = 0.07
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = eye
		e.material_override = _eye_mat
		e.position = Vector3(0.11 * side, 1.41, -0.535)
		e.scale = Vector3(1.2, 0.8, 0.5)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(e)
	# Telegraph ring on the ground.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	ring.rings = 32
	ring.ring_segments = 4
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring = MeshInstance3D.new()
	_ring.mesh = ring
	_ring.material_override = _ring_mat
	_ring.position = Vector3(0, 0.06, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

## A single procedural ribbon mesh: 8 strips x 6 divisions, ~100 triangles.
## No per-frame geometry allocation, just inexpensive vertex displacement.
func _build_spirit_veil() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strips := 8
	var steps := 6
	for strand in strips:
		var angle := TAU * float(strand) / float(strips)
		for segment in steps:
			var y0 := float(segment) / float(steps)
			var y1 := float(segment + 1) / float(steps)
			var v00 := _veil_vertex(angle, y0, 0.0)
			var v10 := _veil_vertex(angle, y0, 1.0)
			var v01 := _veil_vertex(angle, y1, 0.0)
			var v11 := _veil_vertex(angle, y1, 1.0)
			_veil_point(st, v00, Vector2(0.0, y0))
			_veil_point(st, v10, Vector2(1.0, y0))
			_veil_point(st, v11, Vector2(1.0, y1))
			_veil_point(st, v00, Vector2(0.0, y0))
			_veil_point(st, v11, Vector2(1.0, y1))
			_veil_point(st, v01, Vector2(0.0, y1))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = preload("res://game/actors/jinn/spirit_veil.gdshader")
	mi.material_override = _veil_mat
	mi.name = "SpiritVeil"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _veil_vertex(angle: float, h: float, side: float) -> Vector3:
	var twist := angle + h * 0.38
	var across := (side - 0.5) * (0.55 - 0.25 * h)
	var r := 0.29 + 0.13 * sin(angle * 3.0) - 0.11 * h
	return Vector3(cos(twist) * r - sin(twist) * across,
		0.02 + 1.65 * h,
		sin(twist) * r + cos(twist) * across)


func _veil_point(st: SurfaceTool, pos: Vector3, uv: Vector2) -> void:
	st.set_uv(uv)
	st.set_normal(pos.normalized())
	st.add_vertex(pos)
