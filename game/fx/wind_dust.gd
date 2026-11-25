class_name WindDust
extends Node3D
## Blown sand around the player, moved by the shared Wind field: a
## ground-hugging drift sheet of dithered streaks plus airborne grains
## (see wind_dust.gdshader). Follows the player, snapped to whole metres so
## the world-texel pattern never swims.

@export var sheet_size := 48.0
@export var motes := 420
@export var amount := 1.0

var _sheet: MeshInstance3D
var _sheet_mat: ShaderMaterial
var _mote_mat: ShaderMaterial


func _ready() -> void:
	var shader := load("res://game/shaders/wind_dust.gdshader")
	_sheet = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(sheet_size, sheet_size)
	_sheet.mesh = pm
	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = shader
	_sheet_mat.set_shader_parameter("mode", 0)
	_sheet_mat.set_shader_parameter("amount", amount)
	_sheet_mat.set_shader_parameter("radius", sheet_size * 0.48)
	_sheet.material_override = _sheet_mat
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.top_level = true
	add_child(_sheet)

	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var box := Vector3(28, 3, 28)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = motes
	for i in motes:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(rng.randf() * box.x, rng.randf() * box.y, rng.randf() * box.z)))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0))
	_mote_mat = ShaderMaterial.new()
	_mote_mat.shader = shader
	_mote_mat.set_shader_parameter("mode", 1)
	_mote_mat.set_shader_parameter("amount", amount)
	_mote_mat.set_shader_parameter("box", box)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mote_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1000, -50, -1000), Vector3(2000, 100, 2000))
	mi.top_level = true
	add_child(mi)


## Half-size (m) of the square ground; nothing is drawn past it.
func set_ground_half(h: float) -> void:
	_sheet_mat.set_shader_parameter("ground_half", h)
	_mote_mat.set_shader_parameter("ground_half", h)


## No drift sheet over a pond: centre (world) and radius.
func mask_water(centre: Vector3, radius: float) -> void:
	_sheet_mat.set_shader_parameter("water_mask", Vector4(centre.x, centre.z, radius, 0))


func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	_sheet.global_position = Vector3(roundf(p.global_position.x), 0.07, roundf(p.global_position.z))
