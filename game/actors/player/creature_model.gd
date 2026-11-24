class_name CreatureModel
extends Node3D
## Boxy adventurer creature, Rayman-style: long daraa robe, rounded-box head,
## floating hands and shoes (no limbs). Parts are built in Blender by
## tools/blender/build_characters.py and rendered with the toon + outline
## shader. Each hand has five poses and shows one at a time:
##   open       walking, idle, climbing, gliding, casting
##   fist       running, dodging, punching
##   grip       holding the sword (combat)
##   thumbs_up  emote (jinn banished)
##   peace      emote (village claimed, species switch)
## Outside combat the sword and shield are carried on the back.
## player.gd talks to build(), animate(), set_armed() and emote().

const ART_DIR := "res://game/art/characters/"
# Adventurer proportions (~1.75 m), see tools/blender/build_characters.py.
const HEAD_Y := 1.28
const BODY_Y := 0.7312
const HAND := Vector3(0.5, 0.66, -0.1)
const FOOT := Vector3(0.15, 0.0, 0.0)
const POSES: Array[String] = ["open", "fist", "grip", "thumbs_up", "peace"]

var hand_r: Node3D
var hand_l: Node3D
var foot_r: Node3D
var foot_l: Node3D
var body: Node3D
var head: Node3D
var tail: Node3D
var sword: Node3D
var scabbard: Node3D
var hawli: Node3D
var eyes_closed: Node3D
var eyes_shut := false
var turban: Node3D
## Diagonal across the back, hilt over the right shoulder.
const BACK_SWORD := Transform3D(Basis(Vector3.FORWARD, 0.7) * Basis(Vector3.RIGHT, -PI / 2), Vector3(0.16, 0.44, 0.3))
var element_glow: MeshInstance3D
var daraa: Node3D
var eyes: Node3D
var ear_r: Node3D
var ear_l: Node3D
var shield: Node3D
var armed: bool = false
var hand_pose_r: String = "open"
var hand_pose_l: String = "open"
var _poses_r: Dictionary = {}
var _poses_l: Dictionary = {}
var _emote: String = ""
var _emote_t: float = 0.0
var _blink_in := 2.0
var _blink_t := 0.0
var _twitch_in := 3.0
var _twitch_t := 0.0
var _twitch_side := 1.0

var _mat: ShaderMaterial
var _cloth_mat: ShaderMaterial
var _fabric_mat: ShaderMaterial
var _gloss_mat: ShaderMaterial
var _leather_mat: ShaderMaterial
var _sword_mat: ShaderMaterial
var enchanted: bool = false
var _glow_mat: StandardMaterial3D
var _walk_phase := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _species_key := "cat"


func build(data: Dictionary) -> void:
	_species_key = str(data["name"]).to_lower()
	var oc := _outline_color(data)
	_mat = CharacterArt.toon_material(oc, 0.007, "skin")
	_fabric_mat = CharacterArt.toon_material(oc, 0.007, "fabric")
	_gloss_mat = CharacterArt.toon_material(oc, 0.0, "gloss")
	_leather_mat = CharacterArt.toon_material(oc, 0.007, "leather")
	var parts := CharacterArt.load_parts(ART_DIR + _species_key + ".glb")
	var gear := CharacterArt.load_parts(ART_DIR + "equipment.glb")

	body = _take(parts, "Body", Vector3(0, BODY_Y, 0))
	head = _take(parts, "Head", Vector3(0, HEAD_Y, 0))
	tail = _take(parts, "Tail", Vector3(0, 0.5, 0.24))
	hand_r = _hand(parts, "HandR", HAND, _poses_r)
	hand_l = _hand(parts, "HandL", Vector3(-HAND.x, HAND.y, HAND.z), _poses_l)
	foot_r = _take(parts, "FootR", FOOT)
	foot_l = _take(parts, "FootL", Vector3(-FOOT.x, FOOT.y, FOOT.z))
	# Face parts ride on the head so blinks and ear twitches follow it.
	eyes = _attach_to_head(parts, "Eyes")
	eyes_closed = _attach_to_head(parts, "EyesClosed")
	if eyes_closed:
		eyes_closed.visible = false
	ear_r = _attach_to_head(parts, "EarR")
	ear_l = _attach_to_head(parts, "EarL")
	# Hawli / tagelmust: neck wrap and/or turban, worn per species.
	hawli = _attach_to_head(parts, "Hawli")
	turban = _attach_to_head(parts, "Turban")

	daraa = Node3D.new()
	daraa.position = Vector3(0, 0.9912, 0.02)
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
		_sword_mat = CharacterArt.toon_material(Color(0.1, 0.08, 0.08), 0.006)
		(sword as MeshInstance3D).material_override = _sword_mat
	if gear.has("Scabbard"):
		scabbard = gear["Scabbard"]
		(scabbard as MeshInstance3D).material_override = _mat
		body.add_child(scabbard)
		scabbard.transform = BACK_SWORD
	if gear.has("Shield"):
		shield = gear["Shield"]
		(shield as MeshInstance3D).material_override = _mat
	set_armed(false, true)
	_apply_materials()
	_attach_fur(parts)
	for k in parts:
		if (parts[k] as Node).get_parent() == null:
			(parts[k] as Node).queue_free()
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


## Draw (true) or sheathe (false) the sword and shield.
func set_armed(on: bool, force: bool = false) -> void:
	if on == armed and not force:
		return
	armed = on
	if sword:
		if sword.get_parent():
			sword.get_parent().remove_child(sword)
		if on:
			hand_r.add_child(sword)
			sword.transform = Transform3D(Basis(), Vector3(0, 0.0, -0.04))
		else:
			body.add_child(sword)
			sword.transform = BACK_SWORD
	if shield:
		if shield.get_parent():
			shield.get_parent().remove_child(shield)
		if on:
			hand_l.add_child(shield)
			shield.transform = Transform3D(Basis(), Vector3(-0.17, 0, -0.04))
		else:
			body.add_child(shield)
			shield.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0.2, 0.36))


## Play a hand emote for `seconds` (thumbs_up, peace).
func emote(pose: String, seconds: float = 1.6) -> void:
	_emote = pose
	_emote_t = seconds


## Water/Earth enchantment: the blade glows with the element's colour.
func set_enchant(on: bool, color: Color) -> void:
	enchanted = on
	if _sword_mat == null:
		return
	var pulse := 0.45 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
	_sword_mat.set_shader_parameter("flash", pulse if on else 0.0)
	_sword_mat.set_shader_parameter("flash_color", color)


func is_emoting() -> bool:
	return _emote_t > 0.0


func set_hand_pose(side: String, pose: String) -> void:
	var table := _poses_r if side == "r" else _poses_l
	if not table.has(pose):
		return
	for k in table:
		(table[k] as Node3D).visible = k == pose
	if side == "r":
		hand_pose_r = pose
	else:
		hand_pose_l = pose


func _choose_poses(state: String, move: float, sprinting: bool) -> Array[String]:
	if _emote_t > 0.0:
		return [_emote, "open"]
	match state:
		"ATTACK", "HEAVY", "HEAVY_CHARGE":
			return ["grip" if armed else "fist", "fist"]
		"GUARD", "DEFENSE":
			return ["grip" if armed else "fist", "grip" if armed else "fist"]
		"DODGE", "MOBILITY", "HITSTUN":
			return ["grip" if armed else "fist", "fist"]
		"CAST", "CLIMB", "MANTLE", "GLIDE", "AIR":
			return ["open", "open"]
	if sprinting:
		return ["grip" if armed else "fist", "fist"]
	return ["grip" if armed else "open", "grip" if armed else "open"]


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
	var sprinting: bool = info.get("sprinting", false)
	_emote_t = maxf(0.0, _emote_t - delta)
	var poses := _choose_poses(state, move, sprinting)
	if poses[0] != hand_pose_r:
		set_hand_pose("r", poses[0])
	if poses[1] != hand_pose_l:
		set_hand_pose("l", poses[1])

	_walk_phase += delta * (3.5 + 8.0 * move)
	var bob := sin(_walk_phase * 2.0) * 0.035 * move
	var breathe := sin(Time.get_ticks_msec() * 0.003) * 0.01 * (1.0 - move)
	var body_y := BODY_Y + bob
	var head_y := HEAD_Y + bob * 1.2 + breathe
	var head_z := 0.0
	var lean := move * 0.1
	var robe_sway := sin(_walk_phase) * 0.05 * move
	tail.rotation.y = sin(_walk_phase * 0.7) * 0.3
	tail.rotation.x = sin(_walk_phase * 0.5) * 0.08

	var step := sin(_walk_phase) * 0.3 * move
	var fr := Vector3(FOOT.x, FOOT.y + maxf(0.0, sin(_walk_phase)) * 0.16 * move, -step)
	var fl := Vector3(-FOOT.x, FOOT.y + maxf(0.0, -sin(_walk_phase)) * 0.16 * move, step)
	var hr := Vector3(HAND.x, HAND.y + bob, HAND.z + step * 0.7)
	var hl := Vector3(-HAND.x, HAND.y + bob, HAND.z - step * 0.7)
	var hr_rot := Vector3.ZERO
	var hl_rot := Vector3.ZERO

	match state:
		"ATTACK", "HEAVY":
			var combo: int = info.get("combo", 0)
			var side := 1.0 if combo % 2 == 0 else -1.0
			var swing := clampf(t * 1.8, 0.0, 1.0)
			hr = Vector3(lerpf(0.62 * side, -0.4 * side, swing), 1.12, -0.42)
			hr_rot = Vector3(-0.3, lerpf(1.2 * side, -1.4 * side, swing), 0)
			lean = 0.22
			robe_sway = -0.12 * side * swing
			if state == "HEAVY":
				hr = Vector3(0.35, lerpf(1.95, 0.7, swing), -0.48)
				hr_rot = Vector3(lerpf(1.2, -1.3, swing), 0, 0)
		"HEAVY_CHARGE":
			hr = Vector3(0.4, 1.9, 0.1)
			hr_rot = Vector3(1.3, 0, 0)
			lean = -0.1
		"GUARD", "DEFENSE":
			hl = Vector3(-0.2, 1.08, -0.5)
			hl_rot = Vector3(0, -0.4, 0)
			lean = 0.06
		"DODGE", "MOBILITY":
			body_y = BODY_Y - 0.25
			head_y = HEAD_Y - 0.32
			lean = 0.4
		"CAST":
			hr = Vector3(0.25, 1.15, -0.62)
			hl = Vector3(-0.25, 1.15, -0.62)
		"HITSTUN":
			head_z = 0.08
			lean = -0.25
		"CLIMB":
			_walk_phase += delta * absf(t) * 5.0
			var reach := sin(_walk_phase) * 0.22
			hr = Vector3(0.32, 1.75 + reach, -0.34)
			hl = Vector3(-0.32, 1.75 - reach, -0.34)
			fr = Vector3(0.16, 0.3 - reach, -0.3)
			fl = Vector3(-0.16, 0.3 + reach, -0.3)
			lean = 0.15
		"MANTLE":
			hr = Vector3(0.32, 1.2, -0.45)
			hl = Vector3(-0.32, 1.2, -0.45)
			fr = Vector3(0.13, 0.45, 0)
			fl = Vector3(-0.13, 0.45, 0)
		"AIR":
			hr = Vector3(0.62, 1.25, 0)
			hl = Vector3(-0.62, 1.25, 0)
			fr = Vector3(0.13, 0.25, 0.1)
			fl = Vector3(-0.13, 0.06, -0.1)
		"GLIDE":
			hr = Vector3(1.3, 1.32, 0.05)
			hl = Vector3(-1.3, 1.32, 0.05)
			fr = Vector3(0.12, 0.12, 0.3)
			fl = Vector3(-0.12, 0.12, 0.3)
			lean = 0.3
	if charge > 0.0:
		hr = hr.lerp(Vector3(0.35, 1.2, -0.3), 0.6)
	if _emote_t > 0.0:
		if _emote == "peace":  # hand raised beside the face, fingers up
			hr = Vector3(0.38, 1.65, -0.22)
			hr_rot = Vector3(PI / 2, 0.3, 0)
		else:  # thumbs up held out in front
			hr = Vector3(0.36, 1.2, -0.38)
			hr_rot = Vector3(0, 0, 0)

	var gliding := state == "GLIDE"
	daraa.visible = gliding or daraa.scale.x > 0.25
	daraa.scale = daraa.scale.lerp(Vector3.ONE if gliding else Vector3(0.2, 1, 0.2), 1.0 - exp(-14.0 * delta))
	if gliding:
		daraa.rotation.x = sin(_walk_phase * 3.0) * 0.06

	var k := 1.0 - exp(-20.0 * delta)
	body.position.y = lerpf(body.position.y, body_y, k)
	body.rotation.x = lerpf(body.rotation.x, -lean * 0.6, k)
	body.rotation.z = lerpf(body.rotation.z, robe_sway, k * 0.5)
	head.position.y = lerpf(head.position.y, head_y, k)
	head.position.z = lerpf(head.position.z, head_z - lean * 0.35, k)
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
	for m in [_mat, _fabric_mat, _leather_mat]:
		m.set_shader_parameter("flash", _flash * 0.9)
		m.set_shader_parameter("flash_color", _flash_color)


func _hand(parts: Dictionary, prefix: String, pos: Vector3, table: Dictionary) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	for pose in POSES:
		var mi: MeshInstance3D = parts.get(prefix + "_" + pose)
		if mi == null:
			continue
		mi.material_override = _mat
		mi.position = Vector3.ZERO
		mi.visible = pose == "open"
		pivot.add_child(mi)
		table[pose] = mi
	return pivot


## Cloth reads matte with a velvet sheen, eyes glossy, boots leathery.
func _apply_materials() -> void:
	for n in [body, hawli, turban]:
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = _fabric_mat
	for n in [foot_r, foot_l, scabbard]:
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = _leather_mat
	for n in [eyes, eyes_closed]:
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = _gloss_mat


## Shell fur meshes ("<Part>_fur") ride on their base part, so they follow
## hand poses, blinks and ear twitches. Culled beyond FUR_RANGE metres.
const FUR_RANGE := 14.0
var fur_meshes: Array[MeshInstance3D] = []


func _attach_fur(parts: Dictionary) -> void:
	var mat := CharacterArt.fur_material(_species_key)
	if mat == null:
		return
	for k in parts:
		var key := str(k)
		if not key.ends_with("_fur"):
			continue
		var base: Node3D = parts.get(key.trim_suffix("_fur"))
		if base == null or base.get_parent() == null:
			continue
		var fur: MeshInstance3D = parts[k]
		fur.material_override = mat
		fur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fur.visibility_range_end = FUR_RANGE
		fur.visibility_range_end_margin = 2.0
		fur.transform = Transform3D.IDENTITY
		base.add_child(fur)
		fur_meshes.append(fur)


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
		eyes_shut = _blink_t > 0.0 or state == "HITSTUN" or state == "DEAD"
		if eyes_closed:
			# Closed eyes read as "> <".
			eyes.visible = not eyes_shut
			eyes_closed.visible = eyes_shut
		else:
			eyes.scale.y = lerpf(eyes.scale.y, 0.12 if eyes_shut else 1.0, 1.0 - exp(-40.0 * delta))
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
	return fur.darkened(0.62)
