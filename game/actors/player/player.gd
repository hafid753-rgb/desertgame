class_name Player
extends CharacterBody3D
## The playable character. All rules live here so they can later move to the
## server unchanged: inputs in, state out. See README for the control table.
##
## Combat:  Attack tap = combo, hold = heavy.  Dodge tap = dodge, hold = block;
##          block started <=150 ms before a hit = parry.  Hold Special = charge;
##          while holding: Attack = elemental attack, Dodge = elemental mobility.
##          Block + tap Special = elemental defense.
## Travel:  Jump.  Push into a wall = climb (stamina).  Climb past the top =
##          mantle.  In the air, tap Special = open the daraa and glide.

signal health_changed(hp: float, max_hp: float)
signal stamina_changed(stamina: float, max_stamina: float)
signal announced(text: String, color: Color)
signal died

enum State { MOVE, ATTACK, HEAVY_CHARGE, GUARD, DODGE, CAST, MOBILITY, DEFENSE, HITSTUN, DEAD, AIR, CLIMB, MANTLE, GLIDE }

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
const VERTICAL_REACH := 1.8

# Traversal
const JUMP_VELOCITY := 7.2
const COYOTE_TIME := 0.12
const AIR_CONTROL := 0.7
const CLIMB_SPEED := 1.7
const CLIMB_COST := 10.0
const CLIMB_IDLE_COST := 1.5
const CLIMB_START_PUSH := 0.18
const WALL_JUMP_COST := 12.0
const REGRAB_DELAY := 0.6
const MANTLE_TIME := 0.35
const GLIDE_FALL := 1.6
const GLIDE_SPEED := 6.0
const GLIDE_COST := 7.0

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
var climb_mult: float = 1.0
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
var _last_tier_sound: int = 0

var stamina_delay: float = 0.0
var sprint_time: float = 0.0
var sprinting: bool = false
var hitstun_time: float = 0.0
var knock_velocity: Vector3 = Vector3.ZERO
var counter_window: float = 0.0
var element_cooldown: float = 0.0
var last_input_usec: int = 0
var spawn_point: Vector3 = Vector3.ZERO

# Traversal state
var jump_requested: bool = false
var air_time: float = 0.0
var last_floor_time: float = 0.0
var wall_push_time: float = 0.0
var regrab_at: float = 0.0
var climb_normal: Vector3 = Vector3.BACK
var climb_velocity: Vector3 = Vector3.ZERO
var mantle_from: Vector3 = Vector3.ZERO
var mantle_to: Vector3 = Vector3.ZERO
var air_horizontal: Vector3 = Vector3.ZERO
var highest_y: float = 0.0

var camera_rig: CameraRig
var lock_target: Node3D = null
var model: CreatureModel
var fx_parent: Node

## Session stats for the playtest report and the pause screen.
var stats: Dictionary = {
	"parries": 0, "perfect_dodges": 0, "hits_taken": 0, "blocks": 0, "casts": 0,
	"special_cancels": 0, "deaths": 0, "climb_m": 0.0, "glide_s": 0.0, "max_height_m": 0.0,
}


func _ready() -> void:
	add_to_group("player")
	collision_layer = Combat.LAYER_PLAYER
	collision_mask = Combat.LAYER_WORLD | Combat.LAYER_JINN
	floor_snap_length = 0.3
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
	climb_mult = float(species["climb"])
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
	return state == State.MANTLE


func is_airborne() -> bool:
	return state == State.AIR or state == State.GLIDE


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
	if absf(from.y - global_position.y) > VERTICAL_REACH:
		return "none"
	var to_attacker := Combat.flat(from - global_position).normalized()
	var facing_ok := _forward().angle_to(to_attacker) < deg_to_rad(100.0)

	if is_invulnerable():
		if now - dodge_started_at <= PERFECT_DODGE_WINDOW and not perfect_used:
			perfect_used = true
			counter_window = COUNTER_TIME
			stats["perfect_dodges"] += 1
			announced.emit("PERFECT DODGE", Color(0.6, 1.0, 1.0))
			Fx.ring(fx_parent, global_position, Color(0.6, 1.0, 1.0, 0.6), 2.5)
			Juice.play("perfect", global_position)
			Juice.hitstop(0.1)
			return "perfect_dodge"
		return "dodged"

	if state == State.DEFENSE and facing_ok:
		if element == Combat.Element.WIND:
			Fx.burst(fx_parent, global_position + Vector3(0, 0.8, 0), Color(0.6, 0.95, 1.0, 0.5), 1.8)
			Juice.play("wind", global_position, 1.3)
			return "deflected"
		if element == Combat.Element.WATER:
			# Water absorbs one frontal strike and chills its attacker.
			if attacker and attacker.has_method("apply_chill"):
				attacker.apply_chill(2.0, 0.55)
			Fx.ring(fx_parent, global_position, Color(0.48, 0.85, 1.0, 0.75), 2.0)
			return "ice_block"
		if element == Combat.Element.EARTH:
			# Earth is sustain-focused: dampen damage rather than granting immunity.
			_take_damage(dmg * 0.5, -to_attacker * 1.2, 0.2)
			return "earth_guard"

	if (state == State.GUARD or state == State.DEFENSE) and facing_ok:
		guard_absorbed = true
		if state == State.GUARD and now - guard_start <= PARRY_WINDOW:
			counter_window = COUNTER_TIME
			_restore_stamina(10.0)
			stats["parries"] += 1
			announced.emit("PARRY!", Color(1.0, 0.95, 0.5))
			Fx.burst(fx_parent, global_position + _forward() * 0.6 + Vector3(0, 0.8, 0), Color(1, 0.95, 0.6, 0.9), 1.2, 0.2)
			Juice.play("parry", global_position)
			Juice.hitstop(0.12)
			Juice.shake(0.3)
			return "parried"
		var cost := dmg * 1.1
		if stamina >= cost:
			_spend(cost)
			stats["blocks"] += 1
			knock_velocity = -to_attacker * 2.5
			Fx.burst(fx_parent, global_position + _forward() * 0.5 + Vector3(0, 0.8, 0), Color(1, 1, 1, 0.6), 0.6, 0.15)
			Juice.play("block", global_position)
			Juice.shake(0.12)
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
	if is_on_floor():
		last_floor_time = now

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
				_enter(State.AIR if not is_on_floor() else State.MOVE)
		State.DEAD:
			if state_time > 2.5:
				respawn()
		State.AIR:
			horizontal = _tick_air(delta)
		State.GLIDE:
			horizontal = _tick_glide(delta)
		State.CLIMB:
			_tick_climb(delta)
		State.MANTLE:
			_tick_mantle()
			_tick_stamina(delta)
			_animate(delta, Vector3.ZERO)
			return

	if state == State.CLIMB:
		velocity = climb_velocity
	else:
		knock_velocity = knock_velocity.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
		velocity.x = horizontal.x + knock_velocity.x
		velocity.z = horizontal.z + knock_velocity.z
		if jump_requested:
			velocity.y = JUMP_VELOCITY
			jump_requested = false
		elif is_on_floor() and velocity.y <= 0.0:
			velocity.y = -0.5
		else:
			velocity.y -= GRAVITY * delta
			if state == State.GLIDE:
				velocity.y = maxf(velocity.y, -GLIDE_FALL)
	var was_airborne := is_airborne()
	var fall_speed := -velocity.y
	move_and_slide()
	if global_position.y < -10.0:
		respawn()
	if was_airborne and is_on_floor() and state_time > 0.05:
		_land(fall_speed)
	highest_y = maxf(highest_y, global_position.y)
	stats["max_height_m"] = maxf(float(stats["max_height_m"]), global_position.y)

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
		"jump":
			if pressed:
				last_input_usec = t_usec
				_on_jump_pressed()
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
			if state_time >= float(current_attack["windup"]) + float(current_attack["active"]):
				_start_guard()
			else:
				buffered_dodge_t = now
		State.CLIMB:
			_let_go(false)
		State.GLIDE:
			_enter(State.AIR)
		_:
			buffered_dodge_t = now


func _on_special_pressed() -> void:
	special_start = now
	_last_tier_sound = 0
	match state:
		State.GUARD:
			charge_cancelled = true
			_start_defense()
			return
		State.AIR:
			charge_cancelled = true
			_start_glide()
			return
		State.GLIDE:
			charge_cancelled = true
			_enter(State.AIR)
			return
	charge_cancelled = state != State.MOVE


func _on_jump_pressed() -> void:
	match state:
		State.MOVE:
			if now - last_floor_time <= COYOTE_TIME:
				_jump()
		State.CLIMB:
			_let_go(true)
		State.GLIDE:
			_enter(State.AIR)


func _toggle_element() -> void:
	if element_cooldown > 0.0 or state != State.MOVE:
		return
	var idx := Combat.PLAYABLE_ELEMENTS.find(element)
	element = Combat.PLAYABLE_ELEMENTS[(idx + 1) % Combat.PLAYABLE_ELEMENTS.size()]
	element_cooldown = 0.5
	announced.emit("%s element" % Combat.ELEMENT_NAMES[element], Combat.ELEMENT_COLORS[element])


# --- Ground states ----------------------------------------------------------

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
	if not is_on_floor() and now - last_floor_time > COYOTE_TIME:
		air_horizontal = Combat.flat(velocity)
		_enter(State.AIR)
		return air_horizontal
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
	_play_charge_ticks()
	# Push into a wall for a moment to start climbing.
	if dir.length() > 0.5 and not is_charging() and now >= regrab_at:
		var wall := _wall_ray(dir.normalized())
		if not wall.is_empty() and dir.normalized().dot(-wall["normal"]) > 0.7:
			wall_push_time += delta
			if wall_push_time >= CLIMB_START_PUSH:
				_start_climb(wall["normal"])
		else:
			wall_push_time = 0.0
	else:
		wall_push_time = 0.0
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
	Juice.play("swing", global_position, 0.8 if heavy else 1.0 + combo_step * 0.08)
	PerfLogger.record_latency(last_input_usec)


func _tick_attack(_delta: float) -> Vector3:
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
	for j in _jinn_in_reach():
		if Combat.in_arc(global_position, _forward(), j.global_position, float(atk["range"]) + j.radius, float(atk["arc"])):
			j.take_damage({
				"amount": dmg, "element": Combat.Element.NONE, "from": global_position,
				"knockback": 5.0 if is_heavy else 1.5, "stagger": int(atk["stagger"]), "counter": counter_window > 0.0,
			})
			hit_any = true
	if hit_any:
		Fx.burst(fx_parent, global_position + _forward() * 1.4 + Vector3(0, 0.9, 0), Color(1, 1, 0.9, 0.8), 0.7, 0.12)
		Juice.play("hit", global_position, 0.85 if is_heavy else 1.0)
		Juice.hitstop(0.09 if is_heavy else 0.045)
		Juice.shake(0.25 if is_heavy else 0.1)


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
	Juice.play("dodge", global_position)


func _tick_dodge() -> Vector3:
	var k := clampf(1.0 - state_time / DODGE_TIME, 0.0, 1.0)
	var back := dodge_dir.dot(_forward()) < -0.7
	var spd := DODGE_SPEED * (0.75 if back else 1.0) * sqrt(k)
	if state_time >= DODGE_TIME:
		_enter(State.MOVE)
	return dodge_dir * spd


func _play_charge_ticks() -> void:
	var tier := charge_tier()
	if tier > _last_tier_sound:
		_last_tier_sound = tier
		Juice.play("tier%d" % tier, null)


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


func _heal(amount: float) -> float:
	var before := hp
	hp = minf(max_hp, hp + amount)
	var restored := hp - before
	if restored > 0.0:
		health_changed.emit(hp, max_hp)
		Fx.popup(fx_parent, global_position + Vector3(0, 1.9, 0), "+%d" % roundi(restored), Combat.ELEMENT_COLORS[Combat.Element.EARTH])
	return restored


func _release_element(tier: int) -> void:
	var fwd := _forward()
	var mult := 1.5 if counter_window > 0.0 else 1.0
	var color: Color = Combat.ELEMENT_COLORS[element]
	var radius := 0.0
	var arc := 0.0
	var dmg := 0.0
	var knock := 0.0
	var stagger := 0
	match element:
		Combat.Element.FIRE:
			radius = 3.0 + tier * 0.8
			arc = 70.0 + tier * 20.0
			dmg = [0.0, 18.0, 30.0, 55.0][tier]
			knock = 2.0 + tier
			stagger = maxi(0, tier - 1)
			Fx.burst(fx_parent, global_position + fwd * radius * 0.5 + Vector3(0, 0.7, 0), Color(color, 0.8), radius * 0.6, 0.35, Vector3(1, 0.5, 1))
			Juice.play("fire", global_position, 1.1 - tier * 0.08)
		Combat.Element.WIND:
			radius = 5.0 + tier * 2.0
			arc = 40.0 + tier * 10.0
			dmg = [0.0, 8.0, 14.0, 24.0][tier]
			knock = 6.0 + tier * 4.0
			stagger = tier
			for i in 3:
				Fx.burst(fx_parent, global_position + fwd * (1.2 + i * radius * 0.3) + Vector3(0, 0.8, 0), Color(color, 0.5), 0.8 + i * 0.3, 0.3)
			Juice.play("wind", global_position, 1.0 + tier * 0.1)
		Combat.Element.WATER:
			# Water is crowd control, not a second damage-focused fire spell.
			radius = 3.5 + tier * 0.8
			arc = 100.0 + tier * 15.0
			dmg = [0.0, 6.0, 10.0, 15.0][tier]
			knock = 0.5
			Fx.ring(fx_parent, global_position + fwd * 1.2, Color(color, 0.75), radius, 0.4)
			Juice.play("wind", global_position, 0.65)
		Combat.Element.EARTH:
			# Prototype heals the caster; party healing comes with multiplayer.
			var restored := _heal([0.0, 18.0, 32.0, 48.0][tier])
			Fx.ring(fx_parent, global_position, Color(color, 0.7), 1.5 + tier * 0.6)
			announced.emit("Earth restored %d HP" % roundi(restored), color)
			_affect_physics_props(Combat.Element.EARTH, 2.0 + tier, 3.0 * tier, fwd, 360.0)
			return
	Juice.shake(0.1 * tier)
	for j in _jinn_in_reach():
		if Combat.in_arc(global_position, fwd, j.global_position, radius + j.radius, arc):
			j.take_damage({
				"amount": dmg * mult, "element": element, "from": global_position,
				"knockback": knock, "stagger": stagger,
				"chill_seconds": 1.0 + tier * 0.7 if element == Combat.Element.WATER else 0.0,
				"counter": counter_window > 0.0,
			})
	_affect_physics_props(element, radius, (8.0 + 6.0 * tier), fwd, arc)


## Server-friendly element/rigid-body interface. Only nearby props are touched.
func _affect_physics_props(e: int, radius: float, force: float, forward: Vector3, arc: float) -> void:
	for node in get_tree().get_nodes_in_group("elemental_props"):
		var prop := node as ElementalProp
		if prop == null:
			continue
		if Combat.in_arc(global_position, forward, prop.global_position, radius, arc):
			prop.receive_element(e, Combat.flat(prop.global_position - global_position) + Vector3.UP * 0.25, force)


func _start_mobility(tier: int) -> void:
	var cost := 22.0
	match element:
		Combat.Element.FIRE: cost = 25.0
		Combat.Element.WATER: cost = 18.0
		Combat.Element.EARTH: cost = 20.0
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
	if element == Combat.Element.WIND or element == Combat.Element.WATER:
		Juice.play("wind", global_position, 1.4)
	elif element == Combat.Element.FIRE:
		Juice.play("fire", global_position, 1.4)
	PerfLogger.record_latency(last_input_usec)


func _tick_mobility() -> Vector3:
	# Water slide / Earth sand-wave are greybox bursts until equipment and terrain
	# material systems exist; no persistent ice or sand geometry is created.
	var duration := 0.35
	var base := 15.0
	match element:
		Combat.Element.FIRE:
			duration = 0.3
			base = 13.0
		Combat.Element.WATER:
			duration = 0.5
			base = 11.0
		Combat.Element.EARTH:
			duration = 0.65
			base = 9.0
	var spd := base * (1.0 + 0.15 * (cast_tier - 1))
	var color: Color = Combat.ELEMENT_COLORS[element]
	if Engine.get_physics_frames() % 3 == 0:
		Fx.burst(fx_parent, global_position + Vector3(0, 0.6, 0), Color(color, 0.45), 0.7, 0.3)
	if element == Combat.Element.FIRE:
		for j in _jinn_in_reach():
			if mobility_hits.has(j):
				continue
			if global_position.distance_to(j.global_position) < 1.3 + j.radius:
				mobility_hits.append(j)
				j.take_damage({"amount": 12.0, "element": Combat.Element.FIRE, "from": global_position, "knockback": 3.0, "stagger": 0})
	if state_time >= duration:
		_enter(State.MOVE)
	return dodge_dir * spd


func _start_defense() -> void:
	var cost := 25.0 if element == Combat.Element.FIRE else 20.0
	if stamina < cost * 0.5:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		return
	_spend(cost)
	cast_done = false
	_enter(State.DEFENSE)
	PerfLogger.record_latency(last_input_usec)


func _tick_defense() -> Vector3:
	var color: Color = Combat.ELEMENT_COLORS[element]
	match element:
		Combat.Element.WIND:
			if not cast_done:
				cast_done = true
				Fx.ring(fx_parent, global_position, Color(color, 0.6), 3.0)
				Juice.play("wind", global_position, 1.5)
				for j in _jinn_in_reach():
					if global_position.distance_to(j.global_position) < 3.0 + j.radius:
						j.take_damage({"amount": 4.0, "element": Combat.Element.WIND, "from": global_position, "knockback": 7.0, "stagger": 1})
		Combat.Element.FIRE:
			if not cast_done and state_time >= 0.25:
				cast_done = true
				Fx.burst(fx_parent, global_position + Vector3(0, 0.6, 0), Color(color, 0.7), 2.6, 0.35, Vector3(1, 0.5, 1))
				Juice.play("fire", global_position, 1.2)
				for j in _jinn_in_reach():
					if global_position.distance_to(j.global_position) < 2.6 + j.radius:
						j.take_damage({"amount": 20.0, "element": Combat.Element.FIRE, "from": global_position, "knockback": 4.0, "stagger": 1})
		Combat.Element.WATER:
			if not cast_done:
				cast_done = true
				Fx.ring(fx_parent, global_position, Color(color, 0.75), 1.8, 0.45)
		Combat.Element.EARTH:
			if not cast_done:
				cast_done = true
				_heal(8.0)
				Fx.ring(fx_parent, global_position, Color(color, 0.7), 1.6, 0.5)
	if state_time >= 0.55:
		_enter(State.GUARD if dodge_held else State.MOVE)
	return Vector3.ZERO

# --- Traversal --------------------------------------------------------------

func _jump() -> void:
	jump_requested = true
	air_horizontal = _move_vector() * move_speed * (SPRINT_MULT if sprinting else 1.0)
	last_floor_time = -10.0
	_enter(State.AIR)
	Juice.play("jump", global_position)


func _tick_air(delta: float) -> Vector3:
	var dir := _move_vector()
	var target := dir * move_speed
	if air_horizontal.length() > target.length() and dir.dot(air_horizontal) > 0.0:
		target = dir.normalized() * air_horizontal.length() if dir.length() > 0.1 else air_horizontal
	air_horizontal = air_horizontal.lerp(target, 1.0 - exp(-AIR_CONTROL * 4.0 * delta))
	_face_target_or(air_horizontal, delta, 8.0)
	# Grab a wall we are flying into.
	if now >= regrab_at and dir.length() > 0.4 and stamina > 1.0:
		var wall := _wall_ray(dir.normalized())
		if not wall.is_empty() and dir.normalized().dot(-wall["normal"]) > 0.6:
			_start_climb(wall["normal"])
	return air_horizontal


func _land(fall_speed: float) -> void:
	if state == State.AIR or state == State.GLIDE:
		_enter(State.MOVE)
	if fall_speed > 6.0:
		Juice.play("land", global_position, 1.0, -4.0 + minf(6.0, fall_speed * 0.3))
		Fx.ring(fx_parent, global_position, Color(0.9, 0.8, 0.6, 0.5), 1.2, 0.25)
	# Long unbroken falls hurt (gliding avoids it).
	if fall_speed > 17.0:
		var dmg := (fall_speed - 17.0) * 6.0
		_take_damage(dmg, Vector3.ZERO, 0.5)


func _start_glide() -> void:
	if stamina < 3.0:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		return
	air_horizontal = _forward() * GLIDE_SPEED if air_horizontal.length() < 1.0 else air_horizontal
	_enter(State.GLIDE)
	Juice.play("glide", global_position)


func _tick_glide(delta: float) -> Vector3:
	var dir := _move_vector()
	var heading := air_horizontal.normalized() if air_horizontal.length() > 0.1 else _forward()
	if dir.length() > 0.1:
		heading = heading.slerp(dir.normalized(), 1.0 - exp(-2.5 * delta)).normalized()
	var speed := lerpf(air_horizontal.length(), GLIDE_SPEED * (1.0 + 0.3 * dir.length()), 1.0 - exp(-2.0 * delta))
	air_horizontal = heading * speed
	_face_target_or(air_horizontal, delta, 6.0)
	_spend(GLIDE_COST * delta)
	stats["glide_s"] += delta
	if stamina <= 0.0:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		_enter(State.AIR)
	if Engine.get_physics_frames() % 6 == 0:
		var side := heading.cross(Vector3.UP) * (0.9 if Engine.get_physics_frames() % 12 == 0 else -0.9)
		Fx.burst(fx_parent, global_position + Vector3(0, 1.0, 0) + side - heading * 0.6, Color(0.75, 0.92, 1.0, 0.2), 0.25, 0.5)
	if now >= regrab_at and dir.length() > 0.4:
		var wall := _wall_ray(dir.normalized())
		if not wall.is_empty() and dir.normalized().dot(-wall["normal"]) > 0.6:
			_start_climb(wall["normal"])
	return air_horizontal


func _start_climb(normal: Vector3) -> void:
	if stamina < 1.0:
		return
	climb_normal = Combat.flat(normal).normalized()
	wall_push_time = 0.0
	velocity = Vector3.ZERO
	rotation.y = Combat.yaw_for(-climb_normal)
	_set_lock(null)
	_enter(State.CLIMB)
	Juice.play("grab", global_position)


func _tick_climb(delta: float) -> void:
	var input := GameInput.get_move()
	rotation.y = lerp_angle(rotation.y, Combat.yaw_for(-climb_normal), 1.0 - exp(-12.0 * delta))
	var right := (-climb_normal).cross(Vector3.UP).normalized()
	var spd := CLIMB_SPEED * climb_mult
	var up_in := -input.y
	climb_velocity = right * input.x * spd + Vector3.UP * up_in * spd - climb_normal * 0.8
	var moving := input.length() > 0.15
	_spend((CLIMB_COST if moving else CLIMB_IDLE_COST) * delta)
	if up_in > 0.0:
		stats["climb_m"] += up_in * spd * delta
	if stamina <= 0.0:
		announced.emit("Out of stamina", Color(1, 0.6, 0.5))
		_let_go(false)
		return
	# Keep the wall under our hands; follow its normal around corners.
	var chest := _wall_ray(-climb_normal)
	if chest.is_empty():
		var head_low := _wall_ray(-climb_normal, 0.3)
		if head_low.is_empty():
			_let_go(false)
		return
	climb_normal = Combat.flat(chest["normal"]).normalized()
	# Reached the top: the head ray finds no wall but the chest ray does.
	if up_in > 0.1 and _wall_ray(-climb_normal, 1.55).is_empty():
		_try_mantle()
		return
	# Back on the ground and pulling down: step off.
	if is_on_floor() and up_in < -0.5:
		_enter(State.MOVE)


func _try_mantle() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 2.4 - climb_normal * 0.7
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.6, Combat.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit["normal"].y < 0.7:
		return
	mantle_from = global_position
	mantle_to = hit["position"] + Vector3(0, 0.05, 0)
	_enter(State.MANTLE)
	Juice.play("grab", global_position, 1.2)


func _tick_mantle() -> void:
	var p := clampf(state_time / MANTLE_TIME, 0.0, 1.0)
	var up := clampf(p / 0.6, 0.0, 1.0)
	var fwd := clampf((p - 0.4) / 0.6, 0.0, 1.0)
	var pos := mantle_from
	pos.y = lerpf(mantle_from.y, mantle_to.y, up)
	pos.x = lerpf(mantle_from.x, mantle_to.x, fwd)
	pos.z = lerpf(mantle_from.z, mantle_to.z, fwd)
	global_position = pos
	velocity = Vector3.ZERO
	if p >= 1.0:
		last_floor_time = now
		_enter(State.MOVE)


func _let_go(jump_off: bool) -> void:
	regrab_at = now + REGRAB_DELAY
	if jump_off and stamina >= WALL_JUMP_COST * 0.5:
		_spend(WALL_JUMP_COST)
		air_horizontal = climb_normal * 4.0
		velocity.y = 5.0
		Juice.play("jump", global_position)
	else:
		air_horizontal = climb_normal * 1.2
		velocity.y = 0.0
	_enter(State.AIR)


## Ray from the player's body along `dir` against the world. `height_offset`
## raises the ray above chest height (0.9 m). Returns {} or the hit with a
## mostly vertical surface.
func _wall_ray(dir: Vector3, height_offset: float = 0.0) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * (0.9 + height_offset)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.75, Combat.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or absf(hit["normal"].y) > 0.3:
		return {}
	return hit


# --- Damage & stamina -------------------------------------------------------

func _take_damage(amount: float, knock: Vector3, stun: float) -> void:
	hp = maxf(0.0, hp - amount)
	stats["hits_taken"] += 1
	health_changed.emit(hp, max_hp)
	knock_velocity = knock
	model.flash(Color(1, 0.2, 0.2))
	Fx.popup(fx_parent, global_position + Vector3(0, 1.8, 0), str(roundi(amount)), Color(1, 0.4, 0.35))
	Juice.play("hurt", global_position)
	Juice.shake(0.35)
	if hp <= 0.0:
		stats["deaths"] += 1
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
	if sprinting or stamina >= max_stamina or state in [State.CLIMB, State.GLIDE, State.MANTLE]:
		return
	if state == State.AIR:
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


func _jinn_in_reach() -> Array:
	var out: Array = []
	for j in get_tree().get_nodes_in_group("jinn"):
		if not j.is_dead() and absf(j.global_position.y - global_position.y) <= VERTICAL_REACH:
			out.append(j)
	return out


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
		for j in _jinn_in_reach():
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
	elif state == State.CLIMB:
		t = climb_velocity.y
	model.animate(delta, {
		"move": clampf(horizontal.length() / (move_speed * SPRINT_MULT), 0.0, 1.0),
		"state": anim_state,
		"t": t,
		"combo": combo_step,
		"charge": charge_progress(),
		"element_color": Combat.ELEMENT_COLORS[element],
	})
