class_name Player
extends CharacterBody3D
## The playable character. All combat rules live here so they can later be
## moved to the server unchanged: inputs in, state out.
##
## Controls (see docs/controls.md):
##   Attack tap = combo, hold = heavy.  Dodge tap = dodge, hold = block,
##   block started <=150 ms before a hit = parry.  Hold Special = charge
##   element tiers; while holding: Attack = elemental attack, Dodge =
##   elemental mobility.  Block + tap Special = elemental defense.

signal health_changed(hp: float, max_hp: float)
signal stamina_changed(stamina: float, max_stamina: float)
signal announced(text: String, color: Color)
signal died

enum State { MOVE, ATTACK, HEAVY_CHARGE, GUARD, DODGE, CAST, MOBILITY, DEFENSE, HITSTUN, DEAD }

const GRAVITY := 24.0
const BASE_SPEED := 4.6
const SPRINT_MULT := 1.55
const SPRINT_DELAY := 0.5
const SPRINT_COST := 14.0
const BASE_STAMINA := 100.0
const STAMINA_REGEN := 34.0
const STAMINA_DELAY := 0.7
const INPUT_BUFFER := 0.10
const TAP_MAX := 0.18
const PARRY_WINDOW := 0.15
const HEAVY_HOLD := 0.40
const CHARGE_TIERS: Array[float] = [0.35, 0.8, 1.4]
const PERFECT_DODGE_WINDOW := 0.22
const COUNTER_TIME := 1.0
const DODGE_TIME := 0.42
const DODGE_SPEED := 9.0
const DODGE_COST := 20.0
const IFRAME_START := 0.03
const IFRAME_END := 0.32
const LOCK_RANGE := 18.0

const COMBO: Array[Dictionary] = [
	{"windup": 0.10, "active": 0.10, "recovery": 0.26, "damage": 10.0, "range": 2.3, "arc": 110.0, "cost": 7.0, "lunge": 2.5, "stagger": 0},
	{"windup": 0.10, "active": 0.10, "recovery": 0.26, "damage": 11.0, "range": 2.3, "arc": 110.0, "cost": 7.0, "lunge": 2.5, "stagger": 0},
	{"windup": 0.16, "active": 0.12, "recovery": 0.42, "damage": 18.0, "range": 2.6, "arc": 140.0, "cost": 10.0, "lunge": 4.0, "stagger": 1},
]
const HEAVY_ATTACK: Dictionary = {"windup": 0.22, "active": 0.14, "recovery": 0.5, "damage": 32.0, "range": 2.8, "arc": 160.0, "cost": 18.0, "lunge": 5.0, "stagger": 2}

@export var species_id: String = "cat"

var species: Dictionary
var max_hp: float = 100.0
var hp: float = 100.0
var max_stamina: float = BASE_STAMINA
var stamina: float = BASE_STAMINA
var move_speed: float = BASE_SPEED
var element: int = Combat.Element.WIND

var state: int = State.MOVE
var state_time: float = 0.0
var now: float = 0.0

var combo_step: int = 0
var current_attack: Dictionary = {}
var is_heavy: bool = false
var attack_hit_done: bool = false
var queued_attack: bool = false
var attack_held: bool = false
var attack_press_time: float = -10.0
var buffered_attack_t: float = -10.0
var buffered_dodge_t: float = -10.0

var dodge_held: bool = false
var guard_start: float = -10.0
var guard_absorbed: bool = false
var dodge_dir: Vector3 = Vector3.FORWARD
var dodge_started_at: float = -10.0
var perfect_used: bool = false

var special_held: bool = false
var special_start: float = -10.0
var charge_cancelled: bool = true
var cast_tier: int = 0
var cast_done: bool = false
var mobility_hits: Array = []

var stamina_delay: float = 0.0
var sprint_time: float = 0.0
var sprinting: bool = false
var hitstun_time: float = 0.0
var knock_velocity: Vector3 = Vector3.ZERO
var counter_window: float = 0.0
var element_cooldown: float = 0.0
var last_input_usec: int = 0
var spawn_point: Vector3 = Vector3.ZERO

var camera_rig: CameraRig
var lock_target: Node3D = null
var model: CreatureModel
var fx_parent: Node

## Stats for the playtest report.
var stats: Dictionary = {"parries": 0, "perfect_dodges": 0, "hits_taken": 0, "blocks": 0, "casts": 0, "special_cancels": 0}


func _ready() -> void:
	add_to_group("player")
	collision_layer = Combat.LAYER_PLAYER
	collision_mask = Combat.LAYER_WORLD | Combat.LAYER_JINN
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.3
	shape.shape = cap
	shape.position = Vector3(0, 0.65, 0)
	add_child(shape)
	set_species(species_id)
	if fx_parent == null:
		fx_parent = get_parent()
	spawn_point = global_position


# --- Public API -------------------------------------------------------------

func set_species(id: String) -> void:
	species_id = id
	species = Species.get_data(id)
	max_stamina = BASE_STAMINA * float(species["stamina"])
	stamina = max_stamina
	move_speed = BASE_SPEED * float(species["speed"])
	if model:
		model.queue_free()
	model = CreatureModel.new()
	add_child(model)
	model.build(species)
	stamina_changed.emit(stamina, max_stamina)


func next_species() -> void:
	var ids: Array = Species.DATA.keys()
	set_species(ids[(ids.find(species_id) + 1) % ids.size()])
	announced.emit(str(species["name"]), species["fur"])


func is_dead() -> bool:
	return state == State.DEAD


func charge_tier() -> int:
	if not is_charging():
		return 0
	var t := now - special_start
	var tier := 0
	for i in CHARGE_TIERS.size():
		if t >= CHARGE_TIERS[i]:
			tier = i + 1
	return tier


func charge_progress() -> float:
	## 0..3 continuous, for UI.
	if not is_charging():
		return 0.0
	var t := now - special_start
	var prev := 0.0
	for i in CHARGE_TIERS.size():
		if t < CHARGE_TIERS[i]:
			return i + (t - prev) / (CHARGE_TIERS[i] - prev)
		prev = CHARGE_TIERS[i]
	return 3.0


func is_charging() -> bool:
	return special_held and not charge_cancelled and state == State.MOVE


func is_invulnerable() -> bool:
	if state == State.DODGE:
		return state_time >= IFRAME_START and state_time <= IFRAME_END
	if state == State.MOBILITY:
		return element == Combat.Element.WIND or state_time < 0.25
	return false


func state_name() -> String:
	return State.keys()[state]


func respawn() -> void:
	hp = max_hp
	stamina = max_stamina
	global_position = spawn_point
	velocity = Vector3.ZERO
	knock_velocity = Vector3.ZERO
	reset_physics_interpolation()
	_enter(State.MOVE)
	health_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)


## Called by enemies when their attack's active frames reach the player.
## Returns: "hit", "blocked", "parried", "deflected", "guard_break",
## "dodged", "perfect_dodge", "none".
func receive_attack(atk: Dictionary, attacker: Node3D) -> String:
	if state == State.DEAD:
		return "none"
	var dmg: float = atk.get("damage", 10.0)
	var from := attacker.global_position if attacker else global_position + _forward()
	var to_attacker := Combat.flat(from - global_position).normalized()
	var facing_ok := _forward().angle_to(to_attacker) < deg_to_rad(100.0)

	if is_invulnerable():
		if now - dodge_started_at <= PERFECT_DODGE_WINDOW and not perfect_used:
			perfect_used = true
			counter_window = COUNTER_TIME
			stats["perfect_dodges"] += 1
			announced.emit("PERFECT DODGE", Color(0.6, 1.0, 1.0))
			Fx.ring(fx_parent, global_position, Color(0.6, 1.0, 1.0, 0.6), 2.5)
			return "perfect_dodge"
		return "dodged"

	if state == State.DEFENSE and element == Combat.Element.WIND:
		Fx.burst(fx_parent, global_position + Vector3(0, 0.8, 0), Color(0.6, 0.95, 1.0, 0.5), 1.8)
		return "deflected"

	if (state == State.GUARD or state == State.DEFENSE) and facing_ok:
		guard_absorbed = true
		if state == State.GUARD and now - guard_start <= PARRY_WINDOW:
			counter_window = COUNTER_TIME
			_restore_stamina(10.0)
			stats["parries"] += 1
			announced.emit("PARRY!", Color(1.0, 0.95, 0.5))
			Fx.burst(fx_parent, global_position + _forward() * 0.6 + Vector3(0, 0.8, 0), Color(1, 0.95, 0.6, 0.9), 1.2, 0.2)
			return "parried"
		var cost := dmg * 1.1
		if stamina >= cost:
			_spend(cost)
			stats["blocks"] += 1
			knock_velocity = -to_attacker * 2.5
			Fx.burst(fx_parent, global_position + _forward() * 0.5 + Vector3(0, 0.8, 0), Color(1, 1, 1, 0.6), 0.6, 0.15)
			return "blocked"
		_spend(stamina)
		_take_damage(dmg * 0.5, -to_attacker * 4.0, 0.9)
		announced.emit("GUARD BROKEN", Color(1, 0.5, 0.4))
		return "guard_break"

	_take_damage(dmg, -to_attacker * float(atk.get("knockback", 3.0)), float(atk.get("stun", 0.4)))
	return "hit"


func toggle_lock() -> void:
	if lock_target and is_instance_valid(lock_target):
		_set_lock(null)
		return
	var cands := _lock_candidates()
	_set_lock(cands[0] if not cands.is_empty() else null)


func cycle_target() -> void:
	var cands := _lock_candidates()
	if cands.is_empty():
		_set_lock(null)
		return
	var idx := cands.find(lock_target)
	_set_lock(cands[(idx + 1) % cands.size()])


## Tap on an enemy on screen to lock it.
func lock_at_screen(screen_pos: Vector2) -> bool:
	if camera_rig == null:
		return false
	var cam := camera_rig.camera
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var best: Node3D = null
	var best_d := 1.6
	for j in get_tree().get_nodes_in_group("jinn"):
		if j.is_dead():
			continue
		var p: Vector3 = j.global_position + Vector3(0, 1.0, 0)
		var along := (p - origin).dot(dir)
		if along < 0.0:
			continue
		var d := (origin + dir * along).distance_to(p)
		if d < best_d:
			best_d = d
			best = j
	if best:
		_set_lock(best)
		return true
	return false


# --- Main loop --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	now += delta
	state_time += delta
	counter_window = maxf(0.0, counter_window - delta)
	element_cooldown = maxf(0.0, element_cooldown - delta)
	if lock_target and (not is_instance_valid(lock_target) or lock_target.is_dead()):
		_set_lock(null)

	for e in GameInput.consume_events():
		_handle_input(e)

	var horizontal := Vector3.ZERO
	match state:
		State.MOVE:
			horizontal = _tick_move(delta)
		State.ATTACK:
			horizontal = _tick_attack(delta)
		State.HEAVY_CHARGE:
			horizontal = _move_vector() * move_speed * 0.35
			_face_target_or(horizontal, delta, 8.0)
		State.GUARD:
			horizontal = _move_vector() * move_speed * 0.3
			_face_target_or(Vector3.ZERO, delta, 12.0)
			if not dodge_held and state_time > TAP_MAX:
				_enter(State.MOVE)
		State.DODGE:
			horizontal = _tick_dodge()
		State.CAST:
			horizontal = _tick_cast(delta)
		State.MOBILITY:
			horizontal = _tick_mobility()
		State.DEFENSE:
			horizontal = _tick_defense()
		State.HITSTUN:
			if state_time >= hitstun_time:
				_enter(State.MOVE)
		State.DEAD:
			if state_time > 2.5:
				respawn()

	knock_velocity = knock_velocity.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	velocity.x = horizontal.x + knock_velocity.x
	velocity.z = horizontal.z + knock_velocity.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if global_position.y < -10.0:
		respawn()

	_tick_stamina(delta)
	PerfLogger.player_state = state_name()
	_animate(delta, horizontal)


# --- Input ------------------------------------------------------------------

func _handle_input(e: Dictionary) -> void:
	var action: String = e["action"]
	var pressed: bool = e["pressed"]
	var t_usec: int = e["t_usec"]
	match action:
		"attack":
			attack_held = pressed
			if pressed:
				last_input_usec = t_usec
				attack_press_time = now
				_on_attack_pressed()
			elif state == State.HEAVY_CHARGE:
				_start_attack(HEAVY_ATTACK, true)
		"dodge":
			dodge_held = pressed
			if pressed:
				last_input_usec = t_usec
				_on_dodge_pressed()
			elif state == State.GUARD:
				if state_time < TAP_MAX and not guard_absorbed:
					_start_dodge()
				else:
					_enter(State.MOVE)
		"special":
			special_held = pressed
			if pressed:
				last_input_usec = t_usec
				_on_special_pressed()
			else:
				if is_charging():
					stats["special_cancels"] += 1
				charge_cancelled = true
		"lock":
			if pressed:
				toggle_lock()
		"cycle_target":
			if pressed:
				cycle_target()
		"element":
			if pressed:
				_toggle_element()
		"species":
			if pressed and state == State.MOVE:
				next_species()


func _on_attack_pressed() -> void:
	if is_charging():
		var tier := charge_tier()
		if tier >= 1:
			_start_cast(tier)
			return
		charge_cancelled = true
	match state:
		State.MOVE:
			_start_attack(COMBO[0], false)
		State.ATTACK:
			if not is_heavy and state_time >= float(current_attack["windup"]) - INPUT_BUFFER:
				queued_attack = true
		_:
			buffered_attack_t = now


func _on_dodge_pressed() -> void:
	if is_charging():
		_start_mobility(maxi(1, charge_tier()))
		return
	match state:
		State.MOVE, State.HEAVY_CHARGE:
			_start_guard()
		State.ATTACK:
			# Dodge cancels an attack once its active frames are over.
			if state_time >= float(current_attack["windup"]) + float(current_attack["active"]):
				_start_guard()
			else:
				buffered_dodge_t = now
		_:
			buffered_dodge_t = now


func _on_special_pressed() -> void:
	special_start = now
	if state == State.GUARD:
		charge_cancelled = true
		_start_defense()
		return
	charge_cancelled = state != State.MOVE


func _toggle_element() -> void:
	if element_cooldown > 0.0 or state != State.MOVE:
		return
	element = Combat.Element.FIRE if element == Combat.Element.WIND else Combat.Element.WIND
	element_cooldown = 0.5
	announced.emit("%s element" % Combat.ELEMENT_NAMES[element], Combat.ELEMENT_COLORS[element])


# --- States -----------------------------------------------------------------

func _enter(s: int) -> void:
	state = s
	state_time = 0.0
	if s == State.MOVE:
		combo_step = 0 if not queued_attack else combo_step
		if now - buffered_dodge_t <= INPUT_BUFFER and dodge_held:
			buffered_dodge_t = -10.0
			_start_guard()
		elif now - buffered_dodge_t <= INPUT_BUFFER:
			buffered_dodge_t = -10.0
			_start_dodge()
		elif now - buffered_attack_t <= INPUT_BUFFER:
			buffered_attack_t = -10.0
			_start_attack(COMBO[0], false)


func _tick_move(delta: float) -> Vector3:
	var input := GameInput.get_move()
	var dir := _move_vector()
	if input.length() > 0.92 and not is_charging() and lock_target == null:
		sprint_time += delta
	else:
		sprint_time = 0.0
	sprinting = sprint_time > SPRINT_DELAY and stamina > 1.0
	var spd := move_speed * (SPRINT_MULT if sprinting else 1.0) * (0.5 if is_charging() else 1.0)
	if sprinting:
		_spend(SPRINT_COST * delta)
	var h := dir * spd
	_face_target_or(h, delta, 12.0)
	return h


func _start_attack(atk: Dictionary, heavy: bool) -> void:
	var cost: float = atk["cost"]
	if stamina < 1.0:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		_enter(State.MOVE)
		return
	_spend(cost)
	current_attack = atk
	is_heavy = heavy
	attack_hit_done = false
	queued_attack = false
	_soft_aim()
	_enter(State.ATTACK)
	PerfLogger.record_latency(last_input_usec)


func _tick_attack(delta: float) -> Vector3:
	var windup: float = current_attack["windup"]
	var active: float = current_attack["active"]
	var recovery: float = current_attack["recovery"]
	var h := Vector3.ZERO
	if state_time < windup + active:
		var lunge: float = current_attack["lunge"]
		h = _forward() * lunge * (1.0 - state_time / (windup + active))
	if not attack_hit_done and state_time >= windup:
		attack_hit_done = true
		_melee_hit(current_attack)
	if state_time >= windup + active:
		if queued_attack and not is_heavy and combo_step < COMBO.size() - 1:
			combo_step += 1
			queued_attack = false
			_start_attack(COMBO[combo_step], false)
			return h
		# Still holding Attack past HEAVY_HOLD: wind up a heavy strike.
		if attack_held and not is_heavy and now - attack_press_time >= HEAVY_HOLD:
			_enter(State.HEAVY_CHARGE)
			return h
	if state_time >= windup + active + recovery:
		queued_attack = false
		_enter(State.MOVE)
	return h


func _melee_hit(atk: Dictionary) -> void:
	var mult := 1.5 if counter_window > 0.0 else 1.0
	var dmg: float = float(atk["damage"]) * mult
	var hit_any := false
	for j in get_tree().get_nodes_in_group("jinn"):
		if j.is_dead():
			continue
		if Combat.in_arc(global_position, _forward(), j.global_position, float(atk["range"]) + j.radius, float(atk["arc"])):
			j.take_damage({
				"amount": dmg, "element": Combat.Element.NONE, "from": global_position,
				"knockback": 5.0 if is_heavy else 1.5, "stagger": int(atk["stagger"]), "counter": counter_window > 0.0,
			})
			hit_any = true
	if hit_any:
		Fx.burst(fx_parent, global_position + _forward() * 1.4 + Vector3(0, 0.9, 0), Color(1, 1, 0.9, 0.8), 0.7, 0.12)


func _start_guard() -> void:
	guard_start = now
	guard_absorbed = false
	_enter(State.GUARD)
	PerfLogger.record_latency(last_input_usec)


func _start_dodge() -> void:
	if stamina < 5.0:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		_enter(State.MOVE)
		return
	_spend(DODGE_COST)
	var dir := _move_vector()
	dodge_dir = dir.normalized() if dir.length() > 0.2 else -_forward()
	dodge_started_at = now
	perfect_used = false
	_enter(State.DODGE)


func _tick_dodge() -> Vector3:
	var k := clampf(1.0 - state_time / DODGE_TIME, 0.0, 1.0)
	var back := dodge_dir.dot(_forward()) < -0.7
	var spd := DODGE_SPEED * (0.75 if back else 1.0) * sqrt(k)
	if state_time >= DODGE_TIME:
		_enter(State.MOVE)
	return dodge_dir * spd


func _start_cast(tier: int) -> void:
	var cost := 10.0 * tier
	while tier > 1 and stamina < cost:
		tier -= 1
		cost = 10.0 * tier
	if stamina < cost * 0.5:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		charge_cancelled = true
		return
	_spend(cost)
	cast_tier = tier
	cast_done = false
	charge_cancelled = true
	stats["casts"] += 1
	_soft_aim()
	_enter(State.CAST)
	PerfLogger.record_latency(last_input_usec)


func _tick_cast(delta: float) -> Vector3:
	var windup := 0.12 + 0.05 * cast_tier
	_face_target_or(Vector3.ZERO, delta, 16.0)
	if not cast_done and state_time >= windup:
		cast_done = true
		_release_element(cast_tier)
	if state_time >= windup + 0.35:
		_enter(State.MOVE)
	return Vector3.ZERO


func _release_element(tier: int) -> void:
	var fwd := _forward()
	var mult := 1.5 if counter_window > 0.0 else 1.0
	var color: Color = Combat.ELEMENT_COLORS[element]
	var radius: float
	var arc: float
	var dmg: float
	var knock: float
	if element == Combat.Element.FIRE:
		radius = 3.0 + tier * 0.8
		arc = 70.0 + tier * 20.0
		dmg = [0.0, 18.0, 30.0, 55.0][tier]
		knock = 2.0 + tier
		Fx.burst(fx_parent, global_position + fwd * radius * 0.5 + Vector3(0, 0.7, 0), Color(color, 0.8), radius * 0.6, 0.35, Vector3(1, 0.5, 1))
	else:
		radius = 5.0 + tier * 2.0
		arc = 40.0 + tier * 10.0
		dmg = [0.0, 8.0, 14.0, 24.0][tier]
		knock = 6.0 + tier * 4.0
		for i in 3:
			Fx.burst(fx_parent, global_position + fwd * (1.2 + i * radius * 0.3) + Vector3(0, 0.8, 0), Color(color, 0.5), 0.8 + i * 0.3, 0.3)
	for j in get_tree().get_nodes_in_group("jinn"):
		if j.is_dead():
			continue
		if Combat.in_arc(global_position, fwd, j.global_position, radius + j.radius, arc):
			j.take_damage({
				"amount": dmg * mult, "element": element, "from": global_position,
				"knockback": knock, "stagger": tier if element == Combat.Element.WIND else maxi(0, tier - 1),
				"counter": counter_window > 0.0,
			})


func _start_mobility(tier: int) -> void:
	var cost := 22.0 if element == Combat.Element.WIND else 25.0
	if stamina < cost * 0.5:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		charge_cancelled = true
		return
	_spend(cost)
	charge_cancelled = true
	var dir := _move_vector()
	dodge_dir = dir.normalized() if dir.length() > 0.2 else _forward()
	cast_tier = tier
	mobility_hits = []
	dodge_started_at = now
	perfect_used = false
	_enter(State.MOBILITY)
	PerfLogger.record_latency(last_input_usec)


func _tick_mobility() -> Vector3:
	var duration := 0.35 if element == Combat.Element.WIND else 0.3
	var base := 15.0 if element == Combat.Element.WIND else 13.0
	var spd := base * (1.0 + 0.15 * (cast_tier - 1))
	var color: Color = Combat.ELEMENT_COLORS[element]
	if Engine.get_physics_frames() % 3 == 0:
		Fx.burst(fx_parent, global_position + Vector3(0, 0.6, 0), Color(color, 0.45), 0.7, 0.3)
	if element == Combat.Element.FIRE:
		for j in get_tree().get_nodes_in_group("jinn"):
			if j.is_dead() or mobility_hits.has(j):
				continue
			if global_position.distance_to(j.global_position) < 1.3 + j.radius:
				mobility_hits.append(j)
				j.take_damage({"amount": 12.0, "element": Combat.Element.FIRE, "from": global_position, "knockback": 3.0, "stagger": 0})
	if state_time >= duration:
		_enter(State.MOVE)
	return dodge_dir * spd


func _start_defense() -> void:
	var cost := 20.0 if element == Combat.Element.WIND else 25.0
	if stamina < cost * 0.5:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		return
	_spend(cost)
	cast_done = false
	_enter(State.DEFENSE)
	PerfLogger.record_latency(last_input_usec)


func _tick_defense() -> Vector3:
	var color: Color = Combat.ELEMENT_COLORS[element]
	if element == Combat.Element.WIND:
		if not cast_done:
			cast_done = true
			Fx.ring(fx_parent, global_position, Color(color, 0.6), 3.0)
			for j in get_tree().get_nodes_in_group("jinn"):
				if not j.is_dead() and global_position.distance_to(j.global_position) < 3.0 + j.radius:
					j.take_damage({"amount": 4.0, "element": Combat.Element.WIND, "from": global_position, "knockback": 7.0, "stagger": 1})
		if state_time >= 0.5:
			_enter(State.GUARD if dodge_held else State.MOVE)
	else:
		if not cast_done and state_time >= 0.25:
			cast_done = true
			Fx.burst(fx_parent, global_position + Vector3(0, 0.6, 0), Color(color, 0.7), 2.6, 0.35, Vector3(1, 0.5, 1))
			for j in get_tree().get_nodes_in_group("jinn"):
				if not j.is_dead() and global_position.distance_to(j.global_position) < 2.6 + j.radius:
					j.take_damage({"amount": 20.0, "element": Combat.Element.FIRE, "from": global_position, "knockback": 4.0, "stagger": 1})
		if state_time >= 0.55:
			_enter(State.GUARD if dodge_held else State.MOVE)
	return Vector3.ZERO


# --- Damage & stamina -------------------------------------------------------

func _take_damage(amount: float, knock: Vector3, stun: float) -> void:
	hp = maxf(0.0, hp - amount)
	stats["hits_taken"] += 1
	health_changed.emit(hp, max_hp)
	knock_velocity = knock
	model.flash(Color(1, 0.2, 0.2))
	Fx.popup(fx_parent, global_position + Vector3(0, 1.8, 0), str(roundi(amount)), Color(1, 0.4, 0.35))
	if hp <= 0.0:
		_enter(State.DEAD)
		died.emit()
		announced.emit("Defeated", Color(1, 0.4, 0.4))
		return
	hitstun_time = stun
	charge_cancelled = true
	_enter(State.HITSTUN)


func _spend(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	stamina_delay = STAMINA_DELAY
	stamina_changed.emit(stamina, max_stamina)


func _restore_stamina(amount: float) -> void:
	stamina = minf(max_stamina, stamina + amount)
	stamina_changed.emit(stamina, max_stamina)


func _tick_stamina(delta: float) -> void:
	if stamina_delay > 0.0:
		stamina_delay -= delta
		return
	if sprinting or stamina >= max_stamina:
		return
	var rate := STAMINA_REGEN * (0.4 if state == State.GUARD else 1.0)
	_restore_stamina(rate * delta)


# --- Helpers ----------------------------------------------------------------

func _forward() -> Vector3:
	return Combat.flat(-global_transform.basis.z).normalized()


func _move_vector() -> Vector3:
	var input := GameInput.get_move()
	var yaw := camera_rig.yaw if camera_rig else 0.0
	return Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)


func _face_target_or(dir: Vector3, delta: float, rate: float) -> void:
	var look := Vector3.ZERO
	if lock_target and is_instance_valid(lock_target):
		look = Combat.flat(lock_target.global_position - global_position)
	elif dir.length() > 0.1:
		look = dir
	if look.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, Combat.yaw_for(look), 1.0 - exp(-rate * delta))


## Snap toward the lock target, or the nearest jinn in front within 3.5 m.
func _soft_aim() -> void:
	var target: Node3D = lock_target
	if target == null:
		var best_d := 3.5
		for j in get_tree().get_nodes_in_group("jinn"):
			if j.is_dead():
				continue
			var to := Combat.flat(j.global_position - global_position)
			if to.length() < best_d and _forward().angle_to(to.normalized()) < deg_to_rad(75.0):
				best_d = to.length()
				target = j
	if target:
		rotation.y = Combat.yaw_for(Combat.flat(target.global_position - global_position))


func _lock_candidates() -> Array:
	var fwd := -camera_rig.camera.global_transform.basis.z if camera_rig else _forward()
	var list: Array = []
	for j in get_tree().get_nodes_in_group("jinn"):
		if j.is_dead():
			continue
		var to: Vector3 = j.global_position - global_position
		if to.length() <= LOCK_RANGE:
			list.append(j)
	list.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var sa := Combat.flat(fwd).angle_to(Combat.flat(a.global_position - global_position)) + global_position.distance_to(a.global_position) * 0.03
		var sb := Combat.flat(fwd).angle_to(Combat.flat(b.global_position - global_position)) + global_position.distance_to(b.global_position) * 0.03
		return sa < sb)
	return list


func _set_lock(target: Node3D) -> void:
	lock_target = target
	if camera_rig:
		camera_rig.lock_target = target


func _animate(delta: float, horizontal: Vector3) -> void:
	var t := 0.0
	var anim_state := state_name()
	if state == State.ATTACK:
		var total: float = float(current_attack["windup"]) + float(current_attack["active"])
		t = clampf(state_time / total, 0.0, 1.0)
		if is_heavy:
			anim_state = "HEAVY"
	model.animate(delta, {
		"move": clampf(horizontal.length() / (move_speed * SPRINT_MULT), 0.0, 1.0),
		"state": anim_state,
		"t": t,
		"combo": combo_step,
		"charge": charge_progress(),
		"element_color": Combat.ELEMENT_COLORS[element],
	})
