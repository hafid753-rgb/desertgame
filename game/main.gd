extends Node3D
## "The Room": courtyard + the Cat + one shadow jinn that respawns when
## defeated, so a tester can practise for as long as they like.

@export var species_id: String = "cat"
@export var jinn_enabled: bool = true
@export var village_enabled: bool = true

var player: Player
var camera_rig: CameraRig
var hud: TouchHud
var jinn: Jinn
var jinn_kills: int = 0
var village: Village
var env: Environment
var sun: DirectionalLight3D
var _haunt: float = 0.0

const PLAYER_SPAWN := Vector3(0, 0.1, 6)
const JINN_SPAWN := Vector3(0, 0, -3)
const VILLAGE_AT := Vector3(40, 0, 0)


func _ready() -> void:
	_build_environment()
	add_child(Courtyard.new())

	player = Player.new()
	player.species_id = species_id
	player.position = PLAYER_SPAWN
	add_child(player)

	camera_rig = CameraRig.new()
	camera_rig.follow = player
	add_child(camera_rig)
	player.camera_rig = camera_rig
	Juice.camera = camera_rig

	hud = TouchHud.new()
	hud.player = player
	hud.main = self
	add_child(hud)
	player.announced.connect(hud.announce)

	if jinn_enabled:
		spawn_jinn()
	if village_enabled:
		village = Village.new()
		village.position = VILLAGE_AT
		add_child(village)
		village.announced.connect(hud.announce)
		hud.boss = village.king


## Entering a haunted village dims the sun and thickens a violet haze;
## once the village is claimed the desert light comes back.
func _process(delta: float) -> void:
	if village == null or player == null or env == null:
		return
	var inside := Combat.flat(player.global_position - village.global_position).length() < 20.0
	var target := 1.0 if inside and village.is_haunted() else 0.0
	_haunt = lerpf(_haunt, target, 1.0 - exp(-1.5 * delta))
	env.fog_light_color = Color(0.93, 0.82, 0.65).lerp(Color(0.36, 0.26, 0.48), _haunt)
	env.fog_density = lerpf(0.004, 0.028, _haunt)
	sun.light_energy = lerpf(0.85, 0.45, _haunt)


func spawn_jinn() -> Jinn:
	jinn = Jinn.new()
	jinn.position = JINN_SPAWN
	add_child(jinn)
	jinn.defeated.connect(_on_jinn_defeated)
	hud.jinn = jinn
	return jinn


func _on_jinn_defeated(_j: Jinn) -> void:
	jinn_kills += 1
	hud.announce("Jinn banished (%d)" % jinn_kills, Color(0.8, 0.6, 1.0))
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree():
		spawn_jinn()


func _build_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	sun.light_color = Color(1.0, 0.86, 0.67)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.29, 0.40, 0.64)
	sky_mat.sky_horizon_color = Color(0.96, 0.70, 0.54)
	sky_mat.ground_horizon_color = Color(0.89, 0.64, 0.49)
	sky_mat.ground_bottom_color = Color(0.6, 0.45, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.83, 0.67, 0.62)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
