class_name Village
extends Node3D
## An abandoned Saharan village ruled by a Jinn King (fictional: Aïn Sirra).
## Stages, stored in WorldState:
##   haunted         King + shadow jinn guard it; brick piles lie in the ruins
##   claimed         King defeated: the village is yours, survivors kneel and
##                   can be recruited, a banner rises over the square
##   mosque_rebuilt  10 salvaged bricks rebuild the mosque (Chinguetti-style
##                   square minaret with ostrich-egg finials); villagers return
## Geometry is greybox built from boxes so the artist's modular kit can
## replace it without touching the logic.

signal stage_changed(stage: String)
signal announced(text: String, color: Color)

const MOSQUE_COST := 10
const SALVAGE_AMOUNT := 3
const JOBS: Array[String] = ["guard", "merchant", "builder"]
const MUD := Color(0.72, 0.5, 0.32)
const MUD_DARK := Color(0.6, 0.4, 0.26)
const STONE := Color(0.62, 0.53, 0.44)
const BRICK := Color(0.66, 0.4, 0.25)
const DARK := Color(0.12, 0.08, 0.07)
const AGGRO := 15.0

@export var village_id: String = "ain_sirra"
@export var display_name: String = "Aïn Sirra"

var king: JinnKing
var minions: Array[Jinn] = []
var body: StaticBody3D
var mosque_ruin: Node3D
var mosque: Node3D
var banner: Node3D
var piles: Dictionary = {}  # pile id -> Node3D
var mosque_site: Interactable
var _mats: Dictionary = {}
var _batch := MeshBatcher.new()


func _ready() -> void:
	add_to_group("villages")
	seed(hash(village_id))  # deterministic rubble and brick jitter
	body = StaticBody3D.new()
	body.collision_layer = Combat.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	_build_ground()
	_build_houses()
	_build_well()
	_build_mosque()
	_build_banner()
	_build_piles()
	_build_sign()
	_batch.build(_mat)
	mosque_site = _interactable(Vector3(0, 0, -6.6), 2.8,
		func() -> String:
			var st := stage()
			if st == "haunted":
				return "Defeat the Jinn King to claim %s" % display_name
			if st == "mosque_rebuilt":
				return "The mosque stands again"
			if WorldState.bricks() < MOSQUE_COST:
				return "Rebuild mosque: %d/%d bricks" % [WorldState.bricks(), MOSQUE_COST]
			return "Rebuild mosque (%d bricks)" % MOSQUE_COST,
		func() -> bool: return stage() == "claimed" and WorldState.bricks() >= MOSQUE_COST,
		func(_p: Player) -> void: rebuild_mosque())
	mosque_site.show_when_unavailable = true
	_apply_stage(true)


func stage() -> String:
	return WorldState.stage(village_id)


func is_haunted() -> bool:
	return stage() == "haunted"


func center() -> Vector3:
	return global_position


# --- Stage logic ------------------------------------------------------------

func _apply_stage(initial: bool) -> void:
	var st := stage()
	var v := WorldState.village(village_id)
	mosque.visible = st == "mosque_rebuilt"
	mosque_ruin.visible = st != "mosque_rebuilt"
	_set_collision(mosque, st == "mosque_rebuilt")
	_set_collision(mosque_ruin, st != "mosque_rebuilt")
	banner.visible = st != "haunted"
	for pid in piles:
		(piles[pid] as Node3D).visible = not (v["salvaged"] as Array).has(pid)
	if initial:
		if st == "haunted":
			_spawn_haunt()
		for npc in v["npcs"]:
			_spawn_villager(str(npc["job"]))


func _spawn_haunt() -> void:
	king = JinnKing.new()
	king.position = Vector3(0, 0, -3)
	king.aggro_radius = AGGRO
	add_child(king)
	king.minions_alive = func() -> int: return _alive_minions()
	king.summon_requested.connect(_on_summon)
	king.defeated.connect(_on_king_defeated)
	king.raged.connect(func(_k: JinnKing) -> void: announced.emit("The Jinn King rages!", Color(1, 0.8, 0.3)))
	for p in [Vector3(-6, 0, 3), Vector3(6, 0, 5)]:
		_spawn_minion(p)


func _spawn_minion(local_pos: Vector3) -> Jinn:
	var j := Jinn.new()
	j.position = local_pos
	j.aggro_radius = AGGRO
	add_child(j)
	minions.append(j)
	return j


func _alive_minions() -> int:
	var n := 0
	for m in minions:
		if is_instance_valid(m) and not m.is_dead() and not m.subdued:
			n += 1
	return n


func _on_summon(k: JinnKing, count: int) -> void:
	for i in count:
		var a := randf() * TAU
		var j := _spawn_minion(k.position + Vector3(sin(a), 0, cos(a)) * 3.0)
		Fx.burst(self, j.global_position + Vector3(0, 1, 0), Color(0.3, 0.15, 0.45, 0.7), 1.6, 0.5)


func _on_king_defeated(_k: Jinn) -> void:
	if not WorldState.claim_village(village_id, "player"):
		return
	announced.emit("%s is yours" % display_name, Color(1.0, 0.85, 0.4))
	Juice.play("banish", global_position, 0.7)
	# Surviving shadow jinn kneel; if too few survived, freed spirits appear.
	var kneeling := 0
	for m in minions:
		if is_instance_valid(m) and not m.is_dead():
			_make_recruitable(m)
			kneeling += 1
	while kneeling < 2:
		var j := _spawn_minion(Vector3(-1.5 + kneeling * 3.0, 0, -3))
		_make_recruitable(j)
		kneeling += 1
	_apply_stage(false)
	stage_changed.emit(stage())


func _make_recruitable(j: Jinn) -> void:
	j.subdue()
	var it := _interactable(Vector3.ZERO, 2.8,
		func() -> String: return "Recruit this jinn",
		func() -> bool: return stage() != "haunted",
		func(_p: Player) -> void: recruit(j))
	it.get_parent().remove_child(it)
	j.add_child(it)


func recruit(j: Jinn) -> bool:
	var job: String = JOBS[(WorldState.village(village_id)["npcs"] as Array).size() % JOBS.size()]
	if not WorldState.recruit(village_id, job):
		return false
	Fx.burst(self, j.global_position + Vector3(0, 1, 0), Color(0.5, 0.95, 1.0, 0.7), 1.8, 0.5)
	announced.emit("A jinn joins %s as %s" % [display_name, VillagerJinn.JOB_LABELS[job]], Color(0.6, 0.95, 1.0))
	minions.erase(j)
	j.queue_free()
	_spawn_villager(job)
	return true


func salvage(pile_id: String) -> bool:
	if not WorldState.salvage(village_id, pile_id, SALVAGE_AMOUNT):
		return false
	var pile: Node3D = piles[pile_id]
	Fx.burst(self, pile.global_position + Vector3(0, 0.5, 0), Color(0.8, 0.6, 0.4, 0.6), 1.2, 0.3)
	Juice.play("grab", pile.global_position, 0.8)
	pile.visible = false
	announced.emit("+%d bricks (%d)" % [SALVAGE_AMOUNT, WorldState.bricks()], Color(0.95, 0.75, 0.55))
	return true


func rebuild_mosque() -> bool:
	if not WorldState.rebuild_mosque(village_id, MOSQUE_COST):
		return false
	mosque_ruin.visible = false
	_set_collision(mosque_ruin, false)
	mosque.visible = true
	_set_collision(mosque, true)
	# Rise from the sand.
	mosque.position.y = -9.0
	var tw := create_tween()
	tw.tween_property(mosque, "position:y", 0.0, 2.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i in 6:
		Fx.burst(self, to_global(Vector3(randf_range(-4, 4), 0.5, -12 + randf_range(-3, 3))), Color(0.85, 0.72, 0.5, 0.5), 2.0, 1.2)
	Juice.shake(0.4)
	announced.emit("The mosque of %s is rebuilt. Life returns." % display_name, Color(1.0, 0.92, 0.7))
	stage_changed.emit(stage())
	return true


func _spawn_villager(job: String) -> void:
	var n := 0
	for v in get_tree().get_nodes_in_group("villagers"):
		if v.get_parent() == self and v.job == job:
			n += 1
	var vj := VillagerJinn.new()
	vj.job = job
	match job:
		"guard":
			var z := 11.0 + n * 1.5
			vj.route = [to_global(Vector3(-3.5, 0, z)), to_global(Vector3(3.5, 0, z))]
			vj.position = Vector3(-3.5, 0, z)
		"merchant":
			vj.position = Vector3(2.4 + n * 1.5, 0, 1.6)
		_:
			vj.position = Vector3(-3.0 + n * 2.0, 0, -8.5)
	add_child(vj)


# --- Geometry ---------------------------------------------------------------

func _build_ground() -> void:
	var m := MeshInstance3D.new()
	var plane := CylinderMesh.new()
	plane.top_radius = 17.0
	plane.bottom_radius = 17.0
	plane.height = 0.04
	plane.radial_segments = 32
	m.queue_free()
	_batch.add(plane, Transform3D(Basis(), Vector3(0, 0.01, 0)), Color(0.68, 0.54, 0.38), self)


func _build_houses() -> void:
	# [position, size, door side (+1 = door faces +x etc.), collapsed]
	var houses := [
		[Vector3(-10, 0, -6), Vector3(5, 3.2, 4.5), Vector3.RIGHT, false],
		[Vector3(-11, 0, 3.5), Vector3(4.5, 3.0, 5), Vector3.RIGHT, true],
		[Vector3(-8, 0, 11), Vector3(5, 2.8, 4), Vector3.BACK * -1, false],
		[Vector3(10, 0, -5), Vector3(5, 3.4, 5), Vector3.LEFT, true],
		[Vector3(11, 0, 4), Vector3(4.5, 3.0, 4.5), Vector3.LEFT, false],
		[Vector3(8.5, 0, 11.5), Vector3(5, 2.6, 4), Vector3.FORWARD, true],
	]
	for h in houses:
		_house(h[0], h[1], h[2], h[3])


func _house(pos: Vector3, size: Vector3, door: Vector3, collapsed: bool) -> void:
	var height := size.y * (0.55 if collapsed else 1.0)
	_box(Vector3(size.x, height, size.z), pos + Vector3(0, height / 2, 0), MUD)
	if not collapsed:
		# Flat roof with a parapet and triangular corner merlons.
		_box(Vector3(size.x + 0.3, 0.3, size.z + 0.3), pos + Vector3(0, size.y + 0.15, 0), MUD_DARK)
		for cx in [-1, 1]:
			for cz in [-1, 1]:
				_prism(pos + Vector3(cx * size.x * 0.45, size.y + 0.55, cz * size.z * 0.45), 0.5)
	else:
		for i in 4:  # rubble
			_box(Vector3(0.8, 0.5, 0.6), pos + door * (size.x * 0.5 + 0.6) + Vector3(randf_range(-1, 1), 0.25, randf_range(-1, 1)), MUD_DARK)
	# Door and windows (dark insets) on the side facing the square.
	var face := pos + Vector3(door.x * size.x * 0.5, 0, door.z * size.z * 0.5)
	var along := Vector3(1, 0, 0) if absf(door.z) > 0.5 else Vector3(0, 0, 1)
	_box(Vector3(0.12, 1.9, 1.0) if along.z != 0.0 else Vector3(1.0, 1.9, 0.12), face + Vector3(0, 0.95, 0) + door * 0.02, DARK, false)
	for k in [-1, 1]:
		if height > 2.2:
			var wpos: Vector3 = face + along * (k * size.x * 0.28) + Vector3(0, 2.2, 0) + door * 0.02
			_box(Vector3(0.12, 0.35, 0.35) if along.z != 0.0 else Vector3(0.35, 0.35, 0.12), wpos, DARK, false)


func _build_well() -> void:
	_cylinder(1.0, 0.8, Vector3(0, 0.4, 1.0), STONE)
	_cylinder(0.75, 0.82, Vector3(0, 0.42, 1.0), DARK, false)
	_box(Vector3(0.12, 1.8, 0.12), Vector3(-0.9, 0.9, 1.0), Color(0.42, 0.28, 0.16))
	_box(Vector3(0.12, 1.8, 0.12), Vector3(0.9, 0.9, 1.0), Color(0.42, 0.28, 0.16))
	_box(Vector3(2.0, 0.12, 0.12), Vector3(0, 1.8, 1.0), Color(0.42, 0.28, 0.16))


func _build_mosque() -> void:
	var c := Vector3(0, 0, -12)
	mosque_ruin = Node3D.new()
	add_child(mosque_ruin)
	var ruin_parts := [
		[Vector3(9, 2.2, 0.8), Vector3(0, 1.1, 3.1)], [Vector3(0.8, 1.4, 6), Vector3(-4.1, 0.7, 0)],
		[Vector3(0.8, 2.6, 3.5), Vector3(4.1, 1.3, -1.2)], [Vector3(4, 1.0, 0.8), Vector3(-2.5, 0.5, -3.1)],
		[Vector3(2.6, 3.2, 2.6), Vector3(3.2, 1.6, -4.5)],  # minaret stump
	]
	for rp in ruin_parts:
		_box(rp[0], c + rp[1], STONE, true, mosque_ruin)
	for i in 6:
		_box(Vector3(0.7, 0.4, 0.5), c + Vector3(randf_range(-3, 3), 0.2, randf_range(-2, 2.5)), STONE, false, mosque_ruin)

	mosque = Node3D.new()
	add_child(mosque)
	# Prayer hall: thick stone walls, flat roof, crenellations, dark doorway.
	_box(Vector3(9, 4.5, 7), c + Vector3(0, 2.25, 0), STONE, true, mosque)
	_box(Vector3(9.4, 0.35, 7.4), c + Vector3(0, 4.62, 0), Color(0.55, 0.46, 0.38), false, mosque)
	for i in 9:
		_prism(c + Vector3(-4.2 + i * 1.05, 5.05, 3.55), 0.5, mosque)
	_box(Vector3(1.6, 2.6, 0.1), c + Vector3(0, 1.3, 3.52), DARK, false, mosque)
	# Square minaret (Chinguetti-style): tapered stone tower, crenellated top,
	# ostrich-egg finials on the corners.
	var m := c + Vector3(3.2, 0, -4.5)
	_box(Vector3(2.8, 8.0, 2.8), m + Vector3(0, 4.0, 0), STONE, true, mosque)
	_box(Vector3(2.4, 2.6, 2.4), m + Vector3(0, 9.3, 0), STONE, true, mosque)
	_box(Vector3(2.7, 0.3, 2.7), m + Vector3(0, 10.75, 0), Color(0.55, 0.46, 0.38), false, mosque)
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			_prism(m + Vector3(cx * 1.05, 11.2, cz * 1.05), 0.55, mosque)
			var sm := SphereMesh.new()
			sm.radius = 0.16
			sm.height = 0.42
			sm.radial_segments = 10
			sm.rings = 6
			_batch.add(sm, Transform3D(Basis(), m + Vector3(cx * 1.05, 11.75, cz * 1.05)), Color(0.96, 0.94, 0.88), mosque)
	for k in 3:
		_box(Vector3(0.1, 0.5, 0.25), m + Vector3(1.42, 3.0 + k * 2.2, 0), DARK, false, mosque)


func _build_banner() -> void:
	banner = Node3D.new()
	banner.position = Vector3(4, 0, 2)
	add_child(banner)
	_box(Vector3(0.12, 6.0, 0.12), Vector3(0, 3.0, 0), Color(0.42, 0.28, 0.16), false, banner)
	var cloth := MeshInstance3D.new()
	var q := BoxMesh.new()
	q.size = Vector3(1.8, 1.1, 0.04)
	cloth.mesh = q
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.25, 0.42, 0.75)
	cloth.material_override = cm
	cloth.position = Vector3(0.95, 5.3, 0)
	banner.add_child(cloth)
	var emblem := MeshInstance3D.new()
	var e := PrismMesh.new()
	e.size = Vector3(0.6, 0.6, 0.05)
	emblem.mesh = e
	emblem.material_override = _mat(Color(1.0, 0.83, 0.35))
	emblem.position = Vector3(0.95, 5.3, -0.03)
	banner.add_child(emblem)


func _build_piles() -> void:
	var spots := {
		"pile_w1": Vector3(-7.5, 0, 3.5), "pile_e1": Vector3(7.5, 0, -5.5), "pile_s1": Vector3(6.0, 0, 9.5),
		"pile_w2": Vector3(-6.5, 0, -8.5), "pile_mosque": Vector3(-5.0, 0, -9.5),
	}
	for pid in spots:
		var pile := Node3D.new()
		pile.position = spots[pid]
		add_child(pile)
		for i in 5:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.45, 0.2, 0.25)
			_batch.add(bm, Transform3D(Basis(Vector3.UP, randf_range(-0.2, 0.2)), Vector3((i % 3) * 0.48 - 0.48, 0.1 + (i / 3) * 0.2, 0)), BRICK, pile)
		piles[pid] = pile
		var id: String = pid
		var it := _interactable(spots[pid], 2.2,
			func() -> String: return "Salvage mud bricks (+%d)" % SALVAGE_AMOUNT,
			func() -> bool: return not (WorldState.village(village_id)["salvaged"] as Array).has(id),
			func(_p: Player) -> void: salvage(id))
		it.set_meta("pile", id)


func _build_sign() -> void:
	var l := Label3D.new()
	l.text = display_name
	l.font_size = 64
	l.outline_size = 12
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = Vector3(-18.5, 3.4, 0)
	add_child(l)


# --- Helpers ----------------------------------------------------------------

func _interactable(pos: Vector3, r: float, prompt: Callable, available: Callable, action: Callable) -> Interactable:
	var it := Interactable.new()
	it.position = pos
	it.radius = r
	it.prompt = prompt
	it.available = available
	it.action = action
	add_child(it)
	return it


func _set_collision(root: Node, enabled: bool) -> void:
	for c in root.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not enabled
	for shape in root.get_meta("shapes", []):
		(shape as CollisionShape3D).disabled = not enabled


func _box(size: Vector3, pos: Vector3, color: Color, collide: bool = true, parent: Node3D = null) -> void:
	var p: Node3D = parent if parent else self
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch.add(mesh, Transform3D(Basis(), pos), color, p)
	if collide:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.position = pos
		body.add_child(col)
		var shapes: Array = p.get_meta("shapes", [])
		shapes.append(col)
		p.set_meta("shapes", shapes)


func _cylinder(radius: float, h: float, pos: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = h
	mesh.radial_segments = 16
	_batch.add(mesh, Transform3D(Basis(), pos), color, self)
	if collide:
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = h
		col.shape = shape
		col.position = pos
		body.add_child(col)


func _prism(pos: Vector3, s: float, parent: Node3D = null) -> void:
	var p: Node3D = parent if parent else self
	var pm := PrismMesh.new()
	pm.size = Vector3(s, s, s * 0.35)
	_batch.add(pm, Transform3D(Basis(), pos), MUD_DARK, p)


## Phase 7: village architecture on the shared pixel-art texel grid
## (pixel_world.gdshader, 32 px/m). Dark browns become wood, everything else
## mud-brick sandstone or packed earth tinted to the authored colour;
## strongly saturated accent colours (paint, cloth) stay flat.
const PIXEL_SHADER := preload("res://game/shaders/pixel_world.gdshader")
const FAMILY_AVG := {
	"res://game/art/pixel/sandstone_128.png": Color(0.639, 0.549, 0.455),
	"res://game/art/pixel/earth_128.png": Color(0.706, 0.529, 0.4),
	"res://game/art/pixel/wood_64.png": Color(0.439, 0.294, 0.2),
}

func _mat(color: Color) -> Material:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if color.s > 0.62 and color.v > 0.5:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = color
		sm.roughness = 1.0
		m = sm
	else:
		var tex := "res://game/art/pixel/sandstone_128.png"
		var size := 128.0
		if color.v < 0.5 and color.r > color.b:
			tex = "res://game/art/pixel/wood_64.png"
			size = 64.0
		elif color.s > 0.42:
			tex = "res://game/art/pixel/earth_128.png"
		var avg: Color = FAMILY_AVG[tex]
		var sh := ShaderMaterial.new()
		sh.shader = PIXEL_SHADER
		sh.set_shader_parameter("tex", load(tex))
		sh.set_shader_parameter("tex_size", size)
		sh.set_shader_parameter("tint", Color(color.r / avg.r, color.g / avg.g, color.b / avg.b))
		m = sh
	_mats[key] = m
	return m
