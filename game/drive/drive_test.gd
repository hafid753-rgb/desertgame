extends "res://game/main.gd"
## Separate test: top-down driving in the Hafid desert (same courtyard,
## oasis, dunes, sand shading, wind and light as the main game).
##   godot --path . res://game/drive/drive_test.tscn            (drive)
##   ... -- teaser   scripted teaser: drift, the pond, stuck in soft sand
## Controls: arrows / WASD-as-ui or the touch stick; Space = handbrake.

var car: DesertCar
var cam := Camera3D.new()
var teaser := false
var t := 0.0
var _cap := Label.new()
var _title := Label.new()
var _stuck_at := -1.0
var _wp := 0
var _cam_pos := Vector3.ZERO
var _look := Vector3.ZERO
var _first := true

## soft sand at the foot of the south-west dune
const PIT := Vector3(-26.5, 0, -21.5)
const START := Vector3(-46.0, 0.1, 31.0)
## teaser route: control points [x, z, target speed], smoothed into a
## dense path (Catmull-Rom); the autopilot pulls the handbrake itself when
## the path ahead bends more than the car can turn on grip.
const ROUTE := [
	[-46.0, 31.0, 16.0], [-46.0, 24.0, 16.0], [-53.0, 16.0, 15.0], [-45.0, 8.0, 15.0],
	[-53.0, 0.5, 14.0], [-47.0, -3.6, 13.0], [-40.0, -3.6, 16.0], [-22.0, -3.6, 15.0],
	[-19.5, -9.0, 12.0], [-21.0, -15.0, 11.0], [-25.0, -20.0, 10.0], [-26.5, -21.5, 10.0],
]


func _ready() -> void:
	teaser = OS.get_cmdline_user_args().has("teaser")
	Settings.quality = 2
	_build_environment()
	var courtyard := Courtyard.new()
	add_child(courtyard)
	var oasis := Oasis.new()
	oasis.position = OASIS_AT
	add_child(oasis)
	var horizon := DuneHorizon.new()
	var far_sand := courtyard._sand_mat(Courtyard.SAND).duplicate() as ShaderMaterial
	far_sand.set_shader_parameter("y_squash", 0.75)
	far_sand.set_shader_parameter("lambert_gain", 2.2)
	horizon.material_override = far_sand
	add_child(horizon)
	add_child(SandInteraction.new())
	var flare := LensFlare.new()
	flare.sun = sun
	add_child(flare)
	var dust := WindDust.new()
	add_child(dust)
	dust.mask_water(OASIS_AT, oasis.pond_radius * 1.15)
	dust.set_ground_half(Courtyard.BOUND + 5.0)
	apply_quality.call_deferred()
	car = DesertCar.new()
	car.oasis = oasis
	car.soft_pits = [[PIT, 3.2]]
	add_child(car)
	car.global_position = START
	car.yaw = 0.0
	if teaser:
		car.autopilot = _autopilot
	car.stuck_changed.connect(func(s: bool) -> void:
		if s and _stuck_at < 0.0:
			_stuck_at = t)
	add_child(cam)
	cam.fov = 48.0
	cam.far = 500.0
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	for l in [_cap, _title]:
		l.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
		l.add_theme_color_override("font_shadow_color", Color(0.2, 0.12, 0.08, 0.75))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		layer.add_child(l)
	_cap.add_theme_font_size_override("font_size", 22)
	_cap.position = Vector2(48, 650)
	_title.add_theme_font_size_override("font_size", 64)
	_title.position = Vector2(48, 40)


func _process(delta: float) -> void:
	t += delta
	# top-down chase camera: high and a little behind, leading the motion
	var p := car.global_position
	var v := car.velocity
	var lead := Vector3(v.x, 0, v.z) * 0.35
	var height := 15.0
	var back := 6.5
	if _stuck_at >= 0.0:
		# end: push in on the stuck car
		var e := clampf((t - _stuck_at) / 2.5, 0.0, 1.0)
		e = e * e * (3.0 - 2.0 * e)
		height = lerpf(15.0, 6.5, e)
		back = lerpf(6.5, 4.5, e)
		lead = lead * (1.0 - e)
	var pos := p + lead + Vector3(0, height, back)
	var look := p + lead * 1.4
	if _first:
		_cam_pos = pos
		_look = look
		_first = false
	var k := 1.0 - exp(-3.0 * delta)
	_cam_pos = _cam_pos.lerp(pos, k)
	_look = _look.lerp(look, k)
	cam.global_position = _cam_pos
	cam.look_at(_look, Vector3(0, 0, -1))
	if teaser:
		_captions()
	if OS.get_cmdline_user_args().has("trace") and fmod(t, 0.5) < delta:
		print("t %.1f wp %d pos %s spd %.1f water %s soft %s hb %s stuck %s" % [t, _wp, car.global_position.snapped(Vector3.ONE * 0.1), Vector2(car.velocity.x, car.velocity.z).length(), car.in_water, car.on_soft, car.handbrake, car.stuck])


func _captions() -> void:
	var cap := ""
	if t < 3.0:
		cap = "DESERT DRIVING TEST  —  top-down · the Hafid desert"
	elif car.in_water:
		cap = "THE OASIS  —  spray · rings on the pond"
	elif car.handbrake:
		cap = "DRIFT  —  loose sand, tail out"
	elif _stuck_at >= 0.0:
		cap = "SOFT SAND"
	elif t > 3.0:
		cap = "TYRE TRACKS  —  grooves in the sand · dust"
	_cap.text = cap
	_title.text = "Stuck." if _stuck_at >= 0.0 and t - _stuck_at > 1.8 else ""
	if _stuck_at >= 0.0 and t - _stuck_at > 5.5:
		get_tree().quit()
	if t > 40.0:
		get_tree().quit()


var _path: Array[Vector3] = []      # x, z, speed in y
var _pi := 0


func _build_path() -> void:
	var n := ROUTE.size()
	for k in n - 1:
		var p0: Array = ROUTE[maxi(k - 1, 0)]
		var p1: Array = ROUTE[k]
		var p2: Array = ROUTE[k + 1]
		var p3: Array = ROUTE[mini(k + 2, n - 1)]
		var a := Vector3(p0[0], p0[2], p0[1])
		var b := Vector3(p1[0], p1[2], p1[1])
		var c := Vector3(p2[0], p2[2], p2[1])
		var d := Vector3(p3[0], p3[2], p3[1])
		var steps := maxi(4, int(Vector2(c.x - b.x, c.z - b.z).length() / 0.5))
		for i in steps:
			var u := float(i) / steps
			var u2 := u * u
			var u3 := u2 * u
			_path.append(0.5 * ((2.0 * b) + (-a + c) * u + (2.0 * a - 5.0 * b + 4.0 * c - d) * u2 + (-a + 3.0 * b - 3.0 * c + d) * u3))
	var last: Array = ROUTE[n - 1]
	_path.append(Vector3(last[0], last[2], last[1]))


## Pure pursuit on the smoothed route.
func _autopilot() -> Array:
	if t < 0.8:
		return [0.0, 0.0, false]
	if _path.is_empty():
		_build_path()
	var p := car.global_position
	# advance the nearest index (never backwards)
	var best := _pi
	var bd := INF
	for i in range(_pi, mini(_pi + 40, _path.size())):
		var d := Vector2(_path[i].x - p.x, _path[i].z - p.z).length()
		if d < bd:
			bd = d
			best = i
	_pi = best
	_wp = _pi
	var speed := Vector2(car.velocity.x, car.velocity.z).length()
	var look := mini(_pi + int(clampf(4.0 + speed * 0.35, 4.0, 10.0) / 0.5), _path.size() - 1)
	var target := _path[look]
	var to := Vector3(target.x - p.x, 0, target.z - p.z)
	var want := atan2(-to.x, -to.z)
	var err := wrapf(want - car.yaw, -PI, PI)
	var steer := clampf(-err * 2.6, -1.0, 1.0)
	var hb := absf(err) > 0.45 and speed > 9.0 and not car.in_water
	var thr := 1.0 if speed < target.y or car.on_soft else 0.15
	return [thr, steer, hb]
