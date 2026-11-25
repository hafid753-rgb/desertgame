class_name DaraaGarment
extends MeshInstance3D
## The authentic daraa (docs/garment/DARAA.md): one broad sheet folded over
## the shoulders, open sides, lower side seams, open hem, embroidered neck
## and chest pocket. Mesh, UVs, rig weights and the wearing configurations
## come from the flat pattern + Blender cloth drape (tools/garment/).
##
## Runtime (all presentation, no gameplay effect):
##   * wearing configurations as blend shapes, cross-faded (no mesh swaps):
##       DRAPED, GATHER_L / GATHER_R (one side thrown onto the shoulder),
##       GATHER_BOTH; plus Spread (sides held out while gliding)
##   * invisible garment skeleton: two side chains + the hem, damped springs
##     with inertia from run / turn / jump / land / dodge and hidden arm
##     support from the floating hands (the hands themselves stay free)
##   * GPU wind from the shared Wind field (shoulders still, hems free)
##   * collision proxies: hands, boots, invisible legs (shader push-out)
##   * distance LOD: a coarser drape of the same pattern beyond LOD_RANGE

enum Wear { DRAPED, GATHER_L, GATHER_R, GATHER_BOTH }

const MESH_PATH := "res://game/art/garment/daraa.glb"
const LOD_PATH := "res://game/art/garment/daraa_lod1.glb"
const LOD_RANGE := 16.0
const TEX_DIR := "res://game/art/garment/"
## Colourway per species (the colours the robes already had).
const COLOURWAY := {"cat": "blue", "fennec": "white", "rabbit": "navy"}
const INSIDE := {"blue": Color(0.2, 0.41, 0.77), "white": Color(0.92, 0.91, 0.88), "navy": Color(0.13, 0.19, 0.42)}
const SHAPES := ["GatherL", "GatherR", "GatherBoth", "Spread"]
## Blend time between configurations (seconds to ~95%).
const WEAR_TIME := 0.45

var wear: int = Wear.DRAPED
## Forced configuration for validation renders (-1 = automatic).
var wear_override: int = -1
var spread_target := 0.0
var lod: MeshInstance3D
var mat: ShaderMaterial

var _w := {"GatherL": 0.0, "GatherR": 0.0, "GatherBoth": 0.0, "Spread": 0.0}
var _idx := {}
# springs (model space)
var _side_l := Vector3.ZERO
var _side_l_v := Vector3.ZERO
var _side_r := Vector3.ZERO
var _side_r_v := Vector3.ZERO
var _hem := Vector3.ZERO
var _hem_v := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _last_yaw := 0.0
var _hand_rest_l := Vector3(-0.5, 0.82, -0.44)
var _hand_rest_r := Vector3(0.55, 0.75, -0.38)


static func _load_mesh(path: String) -> ArrayMesh:
	if not ResourceLoader.exists(path):
		return null
	var scene := (load(path) as PackedScene).instantiate()
	var found := scene.find_children("*", "MeshInstance3D", true, false)
	var m: ArrayMesh = (found[0] as MeshInstance3D).mesh as ArrayMesh if not found.is_empty() else null
	scene.free()
	return m


static func available() -> bool:
	# "no_daraa" user arg: old robe, for A/B profiling (tools/daraa_perf.gd)
	return ResourceLoader.exists(MESH_PATH) and not OS.get_cmdline_user_args().has("no_daraa")


func setup(species: String, outline_color: Color) -> void:
	name = "Daraa"
	mesh = _load_mesh(MESH_PATH)
	var way: String = COLOURWAY.get(species, "blue")
	mat = ShaderMaterial.new()
	mat.shader = load("res://game/shaders/daraa.gdshader")
	mat.set_shader_parameter("daraa_tex", load(TEX_DIR + "daraa_%s.png" % way))
	mat.set_shader_parameter("inside_color", INSIDE[way])
	mat.set_shader_parameter("debug_uv", OS.get_cmdline_user_args().has("debug_uv"))
	mat.set_shader_parameter("shadow_tint", Color(0.78, 0.66, 0.64))
	mat.set_shader_parameter("rim_strength", 0.12)
	mat.set_shader_parameter("sheen_strength", 0.1 if way != "white" else 0.05)
	var ol := ShaderMaterial.new()
	ol.shader = load("res://game/shaders/daraa_outline.gdshader")
	ol.set_shader_parameter("outline_color", outline_color)
	mat.next_pass = ol
	material_override = mat
	var lm := _load_mesh(LOD_PATH)
	if lm:
		lod = MeshInstance3D.new()
		lod.name = "DaraaLOD1"
		lod.mesh = lm
		lod.material_override = mat
		lod.visibility_range_begin = LOD_RANGE
		lod.visibility_range_begin_margin = 1.0
		lod.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(lod)
		visibility_range_end = LOD_RANGE
		visibility_range_end_margin = 1.0
	for s in SHAPES:
		_idx[s] = find_blend_shape_by_name(s) if mesh else -1


func _set_param(p: String, v) -> void:
	mat.set_shader_parameter(p, v)
	(mat.next_pass as ShaderMaterial).set_shader_parameter(p, v)


func _blend(s: String, v: float) -> void:
	var i: int = _idx.get(s, -1)
	if i < 0:
		return
	set_blend_shape_value(i, v)
	if lod and lod.mesh:
		var j: int = lod.find_blend_shape_by_name(s)
		if j >= 0:
			lod.set_blend_shape_value(j, v)


## Pick the wearing configuration from what the character is doing
## (presentation only): sword arm freed in combat, both sleeves up to
## climb, sides out as wings to glide.
func choose_wear(state: String, armed: bool) -> int:
	if wear_override >= 0:
		return wear_override
	if state in ["CLIMB", "MANTLE"]:
		return Wear.GATHER_BOTH
	if armed or state in ["ATTACK", "HEAVY", "HEAVY_CHARGE", "GUARD", "DEFENSE", "CAST"]:
		return Wear.GATHER_R
	return Wear.DRAPED


## model: the CreatureModel (model space = this garment's space).
func update(delta: float, model: Node3D, state: String, vel: Vector3, armed: bool, hands: Array, feet: Array, feet_up: Array = []) -> void:
	if mesh == null:
		return
	wear = choose_wear(state, armed)
	spread_target = 1.0 if state == "GLIDE" else 0.0
	var tw := {"GatherL": 1.0 if wear == Wear.GATHER_L else 0.0,
		"GatherR": 1.0 if wear == Wear.GATHER_R else 0.0,
		"GatherBoth": 1.0 if wear == Wear.GATHER_BOTH else 0.0,
		"Spread": spread_target}
	var k := 1.0 - exp(-delta * 3.0 / WEAR_TIME)
	for s in SHAPES:
		# a spread glide overrides gathering (the sides are let down first)
		var target: float = tw[s] * (1.0 - _w["Spread"] if s != "Spread" else 1.0)
		_w[s] = lerpf(_w[s], target, k)
		_blend(s, _w[s])
	_set_param("gather_l", maxf(_w["GatherL"], _w["GatherBoth"]))
	_set_param("gather_r", maxf(_w["GatherR"], _w["GatherBoth"]))
	_set_param("spread", _w["Spread"])
	# --- inertia targets in model space -----------------------------------
	var gt := global_transform
	var inv := gt.basis.orthonormalized().inverse()
	var vel_l := inv * vel
	var acc_l := inv * ((vel - _last_vel) / maxf(delta, 0.001))
	_last_vel = vel
	var yaw := model.global_rotation.y
	var yaw_rate := wrapf(yaw - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = yaw
	var speed := Vector2(vel.x, vel.z).length()
	# hem trails behind travel, kicks against acceleration; rising leaves the
	# cloth behind (down), falling lifts it; landing drops it with a bounce
	var hem_t := Vector3(-vel_l.x * 0.012 - acc_l.x * 0.004, clampf(-vel_l.y * 0.018, -0.07, 0.12) + absf(vel_l.z) * 0.004, -vel_l.z * 0.016 - acc_l.z * 0.005)
	hem_t = hem_t.limit_length(0.2)
	# side chains: same lag, plus the swing of a turn (tangential lag)
	var turn := clampf(yaw_rate, -8.0, 8.0) * 0.018
	var side_t_l := hem_t * 1.2 + Vector3(0, 0, turn * 0.6)
	var side_t_r := hem_t * 1.2 + Vector3(0, 0, -turn * 0.6)
	# hidden arm support: a raised or reaching hand carries its side up/out
	var ctr := gt.affine_inverse()
	var hl: Vector3 = ctr * (hands[1] as Vector3) if hands.size() > 1 else _hand_rest_l
	var hr: Vector3 = ctr * (hands[0] as Vector3) if hands.size() > 0 else _hand_rest_r
	side_t_l += _arm_support(hl, _hand_rest_l, -1.0)
	side_t_r += _arm_support(hr, _hand_rest_r, 1.0)
	var steps := clampi(ceili(delta * 120.0), 1, 12)
	var h := minf(delta, 0.1) / float(steps)
	for i in steps:
		var a := (hem_t - _hem) * 70.0 - _hem_v * 7.5
		_hem_v += a * h
		_hem += _hem_v * h
		a = (side_t_l - _side_l) * 55.0 - _side_l_v * 6.0
		_side_l_v += a * h
		_side_l += _side_l_v * h
		a = (side_t_r - _side_r) * 55.0 - _side_r_v * 6.0
		_side_r_v += a * h
		_side_r += _side_r_v * h
	_hem = _hem.limit_length(0.25)
	_side_l = _side_l.limit_length(0.4)
	_side_r = _side_r.limit_length(0.4)
	_set_param("hem_off", _hem)
	_set_param("side_l_off", _side_l)
	_set_param("side_r_off", _side_r)
	_set_param("wind_speed_k", clampf(speed / 10.0, 0.0, 1.5))
	# collision proxies (model space)
	var rad := [0.1, 0.1]
	if hands.size() > 1:
		_set_param("col_hand_r", _sphere(ctr * (hands[0] as Vector3), rad[0]))
		_set_param("col_hand_l", _sphere(ctr * (hands[1] as Vector3), rad[1]))
	if feet.size() > 1:
		# legs: the boot part is a rigid 0.42 m boot + puffed sirwal leg
		# (0.26 wide); a capsule from the ankle to the sirwal top keeps the
		# front panel outside it when striding
		for i in 2:
			var f: Vector3 = ctr * (feet[i] as Vector3)
			var up := ctr.basis * (feet_up[i] as Vector3) if feet_up.size() > i else Vector3.UP
			_set_param("col_foot_r" if i == 0 else "col_foot_l", _sphere(f + up * 0.07, 0.17))
			_set_param("hip_r" if i == 0 else "hip_l", f + up * 0.34)


func _arm_support(hand: Vector3, rest: Vector3, side: float) -> Vector3:
	var d := hand - rest
	var up := clampf(d.y, 0.0, 0.5)
	var out := clampf(d.x * side, 0.0, 0.35)
	var fwd := clampf(d.z, -0.35, 0.35)
	return Vector3(side * out * 0.55, up * 0.5, fwd * 0.35 * (up * 2.0 + out * 2.0))


func _sphere(c: Vector3, r: float) -> Vector4:
	return Vector4(c.x, c.y, c.z, r)
