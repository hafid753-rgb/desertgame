class_name SlideDune
extends StaticBody3D
## A steep surfing dune (owner: "find a steep dune first"): a gentle
## windward back to climb, a sharp crest, a long steep slip face to surf
## down, and a kicker lip that throws the rider into the air (then the
## daraa opens). Smooth height field along local +X, faded across Z.
## Collision is the exact surface (trimesh), so walking, surfing and
## landing all follow what you see.

@export var length := 58.0
@export var half_width := 9.5
@export var crest_h := 8.0
var material: Material


## height profile along the dune (u in metres from the back toe); the
## shape is authored for a 58 m / 8 m dune and scaled to length / crest_h
func profile(u_m: float) -> float:
	return _profile58(u_m * 58.0 / length) * crest_h / 8.0


func _profile58(u: float) -> float:
	if u < 0.0:
		return 0.0
	if u < 14.0:                         # windward back, smooth rise
		var t := u / 14.0
		return 8.0 * t * t * (3.0 - 2.0 * t)
	if u < 16.0:                         # rounded crest
		return 8.0
	if u < 44.0:                         # slip face: steep at the top, easing out
		var t := (u - 16.0) / 28.0
		return lerpf(8.0, 0.7, 1.0 - pow(1.0 - t, 1.7))
	if u < 50.0:                         # kicker: concave rise to the lip
		var t := (u - 44.0) / 6.0
		return 0.7 + 3.0 * t * t
	if u < 53.5:                         # drop behind the lip
		var t := (u - 50.0) / 3.5
		return 3.7 * (1.0 - t * t * (3.0 - 2.0 * t))
	return 0.0


func height_at(local_x: float, local_z: float) -> float:
	var v := clampf(absf(local_z) / half_width, 0.0, 1.0)
	var across := pow(1.0 - pow(v, 2.4), 1.6)
	return profile(local_x + length * 0.5) * across - 0.03


func _ready() -> void:
	collision_layer = Combat.LAYER_WORLD
	var nx := int(length * 2.6)
	var nz := 40
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var grid := []
	for i in nx + 1:
		var row := []
		var x := -length * 0.5 + length * float(i) / nx
		for j in nz + 1:
			var z := -half_width * 1.05 + half_width * 2.1 * float(j) / nz
			row.append(Vector3(x, height_at(x, z), z))
		grid.append(row)
	for i in nx:
		for j in nz:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i][j + 1]
			var c: Vector3 = grid[i + 1][j]
			var d: Vector3 = grid[i + 1][j + 1]
			for v in [a, c, b, b, c, d]:   # clockwise from above = front face up
				st.add_vertex(v)
				faces.append(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
