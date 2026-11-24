extends Node
## Headless combat acceptance tests. Run:
##   godot --headless --path . res://tests/combat_test.tscn
## Exit code 0 = all pass. Each test drives the same GameInput queue the
## touch HUD uses, so it exercises the real input path.

var main: Node3D
var player: Player
var jinn: Jinn
var results: Array[String] = []
var failures: int = 0


func _ready() -> void:
	Juice.enabled_hitstop = false
	main = preload("res://game/main.tscn").instantiate()
	main.jinn_enabled = false
	main.village_enabled = false
	add_child(main)
	await _frames(5)
	player = main.player
	await _run_all()
	print("\n".join(results))
	print("RESULT: %d passed, %d failed" % [results.size() - failures, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	await _test_spirit_visual()
	await _test_elemental_props()
	await _test_light_combo()
	await _test_heavy_attack()
	await _test_taking_hit()
	await _test_block()
	await _test_parry()
	await _test_dodge_iframes()
	await _test_charge_tiers_and_cast()
	await _test_release_special_cancels()
	await _test_elemental_mobility()
	await _test_wind_defense()
	await _test_water_chill()
	await _test_water_defense()
	await _test_earth_healing()
	await _test_earth_defense()
	await _test_element_cycle()
	await _test_lock_on()
	await _test_species_stamina()
	await _test_jinn_ai_attacks()
	await _test_species_switch()
	await _test_jump()
	await _test_climb_wall_and_mantle()
	await _test_glide()
	await _test_fall_damage()
	await _test_mesa_only_lizard()
	await _test_pause_menu()
	await _test_hand_poses()
	await _test_jinn_enchantment_rule()


# --- Tests ------------------------------------------------------------------

func _test_spirit_visual() -> void:
	await _reset(Vector3(0, 0, -3.0))
	# Smoke body, rising wisps, golden rings; no mask.
	_check("jinn is smoke with rising wisps", jinn._wisps != null and jinn._wisps.emitting, "")
	_check("jinn has three golden rings", jinn._gold_rings.size() == 3, str(jinn._gold_rings.size()))
	_check("jinn wears no mask", jinn.find_children("Mask", "", true, false).is_empty(), "")


func _test_elemental_props() -> void:
	var props := get_tree().get_nodes_in_group("elemental_props")
	_check("three physics props exist", props.size() == 3, "count %d" % props.size())
	if props.is_empty():
		return
	var crate := props[0] as ElementalProp
	crate.receive_element(Combat.Element.FIRE, Vector3.FORWARD, 10.0)
	_check("fire ignites wooden crates", crate.burning > 0.0, str(crate.burning))
	crate.receive_element(Combat.Element.WATER, Vector3.FORWARD, 10.0)
	_check("water extinguishes fire", crate.burning == 0.0 and crate.chilled > 0.0, str(crate.chilled))
	crate.receive_element(Combat.Element.WIND, Vector3.RIGHT, 9.0)
	await _frames(2)
	_check("wind pushes physics props", crate.linear_velocity.length() > 0.01, str(crate.linear_velocity))




func _test_light_combo() -> void:
	await _reset(Vector3(0, 0, -1.6))
	for i in 3:
		await _tap("attack", 3)
		await _frames(9)
	await _frames(40)
	_check("light combo 10+11+18 = 39 damage", is_equal_approx(jinn.damage_taken_total, 39.0), "got %.1f" % jinn.damage_taken_total)


func _test_heavy_attack() -> void:
	await _reset(Vector3(0, 0, -1.6))
	GameInput.press("attack")
	await _frames(50)  # > HEAVY_HOLD and past the first light swing
	_check("holding attack enters heavy charge", player.state == Player.State.HEAVY_CHARGE, player.state_name())
	GameInput.release("attack")
	await _frames(40)
	_check("heavy strike lands (10 light + 32 heavy)", is_equal_approx(jinn.damage_taken_total, 42.0), "got %.1f" % jinn.damage_taken_total)


func _test_taking_hit() -> void:
	await _reset(Vector3(0, 0, -1.8))
	jinn.force_attack("swipe")
	await _frames(60)
	_check("undefended swipe deals 14", is_equal_approx(player.hp, 86.0), "hp %.1f result %s" % [player.hp, jinn.last_result])


func _test_block() -> void:
	await _reset(Vector3(0, 0, -1.8))
	GameInput.press("dodge")
	await _frames(15)  # past tap window and parry window
	jinn.force_attack("swipe")
	await _frames(45)
	_check("held guard blocks swipe", jinn.last_result == "blocked" and is_equal_approx(player.hp, 100.0), jinn.last_result)
	_check("block costs stamina", player.stamina < player.max_stamina, "%.1f" % player.stamina)
	GameInput.release("dodge")
	await _frames(5)


func _test_parry() -> void:
	await _reset(Vector3(0, 0, -1.8))
	jinn.force_attack("swipe")  # telegraph 0.6 s = 36 frames
	await _frames(31)
	GameInput.press("dodge")    # ~83 ms before the hit
	await _frames(12)
	_check("guard started <=150 ms before hit = parry", jinn.last_result == "parried", jinn.last_result)
	_check("parry staggers the jinn", jinn.state == Jinn.S.STAGGER, jinn.state_name())
	_check("parry opens counter window", player.counter_window > 0.0, "%.2f" % player.counter_window)
	GameInput.release("dodge")
	await _frames(4)
	var before := jinn.damage_taken_total
	await _tap("attack", 3)
	await _frames(20)
	# 10 x1.5 counter x1.25 stagger = 18.75
	_check("counter attack on staggered jinn deals 18.75", is_equal_approx(jinn.damage_taken_total - before, 18.75), "got %.2f" % (jinn.damage_taken_total - before))


func _test_dodge_iframes() -> void:
	await _reset(Vector3(0, 0, -1.8))
	jinn.force_attack("burst")  # telegraph 1.2 s = 72 frames, radius 3.4
	await _frames(64)
	await _tap("dodge", 4)       # release -> dodge, hits during i-frames
	await _frames(30)
	_check("dodge through burst takes no damage", is_equal_approx(player.hp, 100.0), "hp %.1f result %s" % [player.hp, jinn.last_result])
	_check("well-timed dodge is a perfect dodge", jinn.last_result == "perfect_dodge", jinn.last_result)


func _test_charge_tiers_and_cast() -> void:
	await _reset(Vector3(0, 0, -2.5))
	player.element = Combat.Element.FIRE
	GameInput.press("special")
	await _frames(25)
	_check("0.42 s hold = tier 1", player.charge_tier() == 1, str(player.charge_tier()))
	await _frames(30)
	_check("0.92 s hold = tier 2", player.charge_tier() == 2, str(player.charge_tier()))
	await _frames(35)
	_check("1.5 s hold = tier 3", player.charge_tier() == 3, str(player.charge_tier()))
	await _tap("attack", 2)
	await _frames(30)
	GameInput.release("special")
	# Jinn are smoke: fire passes through (fire is for PvP and props).
	_check("fire tier-3 strike does not harm a jinn", is_equal_approx(jinn.damage_taken_total, 0.0) and jinn.immune_hits > 0, "got %.1f, immune %d" % [jinn.damage_taken_total, jinn.immune_hits])
	_check("fire does not burn a jinn", jinn.burn_time <= 0.0, "%.2f" % jinn.burn_time)
	player.element = Combat.Element.WIND


func _test_release_special_cancels() -> void:
	await _reset(Vector3(0, 0, -2.5))
	var casts_before: int = player.stats["casts"]
	GameInput.press("special")
	await _frames(30)
	GameInput.release("special")
	await _frames(2)
	_check("releasing Special alone cancels the charge", player.charge_tier() == 0 and player.stats["casts"] == casts_before, "tier %d casts %d" % [player.charge_tier(), player.stats["casts"] - casts_before])
	_check("cancel costs no stamina", is_equal_approx(player.stamina, player.max_stamina), "%.1f" % player.stamina)


func _test_elemental_mobility() -> void:
	await _reset(Vector3(6, 0, -6))
	player.element = Combat.Element.WIND
	var start := player.global_position
	GameInput.press("special")
	await _frames(25)
	await _tap("dodge", 2)
	await _frames(3)
	_check("Special + Dodge = elemental mobility", player.state == Player.State.MOBILITY, player.state_name())
	await _frames(30)
	GameInput.release("special")
	var moved := player.global_position.distance_to(start)
	_check("wind dash travels > 3 m", moved > 3.0, "%.2f m" % moved)


func _test_wind_defense() -> void:
	await _reset(Vector3(0, 0, -1.8))
	player.element = Combat.Element.WIND
	GameInput.press("dodge")
	await _frames(15)
	jinn.force_attack("lunge")  # telegraph 0.9 s
	await _frames(50)
	await _tap("special", 2)    # guard + special = wind deflect
	await _frames(20)
	_check("guard + Special = elemental defense", jinn.last_result == "deflected" or player.state == Player.State.DEFENSE, "%s / %s" % [jinn.last_result, player.state_name()])
	_check("wind deflect: no damage", is_equal_approx(player.hp, 100.0), "hp %.1f" % player.hp)
	GameInput.release("dodge")
	await _frames(10)


func _test_water_chill() -> void:
	await _reset(Vector3(0, 0, -2.5))
	player.element = Combat.Element.WATER
	GameInput.press("special")
	await _frames(25)  # tier I
	await _tap("attack", 2)
	await _frames(23)
	GameInput.release("special")
	_check("ice attack slows jinn", jinn.chill_time > 0.0 and jinn.chill_multiplier < 1.0, "chill %.2f mult %.2f" % [jinn.chill_time, jinn.chill_multiplier])
	_check("ice attack harms a jinn (water cuts smoke)", jinn.damage_taken_total > 0.0 and jinn.damage_taken_total < 18.0, "%.1f" % jinn.damage_taken_total)


func _test_water_defense() -> void:
	await _reset(Vector3(0, 0, -1.8))
	player.element = Combat.Element.WATER
	jinn.force_attack("swipe")
	await _frames(17)
	GameInput.press("dodge")
	await _frames(14)
	await _tap("special", 2)
	await _frames(19)
	_check("ice barrier absorbs frontal hit", jinn.last_result == "ice_block" and is_equal_approx(player.hp, 100.0), jinn.last_result)
	_check("ice barrier chills attacker", jinn.chill_time > 0.0, "%.2f" % jinn.chill_time)
	GameInput.release("dodge")
	await _frames(5)


func _test_earth_healing() -> void:
	await _reset(Vector3(0, 0, -2.5))
	player.element = Combat.Element.EARTH
	player.hp = 30.0
	GameInput.press("special")
	await _frames(25)
	await _tap("attack", 2)
	await _frames(23)
	GameInput.release("special")
	_check("earth tier I restores 18 HP", is_equal_approx(player.hp, 48.0), "%.1f" % player.hp)
	_check("earth healing does not damage jinn", is_zero_approx(jinn.damage_taken_total), "%.1f" % jinn.damage_taken_total)


func _test_earth_defense() -> void:
	await _reset(Vector3(0, 0, -1.8))
	player.element = Combat.Element.EARTH
	player.hp = 70.0
	jinn.force_attack("swipe")
	await _frames(17)
	GameInput.press("dodge")
	await _frames(14)
	await _tap("special", 2)
	await _frames(19)
	_check("earth defense halves incoming damage", jinn.last_result == "earth_guard" and player.hp > 70.0, "hp %.1f / %s" % [player.hp, jinn.last_result])
	GameInput.release("dodge")
	await _frames(5)


func _test_element_cycle() -> void:
	await _reset(Vector3(0, 0, -8.0))
	player.element = Combat.Element.WIND
	for e in [Combat.Element.FIRE, Combat.Element.WATER, Combat.Element.EARTH, Combat.Element.WIND]:
		await _tap("element", 2)
		await _frames(32)  # > 0.5 s switch cooldown
		_check("element cycles to %s" % Combat.ELEMENT_NAMES[e], player.element == e, str(player.element))


func _test_lock_on() -> void:
	await _reset(Vector3(0, 0, -5))
	await _tap("lock", 2)
	await _frames(2)
	_check("lock picks the jinn", player.lock_target == jinn, str(player.lock_target))
	await _tap("lock", 2)
	await _frames(2)
	_check("lock again releases", player.lock_target == null, str(player.lock_target))


func _test_species_stamina() -> void:
	var cat := Species.get_data("cat")
	var liz := Species.get_data("lizard")
	_check("cat has less stamina than lizard", float(cat["stamina"]) < float(liz["stamina"]), "")
	_check("cat player max stamina = 70", is_equal_approx(player.max_stamina, 70.0), "%.1f" % player.max_stamina)


func _test_jinn_ai_attacks() -> void:
	await _reset(Vector3(0, 0, -4))
	jinn.ai_enabled = true
	jinn._enter(Jinn.S.IDLE)
	var seen := {}
	for i in 900:  # 15 s
		await get_tree().physics_frame
		if jinn.state == Jinn.S.TELEGRAPH:
			seen[jinn.current] = int(seen.get(jinn.current, 0)) + (1 if jinn.state_time < 0.017 else 0)
		if player.hp < 40.0:
			player.hp = 100.0
	_check("AI jinn telegraphs attacks on its own", seen.size() >= 2, str(seen))


func _test_species_switch() -> void:
	await _reset(Vector3(0, 0, -6))
	await _tap("species", 2)
	await _frames(2)
	_check("species switch: cat -> fennec, stamina 100", player.species_id == "fennec" and is_equal_approx(player.max_stamina, 100.0), player.species_id)
	await _tap("species", 2)
	await _frames(2)
	_check("species switch: fennec -> lizard, stamina 140", player.species_id == "lizard" and is_equal_approx(player.max_stamina, 140.0), player.species_id)
	player.set_species("cat")


func _test_jump() -> void:
	await _reset(Vector3(0, 0, -40))
	player.global_position = Vector3(6, 0.05, 4)
	await _frames(10)
	var y0 := player.global_position.y
	await _tap("jump", 2)
	var peak := y0
	for i in 60:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	_check("jump peaks ~1.1 m", peak - y0 > 0.9 and peak - y0 < 1.3, "%.2f m" % (peak - y0))
	_check("lands back in MOVE", player.state == Player.State.MOVE, player.state_name())


func _test_climb_wall_and_mantle() -> void:
	await _reset(Vector3(0, 0, -40))
	player.global_position = Vector3(3, 0.05, -9.5)
	player.reset_physics_interpolation()
	await _frames(5)
	GameInput.touch_move = Vector2(0, -1)
	var climbed := false
	for i in 300:
		await get_tree().physics_frame
		if player.state == Player.State.CLIMB:
			climbed = true
		if climbed and player.state == Player.State.MOVE:
			break
	GameInput.touch_move = Vector2.ZERO
	await _frames(10)
	_check("pushing into a wall starts a climb", climbed, player.state_name())
	_check("climb + mantle ends standing on the 3.6 m wall", player.global_position.y > 3.4 and player.is_on_floor(), "y %.2f %s" % [player.global_position.y, player.state_name()])
	_check("climbing spends stamina", player.stamina < player.max_stamina, "%.1f" % player.stamina)


func _test_glide() -> void:
	await _reset(Vector3(0, 0, -40))
	player.global_position = Vector3(25, 14, 0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _frames(12)
	_check("falling = AIR state", player.state == Player.State.AIR, player.state_name())
	await _tap("special", 2)
	await _frames(20)
	_check("tap Special in the air opens the daraa", player.state == Player.State.GLIDE, player.state_name())
	var worst := 0.0
	for i in 40:
		await get_tree().physics_frame
		worst = minf(worst, player.velocity.y)
	_check("glide caps fall speed at 1.6 m/s", worst >= -1.65, "%.2f" % worst)
	for i in 600:
		await get_tree().physics_frame
		if player.state == Player.State.MOVE:
			break
	_check("glide lands safely", player.state == Player.State.MOVE and is_equal_approx(player.hp, 100.0), "%s hp %.0f" % [player.state_name(), player.hp])


func _test_fall_damage() -> void:
	await _reset(Vector3(0, 0, -40))
	player.global_position = Vector3(25, 12, 0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for i in 120:
		await get_tree().physics_frame
	_check("a 12 m drop without gliding hurts", player.hp < 100.0, "hp %.1f" % player.hp)


func _test_mesa_only_lizard() -> void:
	var tops := {}
	for sp in ["cat", "fennec", "lizard"]:
		await _reset(Vector3(0, 0, -40))
		player.set_species(sp)
		player.global_position = Vector3(-17, 0.05, 25.3)
		player.rotation.y = PI
		player.camera_rig.yaw = PI
		player.reset_physics_interpolation()
		await _frames(5)
		GameInput.touch_move = Vector2(0, -1)
		var best := 0.0
		for i in 1200:
			await get_tree().physics_frame
			best = maxf(best, player.global_position.y)
			if player.global_position.y > 19.5 and player.state == Player.State.MOVE:
				break
			if player.state == Player.State.AIR and player.regrab_at > player.now - 0.1 and player.stamina <= 0.0:
				break
		GameInput.touch_move = Vector2.ZERO
		tops[sp] = best
	player.set_species("cat")
	_check("Cat cannot top the 20 m mesa in one climb", float(tops["cat"]) < 19.0, str(tops))
	_check("Fennec cannot top the 20 m mesa in one climb", float(tops["fennec"]) < 19.0, str(tops))
	_check("Lizard tops the 20 m mesa", float(tops["lizard"]) > 19.9, str(tops))


func _test_pause_menu() -> void:
	await _reset(Vector3(0, 0, -40))
	main.hud.set_paused(true)
	_check("pause stops the game tree", get_tree().paused, "")
	main.hud.set_paused(false)
	_check("resume restarts it", not get_tree().paused, "")


func _test_hand_poses() -> void:
	await _reset(Vector3(0, 0, -40))
	player.global_position = Vector3(6, 0.05, 4)
	player.last_combat_time = -100.0
	await _frames(10)
	var m := player.model
	_check("idle, no enemy near: sword on the back", not m.armed, "")
	_check("idle: open hands", m.hand_pose_r == "open" and m.hand_pose_l == "open", m.hand_pose_r)
	GameInput.touch_move = Vector2(0, -1)
	await _frames(50)
	_check("sprinting: fists", m.hand_pose_r == "fist" and m.hand_pose_l == "fist", "%s %s" % [m.hand_pose_r, m.hand_pose_l])
	GameInput.touch_move = Vector2.ZERO
	await _tap("attack", 2)
	await _frames(3)
	_check("attacking draws the sword", m.armed, "")
	_check("attacking: right hand grips the sword", m.hand_pose_r == "grip", m.hand_pose_r)
	player.emote("thumbs_up", 1.0)
	await _frames(40)
	_check("emote: thumbs up", m.hand_pose_r == "thumbs_up", m.hand_pose_r)
	_check("emote: sword put away to gesture", not m.armed, "")
	player.emote("peace", 1.0)
	await _frames(3)
	_check("emote: peace", m.hand_pose_r == "peace", m.hand_pose_r)
	await _frames(80)
	player.last_combat_time = -100.0
	await _frames(5)
	_check("calm again: sword sheathed, hands open", not m.armed and m.hand_pose_r == "open", "%s %s" % [m.armed, m.hand_pose_r])


func _test_jinn_enchantment_rule() -> void:
	for e in [Combat.Element.WIND, Combat.Element.FIRE]:
		await _reset(Vector3(0, 0, -1.6))
		player.element = e
		await _tap("attack", 3)
		await _frames(30)
		_check("%s sword passes through a jinn" % Combat.ELEMENT_NAMES[e], is_equal_approx(jinn.damage_taken_total, 0.0) and jinn.immune_hits > 0, "%.1f" % jinn.damage_taken_total)
	for e in [Combat.Element.WATER, Combat.Element.EARTH]:
		await _reset(Vector3(0, 0, -1.6))
		player.element = e
		await _frames(2)
		_check("%s enchants the sword" % Combat.ELEMENT_NAMES[e], player.model.enchanted, "")
		await _tap("attack", 3)
		await _frames(30)
		_check("%s-enchanted sword cuts a jinn (10 dmg)" % Combat.ELEMENT_NAMES[e], is_equal_approx(jinn.damage_taken_total, 10.0), "%.1f" % jinn.damage_taken_total)


# --- Helpers ----------------------------------------------------------------

func _reset(jinn_offset: Vector3) -> void:
	for j in get_tree().get_nodes_in_group("jinn"):
		j.remove_from_group("jinn")
		j.queue_free()
	for a in GameInput.BUTTONS:
		GameInput.release(a)
	await _frames(2)
	GameInput.consume_events()
	player.lock_target = null
	player.camera_rig.lock_target = null
	player.respawn()
	player.global_position = Vector3(0, 0.05, 0)
	player.rotation = Vector3.ZERO
	player.camera_rig.yaw = 0.0
	player.counter_window = 0.0
	player.element = Combat.Element.WATER
	player.charge_cancelled = true
	jinn = Jinn.new()
	jinn.ai_enabled = false
	jinn.position = jinn_offset
	main.add_child(jinn)
	await _frames(3)


func _tap(action: String, hold_frames: int) -> void:
	GameInput.press(action)
	await _frames(hold_frames)
	GameInput.release(action)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		results.append("PASS  %s%s" % [name, ("  [%s]" % detail) if detail != "" else ""])
	else:
		failures += 1
		results.append("FAIL  %s  (%s)" % [name, detail])
