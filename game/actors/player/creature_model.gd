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
## Head size relative to the authored chibi head (owner: smaller head).
const HEAD_SHRINK := 0.8
const HEAD_DROP := 0.09
## Hawli ribbon colour per species (indigo tagelmust cloth).
const HAWLI_COLORS := {"cat": Color(0.2, 0.26, 0.55), "fennec": Color(0.16, 0.22, 0.52), "rabbit": Color(0.13, 0.2, 0.5)}
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
## Squash & stretch spring (+ stretch, - squash) and the state it reacts to.
var squash := 0.0
var _squash_v := 0.0
var _prev_state := "MOVE"
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
var _outline_color_cached := Color(0.2, 0.12, 0.08)
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
	_outline_color_cached = oc
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
	_build_rig()
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
		if on and rig:
			# In the rest pose the rig's own sword points forward, edge up.
			var sr := _rest_model("handslot.r")
			_attach["handslot.r"].add_child(sword)
			sword.transform = sr.affine_inverse() * Transform3D(Basis(Vector3.BACK, PI / 2), sr.origin)
		elif on:
			hand_r.add_child(sword)
			sword.transform = Transform3D(Basis(), Vector3(0, 0.0, -0.04))
		else:
			body.add_child(sword)
			sword.transform = BACK_SWORD
	if shield:
		if shield.get_parent():
			shield.get_parent().remove_child(shield)
		if on and rig:
			# The rig's shield hangs below the left slot, facing outward.
			var sl := _rest_model("handslot.l")
			_attach["handslot.l"].add_child(shield)
			shield.transform = sl.affine_inverse() * Transform3D(Basis(), sl.origin + Vector3(-0.03, -0.24, 0.0))
		elif on:
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

	if rig:
		_animate_rig(delta, info, state, move, t, sprinting)
		_update_squash(delta, state, move)
		rig.basis = Basis(Vector3.UP, PI).scaled(Vector3(1.0 - squash * 0.45, 1.0 + squash, 1.0 - squash * 0.45) * RIG_SCALE)
		_animate_face(delta, state)
		var ga := clampf(charge / 3.0, 0.0, 1.0) * 0.8
		_glow_mat.albedo_color = Color(ecol.r, ecol.g, ecol.b, ga)
		element_glow.scale = Vector3.ONE * (0.6 + charge * 0.5)
		_flash = maxf(0.0, _flash - delta * 6.0)
		for m in [_mat, _fabric_mat, _leather_mat]:
			m.set_shader_parameter("flash", _flash * 0.9)
			m.set_shader_parameter("flash_color", _flash_color)
		return

	_walk_phase += delta * (3.5 + 8.0 * move)
	# Bouncy, hoppy walk: feet push the body up twice per stride.
	var bob := absf(sin(_walk_phase)) * 0.06 * move - 0.02 * move
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
			hr = Vector3(lerpf(0.62 * side, -0.4 * side, swing), 0.92, -0.52)
			hr_rot = Vector3(-0.3, lerpf(1.2 * side, -1.4 * side, swing), 0)
			lean = 0.22
			robe_sway = -0.12 * side * swing
			if state == "HEAVY":
				hr = Vector3(0.42, lerpf(1.75, 0.6, swing), -0.56)
				hr_rot = Vector3(lerpf(1.2, -1.3, swing), 0, 0)
		"HEAVY_CHARGE":
			hr = Vector3(0.52, 1.72, 0.15)
			hr_rot = Vector3(1.3, 0, 0)
			lean = -0.1
		"GUARD", "DEFENSE":
			hl = Vector3(-0.2, 0.9, -0.56)
			hl_rot = Vector3(0, -0.4, 0)
			lean = 0.06
		"DODGE", "MOBILITY":
			body_y = BODY_Y - 0.25
			head_y = HEAD_Y - 0.32
			lean = 0.4
		"CAST":
			hr = Vector3(0.25, 0.95, -0.66)
			hl = Vector3(-0.25, 0.95, -0.66)
		"HITSTUN":
			head_z = 0.08
			lean = -0.25
		"CLIMB":
			_walk_phase += delta * absf(t) * 5.0
			var reach := sin(_walk_phase) * 0.22
			hr = Vector3(0.34, 1.5 + reach, -0.48)
			hl = Vector3(-0.34, 1.5 - reach, -0.48)
			fr = Vector3(0.16, 0.3 - reach, -0.3)
			fl = Vector3(-0.16, 0.3 + reach, -0.3)
			lean = 0.15
		"MANTLE":
			hr = Vector3(0.32, 1.1, -0.52)
			hl = Vector3(-0.32, 1.1, -0.52)
			fr = Vector3(0.13, 0.45, 0)
			fl = Vector3(-0.13, 0.45, 0)
		"AIR":
			hr = Vector3(0.64, 1.05, 0)
			hl = Vector3(-0.64, 1.05, 0)
			fr = Vector3(0.13, 0.25, 0.1)
			fl = Vector3(-0.13, 0.06, -0.1)
		"GLIDE":
			hr = Vector3(1.2, 1.08, 0.05)
			hl = Vector3(-1.2, 1.08, 0.05)
			fr = Vector3(0.12, 0.12, 0.3)
			fl = Vector3(-0.12, 0.12, 0.3)
			lean = 0.3
	if charge > 0.0:
		hr = hr.lerp(Vector3(0.45, 1.0, -0.48), 0.6)
	if _emote_t > 0.0:
		if _emote == "peace":  # hand raised beside the face, fingers up
			hr = Vector3(0.62, 1.3, -0.16)
			hr_rot = Vector3(PI / 2, 0.3, 0)
		else:  # thumbs up held out in front
			hr = Vector3(0.42, 0.96, -0.5)
			hr_rot = Vector3(0, 0, 0)

	var gliding := state == "GLIDE"
	daraa.visible = gliding or daraa.scale.x > 0.25
	daraa.scale = daraa.scale.lerp(Vector3.ONE if gliding else Vector3(0.2, 1, 0.2), 1.0 - exp(-14.0 * delta))
	if gliding:
		daraa.rotation.x = sin(_walk_phase * 3.0) * 0.06

	_update_squash(delta, state, move)
	body_y += -absf(squash) * 0.05 if squash < 0.0 else 0.0
	head_y += squash * 0.22

	var k := 1.0 - exp(-20.0 * delta)
	body.position.y = lerpf(body.position.y, body_y, k)
	body.scale = Vector3(1.0 - squash * 0.45, 1.0 + squash, 1.0 - squash * 0.45)
	head.scale = Vector3(1.0 - squash * 0.3, 1.0 + squash * 0.6, 1.0 - squash * 0.3)
	head.rotation.z = lerpf(head.rotation.z, sin(_walk_phase) * 0.07 * move, k * 0.5)
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


## Spring-driven squash & stretch: stretch on take-off and on swings,
## squash on landing and when hit, a soft breathing pulse when idle.
func _update_squash(delta: float, state: String, move: float) -> void:
	var airborne := state in ["AIR", "GLIDE"]
	var was_air := _prev_state in ["AIR", "GLIDE"]
	if airborne and not was_air:
		_squash_v += 4.0
	elif was_air and not airborne:
		_squash_v -= 6.5
	if state == "HITSTUN" and _prev_state != "HITSTUN":
		_squash_v -= 2.4
	if state in ["ATTACK", "HEAVY"] and _prev_state != state:
		_squash_v += 1.2
	_prev_state = state
	var rest := sin(Time.get_ticks_msec() * 0.004) * 0.012 * (1.0 - move)
	# Fixed 1/120 s sub-steps (semi-implicit Euler) keep the spring stable
	# at any frame rate.
	var steps := clampi(ceili(delta * 120.0), 1, 12)
	var h := minf(delta, 0.1) / float(steps)
	for i in steps:
		var acc := -260.0 * (squash - rest) - 13.0 * _squash_v
		_squash_v = clampf(_squash_v + acc * h, -8.0, 8.0)
		squash = clampf(squash + _squash_v * h, -0.32, 0.32)


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
	if body is MeshInstance3D:
		(body as MeshInstance3D).material_override = _fabric_mat
	# Hawli/turban: matte cotton (no damask, no sheen streaks).
	var cotton := CharacterArt.toon_material(_outline_color_cached, 0.007, "fabric")
	cotton.set_shader_parameter("damask_strength", 0.0)
	cotton.set_shader_parameter("sheen_strength", 0.03)
	cotton.set_shader_parameter("rim_strength", 0.06)
	for n in [hawli, turban]:
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = cotton
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
	if rig:
		_ear_back = lerpf(_ear_back, back, k)
		_ear_tw = tw
		_ear_tw_side = _twitch_side
		return
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


# --- Skeletal rig (v2.0) -----------------------------------------------------
# Our parts ride on a keyframe-animated skeleton (KayKit Rig_Medium, CC0,
# 76 hand-made clips). Arms and legs stay invisible: the mittens and boots
# float, but they move with real animation weight. The robe hangs from a
# spring at the neck so it lags and swings. See game/art/rig/.

const RIG_PATH := "res://game/art/rig/hafid_rig.glb"
const RIG_SCALE := 0.8
const RIG_LOOPS: Array[String] = ["Idle", "Unarmed_Idle", "Walking_A", "Walking_B", "Running_A", "Running_B",
	"Blocking", "Jump_Idle", "Spellcasting", "2H_Melee_Idle"]
## Combo: diagonal sweep, reaching stab, spinning sweep. Heavy: overhead chop.
const ATTACK_CLIPS: Array[String] = ["1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Stab", "2H_Melee_Attack_Spin"]
const HEAVY_CLIP := "2H_Melee_Attack_Chop"
## Fraction of each clip where the blade connects (peak hand speed, measured).
const IMPACT := {"1H_Melee_Attack_Slice_Diagonal": 0.38, "1H_Melee_Attack_Stab": 0.22,
	"2H_Melee_Attack_Spin": 0.48, "2H_Melee_Attack_Chop": 0.42}
## Lunge footwork per clip: [front foot fwd, back foot back, body fwd, body drop, reach]
const FOOTWORK := {"1H_Melee_Attack_Slice_Diagonal": [0.28, 0.16, 0.22, 0.07, 0.05],
	"1H_Melee_Attack_Stab": [0.45, 0.25, 0.38, 0.1, 0.3],
	"2H_Melee_Attack_Spin": [0.12, 0.12, 0.1, 0.12, 0.08],
	"2H_Melee_Attack_Chop": [0.4, 0.22, 0.3, 0.16, 0.1]}
static var use_rig := true

var rig: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var anim_name := ""
var _attach: Dictionary = {}
var _robe_pivot: Node3D
var _foot_base_r := Transform3D.IDENTITY
var _foot_base_l := Transform3D.IDENTITY
var _spread: ArmSpread
var _exag: Exaggerate
var _lunge := 0.0
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array = []
var _trail_on := false
var _trail_mat: StandardMaterial3D
var _ear_v := Vector2.ZERO
var _ear_back := 0.0
var _ear_tw := 0.0
var _ear_tw_side := 1.0
var _ear_o := Vector2.ZERO
var _last_head_pos := Vector3.ZERO
var _head_vel := Vector3.ZERO
var _ear_base_r := Transform3D.IDENTITY
var _ear_base_l := Transform3D.IDENTITY
var _head_base := Transform3D.IDENTITY
var _robe_base := Transform3D.IDENTITY
var _tail_base := Transform3D.IDENTITY
var _robe_sway := Vector2.ZERO
var _robe_sway_v := Vector2.ZERO
var _tail_sway := 0.0
var _tail_sway_v := 0.0
var _last_vel := Vector3.ZERO
var _anim_state := ""
var _hit_flip := false
var _land_t := 0.0
var _step_prev := 0.0
var _dust: Array[CPUParticles3D] = []
var _dust_i := 0


func has_rig() -> bool:
	return rig != null


func _build_rig() -> void:
	if not use_rig or not ResourceLoader.exists(RIG_PATH):
		return
	rig = (load(RIG_PATH) as PackedScene).instantiate()
	add_child(rig)
	rig.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * RIG_SCALE), Vector3.ZERO)
	var sk := rig.find_children("*", "Skeleton3D", true, false)
	var ap := rig.find_children("*", "AnimationPlayer", true, false)
	if sk.is_empty() or ap.is_empty():
		rig.queue_free()
		rig = null
		return
	skel = sk[0]
	anim = ap[0]
	skel.reset_bone_poses()
	for n in RIG_LOOPS:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	# Head (face parts already ride on it).
	_mount(head, "head", Transform3D(Basis().scaled(Vector3.ONE * HEAD_SHRINK), Vector3(0, HEAD_Y - HEAD_DROP, 0)))
	# Robe on a neck pivot so it can swing.
	var neck := Vector3(0, 1.06, 0)
	_robe_pivot = Node3D.new()
	_robe_pivot.name = "RobePivot"
	add_child(_robe_pivot)
	_mount(_robe_pivot, "spine", Transform3D(Basis(), neck))
	body.get_parent().remove_child(body)
	_robe_pivot.add_child(body)
	body.transform = Transform3D(Basis(), Vector3(0, BODY_Y, 0) - neck)
	_journey_robe(body)
	_robe_base = _robe_pivot.transform
	_build_scarf()
	_head_base = head.transform
	if ear_r:
		_ear_base_r = ear_r.transform
	if ear_l:
		_ear_base_l = ear_l.transform
	_mount(tail, "hips", Transform3D(Basis(), Vector3(0, 0.5, 0.24)))
	if tail:
		_tail_base = tail.transform
	var spread := ArmSpread.new()
	skel.add_child(spread)
	# Mittens: fingers follow the arm, palm down in the rest pose.
	var hr := _rest_model("hand.r").origin
	var hl := _rest_model("hand.l").origin
	_mount(hand_r, "hand.r", Transform3D(Basis(Vector3.UP, -PI / 2), hr + Vector3(0.06, 0, 0)))
	_mount(hand_l, "hand.l", Transform3D(Basis(Vector3.UP, PI / 2), hl - Vector3(0.06, 0, 0)))
	# Boots under the foot bones.
	var fr := _rest_model("foot.r").origin
	var fl := _rest_model("foot.l").origin
	_mount(foot_r, "foot.r", Transform3D(Basis(), Vector3(fr.x, 0, fr.z)))
	_mount(foot_l, "foot.l", Transform3D(Basis(), Vector3(fl.x, 0, fl.z)))
	_bone_attach("handslot.r")
	_bone_attach("handslot.l")
	_foot_base_r = foot_r.transform
	_foot_base_l = foot_l.transform
	_spread = spread
	_exag = Exaggerate.new()
	skel.add_child(_exag)
	_exag.setup(anim, "Idle")
	_build_trail()
	_build_dust()
	_play("Unarmed_Idle", 0.0)


## Reshape the daraa into a long cone like Journey's cloak: narrow at the
## shoulders, flaring to a wide hem just above the ground (feet barely
## showing). Vertex colours (embroidery, hem band) are kept.
const ROBE_FLARE := 0.38
const ROBE_EXTEND := 0.1

func _journey_robe(node: Node3D) -> void:
	var mi := node as MeshInstance3D
	if mi == null or not (mi.mesh is ArrayMesh):
		return
	var src := mi.mesh as ArrayMesh
	var top := -INF
	var bottom := INF
	for si in src.get_surface_count():
		for v in src.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			top = maxf(top, v.y)
			bottom = minf(bottom, v.y)
	var span := maxf(top - bottom, 0.01)
	var dst := ArrayMesh.new()
	for si in src.get_surface_count():
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(src, si) != OK:
			return
		for i in mdt.get_vertex_count():
			var v := mdt.get_vertex(i)
			var t := clampf((top - v.y) / span, 0.0, 1.0)
			var s := (0.9 + 0.1 * t) * (1.0 + ROBE_FLARE * pow(t, 1.6))
			mdt.set_vertex(i, Vector3(v.x * s, v.y - ROBE_EXTEND * t * t, v.z * s))
		mdt.commit_to_surface(dst)
	mi.mesh = dst


## Long hawli ribbon trailing from the back of the neck (see HawliScarf).
var scarf: HawliScarf

func _build_scarf() -> void:
	if _robe_pivot == null:
		return
	var anchor := Node3D.new()
	anchor.name = "ScarfAnchor"
	_robe_pivot.add_child(anchor)
	anchor.position = Vector3(0, 0.06, 0.2)
	scarf = HawliScarf.new()
	scarf.color = HAWLI_COLORS.get(_species_key, Color(0.2, 0.26, 0.55))
	scarf.anchor = anchor
	scarf.body_root = self
	add_child(scarf)


func _model_xform(n: Node3D) -> Transform3D:
	var x := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		if cur is Node3D:
			x = (cur as Node3D).transform * x
		cur = cur.get_parent()
	return x


func _rest_model(bone: String) -> Transform3D:
	return _model_xform(skel) * skel.get_bone_global_rest(skel.find_bone(bone))


func _bone_attach(bone: String) -> BoneAttachment3D:
	if _attach.has(bone):
		return _attach[bone]
	var a := BoneAttachment3D.new()
	a.name = "At_" + bone.replace(".", "_")
	a.bone_name = bone
	skel.add_child(a)
	_attach[bone] = a
	return a


## Re-parent `node` under the bone so that, in the rest pose, it sits at
## `model_xform` (model space).
func _mount(node: Node3D, bone: String, model_xform: Transform3D) -> void:
	if node == null:
		return
	var a := _bone_attach(bone)
	if node.get_parent():
		node.get_parent().remove_child(node)
	a.add_child(node)
	node.transform = _rest_model(bone).affine_inverse() * model_xform


func _play(clip: String, blend: float = 0.14, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if clip == anim_name and anim.is_playing():
		anim.speed_scale = speed
		return
	anim_name = clip
	anim.play(clip, blend)
	anim.speed_scale = speed


## Hold a clip at an exact time (attacks are driven by gameplay progress so
## the blade connects on the hit frame).
func _scrub(clip: String, time: float, _blend: float = 0.0) -> void:
	# No crossfade here: at speed 0 a blend would never advance and the
	# pose would stay stuck on the previous clip.
	if anim == null or not anim.has_animation(clip):
		return
	if clip != anim_name:
		anim_name = clip
		anim.play(clip, 0.0)
	anim.speed_scale = 0.0
	anim.seek(clampf(time, 0.0, anim.get_animation(clip).length - 0.01), true)


func _animate_rig(delta: float, info: Dictionary, state: String, move: float, t: float, sprinting: bool) -> void:
	var entered := state != _anim_state
	var prev := _anim_state
	_anim_state = state
	var combo: int = info.get("combo", 0)
	if _emote_t > 0.0:
		_play("Cheer", 0.12)
	else:
		match state:
			"ATTACK", "HEAVY":
				var clip := HEAVY_CLIP if state == "HEAVY" else ATTACK_CLIPS[posmod(combo, ATTACK_CLIPS.size())]
				var length := anim.get_animation(clip).length
				var w: float = info.get("windup_frac", 0.25)
				var a: float = info.get("active_frac", 0.45)
				var imp: float = IMPACT.get(clip, 0.4)
				var at: float
				if t < w:
					at = (t / maxf(w, 0.01)) * imp
				elif t < a:
					at = imp + (t - w) / maxf(a - w, 0.01) * 0.08
				else:
					at = imp + 0.08 + (t - a) / maxf(1.0 - a, 0.01) * (0.92 - imp - 0.08)
				_scrub(clip, at * length)
				_combat_pose(clip, t, w, a)
				attack_trail(true)
			"HEAVY_CHARGE":
				# Anticipation: hold (and exaggerate) the overhead wind-up.
				_scrub(HEAVY_CLIP, 0.3 * anim.get_animation(HEAVY_CLIP).length)
				_combat_pose(HEAVY_CLIP, 0.18, 0.4, 0.6)
			"GUARD", "DEFENSE":
				_play("Blocking", 0.1)
			"DODGE", "MOBILITY":
				_play("Dodge_Forward", 0.06, 1.5)
			"CAST":
				_play("Spellcast_Shoot", 0.08, 1.3)
			"HITSTUN":
				if entered:
					_hit_flip = not _hit_flip
					anim_name = ""
				_play("Hit_A" if _hit_flip else "Hit_B", 0.05, 1.2)
			"DEAD":
				_play("Death_A", 0.1)
			"AIR":
				if entered and prev in ["MOVE", "DODGE", "MOBILITY"] and info.get("rising", false):
					anim_name = ""
					_play("Jump_Start", 0.05, 1.6)
				elif anim_name != "Jump_Start" or not anim.is_playing():
					_play("Jump_Idle", 0.15)
			"GLIDE":
				_play("Jump_Idle", 0.2, 0.5)
			"CLIMB":
				_play("Running_A", 0.15, clampf(absf(t) * 0.5, 0.0, 1.2))
			"MANTLE":
				_play("Jump_Land", 0.08, 1.4)
			_:
				if entered and prev in ["AIR", "GLIDE"]:
					_land_t = 0.22
					anim_name = ""
					puff(global_position, 14)
				_land_t = maxf(0.0, _land_t - delta)
				if _land_t > 0.0 and move < 0.5:
					_play("Jump_Land", 0.04, 1.3)
				elif move < 0.06:
					_play("Idle" if armed else "Unarmed_Idle", 0.2)
				elif sprinting or move > 0.62:
					_play("Running_A", 0.15, lerpf(0.9, 1.25, move))
					_footstep_dust()
				else:
					# walk 0..0.62 of top speed, scaled so feet don't slide
					_play("Walking_A" if move < 0.38 else "Running_A", 0.18, lerpf(0.7, 1.15, move / 0.62))
					_footstep_dust(false)
	if not state in ["ATTACK", "HEAVY", "HEAVY_CHARGE"]:
		_combat_pose("", 0.0, 1.0, 1.0)
		attack_trail(false)
	_secondary_motion(delta, info, move)
	_update_trail()


## Robe and tail lag behind the body: springs driven by acceleration.
func _secondary_motion(delta: float, info: Dictionary, move: float) -> void:
	var vel: Vector3 = info.get("vel", Vector3.ZERO)
	var acc := (vel - _last_vel) / maxf(delta, 0.001)
	_last_vel = vel
	var inv := global_transform.basis.inverse()
	var acc_l := inv * acc
	var vel_l := inv * vel
	# Target: hem trails behind motion and kicks against acceleration.
	var target := Vector2(
		clampf(-vel_l.z * 0.035 + acc_l.z * 0.012, -0.32, 0.32),
		clampf(vel_l.x * 0.02 - acc_l.x * 0.01, -0.25, 0.25))
	var steps := clampi(ceili(delta * 120.0), 1, 12)
	var h := minf(delta, 0.1) / float(steps)
	for i in steps:
		var a := (target - _robe_sway) * 150.0 - _robe_sway_v * 9.0
		_robe_sway_v += a * h
		_robe_sway += _robe_sway_v * h
		var ta := (-vel_l.x * 0.06 - _tail_sway) * 90.0 - _tail_sway_v * 6.0
		_tail_sway_v += ta * h
		_tail_sway += _tail_sway_v * h
	_robe_sway = _robe_sway.clamp(Vector2(-0.4, -0.3), Vector2(0.4, 0.3))
	if _robe_pivot:
		_robe_pivot.transform = _robe_base * Transform3D(Basis.from_euler(Vector3(-_robe_sway.x, 0.0, _robe_sway.y)), Vector3.ZERO)
	_ears_and_head(delta, move)
	if tail:
		var ty := _tail_sway + sin(Time.get_ticks_msec() * 0.003) * 0.12 * (1.0 - move)
		tail.transform = _tail_base * Transform3D(Basis(Vector3.UP, ty), Vector3.ZERO)


# --- Dust --------------------------------------------------------------------

func _build_dust() -> void:
	# pixel-art puff: world-texel disc, dithered transparency (dust_dither)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/shaders/dust_dither.gdshader")
	mat.set_shader_parameter("quad_size", 0.32)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	quad.material = mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6))
	for i in 3:
		var p := CPUParticles3D.new()
		p.top_level = true
		p.mesh = quad
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.95
		p.lifetime = 0.55
		p.amount = 14
		p.direction = Vector3(0, 0.25, 0)
		p.spread = 85.0
		p.flatness = 0.7
		p.initial_velocity_min = 0.8
		p.initial_velocity_max = 2.0
		p.gravity = Vector3(0, -0.6, 0)
		p.damping_min = 3.0
		p.damping_max = 4.0
		p.scale_amount_curve = curve
		p.color_ramp = fade
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.18
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_dust.append(p)


## Puff of sand at `at` (landings, dodges, skids, footsteps).
func puff(at: Vector3, amount: int = 10) -> void:
	if _dust.is_empty():
		return
	var p := _dust[_dust_i]
	_dust_i = (_dust_i + 1) % _dust.size()
	p.global_position = at + Vector3(0, 0.05, 0)
	p.amount = clampi(amount, 2, 24)
	p.restart()


func _footstep_dust(dust: bool = true) -> void:
	if anim == null:
		return
	var len := anim.current_animation_length
	if len <= 0.0:
		return
	var ph := fmod(anim.current_animation_position / len, 0.5)
	if ph < _step_prev:
		var right := fmod(anim.current_animation_position / len, 1.0) < 0.5
		var side := foot_r if right else foot_l
		var at := side.global_position if side else global_position
		if dust:
			puff(at, 4)
	_step_prev = ph
	_sand_trail(1.0 if dust else 0.8)


## Boot prints in the sand (player only; GroundFX decides where they stick):
## one print per STRIDE metres travelled, alternating feet either side of
## the path, so the trail reads at any speed regardless of clip timing.
const STRIDE := 0.5
var _print_from := Vector3.INF
var _print_right := false


func _sand_trail(depth: float) -> void:
	var body := get_parent() as Node3D
	if body == null or not body.is_in_group("player"):
		return
	var pos := body.global_position
	if _print_from == Vector3.INF or pos.distance_to(_print_from) > STRIDE * 4.0:
		_print_from = pos
		return
	var d := Vector3(pos.x - _print_from.x, 0, pos.z - _print_from.z)
	if d.length() < STRIDE:
		return
	var fwd := d.normalized()
	_print_from += fwd * STRIDE
	_print_right = not _print_right
	var side := Vector3(-fwd.z, 0, fwd.x) * (0.09 if _print_right else -0.09)
	var at := Vector3(_print_from.x, pos.y, _print_from.z) + side
	get_tree().call_group("ground_fx", "step", at, atan2(-fwd.x, -fwd.z), _print_right, depth)



## Ears lag behind the head (spring on head velocity), flop on landings and
## hits; the hop adds a little bounce to every stride.
func _ears_and_head(delta: float, move: float) -> void:
	if head == null:
		return
	var hp := head.global_position
	var hv := (hp - _last_head_pos) / maxf(delta, 0.001)
	_last_head_pos = hp
	var acc := (hv - _head_vel) / maxf(delta, 0.001)
	_head_vel = hv
	var acc_l := global_transform.basis.inverse() * acc
	var steps := clampi(ceili(delta * 120.0), 1, 12)
	var h := minf(delta, 0.1) / float(steps)
	for i in steps:
		var target := Vector2(clampf(acc_l.y * 0.012 + acc_l.z * 0.006, -0.6, 0.6), clampf(-acc_l.x * 0.008, -0.4, 0.4))
		var a := (target - _ear_o) * 220.0 - _ear_v * 10.0
		_ear_v += a * h
		_ear_o += _ear_v * h
	if ear_r and _ear_base_r != Transform3D.IDENTITY:
		ear_r.transform = _ear_base_r * Transform3D(Basis.from_euler(Vector3(_ear_o.x + _ear_back, 0, _ear_o.y + (_ear_tw if _ear_tw_side > 0.0 else 0.0))), Vector3.ZERO)
	if ear_l and _ear_base_l != Transform3D.IDENTITY:
		ear_l.transform = _ear_base_l * Transform3D(Basis.from_euler(Vector3(_ear_o.x + _ear_back, 0, _ear_o.y - (_ear_tw if _ear_tw_side < 0.0 else 0.0))), Vector3.ZERO)
	# hop: two bounces per walk/run cycle
	if anim and anim_name in ["Walking_A", "Running_A"] and anim.current_animation_length > 0.0:
		var ph := anim.current_animation_position / anim.current_animation_length
		var hop := absf(sin(ph * TAU)) * 0.05 * clampf(move * 2.0, 0.0, 1.0)
		head.transform = _head_base.translated_local(_head_base.basis.inverse() * Vector3(0, hop * 1.25, 0))
	else:
		head.transform = head.transform.interpolate_with(_head_base, 1.0 - exp(-12.0 * delta))



# --- Combat exaggeration ------------------------------------------------------

## Lunge curve: rises through the wind-up, peaks at impact, eases out in
## recovery. Drives body lunge, footwork, reach and rotation exaggeration.
func _combat_pose(clip: String, t: float, w: float, a: float) -> void:
	var c := 0.0
	if clip != "":
		if t < w:
			c = smoothstep(0.0, 1.0, t / maxf(w, 0.01)) * 0.55
		elif t < a:
			c = lerpf(0.55, 1.0, (t - w) / maxf(a - w, 0.01))
		else:
			c = 1.0 - smoothstep(0.0, 1.0, (t - a) / maxf(1.0 - a, 0.01))
	_lunge = lerpf(_lunge, c, 0.5) if clip != "" else lerpf(_lunge, 0.0, 0.25)
	var fw: Array = FOOTWORK.get(clip, [0.0, 0.0, 0.0, 0.0, 0.0])
	var k := _lunge
	if _exag:
		_exag.amount = minf(1.0, k * 1.2) if clip != "" else _lunge
	if _spread:
		_spread.forward = 0.06 + float(fw[4]) * k
	if rig:
		# body drives forward and down into the strike (model -Z is forward)
		rig.position = Vector3(0.0, -float(fw[3]) * k, -float(fw[2]) * k)
	# floating boots: front (left) foot steps in, back (right) foot plants
	if foot_l and foot_r and _foot_base_l != Transform3D.IDENTITY:
		foot_l.transform = _foot_base_l
		foot_r.transform = _foot_base_r
		var fwd := global_transform.basis * Vector3(0, 0, -1)
		var side := global_transform.basis * Vector3(1, 0, 0)
		var body_fwd := float(fw[2]) * k
		foot_l.global_position += fwd * (float(fw[0]) * k) - side * 0.06 * k + Vector3(0, float(fw[3]) * k, 0)
		foot_r.global_position += fwd * (-float(fw[1]) * k - body_fwd) + side * 0.08 * k + Vector3(0, float(fw[3]) * k, 0)
		# keep the boots on the ground while lunging
		if k > 0.01:
			for f in [foot_l, foot_r]:
				var gp: Vector3 = f.global_position
				gp.y = global_position.y + clampf(gp.y - global_position.y, 0.0, 0.1)
				f.global_position = gp


func _build_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail.material_override = _trail_mat
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY


func attack_trail(on: bool) -> void:
	_trail_on = on


## Ribbon behind the blade: the last ~0.25 s of base/tip positions, fading.
func _update_trail() -> void:
	if _trail_mesh == null:
		return
	if _trail_on and sword and sword.is_inside_tree() and armed:
		var x := sword.global_transform
		_trail_pts.push_front([x * Vector3(0, 0, -0.2), x * Vector3(0, 0, -0.82)])
	elif not _trail_pts.is_empty():
		_trail_pts.pop_back()
	while _trail_pts.size() > 9:
		_trail_pts.pop_back()
	_trail.global_transform = Transform3D.IDENTITY
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	var col := Color(1.0, 0.97, 0.9)
	if enchanted:
		col = _flash_color.lerp(Color(0.6, 0.85, 1.0), 0.5)
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _trail_pts.size()
	for i in n:
		var a := 0.7 * (1.0 - float(i) / float(n - 1))
		_trail_mesh.surface_set_color(Color(col.r, col.g, col.b, a * 0.6))
		_trail_mesh.surface_add_vertex(_trail_pts[i][0])
		_trail_mesh.surface_set_color(Color(col.r, col.g, col.b, a))
		_trail_mesh.surface_add_vertex(_trail_pts[i][1])
	_trail_mesh.surface_end()
