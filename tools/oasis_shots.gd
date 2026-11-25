extends Node
## Oasis review captures from the gameplay camera:
##   godot --path . res://tools/oasis_shots.tscn           (stills)
##   ... --write-movie /tmp/oasis.avi --fixed-fps 30 ... -- movie
## Stills: user://shots/oasis_*.png

var main: Node3D
var p: Player
var movie := false
var t := 0.0


func _ready() -> void:
	movie = OS.get_cmdline_user_args().has("movie")
	main = preload("res://game/main.tscn").instantiate()
	add_child(main)
	await _wait(5)
	p = main.player
	main.jinn.ai_enabled = false
	main.jinn.global_position = Vector3(30, 0, 30)
	main.hud.visible = false
	var o: Vector3 = main.OASIS_AT
	print("oasis grass blades ", main.get_children().filter(func(c): return c is Oasis)[0].grass_count)
	if movie:
		_place(o + Vector3(12.0, 0.05, 1.2), PI * 0.5, -0.32)
		return
	var oasis: Oasis = main.get_children().filter(func(c): return c is Oasis)[0]
	print("acacia+shrub leaves ", oasis.leaf_count)
	var shots := [
		["oasis_01_arrive", o + Vector3(7.5, 0.05, 9.0), 0.72, -0.22],
		["oasis_02_pond", o + Vector3(3.4, 0.05, 4.4), 0.62, -0.42],
		["oasis_03_palms", o + Vector3(-1.0, 0.05, 6.8), 0.1, -0.12],
		["oasis_04_acacia", o + Vector3(-6.0, 0.05, -1.5), 2.4, -0.18],
		["oasis_05_grass_low", o + Vector3(5.4, 0.05, 1.0), 1.45, -0.05],
		["oasis_06_acacia_close", o + Vector3(-8.2, 0.05, -3.6), 2.45, 0.12],
	]
	if OS.get_cmdline_user_args().has("probe"):
		await _probe(o)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("sanddbg"):
		var mats := {}
		for mi in main.find_children("*", "MeshInstance3D", true, false):
			var m = mi.material_override
			if m is ShaderMaterial and m.shader and m.shader.resource_path.ends_with("sand_ripple.gdshader"):
				mats[m] = true
		print("sand mats ", mats.size())
		for v in [["base", 0.42, 4.0], ["boost", 3.0, 60.0], ["dbg", 0.42, 4.0]]:
			for m in mats:
				m.set_shader_parameter("debug_spec", 1.0 if v[0] == "dbg" else 0.0)
				m.set_shader_parameter("ocean_strength", v[1])
				m.set_shader_parameter("glitter_strength", v[2])
			_place(o + Vector3(18.0, 0.05, 12.0), deg_to_rad(35.0), -0.18)
			main.camera_rig.distance = 4.0
			await _wait(30)
			await _shot("sanddbg_" + v[0])
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("cmp"):
		await _compare_shots(o)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("refl"):
		shots = [shots[1], shots[2], ["oasis_11_reflection", o + Vector3(6.2, 0.05, 2.0), 1.25, -0.2]]
		for s in shots:
			_place(s[1], s[2], s[3])
			await _wait(40)
			await _shot(str(s[0]) + "_refl")
		var oz: Oasis = main.get_children().filter(func(c): return c is Oasis)[0]
		oz.reflection.vp.get_texture().get_image().save_png("user://shots/reflection_buffer.png")
		await _probe(o)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("prints"):
		shots = []
	for s in shots:
		_place(s[1], s[2], s[3])
		await _wait(40)
		await _shot(str(s[0]))
	# footprints: walk across open sand, then look back along the trail
	_place(o + Vector3(14.0, 0.05, 14.0), 0.0, -0.35)
	await _wait(10)
	GameInput.touch_move = Vector2(0, -0.45)
	await _wait_s(3.0)
	GameInput.touch_move = Vector2.ZERO
	await _wait_s(0.4)
	main.camera_rig.yaw = p.rotation.y + PI * 0.8
	main.camera_rig.pitch = -0.75
	await _wait(25)
	var gfx: GroundFX = main.get_children().filter(func(c): return c is GroundFX)[0]
	print("prints ", gfx.count, " player ", p.global_position, " model ", p.model.global_position)
	for i in mini(gfx.count, 4):
		print("  print ", gfx._mm.get_instance_transform(i).origin, " ", gfx._mm.get_instance_custom_data(i), " t=", Wind.time)
	if OS.get_cmdline_user_args().has("prints"):
		await _shot("oasis_07_footprints")
		get_tree().quit()
		return
	await _shot("oasis_07_footprints")
	# splash: run into the pond
	var edge := o + Vector3(oasis.pond_radius + 2.2, 0.05, 0.0)
	_place(edge, PI * 0.5, -0.3)
	await _wait(10)
	GameInput.touch_move = Vector2(0, -1)
	var t0 := Time.get_ticks_msec()
	while oasis.splash_count == 0 and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait_s(0.12)
	GameInput.touch_move = Vector2.ZERO
	main.camera_rig.yaw = PI * 0.5 + 0.5
	await _shot("oasis_08_splash")
	await _wait_s(0.6)
	await _shot("oasis_09_ripples")
	# blown sand: open desert, wait for a gust front to reach the player
	_place(o + Vector3(14.0, 0.05, -12.0), 2.2, -0.28)
	await _wait(10)
	t0 = Time.get_ticks_msec()
	while Wind.gust_at(p.global_position) < 0.85 and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	await _shot("oasis_10_dust_gust")
	get_tree().quit()


## Same view, new effects on vs off: primitives, draw calls, frame time.
func _probe(o: Vector3) -> void:
	_place(o + Vector3(7.5, 0.05, 9.0), 0.72, -0.22)
	var fx: Array = main.get_children().filter(func(c): return c is GroundFX or c is WindDust)
	if OS.get_cmdline_user_args().has("canopy"):
		fx = main.find_children("*", "MultiMeshInstance3D", true, false).filter(
			func(m): return m.material_override is ShaderMaterial and str(m.material_override.get_shader_parameter("tex").resource_path).contains("leaf_fine"))
		print("canopy instances ", fx.map(func(m): return m.multimesh.instance_count))
	for on in [true, false, true]:
		for n in fx:
			n.visible = on
		await _wait(30)
		var ft := 0.0
		for i in 30:
			var t0 := Time.get_ticks_usec()
			await get_tree().process_frame
			ft += (Time.get_ticks_usec() - t0) / 1000.0
		print("probe fx=", on, " prims ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			" draws ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " ft_ms ", ft / 30.0)


## Views framed like the Garbage Country reference screenshots: high
## three-quarter camera, farther out than gameplay. Prefix from user args.
func _compare_shots(o: Vector3) -> void:
	var tag := "after"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
	var views := [
		["pond", o + Vector3(6.4, 0.05, 3.2), 1.1, -0.62, 11.0, 0.0],
		["open", o + Vector3(15.0, 0.05, -9.0), 2.3, -0.6, 10.0, 1.4],
		["grove", o + Vector3(-2.0, 0.05, 8.5), 0.35, -0.55, 12.0, 0.0],
		["horizon", o + Vector3(-14.0, 0.05, 6.0), PI * 0.5, -0.1, 6.0, 0.0],
		["horizon2", o + Vector3(8.0, 0.05, -10.0), PI * 1.25, -0.06, 6.0, 0.0],
		["palm", o + Vector3(-3.4, 0.05, 2.8), PI * 1.75, 0.18, 3.2, 0.0],
		["suna", o + Vector3(18.0, 0.05, 12.0), deg_to_rad(35.0), -0.18, 5.0, 0.0],
		["sunb", o + Vector3(18.0, 0.05, 12.0), deg_to_rad(35.0) + PI, -0.18, 5.0, 0.0],
		["flare", Vector3(30.0, 0.05, -28.0), deg_to_rad(35.0) + PI, 0.28, 5.0, 0.0],
		["flare2", Vector3(30.0, 0.05, -28.0), deg_to_rad(55.0) + PI, 0.18, 5.0, 0.0],
	]
	for v in views:
		_place(v[1], v[2], v[3])
		main.camera_rig.distance = v[4]
		await _wait(20)
		if v[5] > 0.0:
			GameInput.touch_move = Vector2(0, -1)
			await _wait_s(v[5])
			GameInput.touch_move = Vector2.ZERO
			await _wait_s(0.15)
		else:
			await _wait(25)
		await _shot("cmp_%s_%s" % [v[0], tag])
	# look straight at the sun from the open desert: sun disc, glare, flare
	var sd: Vector3 = main.sun.global_transform.basis.z
	_place(Vector3(30.0, 0.05, -28.0), atan2(-sd.x, -sd.z), 0.3)
	main.camera_rig.distance = 5.0
	await _wait(40)
	var lf = main.get_children().filter(func(c): return c is LensFlare)
	if lf.size() > 0:
		print("flare intensity ", lf[0].intensity, " sun px ", lf[0]._sun_px)
	await _shot("cmp_sunlook_%s" % tag)
	main.camera_rig.yaw += 0.35
	await _wait(30)
	await _shot("cmp_sunlook2_%s" % tag)
	# character close-up, sun on one side, to judge the cel bands
	_place(o + Vector3(9.0, 0.05, 4.0), 0.4, -0.08)
	main.camera_rig.yaw = 0.4 + PI * 0.75
	main.camera_rig.distance = 2.3
	await _wait(40)
	await _shot("cmp_char_%s" % tag)
	# walking away into the wind: the hawli ribbon trails
	_place(o + Vector3(14.0, 0.05, 10.0), 0.4, -0.12)
	main.camera_rig.distance = 3.6
	await _wait(10)
	GameInput.touch_move = Vector2(0, -0.6)
	await _wait_s(1.6)
	await _shot("cmp_charrun_%s" % tag)
	GameInput.touch_move = Vector2.ZERO
	await _wait_s(0.8)
	main.camera_rig.yaw = 0.4 + PI * 0.6
	main.camera_rig.distance = 3.0
	await _wait(30)
	await _shot("cmp_charside_%s" % tag)
	main.camera_rig.distance = 5.2


func _wait_s(sec: float) -> void:
	var end := Wind.time + sec
	while Wind.time < end:
		await get_tree().process_frame


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	p.global_position = pos
	p.rotation.y = yaw
	p.reset_physics_interpolation()
	main.camera_rig.yaw = yaw
	main.camera_rig.pitch = pitch


func _process(delta: float) -> void:
	if not movie:
		return
	t += delta
	# cross the sand into the grass, splash into the pond, wade out, then
	# stand while a gust carries sand and leaves past; look back at the trail
	var mv := Vector2.ZERO
	if t > 0.8 and t < 3.9:
		mv = Vector2(0, -0.55)              # across the sand into the water
	elif t > 6.0 and t < 8.6:
		mv = Vector2(0.15, 0.55)            # wade back out onto the sand
	GameInput.touch_move = mv
	if t > 9.2 and t < 12.5:
		# swing round to look back along the trail while a gust blows
		main.camera_rig.yaw = lerp_angle(main.camera_rig.yaw, PI * 0.5 + 0.9, delta * 1.0)
		main.camera_rig.pitch = lerpf(main.camera_rig.pitch, -0.55, delta * 1.0)
	if t > 15.0:
		get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % name)
