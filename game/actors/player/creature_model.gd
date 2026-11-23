class_name CreatureModel
extends Node3D
## Stylised Rayman-style creature: rounded body in a daraa robe, big head,
## floating hands and feet (no limbs to skin). Parts are built in Blender by
## tools/blender/build_characters.py and rendered with the toon + outline
## shader: 12 parts (eyes and ears ride on the head).
## player.gd only talks to build() and animate().

const ART_DIR := "res://game/art/characters/"
const HEAD_Y := 1.15
const BODY_Y := 0.62

var hand_r: Node3D
var hand_l: Node3D
var foot_r: Node3D
var foot_l: Node3D
var body: Node3D
var head: Node3D
var tail: Node3D
var sword: Node3D
var element_glow: MeshInstance3D
var daraa: Node3D
var eyes: Node3D
var ear_r: Node3D
var ear_l: Node3D
var _blink_in := 2.0
var _blink_t := 0.0
var _twitch_in := 3.0
var _twitch_t := 0.0
var _twitch_side := 1.0

var _mat: ShaderMaterial
var _cloth_mat: ShaderMaterial
var _glow_mat: StandardMaterial3D
var _walk_phase := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _species_key := "cat"


func build(data: Dictionary) -> void:
	_species_key = str(data["name"]).to_lower()
	_mat = CharacterArt.toon_material(_outline_color(data))
	var parts := CharacterArt.load_parts(ART_DIR + _species_key + ".glb")
	var gear := CharacterArt.load_parts(ART_DIR + "equipment.glb")

	body = _take(parts, "Body", Vector3(0, BODY_Y, 0))
	head = _take(parts, "Head", Vector3(0, HEAD_Y, 0))
	tail = _take(parts, "Tail", Vector3(0, 0.4, 0.26))
	hand_r = _take(parts, "HandR", Vector3(0.45, 0.62, -0.08))
	hand_l = _take(parts, "HandL", Vector3(-0.45, 0.62, -0.08))
	foot_r = _take(parts, "FootR", Vector3(0.17, 0.09, 0))
	foot_l = _take(parts, "FootL", Vector3(-0.17, 0.09, 0))
	# Face parts ride on the head so blinks and ear twitches follow it.
	eyes = _attach_to_head(parts, "Eyes")
	ear_r = _attach_to_head(parts, "EarR")
	ear_l = _attach_to_head(parts, "EarL")

	daraa = Node3D.new()
	daraa.position = Vector3(0, 0.95, 0.05)
	add_child(daraa)
	_cloth_mat = CharacterArt.cloth_material()
	for n in ["DaraaR", "DaraaL"]:
		if parts.has(n):
			var w: MeshInstance3D = parts[n]
			w.position = Vector3.ZERO
			w.material_override = _cloth_mat
			daraa.add_child(w)
	daraa.visible = false
	daraa.scale = Vector3(0.2, 1, 0.2)

	if gear.has("Sword"):
		sword = gear["Sword"]
		sword.transform = Transform3D.IDENTITY
		(sword as MeshInstance3D).material_override = CharacterArt.toon_material(Color(0.1, 0.08, 0.08), 0.006)
		hand_r.add_child(sword)
	if gear.has("Shield"):
		var shield: MeshInstance3D = gear["Shield"]
		shield.transform = Transform3D(Basis(), Vector3(-0.06, 0, -0.02))
		shield.material_override = _mat
		hand_l.add_child(shield)
	for k in gear:
		if (gear[k] as Node).get_parent() == null:
			(gear[k] as Node).queue_free()

	element_glow = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	element_glow.mesh = s
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_color = Color(1, 1, 1, 0)
	element_glow.material_override = _glow_mat
	element_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand_r.add_child(element_glow)


func flash(color: Color, amount: float = 1.0) -> void:
	_flash = amount
	_flash_color = color


## info keys: move (0..1), state (String), t (0..1 progress in state or climb
## speed), combo (int), charge (0..3 float), element_color (Color)
func animate(delta: float, info: Dictionary) -> void:
	var move: float = info.get("move", 0.0)
	var state: String = info.get("state", "MOVE")
	var t: float = info.get("t", 0.0)
	var charge: float = info.get("charge", 0.0)
	var ecol: Color = info.get("element_color", Color.WHITE)

	_walk_phase += delta * (4.0 + 10.0 * move)
	var bob := sin(_walk_phase * 2.0) * 0.04 * move
	var breathe := sin(Time.get_ticks_msec() * 0.003) * 0.012 * (1.0 - move)
	var body_y := BODY_Y + bob
	var head_y := HEAD_Y + bob * 1.3 + breathe
	var head_z := 0.0
	var lean := 0.0
	tail.rotation.y = sin(_walk_phase * 0.7) * 0.35
	tail.rotation.x = sin(_walk_phase * 0.5) * 0.1

	var step := sin(_walk_phase) * 0.22 * move
	var fr := Vector3(0.17, 0.09 + maxf(0.0, sin(_walk_phase)) * 0.12 * move, -step)
	var fl := Vector3(-0.17, 0.09 + maxf(0.0, -sin(_walk_phase)) * 0.12 * move, step)
	var hr := Vector3(0.45, 0.62 + bob, -0.08 + step * 0.6)
	var hl := Vector3(-0.45, 0.62 + bob, -0.08 - step * 0.6)
	var hr_rot := Vector3.ZERO
	var hl_rot := Vector3.ZERO
	lean = move * 0.12

	match state:
		"ATTACK", "HEAVY":
			var combo: int = info.get("combo", 0)
			var side := 1.0 if combo % 2 == 0 else -1.0
			var swing := clampf(t * 1.8, 0.0, 1.0)
			hr = Vector3(lerpf(0.55 * side, -0.35 * side, swing), 0.8, -0.35)
			hr_rot = Vector3(-0.3, lerpf(1.2 * side, -1.4 * side, swing), 0)
			lean = 0.2
			if state == "HEAVY":
				hr = Vector3(0.3, lerpf(1.4, 0.4, swing), -0.4)
				hr_rot = Vector3(lerpf(1.2, -1.3, swing), 0, 0)
		"HEAVY_CHARGE":
			hr = Vector3(0.35, 1.4, 0.05)
			hr_rot = Vector3(1.3, 0, 0)
			lean = -0.1
		"GUARD", "DEFENSE":
			hl = Vector3(-0.15, 0.75, -0.42)
			hl_rot = Vector3(0, -0.4, 0)
			lean = 0.05
		"DODGE", "MOBILITY":
			body_y = 0.45
			head_y = 0.92
			lean = 0.35
		"CAST":
			hr = Vector3(0.2, 0.85, -0.55)
			hl = Vector3(-0.2, 0.85, -0.55)
		"HITSTUN":
			head_z = 0.08
			lean = -0.25
		"CLIMB":
			_walk_phase += delta * absf(t) * 6.0
			var reach := sin(_walk_phase) * 0.18
			hr = Vector3(0.32, 1.25 + reach, -0.3)
			hl = Vector3(-0.32, 1.25 - reach, -0.3)
			fr = Vector3(0.18, 0.15 - reach, -0.25)
			fl = Vector3(-0.18, 0.15 + reach, -0.25)
			lean = 0.15
		"MANTLE":
			hr = Vector3(0.3, 0.9, -0.4)
			hl = Vector3(-0.3, 0.9, -0.4)
			fr = Vector3(0.17, 0.35, 0)
			fl = Vector3(-0.17, 0.35, 0)
		"AIR":
			hr = Vector3(0.5, 0.9, 0)
			hl = Vector3(-0.5, 0.9, 0)
			fr = Vector3(0.17, 0.2, 0.08)
			fl = Vector3(-0.17, 0.05, -0.08)
		"GLIDE":
			hr = Vector3(1.0, 1.0, 0.05)
			hl = Vector3(-1.0, 1.0, 0.05)
			fr = Vector3(0.15, 0.1, 0.25)
			fl = Vector3(-0.15, 0.1, 0.25)
			lean = 0.3
	if charge > 0.0:
		hr = hr.lerp(Vector3(0.3, 0.95, -0.25), 0.6)

	var gliding := state == "GLIDE"
	daraa.visible = gliding or daraa.scale.x > 0.25
	daraa.scale = daraa.scale.lerp(Vector3.ONE if gliding else Vector3(0.2, 1, 0.2), 1.0 - exp(-14.0 * delta))
	if gliding:
		daraa.rotation.x = sin(_walk_phase * 3.0) * 0.06

	var k := 1.0 - exp(-20.0 * delta)
	body.position.y = lerpf(body.position.y, body_y, k)
	body.rotation.x = lerpf(body.rotation.x, -lean, k)
	head.position.y = lerpf(head.position.y, head_y, k)
	head.position.z = lerpf(head.position.z, head_z - lean * 0.25, k)
	head.rotation.x = lerpf(head.rotation.x, -lean * 0.5, k)
	hand_r.position = hand_r.position.lerp(hr, k)
	hand_l.position = hand_l.position.lerp(hl, k)
	foot_r.position = foot_r.position.lerp(fr, k)
	foot_l.position = foot_l.position.lerp(fl, k)
	hand_r.rotation = hand_r.rotation.lerp(hr_rot, k)
	hand_l.rotation = hand_l.rotation.lerp(hl_rot, k)

	_animate_face(delta, state)

	var glow_a := clampf(charge / 3.0, 0.0, 1.0) * 0.8
	_glow_mat.albedo_color = Color(ecol.r, ecol.g, ecol.b, glow_a)
	element_glow.scale = Vector3.ONE * (0.6 + charge * 0.5)

	_flash = maxf(0.0, _flash - delta * 6.0)
	_mat.set_shader_parameter("flash", _flash * 0.9)
	_mat.set_shader_parameter("flash_color", _flash_color)


func _attach_to_head(parts: Dictionary, name: String) -> Node3D:
	var mi: MeshInstance3D = parts.get(name)
	if mi == null:
		return null
	mi.material_override = _mat
	mi.position = mi.position - Vector3(0, HEAD_Y, 0)
	head.add_child(mi)
	return mi


func _animate_face(delta: float, state: String) -> void:
	# Blink every 2-5 s (double-blink sometimes); eyes squeeze shut when hurt.
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_t = 0.14
		_blink_in = randf_range(2.0, 5.0) if randf() > 0.2 else 0.25
	_blink_t = maxf(0.0, _blink_t - delta)
	if eyes:
		var shut := _blink_t > 0.0 or state == "HITSTUN"
		eyes.scale.y = lerpf(eyes.scale.y, 0.12 if shut else 1.0, 1.0 - exp(-40.0 * delta))
	# Ear twitch, and ears flatten back when hit or gliding.
	_twitch_in -= delta
	if _twitch_in <= 0.0:
		_twitch_t = 0.25
		_twitch_side = -1.0 if randf() < 0.5 else 1.0
		_twitch_in = randf_range(2.5, 6.0)
	_twitch_t = maxf(0.0, _twitch_t - delta)
	var back := 0.6 if state in ["HITSTUN", "GLIDE", "DODGE", "MOBILITY"] else 0.0
	var tw := sin(_twitch_t * 40.0) * 0.35 if _twitch_t > 0.0 else 0.0
	var k := 1.0 - exp(-18.0 * delta)
	if ear_r:
		ear_r.rotation.x = lerpf(ear_r.rotation.x, back, k)
		ear_r.rotation.z = lerpf(ear_r.rotation.z, tw if _twitch_side > 0.0 else 0.0, k)
	if ear_l:
		ear_l.rotation.x = lerpf(ear_l.rotation.x, back, k)
		ear_l.rotation.z = lerpf(ear_l.rotation.z, -tw if _twitch_side < 0.0 else 0.0, k)


func _take(parts: Dictionary, name: String, fallback_pos: Vector3) -> Node3D:
	var mi: MeshInstance3D = parts.get(name)
	if mi == null:
		var n := Node3D.new()
		n.position = fallback_pos
		add_child(n)
		return n
	mi.material_override = _mat
	add_child(mi)
	return mi


func _outline_color(data: Dictionary) -> Color:
	var fur: Color = data["fur"]
	return fur.darkened(0.78)
