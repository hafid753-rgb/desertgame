extends Node3D
## "The Room": courtyard + the Cat + one shadow jinn that respawns when
## defeated, so a tester can practise for as long as they like.

@export var species_id: String = "cat"
@export var jinn_enabled: bool = true

var player: Player
var camera_rig: CameraRig
var hud: TouchHud
var jinn: Jinn
var jinn_kills: int = 0

const PLAYER_SPAWN := Vector3(0, 0.1, 6)
const JINN_SPAWN := Vector3(0, 0, -3)


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
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.93, 0.8, 0.62)
	sky_mat.ground_horizon_color = Color(0.85, 0.7, 0.5)
	sky_mat.ground_bottom_color = Color(0.6, 0.45, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.93, 0.82, 0.65)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
