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
	main = preload("res://game/main.tscn").instantiate()
	main.jinn_enabled = false
	add_child(main)
	await _frames(5)
	player = main.player
	await _run_all()
	print("\n".join(results))
	print("RESULT: %d passed, %d failed" % [results.size() - failures, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
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
	await _test_lock_on()
	await _test_species_stamina()
	await _test_jinn_ai_attacks()
	await _test_species_switch()


# --- Tests ------------------------------------------------------------------

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
	# fire tier 3 = 55, x1.3 fire bonus = 71.5, then burn ticks 3/s
	_check("fire tier-3 strike deals >= 71.5", jinn.damage_taken_total >= 71.5, "got %.1f" % jinn.damage_taken_total)
	_check("fire applies burn", jinn.burn_time > 0.0, "%.2f" % jinn.burn_time)
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
	player.element = Combat.Element.WIND
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
		results.append("PASS  %s" % name)
	else:
		failures += 1
		results.append("FAIL  %s  (%s)" % [name, detail])
