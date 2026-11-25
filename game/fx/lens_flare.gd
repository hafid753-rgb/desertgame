class_name LensFlare
extends CanvasLayer
## Pixel-art sun glare and lens flare. When the sun is on screen and not
## blocked (physics ray toward it), draws a stepped glare halo, short rays,
## and a chain of ghosts along the line from the sun through the screen
## centre. Every shape is built from square cells (pixel-art), alpha-blended
## additively over the 3D view. Fades in/out smoothly.

@export var cell := 4.0
var sun: DirectionalLight3D
var intensity := 0.0
var _canvas := Control.new()
var _sun_px := Vector2.ZERO

const GHOSTS := [  # [t along sun->centre axis, radius px, colour]
	[0.35, 10.0, Color(1.0, 0.85, 0.55)],
	[0.62, 22.0, Color(1.0, 0.62, 0.42)],
	[0.9, 7.0, Color(0.95, 0.95, 0.75)],
	[1.18, 30.0, Color(0.75, 0.62, 0.95)],
	[1.45, 14.0, Color(0.6, 0.85, 0.8)],
	[1.8, 40.0, Color(1.0, 0.7, 0.5)],
]


func _ready() -> void:
	layer = 5
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_canvas.material = mat
	_canvas.draw.connect(_draw_flare)
	add_child(_canvas)


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
	_canvas.queue_redraw()


func _blob(at: Vector2, r: float, col: Color, ring := false) -> void:
	var n := int(ceil(r / cell))
	var o := (at / cell).floor() * cell
	for y in range(-n, n + 1):
		for x in range(-n, n + 1):
			var d := Vector2(x, y).length() * cell
			if d > r:
				continue
			var a := col.a
			if ring:
				a *= smoothstep(r * 0.55, r * 0.85, d)
			else:
				a *= 1.0 - smoothstep(r * 0.6, r, d) * 0.6
			_canvas.draw_rect(Rect2(o + Vector2(x, y) * cell, Vector2(cell, cell)), Color(col.r, col.g, col.b, a))


func _draw_flare() -> void:
	if intensity < 0.02:
		return
	var size := get_viewport().get_visible_rect().size
	var c := size * 0.5
	var k := intensity
	# glare: stepped halo rings around the sun
	for i in 4:
		var r := 120.0 - i * 26.0
		_blob(_sun_px, r, Color(1.0, 0.86, 0.66, 0.05 * k + i * 0.02 * k))
	_blob(_sun_px, 16.0, Color(1.0, 0.98, 0.9, 0.85 * k))
	# rays: short pixel spokes
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		var lr := 70.0 if i % 2 == 0 else 44.0
		var steps := int(lr / cell)
		for s in steps:
			var p := _sun_px + Vector2(cos(a), sin(a)) * (18.0 + s * cell)
			var al := (1.0 - float(s) / steps) * 0.35 * k
			_canvas.draw_rect(Rect2((p / cell).floor() * cell, Vector2(cell, cell)), Color(1.0, 0.92, 0.75, al))
	# ghosts along sun -> centre
	var axis := c - _sun_px
	for g in GHOSTS:
		var p: Vector2 = _sun_px + axis * float(g[0])
		var col: Color = g[2]
		col.a = 0.16 * k
		_blob(p, float(g[1]), col, float(g[1]) > 20.0)
