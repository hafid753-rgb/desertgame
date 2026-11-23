extends Node
## Single input path for keyboard, gamepad and the touch HUD.
## Every button press/release becomes a timestamped event in a queue that the
## player consumes once per physics tick, so a touch tap shorter than one frame
## is never lost and input latency can be measured from the event time.

const BUTTONS: Array[String] = ["attack", "dodge", "special", "lock", "cycle_target", "element", "species"]

var held: Dictionary = {}
var touch_move: Vector2 = Vector2.ZERO
var _events: Array[Dictionary] = []
var _look_delta: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input_map()


func press(action: String) -> void:
	if held.get(action, false):
		return
	held[action] = true
	_events.append({"action": action, "pressed": true, "t_usec": Time.get_ticks_usec()})


func release(action: String) -> void:
	if not held.get(action, false):
		return
	held[action] = false
	_events.append({"action": action, "pressed": false, "t_usec": Time.get_ticks_usec()})


func is_held(action: String) -> bool:
	return held.get(action, false)


func consume_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func add_look(delta: Vector2) -> void:
	_look_delta += delta


func consume_look() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


## Joystick / keyboard movement, x = right, y = back (forward is negative).
func get_move() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > v.length():
		v = touch_move
	return v.limit_length(1.0)


func get_look_stick() -> Vector2:
	return Input.get_vector("look_left", "look_right", "look_up", "look_down")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		add_look((event as InputEventMouseMotion).relative)
		return
	if event.is_echo():
		return
	for a in BUTTONS:
		if event.is_action(a):
			if event.is_pressed():
				press(a)
			else:
				release(a)


func _setup_input_map() -> void:
	_add("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add("move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add("move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add("look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_add("look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_add("look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_add("look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_add("attack", [_key(KEY_J), _mouse(MOUSE_BUTTON_LEFT), _joy(JOY_BUTTON_X)])
	_add("dodge", [_key(KEY_K), _key(KEY_SPACE), _joy(JOY_BUTTON_B)])
	_add("special", [_key(KEY_L), _key(KEY_SHIFT), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	_add("lock", [_key(KEY_TAB), _mouse(MOUSE_BUTTON_MIDDLE), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_add("cycle_target", [_key(KEY_Q), _joy(JOY_BUTTON_RIGHT_STICK)])
	_add("element", [_key(KEY_E), _joy(JOY_BUTTON_Y)])
	_add("species", [_key(KEY_1), _joy(JOY_BUTTON_BACK)])


func _add(action: String, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEvent:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEvent:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy(button: JoyButton) -> InputEvent:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEvent:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
