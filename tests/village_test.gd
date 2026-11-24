extends Node
## Village loop acceptance tests: conquest -> recruit -> salvage -> rebuild
## -> persistence. Run:
##   godot --headless --path . --fixed-fps 60 res://tests/village_test.tscn
## Uses its own save file so a tester's world is never touched.

const TEST_SAVE := "user://test_world.json"

var main: Node3D
var player: Player
var village: Village
var results: Array[String] = []
var failures: int = 0


func _ready() -> void:
	Juice.enabled_hitstop = false
	WorldState.use_path(TEST_SAVE, true)
	main = preload("res://game/main.tscn").instantiate()
	main.jinn_enabled = false
	add_child(main)
	await _frames(5)
	player = main.player
	village = main.village
	await _run()
	print("\n".join(results))
	print("RESULT: %d passed, %d failed" % [results.size() - failures, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	_check("village starts haunted", village.stage() == "haunted", village.stage())
	_check("a Jinn King guards it", is_instance_valid(village.king), "")
	_check("two shadow jinn guard it", village._alive_minions() == 2, str(village._alive_minions()))

	# Guards keep to their territory: the player in the courtyard is ignored.
	player.global_position = Vector3(0, 0.05, 6)
	await _frames(60)
	_check("village jinn ignore a player outside their territory", village.king.state == Jinn.S.IDLE, village.king.state_name())

	# Walking in wakes the King.
	player.global_position = village.global_position + Vector3(0, 0.05, 9)
	player.reset_physics_interpolation()
	await _frames(30)
	_check("entering the village wakes the King", village.king.state != Jinn.S.IDLE, village.king.state_name())
	player.hp = 100000.0
	player.max_hp = 100000.0

	# Summon adds minions (max 3 alive).
	var before := village._alive_minions()
	village.king.force_attack("summon")
	await _frames(int(village.king.telegraph_time("summon") * 60) + 10)
	_check("King summons more shadow jinn", village._alive_minions() > before, "%d -> %d" % [before, village._alive_minions()])

	# Rage at half health.
	village.king.take_damage({"amount": village.king.max_hp * 0.55, "element": Combat.Element.NONE, "from": player.global_position, "stagger": 0})
	_check("King rages below half health", village.king.raging and village.king.tempo > 1.0, str(village.king.tempo))

	# Salvage before conquest is allowed (ruins are dangerous but open).
	var pile_it := _interactable_with_meta("pile", "pile_w1")
	pile_it.interact(player)
	_check("salvaging a pile gives 3 bricks", WorldState.bricks() == 3, str(WorldState.bricks()))
	pile_it.interact(player)
	_check("a pile can only be salvaged once", WorldState.bricks() == 3, str(WorldState.bricks()))

	# Mosque cannot be rebuilt while haunted.
	_check("mosque locked while haunted", not village.mosque_site.can_interact(), village.mosque_site.prompt_text())

	# Defeat the King.
	village.king.take_damage({"amount": 99999.0, "element": Combat.Element.NONE, "from": player.global_position, "stagger": 2})
	await _frames(100)
	_check("defeating the King claims the village", village.stage() == "claimed", village.stage())
	_check("claim is owned by the player", WorldState.village(village.village_id)["owner"] == "player", "")
	_check("claim is logged as an event", _has_event("village_claimed"), "")
	_check("a second claim is rejected", not WorldState.claim_village(village.village_id, "rival"), "")
	var kneeling := get_tree().get_nodes_in_group("subdued_jinn")
	_check("at least two jinn kneel, ready to recruit", kneeling.size() >= 2, str(kneeling.size()))
	_check("banner rises over the square", village.banner.visible, "")

	# Recruit.
	var first: Jinn = kneeling[0]
	var rec := _child_interactable(first)
	_check("kneeling jinn offer a Recruit prompt", rec != null and rec.prompt_text().begins_with("Recruit"), "")
	rec.interact(player)
	await _frames(3)
	_check("recruiting creates a villager", get_tree().get_nodes_in_group("villagers").size() == 1, "")
	_check("first recruit becomes a Guard", (WorldState.village(village.village_id)["npcs"] as Array)[0]["job"] == "guard", "")

	# Rebuild the mosque.
	_check("mosque needs 10 bricks", not village.mosque_site.can_interact(), village.mosque_site.prompt_text())
	for pid in ["pile_e1", "pile_s1", "pile_w2"]:
		_interactable_with_meta("pile", pid).interact(player)
	_check("four piles = 12 bricks", WorldState.bricks() == 12, str(WorldState.bricks()))
	village.mosque_site.interact(player)
	await _frames(10)
	_check("mosque rebuilt", village.stage() == "mosque_rebuilt" and village.mosque.visible, village.stage())
	_check("rebuilding spends 10 bricks", WorldState.bricks() == 2, str(WorldState.bricks()))

	# Persistence: a fresh load of the same file sees the same world.
	var saved := FileAccess.get_file_as_string(TEST_SAVE)
	var parsed: Dictionary = JSON.parse_string(saved)
	var v: Dictionary = parsed["villages"][village.village_id]
	_check("save file records mosque_rebuilt", v["stage"] == "mosque_rebuilt", str(v["stage"]))
	_check("save file records the recruit", (v["npcs"] as Array).size() == 1, "")
	_check("save file records the brick count", int(parsed["player"]["bricks"]) == 2, "")

	# Reloading the scene rebuilds the restored village, without a King.
	main.queue_free()
	await _frames(3)
	WorldState.load_world()
	main = preload("res://game/main.tscn").instantiate()
	main.jinn_enabled = false
	add_child(main)
	await _frames(5)
	village = main.village
	_check("after reload: still rebuilt", village.stage() == "mosque_rebuilt" and village.mosque.visible, village.stage())
	_check("after reload: no King respawns", village.king == null, "")
	var vills := 0
	for n in get_tree().get_nodes_in_group("villagers"):
		if n.get_parent() == village:
			vills += 1
	_check("after reload: the villager is back", vills == 1, str(vills))
	WorldState.use_path("user://world.json")


func _interactable_with_meta(key: String, value: String) -> Interactable:
	for it in get_tree().get_nodes_in_group("interactables"):
		if it.has_meta(key) and it.get_meta(key) == value:
			return it
	return null


func _child_interactable(n: Node) -> Interactable:
	for c in n.get_children():
		if c is Interactable:
			return c
	return null


func _has_event(kind: String) -> bool:
	for e in WorldState.data["events"]:
		if e["kind"] == kind:
			return true
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		results.append("PASS  %s%s" % [name, ("  [%s]" % detail) if detail != "" else ""])
	else:
		failures += 1
		results.append("FAIL  %s  (%s)" % [name, detail])
