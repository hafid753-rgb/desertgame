extends Node
## A/B frame cost of the daraa vs the old robe, in the real game scene:
##   xvfb-run godot --path . res://tools/daraa_perf.tscn [-- no_daraa]
## Close third-person view at the oasis, character walking in a circle.
## Prints mean / p95 frame time, primitives and the garment's CPU update.

var main: Node3D
var t := 0.0
var samples: Array[float] = []
var prims: Array[float] = []
var last := 0


func _ready() -> void:
	Settings.quality = 2
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	main.hud.visible = false
	main.player.global_position = Vector3(-19, 0.05, 5)
	last = Time.get_ticks_usec()


func _process(delta: float) -> void:
	t += delta
	GameInput.touch_move = Vector2(sin(t * 0.8), -cos(t * 0.8)) * 0.5
	var now := Time.get_ticks_usec()
	if t > 3.0:
		samples.append((now - last) / 1000.0)
		prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	last = now
	if samples.size() >= 150:
		var s := samples.duplicate()
		s.sort()
		var mean := 0.0
		for v in s:
			mean += v
		mean /= s.size()
		var pm := 0.0
		for v in prims:
			pm += v
		print("PERF daraa=%s mean_ms=%.1f p95_ms=%.1f primitives=%d" % [str(not OS.get_cmdline_user_args().has("no_daraa")), mean, s[int(s.size() * 0.95)], int(pm / prims.size())])
		get_tree().quit()
