class_name VoxelCar
extends RefCounted
## Original boxy 1980s desert sedan, built from 0.1 m voxels in code (no
## external model, no brand marks). Three-box body: long hood, upright glass
## house, flat trunk; chrome bumpers, slatted grille, square lamps, a black
## rubbing strip, sun-faded cream paint with rust at the arches and sills.
## Model space: front is -Z, origin on the ground between the axles.

const VOX := 0.1
const W := 18          # x voxels (1.8 m)
const L := 44          # z voxels (4.4 m), index 0 = front bumper
const FRONT_AXLE := 8
const REAR_AXLE := 34
const WHEEL_R := 3.2   # voxels
const BODY_LOW := 2    # underside at 0.2 m

const PAINT := Color(0.9, 0.84, 0.7)
const PAINT_SHADE := Color(0.82, 0.75, 0.6)
const RUST := Color(0.62, 0.34, 0.18)
const CHROME := Color(0.78, 0.8, 0.82)
const TRIM := Color(0.12, 0.11, 0.11)
const GLASS := Color(0.22, 0.3, 0.36)
const LAMP := Color(1.0, 0.95, 0.75)
const TAIL := Color(0.78, 0.14, 0.1)
const AMBER := Color(0.95, 0.55, 0.12)
const TYRE := Color(0.1, 0.09, 0.09)
const HUB := Color(0.7, 0.72, 0.74)


static func _body_voxels() -> Dictionary:
	var v := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 190
	for z in L:
		for x in W:
			# profile: top height of the body at this z
			var top := 7
			var cabin := z >= 13 and z <= 29
			var trunk := z > 29
			if trunk:
				top = 8
			if z <= 1 or z >= L - 2:
				top = 5              # bumper zone handled below
			for y in range(BODY_LOW, top + 1):
				var c := PAINT
				if y == 5 and (x == 0 or x == W - 1):
					c = TRIM            # rubbing strip
				if y <= 3 and (x <= 1 or x >= W - 2) and rng.randf() < 0.35:
					c = RUST
				if y == top and not cabin:
					c = PAINT if (x + z) % 7 != 0 else PAINT_SHADE
				v[Vector3i(x, y, z)] = c
			# glass house: pillars + windows, sloped windscreen and rear glass
			if cabin:
				var roof := 12
				var lo := 8
				var front_slope := clampi(z - 13, 0, 4)    # windscreen rake
				var rear_slope := clampi(29 - z, 0, 3)
				var h := mini(roof, lo + mini(front_slope, rear_slope) + 1)
				h = roof if (z > 16 and z < 27) else h
				for y in range(lo, h + 1):
					var inset := x >= 1 and x <= W - 2
					if not inset:
						continue
					var edge := x == 1 or x == W - 2
					var pillar := z == 13 or z == 20 or z == 29 or z == 14
					var c := GLASS
					if y == h:
						# raked windscreen and rear glass read from above;
						# the roof between them is painted
						c = GLASS if (z <= 16 or z >= 27) else PAINT
					elif edge and pillar:
						c = PAINT_SHADE
					elif not edge and (z > 15 and z < 28) and y < h:
						continue                        # hollow cabin (glass on the outside only)
					v[Vector3i(x, y, z)] = c
	# bumpers (chrome), grille, lamps
	for x in W:
		for y in range(3, 6):
			v[Vector3i(x, y, 0)] = CHROME
			v[Vector3i(x, y, L - 1)] = CHROME
	for x in range(5, 13):
		for y in range(4, 7):
			v[Vector3i(x, y, 1)] = TRIM if y % 2 == 0 else CHROME
	for x in [1, 2, 3, 14, 15, 16]:
		for y in range(5, 7):
			v[Vector3i(x, y, 1)] = LAMP
		v[Vector3i(x, 4, 1)] = AMBER if x in [1, 16] else PAINT
	for x in [1, 2, 3, 4, 13, 14, 15, 16]:
		for y in range(5, 8):
			v[Vector3i(x, y, L - 2)] = TAIL if y > 5 else AMBER
	# door seams and handles
	for side in [0, W - 1]:
		for y in range(BODY_LOW + 1, 8):
			v[Vector3i(side, y, 20)] = PAINT_SHADE
		v[Vector3i(side, 6, 17)] = CHROME
		v[Vector3i(side, 6, 24)] = CHROME
	# wheel arches: cut the body round each wheel
	for az in [FRONT_AXLE, REAR_AXLE]:
		for x in [0, 1, 2, W - 3, W - 2, W - 1]:
			for z in range(az - 5, az + 6):
				for y in range(0, 8):
					var d := Vector2(z - az, y - WHEEL_R).length()
					if d < WHEEL_R + 1.4:
						v.erase(Vector3i(x, y, z))
	return v


static func _wheel_voxels() -> Dictionary:
	var v := {}
	var r := WHEEL_R
	for x in 2:
		for y in range(-4, 5):
			for z in range(-4, 5):
				var d := Vector2(y, z).length()
				if d <= r + 0.3:
					var c := TYRE
					if x == 0 and d < 1.6:
						c = HUB
					v[Vector3i(x, y, z)] = c
	return v


## Mesh from voxels: one quad per exposed face, flat normals, vertex colour
## (alpha 1: no baked AO; the toon shader reads albedo from COLOR).
static func _mesh(vox: Dictionary, offset: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for k in vox:
		var p: Vector3i = k
		var col: Color = vox[k]
		for d in dirs:
			if vox.has(p + d):
				continue
			var n := Vector3(d)
			# face shading so voxel steps read (top lighter, underside darker)
			var shade := 1.0 + 0.04 * n.y - 0.03 * absf(n.x)
			var c := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			var u := Vector3(n.y, n.z, n.x) if d.x == 0 else Vector3(0, 1, 0)
			if d.y != 0:
				u = Vector3(1, 0, 0)
			var w := n.cross(u)
			var ctr := (Vector3(p) + Vector3(0.5, 0.5, 0.5) + n * 0.5) * VOX + offset
			var a := ctr + (-u - w) * VOX * 0.5
			var b := ctr + (u - w) * VOX * 0.5
			var cc := ctr + (u + w) * VOX * 0.5
			var dd := ctr + (-u + w) * VOX * 0.5
			for q in [[a, b, cc], [a, cc, dd]]:
				var tri: Array = q
				# wind triangles so the face normal points along n
				var t0: Vector3 = tri[0]
				var t1: Vector3 = tri[1]
				var t2: Vector3 = tri[2]
				var fn := (t1 - t0).cross(t2 - t0)
				if fn.dot(n) > 0.0:
					tri = [tri[0], tri[2], tri[1]]
				for vert in tri:
					st.set_normal(n)
					st.set_color(c)
					st.add_vertex(vert)
	return st.commit()


static func body_mesh() -> ArrayMesh:
	# centre x, front at -z, axles symmetric about the origin
	var mid := (FRONT_AXLE + REAR_AXLE) * 0.5
	return _mesh(_body_voxels(), Vector3(-W * 0.5 * VOX, 0.0, -mid * VOX - 0.0))


static func wheel_mesh() -> ArrayMesh:
	return _mesh(_wheel_voxels(), Vector3(-VOX, -0.5 * VOX, -0.5 * VOX) * 1.0)


## Wheel hub positions (model space).
static func wheel_positions() -> Array[Vector3]:
	var mid := (FRONT_AXLE + REAR_AXLE) * 0.5
	var y := WHEEL_R * VOX
	var x := (W * 0.5 - 0.6) * VOX
	var fz := (FRONT_AXLE + 0.5 - mid) * VOX
	var rz := (REAR_AXLE + 0.5 - mid) * VOX
	return [Vector3(-x, y, fz), Vector3(x, y, fz), Vector3(-x, y, rz), Vector3(x, y, rz)]
