class_name Fx
extends RefCounted
## Cheap, mobile-friendly effects: unshaded meshes that scale and fade.
## No particles, so they behave the same on the Mobile and Compatibility renderers.

static var _sphere: SphereMesh
static var _disc: CylinderMesh


static func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func burst(parent: Node, pos: Vector3, color: Color, radius: float, duration: float = 0.3, squash: Vector3 = Vector3.ONE) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radial_segments = 12
		_sphere.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	var mat := _mat(color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = squash * 0.2
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", squash * radius, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)


## A flat expanding ring on the ground (used for shockwaves).
static func ring(parent: Node, pos: Vector3, color: Color, radius: float, duration: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _disc == null:
		_disc = CylinderMesh.new()
		_disc.height = 0.04
		_disc.top_radius = 1.0
		_disc.bottom_radius = 1.0
		_disc.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = _disc
	var mat := _mat(color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3(0.2, 1, 0.2)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1, radius), duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)


static func popup(parent: Node, pos: Vector3, text: String, color: Color, size: int = 64) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.font_size = size
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position", pos + Vector3(0, 0.9, 0), 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)
