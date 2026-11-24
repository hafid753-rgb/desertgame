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
		_place(o + Vector3(6.5, 0.05, 7.5), 0.75, -0.2)
		return
	var shots := [
		["oasis_01_arrive", o + Vector3(7.5, 0.05, 9.0), 0.72, -0.22],
		["oasis_02_pond", o + Vector3(3.4, 0.05, 4.4), 0.62, -0.42],
		["oasis_03_palms", o + Vector3(-1.0, 0.05, 6.8), 0.1, -0.12],
		["oasis_04_acacia", o + Vector3(-6.0, 0.05, -1.5), 2.4, -0.18],
		["oasis_05_grass_low", o + Vector3(5.4, 0.05, 1.0), 1.45, -0.05],
	]
	for s in shots:
		_place(s[1], s[2], s[3])
		await _wait(40)
		await _shot(str(s[0]))
	get_tree().quit()


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
	# walk through the grass toward the pond, then stand while a gust passes
	GameInput.touch_move = Vector2(-0.35, -0.75) if t > 1.0 and t < 5.0 else Vector2.ZERO
	if t > 11.0:
		get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % name)
