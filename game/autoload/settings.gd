extends Node
## Player-facing settings, saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"
const BUTTON_SCALES: Array[float] = [0.85, 1.0, 1.2]

var left_handed: bool = false
var button_scale_index: int = 1
var show_debug: bool = true
var sound_on: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		left_handed = cfg.get_value("controls", "left_handed", left_handed)
		button_scale_index = clampi(cfg.get_value("controls", "button_scale_index", button_scale_index), 0, BUTTON_SCALES.size() - 1)
		show_debug = cfg.get_value("display", "show_debug", show_debug)
		sound_on = cfg.get_value("audio", "sound_on", sound_on)
	_apply()


func button_scale() -> float:
	return BUTTON_SCALES[button_scale_index]


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "left_handed", left_handed)
	cfg.set_value("controls", "button_scale_index", button_scale_index)
	cfg.set_value("display", "show_debug", show_debug)
	cfg.set_value("audio", "sound_on", sound_on)
	cfg.save(PATH)
	_apply()
	changed.emit()


func _apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, not sound_on)
