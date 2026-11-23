extends Node
## Writes one CSV row per second to user://perf_<timestamp>.csv:
## FPS, frame-time percentiles, draw calls, memory and input latency.
## On Android the file is in the app's private data folder; the on-screen
## overlay shows the same numbers live.

var player_state: String = ""
var last_row: Dictionary = {}
var file_path: String = ""

var _frames: PackedFloat32Array = PackedFloat32Array()
var _latency: PackedFloat32Array = PackedFloat32Array()
var _acc: float = 0.0
var _elapsed: float = 0.0
var _file: FileAccess


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	file_path = "user://perf_%s.csv" % stamp
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file:
		_file.store_line("t_s,fps,ft_mean_ms,ft_p95_ms,ft_p99_ms,ft_max_ms,draw_calls,primitives,static_mem_mb,input_to_action_ms_p50,device,renderer,player_state")


## Call with the input event timestamp when the action it triggered starts.
func record_latency(t_usec: int) -> void:
	if t_usec <= 0:
		return
	_latency.append(float(Time.get_ticks_usec() - t_usec) / 1000.0)


func _process(delta: float) -> void:
	_frames.append(delta * 1000.0)
	_acc += delta
	_elapsed += delta
	if _acc >= 1.0:
		_flush()
		_acc = 0.0


func _flush() -> void:
	if _frames.is_empty():
		return
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for f in sorted:
		total += f
	var lat_p50 := -1.0
	if not _latency.is_empty():
		var ls := _latency.duplicate()
		ls.sort()
		lat_p50 = ls[ls.size() / 2]
	last_row = {
		"fps": Engine.get_frames_per_second(),
		"mean": total / n,
		"p95": sorted[mini(n - 1, int(n * 0.95))],
		"p99": sorted[mini(n - 1, int(n * 0.99))],
		"max": sorted[n - 1],
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"mem_mb": OS.get_static_memory_usage() / 1048576.0,
		"latency_p50": lat_p50,
	}
	if _file:
		var device := OS.get_model_name().replace(",", " ")
		var renderer := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
		_file.store_line("%.1f,%d,%.2f,%.2f,%.2f,%.2f,%d,%d,%.1f,%.1f,%s,%s,%s" % [
			_elapsed, last_row.fps, last_row.mean, last_row.p95, last_row.p99, last_row.max,
			last_row.draw_calls, last_row.primitives, last_row.mem_mb, lat_p50, device, renderer, player_state])
		_file.flush()
	_frames.clear()
	_latency.clear()
