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
## Phase 1 low-res pixel render layer (see PixelRender).
## Off: the pixel-art look lives in the assets at full resolution (Noio's
## approach); the low-res layer stays available as an option.
@export var pixel_render_enabled: bool = false
var pixel_render: PixelRender
var sun: DirectionalLight3D
var _haunt: float = 0.0

const PLAYER_SPAWN := Vector3(0, 0.1, 6)
const JINN_SPAWN := Vector3(0, 0, -3)
const OASIS_AT := Vector3(-32, 0, -4)
const VILLAGE_AT := Vector3(40, 0, 0)


func _ready() -> void:
	_build_environment()
	var courtyard := Courtyard.new()
	add_child(courtyard)
	var oasis := Oasis.new()
	oasis.position = OASIS_AT
	add_child(oasis)
	var horizon := DuneHorizon.new()
	# far dunes: same sand, but smooth (no patches or pebbles), as in the photo
	var far_sand := courtyard._sand_mat(Courtyard.SAND).duplicate() as ShaderMaterial
	far_sand.set_shader_parameter("mottle", 0.0)
	far_sand.set_shader_parameter("pebble_density", 0.0)
	far_sand.set_shader_parameter("y_squash", 0.75)
	far_sand.set_shader_parameter("lambert_gain", 2.2)
	horizon.material_override = far_sand
	add_child(horizon)
	add_child(GroundFX.new())
	var dust := WindDust.new()
	add_child(dust)
	dust.mask_water(OASIS_AT, oasis.pond_radius * 1.15)
	dust.set_ground_half(Courtyard.BOUND + 5.0)

	player = Player.new()
	player.species_id = species_id
	player.position = PLAYER_SPAWN
	add_child(player)

	camera_rig = CameraRig.new()
	camera_rig.follow = player
	add_child(camera_rig)
	player.camera_rig = camera_rig
	if pixel_render_enabled and DisplayServer.get_name() != "headless":
		pixel_render = PixelRender.attach(self, camera_rig.camera)
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
		village.stage_changed.connect(func(_s: String) -> void: player.emote("peace", 2.2))
		hud.boss = village.king


## Entering a haunted village dims the sun and thickens a violet haze;
## once the village is claimed the desert light comes back.
func _process(delta: float) -> void:
	if village == null or player == null or env == null:
		return
	var inside := Combat.flat(player.global_position - village.global_position).length() < 20.0
	var target := 1.0 if inside and village.is_haunted() else 0.0
	_haunt = lerpf(_haunt, target, 1.0 - exp(-1.5 * delta))
	env.fog_light_color = Color("F0D1B5").lerp(Color(0.36, 0.26, 0.48), _haunt)
	env.fog_density = lerpf(0.92, 1.0, _haunt)
	env.fog_depth_begin = lerpf(18.0, 2.0, _haunt)
	sun.light_energy = lerpf(0.95, 0.5, _haunt)


func spawn_jinn() -> Jinn:
	jinn = Jinn.new()
	jinn.position = JINN_SPAWN
	add_child(jinn)
	jinn.defeated.connect(_on_jinn_defeated)
	hud.jinn = jinn
	return jinn


func _on_jinn_defeated(_j: Jinn) -> void:
	jinn_kills += 1
	player.emote("thumbs_up")
	hud.announce("Jinn banished (%d)" % jinn_kills, Color(0.8, 0.6, 1.0))
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree():
		spawn_jinn()


func _build_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-33), deg_to_rad(35), 0)   # low golden sun: long shadows, modelled dunes
	sun.light_color = Color("FFE3C4")  # warm, soft desert sun (reference photo)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	# sun-bleached, dusty sky: pale horizon haze, restrained blue
	sky_mat.sky_top_color = Color("EDD2B8")      # hazy cream sky (reference photo)
	sky_mat.sky_horizon_color = Color("F0D1B5")
	sky_mat.ground_horizon_color = Color("F0D1B5")
	sky_mat.ground_bottom_color = Color("D99A70")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# warm ambient: cream sky + light bounced off orange sand, so shadows
	# stay rust/peach as in the reference photo, never grey or purple
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("D9A88A")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
	# atmospheric depth: warm dusty haze, distant scenery loses contrast
	env.fog_enabled = true
	# strong warm aerial perspective: far dunes melt into the cream haze
	env.fog_light_color = Color("F0D1B5")
	# depth fog: near sand stays saturated, haze builds with distance and
	# swallows the far dunes (reference photo)
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 240.0
	env.fog_depth_curve = 1.6
	env.fog_density = 0.92
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 1.0
	# restrained saturation
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
