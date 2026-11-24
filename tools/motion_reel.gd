extends Node
## Deterministic motion reel for judging weight and timing.
##   godot --path . --write-movie /tmp/reel.avi --fixed-fps 30 res://tools/motion_reel.tscn
## Idle, walk, run, stop, 3-hit combo, charged heavy, jump + land, cheer.

const SEQ := [
	# [until_s, state, move, speed m/s, extra]
	[0.9, "MOVE", 0.0, 0.0, {}],
	[2.7, "MOVE", 0.3, 2.2, {}],
	[4.5, "MOVE", 1.0, 6.6, {"sprinting": true}],
	[5.0, "MOVE", 0.0, 0.0, {}],
	[5.55, "ATTACK", 0.0, 0.0, {"combo": 0}],
	[6.1, "ATTACK", 0.0, 0.0, {"combo": 1}],
	[6.75, "ATTACK", 0.0, 0.0, {"combo": 2}],
	[7.4, "MOVE", 0.0, 0.0, {}],
	[8.2, "HEAVY_CHARGE", 0.0, 0.0, {}],
	[8.7, "HEAVY", 0.0, 0.0, {}],
	[9.2, "MOVE", 0.0, 0.0, {}],
	[9.95, "AIR", 0.0, 2.5, {}],
	[10.8, "MOVE", 0.0, 0.0, {}],
	[12.2, "EMOTE", 0.0, 0.0, {}],
	[12.8, "MOVE", 0.0, 0.0, {}],
]

var m: CreatureModel
var cam: Camera3D
var t := 0.0
var seg := 0
var seg_start := 0.0
var speed := 0.0
var y_vel := 0.0
var ground: MeshInstance3D


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(35), 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
	sun.directional_shadow_max_distance = 30.0
	root.add_child(sun)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.62, 0.9)
	sm.sky_horizon_color = Color(0.9, 0.86, 0.78)
	sm.ground_horizon_color = Color(0.86, 0.74, 0.56)
	sm.ground_bottom_color = Color(0.7, 0.56, 0.4)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = load("res://game/world/sand_ripple.gdshader")
	gm.set_shader_parameter("sand_color", Color(0.78, 0.58, 0.38))
	ground.material_override = gm
	ground.position = Vector3(0, 0, -30)
	root.add_child(ground)
	# a few markers so motion over the ground reads
	for i in 14:
		var r := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.5, 0.35 + (i % 3) * 0.2, 0.5)
		r.mesh = b
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.62, 0.42, 0.3)
		r.material_override = rm
		r.position = Vector3(2.2 if i % 2 == 0 else -2.4, b.size.y * 0.5, -i * 3.0)
		root.add_child(r)
	m = CreatureModel.new()
	root.add_child(m)
	m.build(Species.get_data("cat"))
	m.set_armed(true)
	cam = Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	_place_cam(1.0)


func _place_cam(k: float) -> void:
	var target := m.global_position + Vector3(0, 0.85, 0)
	var want := m.global_position + Vector3(2.1, 1.25, -1.9)
	cam.global_position = cam.global_position.lerp(want, k)
	cam.look_at(target)


func _process(delta: float) -> void:
	t += delta
	while seg < SEQ.size() - 1 and t >= float(SEQ[seg][0]):
		seg_start = float(SEQ[seg][0])
		seg += 1
		if SEQ[seg][1] == "AIR":
			y_vel = 6.0
		if SEQ[seg][1] == "EMOTE":
			m.emote("thumbs_up", 1.3)
	if t > float(SEQ[-1][0]) + 0.3:
		get_tree().quit()
		return
	var s: Array = SEQ[seg]
	var dur := float(s[0]) - seg_start
	var p := clampf((t - seg_start) / dur, 0.0, 1.0)
	var state: String = s[1]
	if state == "EMOTE":
		state = "MOVE"
	# momentum: ease toward the segment's speed
	var target_speed: float = s[3]
	var rate := 26.0 if target_speed > speed else 34.0
	speed = move_toward(speed, target_speed, rate * delta)
	var vel := Vector3(0, 0, -speed)
	if state == "AIR" or m.global_position.y > 0.0:
		y_vel -= 16.0 * delta
		m.global_position.y = maxf(0.0, m.global_position.y + y_vel * delta)
		if m.global_position.y <= 0.0 and y_vel < 0.0:
			y_vel = 0.0
		vel.y = y_vel
	m.global_position.z += vel.z * delta
	var info := {"state": state, "move": clampf(speed / 7.1, 0.0, 1.0), "t": p, "vel": vel,
		"windup_frac": 0.45, "rising": y_vel > 0.5}
	info.merge(s[4], true)
	if state in ["ATTACK", "HEAVY"]:
		info["state"] = "ATTACK" if state == "ATTACK" else "HEAVY"
	if state == "AIR" and m.global_position.y <= 0.0 and y_vel == 0.0:
		info["state"] = "MOVE"
	m.animate(delta, info)
	_place_cam(1.0 - exp(-6.0 * delta))
