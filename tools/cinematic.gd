extends Node
## Tech-demo cinematics in the real game (High quality, real systems).
##   godot --path . --write-movie /tmp/c.avi --fixed-fps 30 res://tools/cinematic.tscn -- shot=sand
## shots: open, sand, character, oasis, run, surf, fight, sun
## A free camera (not the gameplay rig) flies scripted moves; the cat is
## driven through GameInput like a player; captions name the systems shown.

var main: Node3D
var p: Player
var cam := Camera3D.new()
var t := 0.0
var shot := "open"
var dur := 8.0
var _release := {}
var _cap := Label.new()
var _cap_text := ""
var _cam_pos := Vector3.ZERO
var _look := Vector3.ZERO
var _first := true
# fight bot
var next_tap := 0.0
var dodge_cd := 0.0
var heavy_until := -1.0
var taps := 0
const OASIS := Vector3(-32, 0, -4)

const CAPTIONS := {
	"open": "HAFID  —  Journey-style sand · atmospheric haze · lens flare",
	"sand": "SAND  —  ripples · silky sheen · stable glitter · footprint dents",
	"character": "CHARACTER  —  cel shading · daraa cloth · hawli in the wind",
	"oasis": "OASIS  —  individual grass blades · wind gusts · water ripples · reflections",
	"run": "MOVEMENT  —  dust trail · landing impressions · dithered pixel dust",
	"surf": "SAND SURFING  —  shield board · dust plume · daraa glide · face veil",
	"fight": "COMBAT  —  takoba combos · shadow jinn · pixel hit effects",
	"sun": "LIGHT  —  sun disc · glare · chromatic ghosts · diffraction",
}


func _ready() -> void:
	Settings.quality = 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot = a.substr(5)
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	main.hud.visible = false
	p = main.player
	process_priority = 1000
	add_child(cam)
	cam.fov = 55.0
	cam.far = 600.0
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_cap.add_theme_font_size_override("font_size", 22)
	_cap.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
	_cap.add_theme_color_override("font_shadow_color", Color(0.2, 0.12, 0.08, 0.7))
	_cap.add_theme_constant_override("shadow_offset_x", 2)
	_cap.add_theme_constant_override("shadow_offset_y", 2)
	_cap.position = Vector2(48, 640)
	layer.add_child(_cap)
	_cap_text = CAPTIONS.get(shot, "")
	match shot:
		"open":
			_place(Vector3(-37.5, 0.05, -12.5), atan2(-0.57, -0.82))
			dur = 8.0
		"sand":
			_place(Vector3(-46.0, 0.05, 28.0), 0.0)
			dur = 8.0
		"character":
			_place(OASIS + Vector3(13, 0.05, 9), 0.4)
			dur = 9.0
		"oasis":
			_place(OASIS + Vector3(9.5, 0.05, 1.0), PI * 0.5)
			dur = 9.0
		"run":
			_place(Vector3(10.0, 0.05, -40.0), PI * 0.5)
			dur = 8.0
		"surf":
			_place(Vector3(-28.5, 8.3, 46.0), -PI * 0.5)
			dur = 8.5
		"fight":
			_place(Vector3(0, 0.1, 7), 0.0)
			dur = 26.0
		"sun":
			_place(Vector3(30, 0.05, -28), 0.0)
			dur = 7.0


func _place(at: Vector3, yaw: float) -> void:
	p.global_position = at
	p.rotation.y = yaw
	p.reset_physics_interpolation()
	main.camera_rig.yaw = yaw


func _tap(action: String, hold: float = 0.06) -> void:
	GameInput.press(action)
	_release[action] = t + hold


func _physics_process(delta: float) -> void:
	t += delta
	for k in _release.keys():
		if t >= _release[k]:
			GameInput.release(k)
			_release.erase(k)
	var mv := Vector2.ZERO
	match shot:
		"open":
			mv = Vector2(0, -0.35) if t > 2.5 else Vector2.ZERO
		"sand":
			mv = Vector2(0, -0.32) if t > 0.6 and t < 7.4 else Vector2.ZERO
		"character":
			mv = Vector2(0, -0.2) if t > 5.5 and t < 8.0 else Vector2.ZERO
		"oasis":
			if t > 3.0 and t < 5.0:
				mv = Vector2(0, -0.5)
			elif t > 5.8 and t < 7.0:
				mv = Vector2(0.5, -0.2)
		"run":
			mv = Vector2(0, -1.0) if t > 0.4 and t < 7.6 else Vector2.ZERO
			if t > 2.4 and fmod(t, 1.6) < delta and t < 7.0:
				_tap("jump", 0.22)
		"surf":
			mv = Vector2(sin(t * 1.3) * 0.25, -1.0) if t > 0.4 else Vector2.ZERO
		"fight":
			mv = _fight_bot(delta)
	GameInput.touch_move = mv
	if t > dur:
		get_tree().quit()


func _fight_bot(delta: float) -> Vector2:
	var j: Jinn = main.jinn
	if j == null or not is_instance_valid(j) or j.is_dead():
		return Vector2.ZERO
	if not j.has_meta("cine"):
		j.set_meta("cine", true)
		j.hp = 220.0
	if t < 1.0:
		return Vector2.ZERO
	if p.lock_target == null:
		p.toggle_lock()
	dodge_cd -= delta
	var d := Combat.flat(j.global_position - p.global_position).length()
	if j.state_name() == "TELEGRAPH" and d < 5.0 and dodge_cd <= 0.0:
		_tap("dodge")
		dodge_cd = 1.0
		return Vector2(1.0 if int(t) % 2 == 0 else -1.0, 0.3)
	if t < heavy_until:
		return Vector2.ZERO
	if d > 2.0:
		return Vector2(0, -1)
	if p.stamina < 30.0:
		return Vector2(0.0, 0.6) if d < 3.2 else Vector2.ZERO
	if t >= next_tap:
		taps += 1
		if taps % 5 == 0:
			_tap("attack", 0.9)
			heavy_until = t + 1.3
			next_tap = t + 1.5
		else:
			_tap("attack")
			next_tap = t + (0.32 if taps % 5 != 4 else 0.7)
	return Vector2.ZERO


## Camera moves, run after everything else each frame.
func _process(delta: float) -> void:
	var pp := p.global_position
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var u := clampf(t / dur, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var pos := Vector3.ZERO
	var look := pp + Vector3(0, 0.8, 0)
	var smooth := 4.0
	match shot:
		"open":
			# crane up from the sand toward the oasis, sun in frame
			# from the west, low over the sand: the oasis backlit, sun and flare
			# beyond it; crane up as the cat walks in
			var base := Vector3(-41.5, 0.0, -17.0)
			var sd: Vector3 = main.sun.global_transform.basis.z
			pos = base + Vector3(lerpf(0.0, 2.0, e), lerpf(0.45, 4.0, e), lerpf(0.0, 1.5, e))
			look = lerp(base + sd * 30.0, OASIS + Vector3(0, 1.5, 0), smoothstep(0.15, 0.85, u))
			smooth = 2.0
		"sand":
			# grazing dolly alongside the feet: dents, glitter, ripples
			pos = pp + fwd * 0.9 + side * 1.3 + Vector3(0, 1.35, 0)
			look = pp - fwd * 2.2 + Vector3(0, 0.0, 0)
			cam.fov = 50.0
		"character":
			# slow orbit, close: cel bands, daraa, hawli in the wind
			var a := lerpf(-0.6, 2.4, e)
			pos = pp + Vector3(sin(a), 0, cos(a)) * 2.4 + Vector3(0, 1.05, 0)
			look = pp + Vector3(0, 0.95, 0)
			cam.fov = 42.0
		"oasis":
			# push through the grass to the water's surface, then low angle
			var start := OASIS + Vector3(13.5, 0.35, 3.5)
			var end := OASIS + Vector3(6.2, 0.3, 2.4)
			pos = start.lerp(end, e)
			look = lerp(OASIS + Vector3(0, 0.6, 0), pp + Vector3(0, 0.5, 0), smoothstep(0.3, 0.6, u))
			cam.fov = 50.0
		"run":
			# side tracking shot, low: dust trail and landings
			pos = pp + side * 4.2 + fwd * 0.6 + Vector3(0, 0.7, 0)
			look = pp + fwd * 1.0 + Vector3(0, 0.6, 0)
			smooth = 6.0
		"surf":
			if t < 3.2:     # chase from behind and above
				pos = pp - fwd * 4.0 + side * 1.2 + Vector3(0, 1.8, 0)
				look = pp + fwd * 3.0 + Vector3(0, 0.3, 0)
			else:           # side profile at the lip, follow the glide
				pos = Vector3(9.0, 2.8, 39.0) if t < 5.4 else pp + side * 4.5 + Vector3(0, 1.4, 0)
				look = pp + Vector3(0, 0.8, 0)
			smooth = 5.0
		"fight":
			var j: Jinn = main.jinn
			var jp := j.global_position if j and is_instance_valid(j) else pp + fwd * 2.0
			var mid := (pp + jp) * 0.5
			var line := Combat.flat(jp - pp)
			line = line.normalized() if line.length() > 0.1 else fwd
			var perp := Vector3(-line.z, 0, line.x)
			var phase := int(t / 4.5) % 5
			match phase:
				0:   # slow orbit
					var a := t * 0.35
					pos = mid + Vector3(sin(a), 0, cos(a)) * 5.5 + Vector3(0, 1.8, 0)
					look = mid + Vector3(0, 0.9, 0)
				1:   # low hero angle behind the cat
					pos = pp - line * 2.6 + perp * 0.9 + Vector3(0, 0.5, 0)
					look = jp + Vector3(0, 1.1, 0)
				2:   # close side profile
					pos = mid + perp * 3.4 + Vector3(0, 1.1, 0)
					look = mid + Vector3(0, 0.9, 0)
				3:   # over the jinn's shoulder
					pos = jp + line * 3.6 + perp * 1.8 + Vector3(0, 2.8, 0)
					look = pp + Vector3(0, 0.8, 0)
				_:   # wide crane
					pos = mid + perp * 5.0 - line * 2.0 + Vector3(0, 6.8, 0)
					look = mid + Vector3(0, 0.6, 0)
			# keep the camera inside the courtyard walls
			pos.x = clampf(pos.x, -9.0, 9.0)
			pos.z = clampf(pos.z, -9.0, 9.0)
			smooth = 3.5
		"sun":
			var sd: Vector3 = main.sun.global_transform.basis.z
			var a := lerpf(-0.7, 0.35, e)
			var dir := Basis(Vector3.UP, a) * Vector3(sd.x, 0, sd.z).normalized()
			pos = pp + Vector3(0, 1.6, 0) - dir * 3.0
			look = pos + dir * 10.0 + Vector3(0, lerpf(2.0, 6.5, e), 0)
			smooth = 3.0
	if _first:
		_cam_pos = pos
		_look = look
		_first = false
	var k := 1.0 - exp(-smooth * delta)
	_cam_pos = _cam_pos.lerp(pos, k)
	_look = _look.lerp(look, k)
	cam.global_position = _cam_pos
	if _cam_pos.distance_to(_look) > 0.01:
		cam.look_at(_look)
	cam.make_current()
	# caption fades in at 0.6 s and out before the cut
	var ca := clampf((t - 0.6) / 0.6, 0.0, 1.0) * clampf((dur - 0.8 - t) / 0.6, 0.0, 1.0)
	_cap.text = _cap_text
	_cap.modulate.a = ca
