class_name TouchHud
extends CanvasLayer
## Landscape touch controls + status bars, drawn in one Control.
## Multi-touch is handled by finger index so the joystick, camera swipe and
## buttons work at the same time. Buttons feed GameInput exactly like keys.
##
## Left 42% of the screen: floating joystick (appears where the thumb lands).
## Right side: swipe = camera, tap on a jinn = lock-on, buttons bottom-right.

const BUTTONS := {
	"attack": {"label": "ATK", "offset": Vector2(-150, -150), "r": 74.0, "color": Color(0.95, 0.85, 0.7)},
	"dodge": {"label": "DGE", "offset": Vector2(-300, -95), "r": 56.0, "color": Color(0.7, 0.9, 1.0)},
	"special": {"label": "SPC", "offset": Vector2(-115, -305), "r": 56.0, "color": Color(1.0, 0.8, 0.5)},
	"lock": {"label": "LOCK", "offset": Vector2(-290, -265), "r": 40.0, "color": Color(1, 1, 1)},
	"element": {"label": "ELM", "offset": Vector2(-70, 150), "r": 38.0, "color": Color(1, 1, 1), "top": true},
}
const JOY_RADIUS := 90.0
const SPECIES_RECT := Rect2(24, 80, 230, 32)  # tap to switch species
const TAP_MOVE := 14.0
const TAP_TIME := 0.25

var player: Player
var jinn: Jinn

var _canvas: Control
var _touches: Dictionary = {}  # index -> {role, start, pos, time}
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_active := false
var _announce_text := ""
var _announce_color := Color.WHITE
var _announce_time := 0.0
var _font: Font
var show_debug := true


func _ready() -> void:
	layer = 10
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_font = ThemeDB.fallback_font


func announce(text: String, color: Color) -> void:
	_announce_text = text
	_announce_color = color
	_announce_time = 1.1


func _process(delta: float) -> void:
	_announce_time = maxf(0.0, _announce_time - delta)
	_canvas.queue_redraw()


func _screen() -> Vector2:
	return _canvas.get_viewport_rect().size


func _button_center(id: String) -> Vector2:
	var b: Dictionary = BUTTONS[id]
	var s := _screen()
	var off: Vector2 = b["offset"]
	if b.get("top", false):
		return Vector2(s.x + off.x, off.y)
	return s + off


func _button_at(pos: Vector2) -> String:
	for id in BUTTONS:
		var r: float = BUTTONS[id]["r"]
		if pos.distance_to(_button_center(id)) <= r * 1.15:
			return id
	return ""


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index, t.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_move(d.index, d.position, d.relative)


func _touch_down(idx: int, pos: Vector2) -> void:
	var b := _button_at(pos)
	if b != "":
		_touches[idx] = {"role": b}
		GameInput.press(b)
		return
	if SPECIES_RECT.has_point(pos) and player:
		player.next_species()
		return
	var s := _screen()
	if pos.x < s.x * 0.42 and pos.y > s.y * 0.25 and not _joy_active:
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
			# Drag the origin along so the stick never "sticks" at the edge.
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


func _draw_hud() -> void:
	var s := _screen()
	# Bars: width reflects the species' max stamina so the trade-off is visible.
	if player:
		_bar(Vector2(30, 28), 300.0, player.hp / player.max_hp, Color(0.9, 0.3, 0.3), "HP")
		_bar(Vector2(30, 58), 300.0 * player.max_stamina / 100.0, player.stamina / player.max_stamina, Color(0.45, 0.85, 0.4), "ST")
		var ename: String = Combat.ELEMENT_NAMES[player.element]
		_canvas.draw_rect(SPECIES_RECT, Color(0, 0, 0, 0.35))
		_canvas.draw_string(_font, Vector2(30, 102), "%s  |  %s   >" % [str(player.species["name"]), ename], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Combat.ELEMENT_COLORS[player.element])
		if player.counter_window > 0.0:
			_canvas.draw_string(_font, Vector2(30, 126), "COUNTER x1.5", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.95, 0.5))
	if jinn and is_instance_valid(jinn) and not jinn.is_dead():
		_bar(Vector2(s.x / 2 - 200, 28), 400.0, jinn.hp / jinn.max_hp, Color(0.6, 0.35, 0.9), "JINN")

	# Joystick.
	if _joy_active:
		_canvas.draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		_canvas.draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
		var knob := _joy_origin + (_joy_pos - _joy_origin).limit_length(JOY_RADIUS)
		_canvas.draw_circle(knob, 38, Color(1, 1, 1, 0.4))
	else:
		var hint := Vector2(s.x * 0.16, s.y * 0.74)
		_canvas.draw_arc(hint, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0)

	# Buttons.
	for id in BUTTONS:
		var b: Dictionary = BUTTONS[id]
		var c := _button_center(id)
		var r: float = b["r"]
		var col: Color = b["color"]
		if id == "special" and player:
			col = Combat.ELEMENT_COLORS[player.element]
		var pressed := GameInput.is_held(id)
		_canvas.draw_circle(c, r, Color(0.05, 0.04, 0.06, 0.55 if pressed else 0.35))
		if pressed:
			_canvas.draw_circle(c, r, Color(col, 0.3))
		_canvas.draw_arc(c, r, 0, TAU, 48, Color(col, 0.8), 3.0)
		var label: String = b["label"]
		if id == "lock" and player and player.lock_target:
			label = "UNLK"
		_canvas.draw_string(_font, c + Vector2(-r, 7), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2, 20, Color(1, 1, 1, 0.9))
	# Special charge ring with tier ticks.
	if player:
		var c2 := _button_center("special")
		var r2: float = BUTTONS["special"]["r"] + 10.0
		var prog := player.charge_progress()
		if prog > 0.0:
			var ecol: Color = Combat.ELEMENT_COLORS[player.element]
			_canvas.draw_arc(c2, r2, -PI / 2, -PI / 2 + TAU * prog / 3.0, 48, ecol, 8.0)
			for i in 3:
				var a := -PI / 2 + TAU * (i + 1) / 3.0
				_canvas.draw_circle(c2 + Vector2(cos(a), sin(a)) * r2, 6, Color.WHITE if prog >= i + 1 else Color(1, 1, 1, 0.3))
			_canvas.draw_string(_font, c2 + Vector2(-60, -r2 - 14), "TIER %d" % player.charge_tier(), HORIZONTAL_ALIGNMENT_CENTER, 120, 22, ecol)

	# Announcements (PARRY!, PERFECT DODGE...).
	if _announce_time > 0.0:
		var a2 := clampf(_announce_time / 0.4, 0.0, 1.0)
		_canvas.draw_string(_font, Vector2(0, s.y * 0.3), _announce_text, HORIZONTAL_ALIGNMENT_CENTER, s.x, 48, Color(_announce_color, a2))

	# Debug line.
	if show_debug and player:
		var row := PerfLogger.last_row
		var txt := "FPS %d  p95 %.1f ms  draws %d  |  %s" % [Engine.get_frames_per_second(), float(row.get("p95", 0.0)), int(row.get("draw_calls", 0)), player.state_name()]
		_canvas.draw_string(_font, Vector2(0, s.y - 14), txt, HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, Color(1, 1, 1, 0.6))


func _bar(pos: Vector2, width: float, frac: float, color: Color, label: String) -> void:
	_canvas.draw_rect(Rect2(pos, Vector2(width, 18)), Color(0, 0, 0, 0.45))
	_canvas.draw_rect(Rect2(pos + Vector2(2, 2), Vector2((width - 4) * clampf(frac, 0.0, 1.0), 14)), color)
	_canvas.draw_string(_font, pos + Vector2(width + 8, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
