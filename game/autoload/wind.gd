extends Node
## EnvironmentalWind: one world-space wind field shared by grass, leaves,
## palm fronds, cloth, smoke, dust and debris. Shaders read it through
## global uniforms (see game/shaders/wind.gdshaderinc); CPU-side effects
## (particles, cloth springs) sample the same field with wind_at().
##
## Field: a base breeze along `direction`, gust fronts travelling downwind
## (sine fronts of `wavelength` metres every 1/gust_freq s, shaped so gusts
## are short and calms are long), plus cross-wind turbulence.

var direction := Vector2(0.92, 0.38)
var strength := 0.35
var gust := 0.55
var gust_freq := 0.13
var wavelength := 14.0
var turbulence := 0.3
var time := 0.0
## Sheltered regions: [Vector3 centre, radius, factor 0..1].
var shelters: Array = []


func _process(delta: float) -> void:
	time += delta
	var rs := RenderingServer
	rs.global_shader_parameter_set("wind_time", time)
	rs.global_shader_parameter_set("wind_dir", direction.normalized())
	rs.global_shader_parameter_set("wind_strength", strength)
	rs.global_shader_parameter_set("wind_gust", gust)
	rs.global_shader_parameter_set("wind_gust_freq", gust_freq)
	rs.global_shader_parameter_set("wind_wavelength", wavelength)
	rs.global_shader_parameter_set("wind_turbulence", turbulence)
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		rs.global_shader_parameter_set("player_pos", p.global_position)


## Gust envelope 0..1 at a world position (same maths as the shader).
func gust_at(pos: Vector3) -> float:
	var d := direction.normalized()
	var ph := (Vector2(pos.x, pos.z).dot(d) / wavelength - time * gust_freq) * TAU
	var g := 0.5 + 0.5 * sin(ph)
	return g * g * g


## Horizontal wind vector (x, z) at a world position, in "bend units".
func wind_at(pos: Vector3) -> Vector3:
	var d := direction.normalized()
	var w := strength + gust * gust_at(pos)
	var t := sin(pos.x * 0.7 + time * 1.7) * cos(pos.z * 0.6 - time * 1.3) * turbulence
	var v := Vector3(d.x, 0, d.y) * w + Vector3(-d.y, 0, d.x) * t * 0.5
	for s in shelters:
		var k := clampf(Vector3(pos.x, 0, pos.z).distance_to(Vector3(s[0].x, 0, s[0].z)) / float(s[1]), 0.0, 1.0)
		v *= lerpf(float(s[2]), 1.0, k)
	return v
