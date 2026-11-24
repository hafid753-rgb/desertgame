class_name PixelRender
extends Node
## Low-resolution render layer for the pixel-art look (Phase 1).
## The 3D world is rendered by a SubViewport at ~TARGET_LINES vertical
## resolution (integer scale of the window) and shown upscaled with nearest
## filtering; the HUD stays at native resolution on top. The game camera and
## all gameplay keep moving freely: the sub-camera copies the game camera's
## transform each frame, nothing is snapped. The root viewport stops drawing
## 3D (3D processing, physics and audio keep running).
## Assets carry their own pixel-art textures; this layer only unifies them.

const TARGET_LINES := 270
const EDGE_LAYER := 1 << 19

var source: Camera3D
var vp: SubViewport
var cam: Camera3D
var rect: TextureRect
var scale_factor := 1
var _edges: MeshInstance3D


static func attach(parent: Node, game_camera: Camera3D) -> PixelRender:
	var p := PixelRender.new()
	p.source = game_camera
	parent.add_child(p)
	return p


func _ready() -> void:
	process_priority = 1000  # after CameraRig and any shot tooling
	vp = SubViewport.new()
	vp.world_3d = get_viewport().world_3d
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.positional_shadow_atlas_size = 1024
	add_child(vp)
	cam = Camera3D.new()
	cam.current = true
	vp.add_child(cam)
	# depth-edge pass, seen only by the pixel camera
	_edges = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	_edges.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/pixel_edges.gdshader")
	m.render_priority = 100
	_edges.material_override = m
	_edges.extra_cull_margin = 16384.0
	_edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edges.layers = EDGE_LAYER
	cam.add_child(_edges)
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	rect = TextureRect.new()
	rect.texture = vp.get_texture()
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	get_viewport().size_changed.connect(_resize)
	_resize()
	get_viewport().disable_3d = true


func _exit_tree() -> void:
	if get_viewport():
		get_viewport().disable_3d = false


func _resize() -> void:
	var win := get_viewport().get_visible_rect().size
	scale_factor = maxi(1, roundi(win.y / float(TARGET_LINES)))
	vp.size = Vector2i(ceili(win.x / scale_factor), ceili(win.y / scale_factor))


func _process(_delta: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	cam.global_transform = source.global_transform
	cam.fov = source.fov
	cam.near = source.near
	cam.far = source.far
	cam.h_offset = source.h_offset
	cam.v_offset = source.v_offset
	cam.cull_mask = source.cull_mask | EDGE_LAYER
	cam.environment = source.environment
