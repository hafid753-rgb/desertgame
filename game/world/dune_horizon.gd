class_name DuneHorizon
extends MeshInstance3D
## A ring of large wind-shaped dunes outside the play area, so the horizon
## reads like the owner's reference photo: layered orange dunes with sharp
## crests and slip faces, melting into the cream haze. Visual only (no
## collision), built once as a smooth height-field annulus using the same
## sand material as the playable ground.

@export var inner := 61.0          # starts just inside the floor edge
@export var outer := 230.0
@export var radial_steps := 84
@export var angular_steps := 240
@export var seed_value := 3

var _noise := FastNoiseLite.new()


func _ready() -> void:
	_noise.seed = seed_value
	_noise.frequency = 0.012
	mesh = _build()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Asymmetric dune profile: long gentle windward slope, short steep lee
## (slip face), crest kept sharp, valleys rounded.
static func _ridge(t: float) -> float:
	var s := t - floorf(t)
	var up := s / 0.72
	var down := (1.0 - s) / 0.28
	var h := minf(up, down)
	return h * h * (3.0 - 2.0 * h) * 0.85 + h * 0.15


func height_at(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var rise := smoothstep(inner, inner + 30.0, r)
	var warp := _noise.get_noise_2d(x * 0.5, z * 0.5) * 14.0
	var a := _ridge((x * 0.92 + z * 0.38 + warp) / 52.0)
	var b := _ridge((x * -0.3 + z * 0.95 + warp * 0.7) / 33.0)
	var mass := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	var h := (a * 0.7 + b * 0.45) * (6.0 + mass * 16.0)
	# a few great dunes like the one in the reference
	for c in [Vector3(-150, 48, -40), Vector3(40, 38, -165), Vector3(150, 30, 70), Vector3(-60, 26, 160)]:
		var d := Vector2(x - c.x, z - c.z).length() / 55.0
		h += c.y * maxf(0.0, 1.0 - d * d) * (0.75 + 0.25 * a)
	return h * rise - 0.4 * (1.0 - rise)


func _build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in radial_steps + 1:
		# denser rings near the play area
		var t := float(i) / radial_steps
		var r := lerpf(inner, outer, t * t * 0.6 + t * 0.4)
		for j in angular_steps:
			var a := TAU * float(j) / angular_steps
			var x := cos(a) * r
			var z := sin(a) * r
			st.add_vertex(Vector3(x, height_at(x, z), z))
	for i in radial_steps:
		for j in angular_steps:
			var j1 := (j + 1) % angular_steps
			var a := i * angular_steps + j
			var b := i * angular_steps + j1
			var c := (i + 1) * angular_steps + j
			var d := (i + 1) * angular_steps + j1
			for k in [a, c, b, b, c, d]:   # clockwise from above = front face up
				st.add_index(k)
	st.generate_normals()
	return st.commit()
