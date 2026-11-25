class_name WaterReflection
extends Node
## Planar reflection for a pond, the way Noio does it: a second camera,
## mirrored below the water plane, renders only objects on the REFLECT
## layer (palms, acacias, the player) over the sky into a full-resolution
## SubViewport; pixel_water.gdshader samples it at the mirrored screen UV
## and dithers it onto the water's world texel grid. The ground is never
## on the REFLECT layer, so no oblique clipping is needed. Rendering is
## skipped while the pond is off-screen or far away.

const REFLECT_LAYER := 1 << 19   # render layer 20

@export var water_y := 0.05
@export var max_distance := 60.0
var centre := Vector3.ZERO
var material: ShaderMaterial
var vp: SubViewport
var cam: Camera3D
var active := false
var _tagged_player := false


static func tag(node: Node) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers |= REFLECT_LAYER
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers |= REFLECT_LAYER


func _ready() -> void:
	vp = SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	vp.transparent_bg = true      # alpha marks reflected objects; sky stays stylised
	add_child(vp)
	cam = Camera3D.new()
	cam.cull_mask = REFLECT_LAYER
	cam.far = max_distance
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("82788D")
	env.ambient_light_energy = 0.75
	cam.environment = env
	vp.add_child(cam)
	if material:
		material.set_shader_parameter("reflection_tex", vp.get_texture())


func _process(_delta: float) -> void:
	var main_cam := get_viewport().get_camera_3d()
	if main_cam == null or material == null:
		return
	if not _tagged_player:
		var p := get_tree().get_first_node_in_group("player")
		if p:
			tag(p)
			_tagged_player = true
	vp.world_3d = get_viewport().world_3d
	var size := get_viewport().get_visible_rect().size
	if Vector2(vp.size) != size:
		vp.size = Vector2i(size)
	var g := main_cam.global_transform
	var near := g.origin.distance_to(centre) < max_distance
	var seen := near and (main_cam.is_position_in_frustum(centre) or g.origin.distance_to(centre) < 12.0)
	if seen != active:
		active = seen
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if seen else SubViewport.UPDATE_DISABLED
		material.set_shader_parameter("reflection_on", 1.0 if seen else 0.0)
	if not active:
		return
	# Mirror the main camera in the plane y = water_y. A proper (det +1)
	# camera built with look_at ends up flipped left-right relative to the
	# true mirror view; the water shader samples at (1 - u, v) to undo it.
	var pos := g.origin
	pos.y = 2.0 * water_y - pos.y
	var fwd := -g.basis.z
	fwd.y = -fwd.y
	var up := g.basis.y
	up.y = -up.y
	cam.fov = main_cam.fov
	cam.near = main_cam.near
	cam.keep_aspect = main_cam.keep_aspect
	cam.look_at_from_position(pos, pos + fwd, up)
