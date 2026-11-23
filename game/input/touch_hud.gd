class_name TouchHud
extends CanvasLayer
## Landscape touch controls, status bars and the pause/settings menu, drawn in
## one Control. Multi-touch is tracked by finger index so the joystick, camera
## swipe and buttons work at the same time. Buttons feed GameInput exactly
## like keys do.
##
## Movement thumb side (left by default): floating joystick.
## Other side: swipe = camera, tap a jinn = lock-on, action buttons.

const BUTTONS := {
	"attack": {"label": "ATK", "offset": Vector2(-150, -150), "r": 74.0, "color": Color(0.95, 0.85, 0.7)},
	"dodge": {"label": "DGE", "offset": Vector2(-300, -95), "r": 56.0, "color": Color(0.7, 0.9, 1.0)},
	"special": {"label": "SPC", "offset": Vector2(-115, -305), "r": 56.0, "color": Color(1.0, 0.8, 0.5)},
	"jump": {"label": "JMP", "offset": Vector2(-300, -245), "r": 50.0, "color": Color(0.85, 1.0, 0.8)},
	"lock": {"label": "LOCK", "offset": Vector2(-185, 150), "r": 38.0, "color": Color(1, 1, 1), "top": true},
	"element": {"label": "ELM", "offset": Vector2(-75, 150), "r": 38.0, "color": Color(1, 1, 1), "top": true},
}
const JOY_RADIUS := 90.0
const TAP_MOVE := 14.0
const TAP_TIME := 0.25
const SPECIES_RECT := Rect2(24, 80, 230, 32)
const PAUSE_R := 26.0
const MENU_ROWS := ["resume", "left_handed", "button_size", "sound", "debug", "species"]

var player: Player
var jinn: Jinn
var main: Node  # for session stats (jinn_kills)
var paused: bool = false

var _canvas: Control
var _touches: Dictionary = {}
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_active := false
var _announce_text := ""
var _announce_color := Color.WHITE
var _announce_time := 0.0
var _font: Font
var _session_start_ms: int = 0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_font = ThemeDB.fallback_font
	_session_start_ms = Time.get_ticks_msec()


func announce(text: String, color: Color) -> void:
	_announce_text = text
	_announce_color = color
	_announce_time = 1.1


func set_paused(p: bool) -> void:
	paused = p
	for id in _touches:
		var role: String = _touches[id]["role"]
		if BUTTONS.has(role):
			GameInput.release(role)
	for a in GameInput.BUTTONS:
		GameInput.release(a)
	_touches.clear()
	_joy_active = false
	GameInput.touch_move = Vector2.ZERO
	get_tree().paused = p
	if not p:
		GameInput.consume_events()


func _process(delta: float) -> void:
	_announce_time = maxf(0.0, _announce_time - delta)
	_canvas.queue_redraw()


# --- Layout -----------------------------------------------------------------

func _screen() -> Vector2:
	return _canvas.get_viewport_rect().size


func _button_center(id: String) -> Vector2:
	var b: Dictionary = BUTTONS[id]
	var s := _screen()
	var off: Vector2 = b["offset"] * Settings.button_scale()
	var pos := Vector2(s.x + off.x, off.y) if b.get("top", false) else s + off
	if Settings.left_handed:
		pos.x = s.x - pos.x
	return pos


func _button_radius(id: String) -> float:
	return float(BUTTONS[id]["r"]) * Settings.button_scale()


func _button_at(pos: Vector2) -> String:
	for id in BUTTONS:
		if pos.distance_to(_button_center(id)) <= _button_radius(id) * 1.15:
			return id
	return ""


func _pause_center() -> Vector2:
	return Vector2(_screen().x - 48, 40)


func _in_joy_zone(pos: Vector2) -> bool:
	var s := _screen()
	if pos.y < s.y * 0.25:
		return false
	return pos.x > s.x * 0.58 if Settings.left_handed else pos.x < s.x * 0.42


func _menu_rect() -> Rect2:
	var s := _screen()
	var size := Vector2(820, 470)
	return Rect2((s - size) / 2, size)


func _menu_row_rect(i: int) -> Rect2:
	var m := _menu_rect()
	return Rect2(m.position + Vector2(30, 80 + i * 62), Vector2(380, 52))


# --- Input ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		set_paused(not paused)
		return
	if paused and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_menu_tap((event as InputEventMouseButton).position)
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if paused:
			if t.pressed:
				_menu_tap(t.position)
			return
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index, t.position)
	elif event is InputEventScreenDrag and not paused:
		var d := event as InputEventScreenDrag
		_touch_move(d.index, d.position, d.relative)


func _touch_down(idx: int, pos: Vector2) -> void:
	if pos.distance_to(_pause_center()) <= PAUSE_R * 1.4:
		set_paused(true)
		return
	var b := _button_at(pos)
	if b != "":
		_touches[idx] = {"role": b}
		GameInput.press(b)
		return
	if SPECIES_RECT.has_point(pos) and player:
		player.next_species()
		return
	if _in_joy_zone(pos) and not _joy_active:
		_touches[idx] = {"role": "joy"}
		_joy_active = true
		_joy_origin = pos
		_joy_pos = pos
		return
	_touches[idx] = {"role": "cam", "start": pos, "time": Time.get_ticks_msec() / 1000.0}


func _touch_move(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _touches.has(idx):
		return
	var role: String = _touches[idx]["role"]
	if role == "joy":
		var v := pos - _joy_origin
		if v.length() > JOY_RADIUS:
			_joy_origin = pos - v.normalized() * JOY_RADIUS
			v = pos - _joy_origin
		_joy_pos = pos
		GameInput.touch_move = v / JOY_RADIUS
	elif role == "cam":
		GameInput.add_look(rel)


func _touch_up(idx: int, pos: Vector2) -> void:
	if not _touches.has(idx):
		return
	var info: Dictionary = _touches[idx]
	var role: String = info["role"]
	_touches.erase(idx)
	if role == "joy":
		_joy_active = false
		GameInput.touch_move = Vector2.ZERO
	elif role == "cam":
		var start: Vector2 = info["start"]
		var t0: float = info["time"]
		if pos.distance_to(start) < TAP_MOVE and Time.get_ticks_msec() / 1000.0 - t0 < TAP_TIME and player:
			player.lock_at_screen(pos)
	elif BUTTONS.has(role):
		GameInput.release(role)


func _menu_tap(pos: Vector2) -> void:
	for i in MENU_ROWS.size():
		if _menu_row_rect(i).has_point(pos):
			match MENU_ROWS[i]:
				"resume":
					set_paused(false)
				"left_handed":
					Settings.left_handed = not Settings.left_handed
					Settings.save()
				"button_size":
					Settings.button_scale_index = (Settings.button_scale_index + 1) % Settings.BUTTON_SCALES.size()
					Settings.save()
				"sound":
					Settings.sound_on = not Settings.sound_on
					Settings.save()
				"debug":
					Settings.show_debug = not Settings.show_debug
					Settings.save()
				"species":
					if player:
						player.next_species()
			return


# --- Drawing ----------------------------------------------------------------

func _draw_hud() -> void:
	var s := _screen()
	if player:
		_bar(Vector2(30, 28), 300.0, player.hp / player.max_hp, Color(0.9, 0.3, 0.3), "HP")
		_bar(Vector2(30, 58), 300.0 * player.max_stamina / 100.0, player.stamina / player.max_stamina, Color(0.45, 0.85, 0.4), "ST")
		var ename: String = Combat.ELEMENT_NAMES[player.element]
		_canvas.draw_rect(SPECIES_RECT, Color(0, 0, 0, 0.35))
		_canvas.draw_string(_font, Vector2(30, 102), "%s  |  %s   >" % [str(player.species["name"]), ename], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Combat.ELEMENT_COLORS[player.element])
		if player.counter_window > 0.0:
			_canvas.draw_string(_font, Vector2(30, 136), "COUNTER x1.5", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.95, 0.5))
		# Stamina wheel beside the character while climbing/gliding (BOTW-style).
		if player.state in [Player.State.CLIMB, Player.State.GLIDE] or (player.sprinting and player.stamina < player.max_stamina):
			var c := Vector2(s.x * 0.5 + 70, s.y * 0.5 - 40)
			var frac := player.stamina / player.max_stamina
			_canvas.draw_arc(c, 22, 0, TAU, 32, Color(0, 0, 0, 0.4), 8)
			_canvas.draw_arc(c, 22, -PI / 2, -PI / 2 + TAU * frac, 32, Color(0.45, 0.85, 0.4) if frac > 0.25 else Color(0.95, 0.35, 0.3), 8)
	if jinn and is_instance_valid(jinn) and not jinn.is_dead():
		_bar(Vector2(s.x / 2 - 200, 28), 400.0, jinn.hp / jinn.max_hp, Color(0.6, 0.35, 0.9), "JINN")

	# Zelda-style focus diamond. Pure presentation: no targeting authority here.
	if player and player.lock_target and is_instance_valid(player.lock_target) and player.camera_rig:
		var cam := player.camera_rig.camera
		var world_at := player.lock_target.global_position + Vector3(0, 1.6, 0)
		if cam and not cam.is_position_behind(world_at):
			var screen_at := cam.unproject_position(world_at)
			if Rect2(Vector2.ZERO, s).has_point(screen_at):
				var col := Color(0.95, 0.82, 0.54, 0.9)
				for i in 4:
					var a := float(i) * PI * 0.5 - PI * 0.25
					var b := a + PI * 0.5
					_canvas.draw_line(screen_at + Vector2(cos(a), sin(a)) * 24.0, screen_at + Vector2(cos(b), sin(b)) * 24.0, col, 2.0, true)

	# Pause button.
	var pc := _pause_center()
	_canvas.draw_circle(pc, PAUSE_R, Color(0, 0, 0, 0.4))
	_canvas.draw_rect(Rect2(pc + Vector2(-8, -10), Vector2(5, 20)), Color.WHITE)
	_canvas.draw_rect(Rect2(pc + Vector2(3, -10), Vector2(5, 20)), Color.WHITE)

	if paused:
		_draw_menu()
		return

	# Joystick.
	if _joy_active:
		_canvas.draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		_canvas.draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
		var knob := _joy_origin + (_joy_pos - _joy_origin).limit_length(JOY_RADIUS)
		_canvas.draw_circle(knob, 38, Color(1, 1, 1, 0.4))
	else:
		var hint := Vector2(s.x * (0.84 if Settings.left_handed else 0.16), s.y * 0.74)
		_canvas.draw_arc(hint, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0)

	# Buttons.
	for id in BUTTONS:
		var b: Dictionary = BUTTONS[id]
		var c := _button_center(id)
		var r := _button_radius(id)
		var col: Color = b["color"]
		if id == "special" and player:
			col = Combat.ELEMENT_COLORS[player.element]
		var pressed := GameInput.is_held(id)
		_canvas.draw_circle(c, r, Color(0.05, 0.04, 0.06, 0.55 if pressed else 0.35))
		if pressed:
			_canvas.draw_circle(c, r, Color(col, 0.3))
		_canvas.draw_arc(c, r, 0, TAU, 48, Color(col, 0.8), 3.0)
		var label: String = b["label"]
		if player:
			if id == "lock" and player.lock_target:
				label = "UNLK"
			elif id == "special" and player.is_airborne():
				label = "GLIDE" if player.state == Player.State.AIR else "CLOSE"
			elif id == "jump" and player.state == Player.State.CLIMB:
				label = "LEAP"
			elif id == "dodge" and player.state == Player.State.CLIMB:
				label = "DROP"
		_canvas.draw_string(_font, c + Vector2(-r, 7), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2, 20, Color(1, 1, 1, 0.9))
	# Special charge ring with tier ticks.
	if player:
		var c2 := _button_center("special")
		var r2 := _button_radius("special") + 10.0
		var prog := player.charge_progress()
		if prog > 0.0:
			var ecol: Color = Combat.ELEMENT_COLORS[player.element]
			_canvas.draw_arc(c2, r2, -PI / 2, -PI / 2 + TAU * prog / 3.0, 48, ecol, 8.0)
			for i in 3:
				var a := -PI / 2 + TAU * (i + 1) / 3.0
				_canvas.draw_circle(c2 + Vector2(cos(a), sin(a)) * r2, 6, Color.WHITE if prog >= i + 1 else Color(1, 1, 1, 0.3))
			_canvas.draw_string(_font, c2 + Vector2(-60, -r2 - 14), "TIER %d" % player.charge_tier(), HORIZONTAL_ALIGNMENT_CENTER, 120, 22, ecol)

	if _announce_time > 0.0:
		var a2 := clampf(_announce_time / 0.4, 0.0, 1.0)
		_canvas.draw_string(_font, Vector2(0, s.y * 0.3), _announce_text, HORIZONTAL_ALIGNMENT_CENTER, s.x, 48, Color(_announce_color, a2))

	if Settings.show_debug and player:
		var row := PerfLogger.last_row
		var txt := "FPS %d  p95 %.1f ms  draws %d  |  %s" % [Engine.get_frames_per_second(), float(row.get("p95", 0.0)), int(row.get("draw_calls", 0)), player.state_name()]
		_canvas.draw_rect(Rect2(s.x / 2 - 220, s.y - 30, 440, 24), Color(0, 0, 0, 0.35))
		_canvas.draw_string(_font, Vector2(0, s.y - 12), txt, HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, Color(1, 1, 1, 0.85))


func _draw_menu() -> void:
	var s := _screen()
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.55))
	var m := _menu_rect()
	_canvas.draw_rect(m, Color(0.12, 0.09, 0.08, 0.95))
	_canvas.draw_rect(m, Color(0.85, 0.65, 0.4), false, 2.0)
	_canvas.draw_string(_font, m.position + Vector2(30, 52), "Paused", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1, 0.9, 0.75))
	var labels := {
		"resume": "Resume",
		"left_handed": "Left-handed: %s" % ("On" if Settings.left_handed else "Off"),
		"button_size": "Button size: %s" % ["Small", "Medium", "Large"][Settings.button_scale_index],
		"sound": "Sound: %s" % ("On" if Settings.sound_on else "Off"),
		"debug": "Performance overlay: %s" % ("On" if Settings.show_debug else "Off"),
		"species": "Species: %s (tap to change)" % (str(player.species["name"]) if player else "-"),
	}
	for i in MENU_ROWS.size():
		var r := _menu_row_rect(i)
		_canvas.draw_rect(r, Color(1, 1, 1, 0.08))
		_canvas.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
		_canvas.draw_string(_font, r.position + Vector2(16, 34), labels[MENU_ROWS[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	# Session stats for the playtest form.
	if player:
		var st := player.stats
		var minutes := (Time.get_ticks_msec() - _session_start_ms) / 60000.0
		var kills: int = main.jinn_kills if main else 0
		var lines := [
			"Session  %.1f min" % minutes,
			"Jinn banished  %d" % kills,
			"Deaths  %d" % int(st["deaths"]),
			"Parries  %d" % int(st["parries"]),
			"Perfect dodges  %d" % int(st["perfect_dodges"]),
			"Blocks  %d" % int(st["blocks"]),
			"Hits taken  %d" % int(st["hits_taken"]),
			"Elemental casts  %d" % int(st["casts"]),
			"Special cancels  %d" % int(st["special_cancels"]),
			"Climbed  %.0f m" % float(st["climb_m"]),
			"Glided  %.0f s" % float(st["glide_s"]),
			"Highest point  %.1f m" % float(st["max_height_m"]),
		]
		var x := m.position.x + 450
		_canvas.draw_string(_font, Vector2(x, m.position.y + 52), "This session", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.9, 0.75))
		for i in lines.size():
			_canvas.draw_string(_font, Vector2(x, m.position.y + 92 + i * 30), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1, 0.85))


func _bar(pos: Vector2, width: float, frac: float, color: Color, label: String) -> void:
	_canvas.draw_rect(Rect2(pos, Vector2(width, 18)), Color(0, 0, 0, 0.45))
	_canvas.draw_rect(Rect2(pos + Vector2(2, 2), Vector2((width - 4) * clampf(frac, 0.0, 1.0), 14)), color)
	_canvas.draw_string(_font, pos + Vector2(width + 8, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
