class_name LensFlare
extends CanvasLayer
## Realistic lens flare: when the sun is on screen and not blocked (physics
## ray toward it), a full-screen additive shader draws veiling glare,
## diffraction spikes, a chromatic halo, hexagonal ghosts with dispersion
## along the sun-centre line and a faint anamorphic streak
## (lens_flare.gdshader). Fades with occlusion and distance from centre.

var sun: DirectionalLight3D
var intensity := 0.0
var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()
var _sun_px := Vector2.ZERO


func _ready() -> void:
	layer = 5
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = load("res://game/shaders/lens_flare.gdshader")
	_rect.material = _mat
	add_child(_rect)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var target := 0.0
	if cam and sun:
		var dir := sun.global_transform.basis.z.normalized()
		var far := cam.global_position + dir * 500.0
		if not cam.is_position_behind(far):
			_sun_px = cam.unproject_position(far)
			var size := get_viewport().get_visible_rect().size
			var margin := 0.15 * size.x
			if Rect2(-Vector2.ONE * margin, size + Vector2.ONE * margin * 2.0).has_point(_sun_px):
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + dir * 300.0)
				var pl := get_tree().get_first_node_in_group("player")
				if pl is CollisionObject3D:
					q.exclude = [(pl as CollisionObject3D).get_rid()]
				var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
				# the invisible world boundary does not block the sun
				if not hit.is_empty():
					var hp: Vector3 = hit["position"]
					if maxf(absf(hp.x), absf(hp.z)) > Courtyard.BOUND - 0.7:
						hit = {}
				if hit.is_empty():
					var c := size * 0.5
					var off := (_sun_px - c).length() / c.length()
					target = clampf(1.15 - off, 0.0, 1.0)
	intensity = lerpf(intensity, target, 1.0 - exp(-6.0 * delta))
	var size := get_viewport().get_visible_rect().size
	_rect.visible = intensity > 0.002
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("sun_uv", _sun_px / size)
	_mat.set_shader_parameter("aspect", size.x / size.y)


