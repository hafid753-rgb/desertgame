class_name GroundFX
extends Node3D
## Traces left in the sand: boot prints from the player's footsteps,
## resampled on the world texel grid and eroded by the wind (see
## footprint.gdshader). A ring buffer of MultiMesh instances, no per-frame
## CPU work. Water bodies (group "water", is_water()) take no prints.

const MAX_PRINTS := 160

var _mm: MultiMesh
var _i := 0
var count := 0


func _ready() -> void:
	add_to_group("ground_fx")
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.46, 0.46)
	_mm.mesh = pm
	_mm.instance_count = MAX_PRINTS
	for i in MAX_PRINTS:
		_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -50, 0)))
		_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/footprint.gdshader")
	m.set_shader_parameter("tex", load("res://game/art/pixel/fx_footprint.png"))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-500, -60, -500), Vector3(1000, 120, 1000))
	add_child(mi)


## A boot print at `pos` (ground height), facing `yaw` (radians, model
## forward = -Z rotated by yaw), `right` foot or left, `depth` 0..1.
func step(pos: Vector3, yaw: float, right: bool, depth: float = 1.0) -> void:
	for w in get_tree().get_nodes_in_group("water"):
		if w.has_method("is_water") and w.is_water(pos):
			return
	# on sand the print is a real dent in the interaction mask (spec 06)
	var sfx := get_tree().get_first_node_in_group("sand_fx")
	if sfx:
		sfx.footprint(pos, Vector3(-sin(yaw), 0, -cos(yaw)), depth)
		count += 1
		return
	var basis := Basis(Vector3.UP, yaw + PI)
	_mm.set_instance_transform(_i, Transform3D(basis, Vector3(pos.x, pos.y + 0.012, pos.z)))
	_mm.set_instance_custom_data(_i, Color(maxf(Wind.time, 0.001), 0.0 if right else 1.0, depth, 0.0))
	_i = (_i + 1) % MAX_PRINTS
	count += 1
