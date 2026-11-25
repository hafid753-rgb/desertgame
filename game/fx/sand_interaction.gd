class_name SandInteraction
extends Node
## Spec 06 "Interaction & erosion": a signed height / compaction mask in
## world space around the player, sampled by sand_ripple.gdshader.
##   R  height offset, 0.5 = untouched (< 0.5 dent, > 0.5 raised rim)
##   G  compaction (darker, no glitter)
##   B  stamp time (half-seconds, mod 256): the shader fades marks with age,
##      so there is no per-frame CPU decay; a background sweep clears marks
##      older than a minute before the 128 s clock wraps.
## 256 x 256 texels over 16 m (6.25 cm/texel), recentred in whole texels as
## the player moves. Visual only: collision and movement are untouched.

const RES := 256
const SIZE := 16.0
const TEXEL := SIZE / RES
const RECENTRE := 4.0

var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
var tex: ImageTexture
var origin := Vector2.ZERO          # world xz of texel (0, 0)
var _dirty := false
var _sweep := 0
var stamps := 0


func _ready() -> void:
	add_to_group("sand_fx")
	img.fill(Color(0.5, 0.0, 0.0))
	tex = ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("sand_mask", tex)
	_publish()


func _now_q() -> int:
	return int(floor(Wind.time * 2.0)) % 256


func _publish() -> void:
	RenderingServer.global_shader_parameter_set("sand_mask_rect", Vector4(origin.x, origin.y, SIZE, 1.0))
	RenderingServer.global_shader_parameter_set("sand_mask_now", float(_now_q()))


func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		var centre := origin + Vector2.ONE * SIZE * 0.5
		var at := Vector2(p.global_position.x, p.global_position.z)
		if at.distance_to(centre) > RECENTRE:
			_recentre(at)
	# clear marks older than ~60 s, 2048 texels per frame
	var now := _now_q()
	for i in 2048:
		var x := _sweep % RES
		var y := (_sweep / RES) % RES
		_sweep = (_sweep + 1) % (RES * RES)
		var c := img.get_pixel(x, y)
		if c.r != 0.5 or c.g > 0.0:
			var age := (now - int(round(c.b * 255.0)) + 256) % 256
			if age > 120:
				img.set_pixel(x, y, Color(0.5, 0.0, 0.0))
				_dirty = true
	if _dirty:
		tex.update(img)
		_dirty = false
	_publish()


func _recentre(at: Vector2) -> void:
	var new_origin := ((at - Vector2.ONE * SIZE * 0.5) / TEXEL).floor() * TEXEL
	var shift := Vector2i(((new_origin - origin) / TEXEL).round())
	var fresh := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	fresh.fill(Color(0.5, 0.0, 0.0))
	var src := Rect2i(Vector2i.ZERO, Vector2i(RES, RES)).intersection(Rect2i(shift, Vector2i(RES, RES)))
	if src.size.x > 0 and src.size.y > 0:
		fresh.blit_rect(img, src, src.position - shift)
	img = fresh
	origin = new_origin
	_dirty = true


func _texel(world: Vector3) -> Vector2:
	return (Vector2(world.x, world.z) - origin) / TEXEL


## Write a mark: `h` signed height (-1 dent .. +1 rim), `comp` 0..1.
func _put(x: int, y: int, h: float, comp: float) -> void:
	if x < 0 or y < 0 or x >= RES or y >= RES:
		return
	var c := img.get_pixel(x, y)
	var age := (_now_q() - int(round(c.b * 255.0)) + 256) % 256
	var keep := 1.0 - clampf(float(age) / 90.0, 0.0, 1.0)     # older marks give way
	var cur_h := (c.r - 0.5) * 2.0 * keep
	var nh := clampf(minf(cur_h, h) if h < 0.0 else maxf(cur_h, h), -1.0, 1.0)
	if h > 0.0 and cur_h < -0.1:
		nh = cur_h                       # rims never fill an existing dent
	img.set_pixel(x, y, Color(0.5 + nh * 0.5, maxf(c.g * keep, comp), float(_now_q()) / 255.0))
	_dirty = true


## Boot print: heel-to-toe depression (deeper at the heel), sand pushed up
## in a thin rim, strongest at the toe.
func footprint(world: Vector3, fwd: Vector3, depth: float = 1.0) -> void:
	stamps += 1
	var c := _texel(world)
	var f := Vector2(fwd.x, fwd.z).normalized()
	var s := Vector2(-f.y, f.x)
	var half_l := 0.15 / TEXEL
	var half_w := 0.075 / TEXEL
	var rmax := int(ceil(half_l + 3.0))
	for y in range(int(c.y) - rmax, int(c.y) + rmax + 1):
		for x in range(int(c.x) - rmax, int(c.x) + rmax + 1):
			var q := Vector2(x + 0.5, y + 0.5) - c
			var u := q.dot(f) / half_l              # -1 heel .. +1 toe
			var v := q.dot(s) / (half_w * (1.0 - 0.25 * u))
			var d := sqrt(u * u + v * v)
			if d < 1.0:
				_put(x, y, -(0.75 + 0.25 * (-u)) * depth * (1.0 - d * d * 0.5), 0.8 * depth)
			elif d < 1.35:
				var rim := (1.0 - absf(d - 1.15) / 0.2) * (0.45 + 0.35 * maxf(u, 0.0))
				if rim > 0.0:
					_put(x, y, rim * depth * 0.6, 0.0)


## Continuous groove (slides, dodges): stamps along the segment.
func groove(a: Vector3, b: Vector3, width: float = 0.22, depth: float = 0.8) -> void:
	var n := maxi(1, int(a.distance_to(b) / (TEXEL * 1.5)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		crater(p, width * 0.5, depth, 0.0)


## Round impression (landings): bowl with a soft rim.
func crater(world: Vector3, radius: float = 0.4, depth: float = 1.0, rim_amt: float = 0.7) -> void:
	stamps += 1
	var c := _texel(world)
	var r := radius / TEXEL
	var rmax := int(ceil(r * 1.4))
	for y in range(int(c.y) - rmax, int(c.y) + rmax + 1):
		for x in range(int(c.x) - rmax, int(c.x) + rmax + 1):
			var d := (Vector2(x + 0.5, y + 0.5) - c).length() / r
			if d < 1.0:
				_put(x, y, -depth * (1.0 - d * d), 0.6 * depth)
			elif d < 1.4 and rim_amt > 0.0:
				_put(x, y, rim_amt * (1.0 - absf(d - 1.2) / 0.2) * depth, 0.0)
