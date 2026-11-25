class_name Fireball
extends Node3D
## Jinn fireball: thrown at the player, curves gently toward them, bursts on
## contact with the player or the world. Blockable and parryable through the
## player's normal receive_attack rules.

const SPEED := 10.5
const TURN := 1.6        # rad/s of homing
const LIFE := 3.0
const HIT_RADIUS := 0.65

var atk: Dictionary
var target: Player
var dir := Vector3.FORWARD
var fx_parent: Node
var _t := 0.0
var _trail: CPUParticles3D
var _light: OmniLight3D
var _done := false


static func spawn(parent: Node, at: Vector3, direction: Vector3, attack: Dictionary, who: Player, scale: float = 1.0) -> Fireball:
	var f := Fireball.new()
	f.atk = attack
	f.target = who
	f.dir = direction.normalized()
	f.fx_parent = parent
	parent.add_child(f)
	f.global_position = at
	f.scale = Vector3.ONE * scale
	return f


func _ready() -> void:
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	sm.radial_segments = 12
	sm.rings = 6
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.0, 0.92, 0.6)
	core.material_override = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	halo.mesh = q
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_texture = JinnLook.glow_texture()
	hm.albedo_color = Color(1.0, 0.45, 0.12)
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	_trail = CPUParticles3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(0.45, 0.45)
	# Phase 4: pixel-art flame puffs (world-texel discs, dithered fade)
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://game/shaders/dust_dither.gdshader")
	pm.set_shader_parameter("lit", Color(1.0, 0.96, 0.72))
	pm.set_shader_parameter("shade", Color(1.0, 0.52, 0.22))
	pm.set_shader_parameter("quad_size", 0.45)
	pq.material = pm
	_trail.mesh = pq
	_trail.amount = 24
	_trail.lifetime = 0.45
	_trail.local_coords = false
	_trail.spread = 180.0
	_trail.initial_velocity_min = 0.2
	_trail.initial_velocity_max = 0.8
	_trail.gravity = Vector3(0, 1.2, 0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	ramp.set_color(1, Color(0.4, 0.05, 0.02, 0.0))
	ramp.add_point(0.4, Color(1.0, 0.35, 0.08, 0.6))
	_trail.color_ramp = ramp
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1.0))
	shrink.add_point(Vector2(1, 0.2))
	_trail.scale_amount_curve = shrink
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 1.4
	_light.omni_range = 4.0
	add_child(_light)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if target and is_instance_valid(target) and not target.is_dead():
		var want := (target.global_position + Vector3(0, 0.9, 0) - global_position).normalized()
		var ang := dir.angle_to(want)
		if ang > 0.001:
			var axis := dir.cross(want).normalized()
			if axis.length() > 0.5:
				dir = dir.rotated(axis, minf(ang, TURN * delta))
	var step := dir * SPEED * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step, Combat.LAYER_WORLD)
	if not space.intersect_ray(q).is_empty():
		_explode()
		return
	global_position += step
	if target and is_instance_valid(target) and global_position.distance_to(target.global_position + Vector3(0, 0.9, 0)) < HIT_RADIUS:
		target.receive_attack(atk, self)
		_explode()
		return
	if _t > LIFE:
		_explode()


func _explode() -> void:
	_done = true
	Fx.burst(fx_parent, global_position, Color(1.0, 0.5, 0.15, 0.8), 1.3, 0.3)
	Fx.ring(fx_parent, global_position - Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.2, 0.5), 1.4, 0.3)
	Juice.play("fire", global_position)
	queue_free()
