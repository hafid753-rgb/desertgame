extends Node
## Game feel: sound effects, hit-stop and camera shake in one place.
## Hit-stop dips Engine.time_scale; in multiplayer this becomes a
## client-only presentation effect (the server never pauses).

const SOUNDS := [
	"swing", "hit", "parry", "block", "dodge", "perfect", "hurt", "tier1", "tier2", "tier3",
	"fire", "wind", "jump", "land", "glide", "grab", "tel_swipe", "tel_lunge", "tel_burst", "banish",
]
const POOL_SIZE := 12

var enabled_hitstop: bool = true
var camera: Node  # CameraRig
var volume_db: float = 0.0

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _next: int = 0
var _hitstop_until: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SOUNDS:
		var path := "res://game/audio/%s.wav" % s
		if ResourceLoader.exists(path):
			_streams[s] = load(path)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 45.0
		add_child(p)
		_pool.append(p)
	for i in 4:
		var f := AudioStreamPlayer.new()
		add_child(f)
		_flat.append(f)


## Positional sound. pos = null plays it flat (UI-style).
func play(name: String, pos: Variant = null, pitch: float = 1.0, db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var p_scale := pitch * randf_range(0.94, 1.06)
	if pos == null:
		for f in _flat:
			if not f.playing:
				f.stream = stream
				f.pitch_scale = p_scale
				f.volume_db = db + volume_db
				f.play()
				return
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.global_position = pos
	p.pitch_scale = p_scale
	p.volume_db = db + volume_db
	p.play()


func hitstop(seconds: float) -> void:
	if not enabled_hitstop or seconds <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	if until <= _hitstop_until:
		return
	_hitstop_until = until
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	if Time.get_ticks_msec() >= _hitstop_until:
		Engine.time_scale = 1.0


func shake(amount: float) -> void:
	if camera and camera.has_method("shake"):
		camera.shake(amount)
