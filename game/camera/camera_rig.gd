class_name CameraRig
extends Node3D
## Third-person orbit camera with Z-target style lock-on.
## Free: swipe / mouse (right button) / right stick orbits the player.
## Locked: yaw swings behind the player toward the target and frames both.

const TOUCH_SENS := 0.0055
const STICK_RATE := 2.6
const MIN_PITCH := -1.05
const MAX_PITCH := 0.30

var follow: Node3D
var lock_target: Node3D
var camera: Camera3D
var yaw: float = 0.0
## Closer and lower than before (owner: "everything feels small"): the
## character fills ~40% of a phone screen instead of under a quarter.
var pitch: float = -0.24
var distance: float = 3.6
var height: float = 1.15
var focus: Vector3 = Vector3.ZERO
var _current_distance: float = 3.6
var _shake: float = 0.0


func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 0.6)


func _ready() -> void:
	top_level = true
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.1
	camera.far = 250.0
	add_child(camera)
	camera.current = true
	if follow:
		focus = follow.global_position + Vector3(0, height, 0)


func _process(delta: float) -> void:
	if follow == null:
		return
	var look := GameInput.consume_look()
	var stick := GameInput.get_look_stick()
	var locked := lock_target != null and is_instance_valid(lock_target)
	var player_pos := follow.get_global_transform_interpolated().origin

	if locked:
		var to := Combat.flat(lock_target.global_position - player_pos)
		if to.length() > 0.3:
			yaw = lerp_angle(yaw, Combat.yaw_for(to), 1.0 - exp(-7.0 * delta))
		pitch = lerpf(pitch, -0.32, 1.0 - exp(-4.0 * delta))
		pitch -= look.y * TOUCH_SENS * 0.3
	else:
		yaw -= look.x * TOUCH_SENS + stick.x * STICK_RATE * delta
		pitch -= look.y * TOUCH_SENS + stick.y * STICK_RATE * 0.6 * delta
	pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)

	focus = focus.lerp(player_pos + Vector3(0, height, 0), 1.0 - exp(-14.0 * delta))
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var dist := distance + (1.0 if locked else 0.0)
	var desired := focus + basis * Vector3(0.0, 0.0, dist)

	# Pull in when a wall is between the player and the camera.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, desired, Combat.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	var target_dist := dist
	if not hit.is_empty():
		target_dist = maxf(0.8, focus.distance_to(hit["position"]) - 0.3)
	_current_distance = lerpf(_current_distance, target_dist, 1.0 - exp(-(25.0 if target_dist < _current_distance else 5.0) * delta))
	camera.global_position = focus + basis * Vector3(0.0, 0.0, _current_distance)

	var look_at_point := focus
	if locked:
		look_at_point = focus.lerp(lock_target.global_position + Vector3(0, 1.1, 0), 0.35)
	if camera.global_position.distance_to(look_at_point) > 0.01:
		camera.look_at(look_at_point, Vector3.UP)
	if _shake > 0.001:
		var s := _shake * _shake
		camera.rotate_object_local(Vector3.RIGHT, randf_range(-1.0, 1.0) * s * 0.08)
		camera.rotate_object_local(Vector3.UP, randf_range(-1.0, 1.0) * s * 0.08)
		camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * s * 0.25
		_shake = maxf(0.0, _shake - delta * 2.2)
