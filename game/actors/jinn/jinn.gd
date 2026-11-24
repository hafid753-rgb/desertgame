class_name Jinn
extends CharacterBody3D
## Shadow jinn (ICO-style shadow creature, see ShadowLook). Telegraphed
## attacks; the golden rings flare to the attack colour:
##   swipe    (orange, 0.6 s): hook punch, close arc in front
##   lunge    (red, 0.9 s): dashing punch
##   burst    (violet, 1.2 s): smoke detonation around itself
##   fireball (amber, 0.85 s): wind-up throw, homing fireball
##   vanish   (grey, 0.5 s): melts into its pool, gone for 2 s; a pool opens
##            behind the player 0.5 s before it erupts into an ambush kick
## Facing locks at 70% of the telegraph so the player can read and react.

signal defeated(jinn: Jinn)
signal health_changed(hp: float, max_hp: float)
## A hit that could not harm this jinn (wrong element).
signal immune_hit(element: int)

enum S { IDLE, CHASE, CIRCLE, TELEGRAPH, ATTACK, RECOVER, STAGGER, DEAD, RETURN, SUBDUED }

const ATTACKS := {
	"swipe": {"telegraph": 0.6, "active": 0.15, "recovery": 0.6, "damage": 14.0, "range": 2.4, "arc": 120.0,
		"color": Color(1.0, 0.6, 0.1), "stun": 0.35, "knockback": 3.0},
	"lunge": {"telegraph": 0.9, "active": 0.35, "recovery": 0.9, "damage": 20.0, "range": 1.4, "arc": 360.0,
		"color": Color(1.0, 0.12, 0.1), "stun": 0.5, "knockback": 6.0, "dash_speed": 14.0},
	"burst": {"telegraph": 1.2, "active": 0.2, "recovery": 1.0, "damage": 24.0, "range": 3.4, "arc": 360.0,
		"color": Color(0.75, 0.35, 1.0), "stun": 0.6, "knockback": 7.0},
	"fireball": {"telegraph": 0.85, "active": 0.15, "recovery": 0.7, "damage": 16.0, "range": 14.0, "arc": 360.0,
		"color": Color(1.0, 0.45, 0.1), "stun": 0.4, "knockback": 4.0},
	"vanish": {"telegraph": 0.5, "active": 2.0, "recovery": 0.0, "damage": 0.0, "range": 0.0, "arc": 0.0,
		"color": Color(0.7, 0.7, 0.78), "stun": 0.0, "knockback": 0.0},
	"ambush": {"telegraph": 0.55, "active": 0.15, "recovery": 0.6, "damage": 18.0, "range": 2.4, "arc": 140.0,
		"color": Color(0.85, 0.75, 1.0), "stun": 0.45, "knockback": 5.0},
}
## Clip + impact fraction (peak limb speed) for each attack on the shadow rig.
const CLIPS := {"swipe": ["Unarmed_Melee_Attack_Punch_A", 0.28], "lunge": ["Unarmed_Melee_Attack_Punch_B", 0.28],
	"burst": ["Spellcast_Raise", 0.45], "fireball": ["Throw", 0.5], "vanish": ["Spellcast_Long", 0.3],
	"ambush": ["Unarmed_Melee_Attack_Kick", 0.34], "slam": ["Unarmed_Melee_Attack_Punch_B", 0.28],
	"summon": ["Spellcast_Raise", 0.45]}
const VANISH_TIME := 2.0
const CHASE_SPEED := 3.2
const CIRCLE_SPEED := 2.0
const STAGGER_PARRIED := 1.4
const DEFAULT_VISUAL_SCALE := 1.25  # towers over the ~1.75 m adventurers

@export var ai_enabled: bool = true
@export var max_hp: float = 160.0

var hp: float = 160.0
var radius: float = 0.6
var attacks: Dictionary = ATTACKS.duplicate(true)
var visual_scale: float = DEFAULT_VISUAL_SCALE
var chase_speed: float = CHASE_SPEED
## Telegraph speed multiplier (>1 = faster tells; the Jinn King's rage phase).
var tempo: float = 1.0
## Guard behaviour: only engage players within aggro_radius of home, and walk
## back when they leave. Default = unlimited (the practice jinn).
var home: Vector3 = Vector3.ZERO
var aggro_radius: float = 1.0e9
var subdued: bool = false
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
var immune_hits: int = 0

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
var _gold_rings: Array[Node3D] = []
var _wisps: CPUParticles3D
## Golden rings orbiting the smoke (the King has more).
var ring_count: int = 3
var _immune_popup_at: int = -10000
var _recent: Array[String] = []
var _anim: AnimationPlayer
var _anim_clip := ""
var _exag: Exaggerate
var _pool: MeshInstance3D
var _pool_mat: StandardMaterial3D
var _emitters: Array = []
var _eyes: Array = []
var _skel: Skeleton3D
## Head bone anchor (crowns etc. ride on it).
var head_anchor: Node3D
var hidden := false
var _vanish_cd := 0.0
var _ambush_at := Vector3.ZERO
var _range_cd := 0.0


func _ready() -> void:
	add_to_group("jinn")
	hp = max_hp
	collision_layer = Combat.LAYER_JINN
	collision_mask = Combat.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = 2.2 * visual_scale / DEFAULT_VISUAL_SCALE
	shape.shape = cap
	shape.position = Vector3(0, cap.height * 0.5, 0)
	add_child(shape)
	home = global_position if is_inside_tree() else position
	_build_visual()
	if fx_parent == null:
		fx_parent = get_parent()
	_rng.seed = hash(get_instance_id())


func is_dead() -> bool:
	return state == S.DEAD


func _target_in_territory(margin: float = 0.0) -> bool:
	if target == null:
		return false
	return Combat.flat(target.global_position - home).length() <= aggro_radius + margin


func telegraph_time(name: String) -> float:
	return float(attacks[name]["telegraph"]) / tempo


## The Jinn King has fallen: stop fighting, kneel, become recruitable.
func subdue() -> void:
	if state == S.DEAD:
		return
	subdued = true
	ai_enabled = false
	remove_from_group("jinn")
	add_to_group("subdued_jinn")
	collision_layer = 0
	burn_time = 0.0
	_enter(S.SUBDUED)
	_eye_mat.albedo_color = Color(0.7, 0.95, 1.0)
	# The shadow lifts: core softens, rim turns pale turquoise.
	_smoke_mat.set_shader_parameter("core_color", Color(0.1, 0.1, 0.22))
	_smoke_mat.set_shader_parameter("rim_color", Color(0.5, 0.85, 0.95))
	_eye_mat.albedo_color = Color(0.6, 0.95, 1.0)


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
	if state == S.DEAD or hidden:
		return
	var amount: float = info.get("amount", 0.0)
	var element: int = info.get("element", Combat.Element.NONE)
	var stagger: int = info.get("stagger", 0)
	if not Combat.harms_jinn(element):
		_pass_through(info, element)
		return
	if element == Combat.Element.WATER:
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


## Steel, Wind and Fire pass through the smoke: no damage, no burn.
## Wind still pushes the jinn back (crowd control, not harm).
func _pass_through(info: Dictionary, element: int) -> void:
	immune_hits += 1
	if element == Combat.Element.WIND:
		var from: Vector3 = info.get("from", global_position)
		knock_velocity = Combat.flat(global_position - from).normalized() * float(info.get("knockback", 1.5))
	Fx.burst(fx_parent, global_position + Vector3(0, 1.2, 0), Color(0.3, 0.2, 0.45, 0.4), 1.0, 0.35)
	if Time.get_ticks_msec() - _immune_popup_at > 600:
		_immune_popup_at = Time.get_ticks_msec()
		Fx.popup(fx_parent, global_position + Vector3(0, 2.3, 0), "immune", Color(0.75, 0.7, 0.85), 40)
	immune_hit.emit(element)


func _physics_process(delta: float) -> void:
	state_time += delta
	_vanish_cd = maxf(0.0, _vanish_cd - delta)
	_range_cd = maxf(0.0, _range_cd - delta)
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
			if ai_enabled and target and not target.is_dead() and _target_in_territory():
				_enter(S.CHASE)
		S.CHASE:
			h = _tick_chase(delta)
			if ai_enabled and not _target_in_territory(4.0):
				_enter(S.RETURN)
		S.RETURN:
			var back := Combat.flat(home - global_position)
			if back.length() < 0.6:
				_enter(S.IDLE)
			else:
				_face(back, 1.0 - exp(-6.0 * delta))
				h = back.normalized() * chase_speed
		S.SUBDUED:
			pass
		S.CIRCLE:
			h = _tick_circle(delta)
			if ai_enabled and not _target_in_territory(4.0):
				_enter(S.RETURN)
		S.TELEGRAPH:
			h = _tick_telegraph(delta)
		S.ATTACK:
			h = _tick_attack(delta)
		S.RECOVER:
			var rec: float = attacks[current]["recovery"]
			if state_time >= rec:
				_enter(S.CIRCLE if ai_enabled else S.IDLE)
		S.STAGGER:
			if state_time >= stagger_time:
				_enter(S.CIRCLE if ai_enabled else S.IDLE)
		S.DEAD:
			_smoke_mat.set_shader_parameter("dissolve", clampf(state_time / 1.2, 0.0, 1.0))
			if _veil_mat:
				_veil_mat.set_shader_parameter("dissolve", clampf(state_time / 0.85, 0.0, 1.0))
			for r in _gold_rings:
				r.scale = Vector3.ONE * maxf(0.01, 1.0 + state_time * 1.5)
			for e in _emitters:
				(e as CPUParticles3D).emitting = false
			if _pool_mat:
				_pool_mat.albedo_color.a = 0.85 * (1.0 - clampf(state_time / 1.2, 0.0, 1.0))
			_drive_anim(1.0 / 60.0)
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
		_eye_mat.albedo_color = JinnLook.GOLD


func _tick_chase(delta: float) -> Vector3:
	if target == null or target.is_dead():
		_enter(S.IDLE)
		return Vector3.ZERO
	var to := Combat.flat(target.global_position - global_position)
	_face(to, 1.0 - exp(-6.0 * delta))
	if to.length() < 3.2:
		_enter(S.CIRCLE)
		return Vector3.ZERO
	# from range: throw fire or step into the shadows
	if ai_enabled and state_time > 1.0 and to.length() > 5.0 and to.length() < 13.0 and _range_cd <= 0.0 and attacks.has("fireball"):
		_range_cd = 2.5
		_begin_telegraph("vanish" if attacks.has("vanish") and _vanish_cd <= 0.0 and _rng.randf() < 0.3 else "fireball")
		return Vector3.ZERO
	return to.normalized() * chase_speed * chill_multiplier


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
	var r := _rng.randf()
	var can_vanish := attacks.has("vanish") and _vanish_cd <= 0.0
	var can_fire := attacks.has("fireball")
	if dist > 3.6:
		pick = "fireball" if can_fire and r < 0.45 else ("vanish" if can_vanish and r < 0.65 else "lunge")
	elif dist < 2.0:
		pick = "vanish" if can_vanish and r < 0.12 else ("burst" if r < 0.5 else "swipe")
	else:
		if can_vanish and r < 0.15:
			pick = "vanish"
		elif can_fire and r < 0.32:
			pick = "fireball"
		else:
			pick = "swipe" if _rng.randf() < 0.65 else "burst"
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
	var col: Color = attacks[name]["color"]
	_eye_mat.albedo_color = col
	_smoke_mat.set_shader_parameter("warning_color", col)
	Juice.play("tel_" + name, global_position)
	_ring_mat.albedo_color = Color(col, 0.35)


func _tick_telegraph(delta: float) -> Vector3:
	var atk: Dictionary = attacks[current]
	var tel: float = telegraph_time(current)
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
	if current == "vanish":
		_smoke_mat.set_shader_parameter("dissolve", smoothstep(0.35, 1.0, p))
	if state_time >= tel:
		_enter(S.ATTACK)
		_eye_mat.albedo_color = Color(1, 1, 1)
	return h


func _tick_attack(_delta: float) -> Vector3:
	var atk: Dictionary = attacks[current]
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
				Fx.burst(fx_parent, global_position + Vector3(0, 1.0, 0), Color(0.02, 0.01, 0.04, 0.85), float(atk["range"]) * 0.8, 0.45)
				_try_hit(atk)
		"fireball":
			if not attack_hit_done:
				attack_hit_done = true
				var from := global_position + Vector3(0, 1.7, 0) * visual_scale / DEFAULT_VISUAL_SCALE + _forward() * 0.6
				var aim := _forward()
				if target:
					aim = (target.global_position + Vector3(0, 0.9, 0) - from).normalized()
				Fireball.spawn(fx_parent, from, aim, atk, target, visual_scale / DEFAULT_VISUAL_SCALE)
		"vanish":
			return _tick_vanish()
		"ambush":
			if not attack_hit_done:
				attack_hit_done = true
				Fx.burst(fx_parent, global_position + _forward() * 1.2 + Vector3(0, 0.8, 0), Color(0.02, 0.01, 0.04, 0.8), 1.4, 0.25)
				_try_hit(atk)
	if state_time >= active:
		_enter(S.RECOVER)
	return h


## Melted into the ground for VANISH_TIME: intangible and invisible. Half a
## second before it returns, a pool opens behind the player (the tell).
func _tick_vanish() -> Vector3:
	if not hidden:
		_set_hidden(true)
		Fx.burst(fx_parent, global_position + Vector3(0, 0.5, 0), Color(0.02, 0.01, 0.04, 0.8), 1.6, 0.4)
		_vanish_cd = 7.0
	var warn_at := VANISH_TIME - 0.5
	if state_time >= warn_at and _ambush_at == Vector3.ZERO:
		var back := Vector3(0, 0, 1)
		if target:
			back = target.global_transform.basis.z
			back.y = 0.0
			back = back.normalized()
			_ambush_at = target.global_position + back * 2.0
			_ambush_at.y = global_position.y
		else:
			_ambush_at = global_position
		global_position = _ambush_at
		_pool.visible = true
		_pool_mat.albedo_color.a = 0.0
		Juice.play("tel_burst", _ambush_at, 0.7)
	if _ambush_at != Vector3.ZERO and _pool:
		_pool_mat.albedo_color.a = 0.85 * clampf((state_time - warn_at) / 0.4, 0.0, 1.0)
	if state_time >= VANISH_TIME:
		_set_hidden(false)
		_ambush_at = Vector3.ZERO
		if target:
			_face(Combat.flat(target.global_position - global_position), 1.0)
		_begin_telegraph("ambush" if attacks.has("ambush") else "swipe")
	return Vector3.ZERO


func _set_hidden(on: bool) -> void:
	hidden = on
	collision_layer = 0 if on else Combat.LAYER_JINN
	if on:
		remove_from_group("jinn")
	elif not subdued:
		add_to_group("jinn")
	if _visual:
		_visual.visible = not on
	if _pool:
		_pool.visible = not on
	for e in _emitters:
		(e as CPUParticles3D).emitting = not on
	if not on:
		_smoke_mat.set_shader_parameter("dissolve", 0.0)


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
		tel_p = clampf(state_time / telegraph_time(current), 0.0, 1.0)
	if _visual:
		var hover := 0.05 + sin(Time.get_ticks_msec() * 0.002 + get_instance_id()) * 0.04
		_visual.position.y = lerpf(_visual.position.y, hover, 1.0 - exp(-8.0 * delta))
		if state == S.STAGGER:
			_visual.rotation.z = sin(state_time * 20.0) * 0.08
		else:
			_visual.rotation.z = 0.0
	_drive_anim(delta)
	_flash = maxf(0.0, _flash - delta * 6.0)
	_smoke_mat.set_shader_parameter("flash", _flash * 0.8)
	_smoke_mat.set_shader_parameter("warning", tel_p * 0.55)
	# eyes flare to the attack colour during a telegraph
	var eye_col := Color(1, 1, 1)
	if state == S.TELEGRAPH:
		eye_col = Color(1, 1, 1).lerp(attacks[current]["color"], tel_p)
	for e in _eyes:
		((e as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = eye_col
	JinnLook.spin(_gold_rings, delta, tel_p if state == S.TELEGRAPH else (0.6 if state == S.ATTACK else 0.0))


func _jplay(clip: String, blend: float = 0.2, speed: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if clip == _anim_clip and _anim.is_playing():
		_anim.speed_scale = speed
		return
	_anim_clip = clip
	_anim.play(clip, blend)
	_anim.speed_scale = speed


func _jscrub(clip: String, frac: float) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if clip != _anim_clip:
		_anim_clip = clip
		_anim.play(clip, 0.0)
	_anim.speed_scale = 0.0
	var length := _anim.get_animation(clip).length
	_anim.seek(clampf(frac, 0.0, 0.98) * length, true)


## Skeletal animation for every state. Attacks are scrubbed from the state
## timers so the hit lands on the clip's impact frame.
func _drive_anim(delta: float) -> void:
	if _anim == null:
		return
	var ex := 0.3
	var clip_info: Array = CLIPS.get(current, ["Unarmed_Melee_Attack_Punch_A", 0.28])
	var clip: String = clip_info[0]
	var imp: float = clip_info[1]
	match state:
		S.TELEGRAPH:
			var p := clampf(state_time / telegraph_time(current), 0.0, 1.0)
			_jscrub(clip, p * imp * 0.85)
			ex = 0.3 + 0.7 * p
		S.ATTACK:
			if current == "vanish":
				return
			var active: float = attacks[current]["active"]
			_jscrub(clip, imp * 0.85 + clampf(state_time / maxf(active, 0.01), 0.0, 1.0) * imp * 0.3)
			ex = 1.0
		S.RECOVER:
			var rec: float = attacks[current]["recovery"]
			var r := clampf(state_time / maxf(rec, 0.01), 0.0, 1.0)
			_jscrub(clip, imp * 1.15 + r * (0.95 - imp * 1.15))
			ex = lerpf(1.0, 0.3, r)
		S.CHASE, S.RETURN:
			_jplay("Walking_B", 0.25, 0.75 * chill_multiplier)
		S.CIRCLE:
			_jplay("Running_Strafe_Right" if circle_dir > 0.0 else "Running_Strafe_Left", 0.25, 0.5 * chill_multiplier)
		S.STAGGER:
			_jplay("Hit_A", 0.05, 1.0)
		S.DEAD:
			_jplay("Death_A", 0.1, 1.2)
			ex = 0.0
		S.SUBDUED:
			_jplay("Sit_Floor_Idle", 0.4, 0.8)
			ex = 0.0
		_:
			_jplay("Unarmed_Idle", 0.3, 0.6)
	if _exag:
		_exag.amount = lerpf(_exag.amount, ex, 1.0 - exp(-12.0 * delta))


func _build_visual() -> void:
	var look := ShadowLook.build(self, visual_scale, ring_count)
	_visual = look["visual"]
	_smoke_mat = look["smoke_mat"]
	# _eye_mat drives the golden rings: they carry the attack colours.
	_eye_mat = look["ring_mat"]
	_gold_rings = look["rings"]
	_wisps = look["wisps"]
	_emitters = look["emitters"]
	_eyes = look["eyes"]
	_anim = look["anim"]
	_exag = look["exag"]
	_pool = look["pool"]
	_pool_mat = look["pool_mat"]
	_skel = look["skel"]
	head_anchor = BoneAttachment3D.new()
	(head_anchor as BoneAttachment3D).bone_name = "head"
	_skel.add_child(head_anchor)
	_jplay("Unarmed_Idle", 0.0, 0.6)
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


