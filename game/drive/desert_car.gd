class_name DesertCar
extends Node3D
## Arcade top-down car for the driving test. Not a physics body: it rides
## the ground by raycasts at the four wheels (dunes, slopes, the pond bed),
## and its handling is a simple slip model tuned for loose sand:
##   * engine force along the heading, rolling drag
##   * lateral grip that lets the tail step out (handbrake = big drift)
##   * surfaces: sand, water (heavy drag, spray, ripples), soft sand (wheels
##     spin, the car digs in and stops: stuck)
## It joins the "player" group so the shared systems follow it: the sand
## interaction mask (tyre grooves), grass parting, the oasis splash/ripples.
## `velocity` is exposed for those systems.

signal stuck_changed(stuck: bool)

var velocity := Vector3.ZERO
var yaw := 0.0
var yaw_rate := 0.0
var throttle := 0.0
var steer := 0.0
var handbrake := false
var autopilot: Callable          # returns [throttle, steer, handbrake] (teaser)
var oasis: Oasis
## Soft-sand pits: [centre (Vector3), radius]
var soft_pits: Array = []
var stuck := false
var sink := 0.0
var in_water := false
var on_soft := false

var body: MeshInstance3D
var wheels: Array[Node3D] = []
var _wheel_spin := 0.0
var _steer_vis := 0.0
var _pitch := 0.0
var _roll := 0.0
var _ground_y := 0.0
var _prev_wheel_world: Array[Vector3] = []
var _dust: Array[CPUParticles3D] = []
var _spray: CPUParticles3D
var _roost: CPUParticles3D
var _ripple_cd := 0.0
var _stuck_t := 0.0

const ENGINE := 12.0
const REVERSE := 6.0
const DRAG := 0.28
const GRIP := 3.4
const GRIP_HANDBRAKE := 0.5
const TURN := 2.3
const MAX_SPEED := 22.0


func _ready() -> void:
	add_to_group("player")
	var mat := CharacterArt.toon_material(Color(0.12, 0.08, 0.07), 0.0, "gloss")
	body = MeshInstance3D.new()
	body.mesh = VoxelCar.body_mesh()
	body.material_override = mat
	add_child(body)
	var wmat := CharacterArt.toon_material(Color(0.1, 0.08, 0.07), 0.0, "leather")
	var wm := VoxelCar.wheel_mesh()
	var i := 0
	for p in VoxelCar.wheel_positions():
		var pivot := Node3D.new()       # steering pivot
		pivot.position = p
		add_child(pivot)
		var w := MeshInstance3D.new()
		w.mesh = wm
		w.material_override = wmat
		if p.x > 0.0:
			w.scale = Vector3(-1, 1, 1)
		pivot.add_child(w)
		wheels.append(pivot)
		_prev_wheel_world.append(Vector3.ZERO)
		if i >= 2:
			_dust.append(_make_dust(Color(0.98, 0.78, 0.64), Color(0.88, 0.62, 0.5), 60, 0.55))
		i += 1
	_spray = _make_dust(Color(0.93, 0.95, 0.9), Color(0.55, 0.72, 0.72), 90, 0.22)
	_spray.gravity = Vector3(0, -6.0, 0)
	_spray.initial_velocity_min = 2.5
	_spray.initial_velocity_max = 5.0
	_spray.spread = 55.0
	_spray.lifetime = 0.9
	_roost = _make_dust(Color(0.95, 0.72, 0.56), Color(0.8, 0.55, 0.42), 120, 0.4)
	_roost.gravity = Vector3(0, -4.0, 0)
	_roost.initial_velocity_min = 3.0
	_roost.initial_velocity_max = 6.0
	_roost.spread = 22.0
	_roost.lifetime = 1.3
	yaw = rotation.y


func _make_dust(lit: Color, shade: Color, amount: int, size: float) -> CPUParticles3D:
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/dust_dither.gdshader")
	m.set_shader_parameter("quad_size", size)
	m.set_shader_parameter("lit", lit)
	m.set_shader_parameter("shade", shade)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 2.6))
	var p := CPUParticles3D.new()
	p.top_level = true
	p.mesh = q
	p.amount = amount
	p.lifetime = 1.6
	p.local_coords = false
	p.emitting = false
	p.spread = 30.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -0.5, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.color_ramp = fade
	p.scale_amount_curve = grow
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _read_input() -> void:
	if autopilot.is_valid():
		var a: Array = autopilot.call()
		throttle = a[0]
		steer = a[1]
		handbrake = a[2]
		return
	var mv: Vector2 = GameInput.touch_move
	throttle = clampf(Input.get_axis("ui_down", "ui_up") - mv.y, -1.0, 1.0)
	steer = clampf(Input.get_axis("ui_left", "ui_right") + mv.x, -1.0, 1.0)
	handbrake = Input.is_action_pressed("ui_accept")


func _physics_process(delta: float) -> void:
	_read_input()
	var pos := global_position
	in_water = oasis != null and oasis.is_water(pos)
	on_soft = false
	for pit in soft_pits:
		if Vector2(pos.x - pit[0].x, pos.z - pit[0].z).length() < pit[1]:
			on_soft = true
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var vl := velocity.dot(fwd)
	var vt := velocity.dot(right)
	var power := ENGINE
	var drag := DRAG
	var grip := GRIP_HANDBRAKE if handbrake else GRIP
	if in_water:
		power *= 0.45
		drag += 1.1
		grip = maxf(grip, 2.0)
	if on_soft:
		# the wheels dig instead of driving: power goes into spin
		power *= 0.08
		drag += 2.6 + sink * 10.0
		grip = 6.0
	var push := throttle * (power if throttle >= 0.0 else REVERSE)
	if handbrake:
		push *= 0.4
		drag += 0.35
	vl += push * delta
	vl -= vl * drag * delta
	vl = clampf(vl, -8.0, MAX_SPEED)
	vt *= exp(-grip * delta)
	# steering: needs speed, reverses in reverse; handbrake swings the tail
	var speed_k := clampf(absf(vl) / 6.0, 0.0, 1.0) * signf(vl if absf(vl) > 0.1 else 1.0)
	var target_rate := -steer * TURN * speed_k * (1.8 if handbrake else 1.0)
	if on_soft:
		target_rate *= 0.2
	yaw_rate = lerpf(yaw_rate, target_rate, 1.0 - exp(-(5.0 if handbrake else 8.0) * delta))
	yaw += yaw_rate * delta
	velocity = fwd * vl + right * vt
	velocity.y = 0.0
	pos += velocity * delta
	# ride the ground: four wheel rays
	var hits: Array[float] = []
	var basis_now := Basis(Vector3.UP, yaw)
	for p in VoxelCar.wheel_positions():
		var wp := pos + basis_now * Vector3(p.x, 0, p.z)
		hits.append(_ground_at(wp))
	var gy := (hits[0] + hits[1] + hits[2] + hits[3]) * 0.25
	var front := (hits[0] + hits[1]) * 0.5
	var rear := (hits[2] + hits[3]) * 0.5
	var left := (hits[0] + hits[2]) * 0.5
	var rgt := (hits[1] + hits[3]) * 0.5
	var wb := absf(VoxelCar.wheel_positions()[0].z - VoxelCar.wheel_positions()[2].z)
	var tr := absf(VoxelCar.wheel_positions()[0].x * 2.0)
	var k := 1.0 - exp(-12.0 * delta)
	_ground_y = lerpf(_ground_y, gy, k)
	# stuck: sink into the soft sand while the wheels spin
	if on_soft and absf(throttle) > 0.2:
		sink = minf(sink + delta * 0.09, 0.26)
	pos.y = _ground_y - sink
	# body attitude: slope + weight transfer (squat, nose dive, lean out of turns)
	var slope_pitch := atan2(front - rear, wb)
	var slope_roll := atan2(rgt - left, tr)
	var accel_pitch := clampf(-push * 0.006, -0.06, 0.06)
	var lean := clampf(vt * 0.025 + yaw_rate * vl * 0.004, -0.12, 0.12)
	_pitch = lerpf(_pitch, slope_pitch + accel_pitch, 1.0 - exp(-8.0 * delta))
	_roll = lerpf(_roll, slope_roll - lean, 1.0 - exp(-8.0 * delta))
	global_position = pos
	rotation = Vector3(_pitch, yaw, _roll)
	if on_soft and absf(throttle) > 0.2 and Vector2(velocity.x, velocity.z).length() < 1.2:
		_stuck_t += delta
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta)
	var now_stuck := _stuck_t > 0.6
	if now_stuck != stuck:
		stuck = now_stuck
		stuck_changed.emit(stuck)
	_wheels_and_fx(delta, vl, vt)


func _ground_at(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 6.0, p - Vector3.UP * 3.0, 1)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


func _wheels_and_fx(delta: float, vl: float, vt: float) -> void:
	var r := VoxelCar.WHEEL_R * VoxelCar.VOX
	var spin_rate := vl / r
	var spinning := (on_soft and absf(throttle) > 0.2) or (handbrake == false and throttle > 0.8 and absf(vl) < 4.0)
	if spinning:
		spin_rate = 28.0 * signf(throttle)
	_wheel_spin += spin_rate * delta
	_steer_vis = lerpf(_steer_vis, -steer * 0.5, 1.0 - exp(-10.0 * delta))
	for i in wheels.size():
		var piv := wheels[i]
		piv.rotation.y = _steer_vis if i < 2 else 0.0
		(piv.get_child(0) as Node3D).rotation.x = -_wheel_spin
	var speed := Vector2(velocity.x, velocity.z).length()
	var slip := absf(vt)
	# tyre grooves in the sand (not in the water)
	var sfx := get_tree().get_first_node_in_group("sand_fx")
	for i in wheels.size():
		var wp := wheels[i].global_position
		wp.y = global_position.y
		if sfx and not in_water and _prev_wheel_world[i] != Vector3.ZERO and _prev_wheel_world[i].distance_to(wp) > 0.05:
			sfx.groove(_prev_wheel_world[i], wp, 0.24, 1.0 if not on_soft else 1.0)
		_prev_wheel_world[i] = wp
	# dust behind the rear wheels: speed + slide
	for j in _dust.size():
		var d := _dust[j]
		var w := wheels[2 + j].global_position
		d.global_position = Vector3(w.x, global_position.y + 0.12, w.z)
		d.emitting = not in_water and (speed > 3.0 or slip > 1.5 or spinning)
		d.speed_scale = clampf(0.6 + (speed + slip * 2.0) / 16.0, 0.6, 1.6)
		var back := -Vector3(-sin(yaw), 0, -cos(yaw))
		d.direction = (back + Vector3(0, 0.7, 0) + Vector3(cos(yaw), 0, -sin(yaw)) * signf(vt) * 0.6).normalized()
	# water: spray from the wheels + rings on the pond
	_spray.emitting = in_water and speed > 1.0
	_spray.global_position = global_position + Vector3(0, 0.15, 0)
	_spray.speed_scale = clampf(speed / 8.0, 0.5, 1.6)
	if in_water and oasis:
		_ripple_cd -= delta
		if _ripple_cd <= 0.0:
			oasis.ripple(global_position, clampf(speed / 8.0, 0.4, 1.0))
			_ripple_cd = 0.12
	# stuck: rooster tails of sand thrown back by the spinning rear wheels
	_roost.emitting = spinning and on_soft
	if _roost.emitting:
		var back := -Vector3(-sin(yaw), 0, -cos(yaw)) * signf(throttle)
		var rc := (wheels[2].global_position + wheels[3].global_position) * 0.5
		_roost.global_position = rc + Vector3(0, -0.1, 0)
		_roost.direction = (back + Vector3(0, 0.9, 0)).normalized()
		if sfx and Engine.get_physics_frames() % 10 == 0:
			sfx.crater(wheels[2].global_position, 0.35, 0.8, 0.9)
			sfx.crater(wheels[3].global_position, 0.35, 0.8, 0.9)
