class_name ChildBuild
extends RefCounted
## The playable character is a child (owner: "children like Little
## Nightmares", original Mauritanian design): a big round head under the
## hood of a daraa worn as a poncho, thin limbs, small hands, and an animal
## MASK (cat / fennec / rabbit) made from that species' sculpted head,
## flattened into a lacquered shell with hollow eyes. Built procedurally on
## top of the species parts, so every mask and its ear animation keep
## working. All lengths are in the head node's local units unless noted.

const SKIN := Color(0.5, 0.33, 0.24)
const SKULL_R := 0.25
const SKULL_C := Vector3(0, -0.02, 0)
const MASK_SCALE := 0.62
const MASK_Z := -0.19
const HOOD_R := 0.285
const CERAMIC := Color(0.97, 0.94, 0.88)


## Lighten a part's vertex colours toward lacquered ceramic (painted mask).
static func paint(mi: MeshInstance3D, toward: Color, amount: float, keep_alpha := true) -> void:
	if mi == null or not (mi.mesh is ArrayMesh):
		return
	var src := mi.mesh as ArrayMesh
	var dst := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var cols = arrays[Mesh.ARRAY_COLOR]
		if cols != null:
			var out := PackedColorArray()
			for c in cols:
				var n: Color = c.lerp(toward, amount)
				n.a = c.a if keep_alpha else 1.0
				out.append(n)
			arrays[Mesh.ARRAY_COLOR] = out
		dst.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = dst


## Flatten a sculpted head into a mask shell: the front (face) is kept, the
## back half collapses onto a plane just behind the cheeks.
static func flatten_to_mask(src: ArrayMesh, cut_z: float = -0.04, keep: float = 0.12) -> ArrayMesh:
	var dst := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var out := PackedVector3Array()
		for v in verts:
			var w := v
			if w.z > cut_z:
				w.z = cut_z + (w.z - cut_z) * keep
			out.append(w)
		arrays[Mesh.ARRAY_VERTEX] = out
		dst.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return dst


## Hood: a cloth shell round the skull, open at the face, with a soft peak at
## the back-top and a skirt that drops into the poncho's neck.
static func hood_mesh(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var segs := 32
	var open_cos := 0.42                 # face opening (angle from -Z)
	var grid := []
	for i in rings + 1:
		var th := lerpf(0.0, deg_to_rad(128.0), float(i) / rings)   # from +Y down
		var row := []
		for j in segs + 1:
			var ph := TAU * float(j) / segs
			var d := Vector3(sin(th) * sin(ph), cos(th), -sin(th) * cos(ph))
			var r := HOOD_R
			# peak: back-top rises into a soft point; skirt flares a little
			r += 0.06 * maxf(d.y, 0.0) * maxf(d.z, 0.0) * 2.0
			if d.y < -0.2:
				r += (-d.y - 0.2) * 0.12
			# folds
			r *= 1.0 + 0.025 * sin(ph * 9.0 + th * 3.0)
			row.append([SKULL_C + d * r, d])
		grid.append(row)
	for i in rings:
		for j in segs:
			var q = [grid[i][j], grid[i + 1][j], grid[i][j + 1], grid[i + 1][j + 1]]
			var face_dir: Vector3 = (q[0][1] + q[1][1] + q[2][1] + q[3][1]).normalized()
			if face_dir.dot(Vector3(0, 0, -1)) > open_cos and face_dir.y < 0.75:
				continue          # face opening
			var shade := color if (j + i / 2) % 5 != 0 else color.darkened(0.12)
			for k in [0, 1, 2, 2, 1, 3]:
				st.set_color(Color(shade.r, shade.g, shade.b, 0.85 if q[k][1].y < -0.1 else 1.0))
				st.set_normal(q[k][1])
				st.add_vertex(q[k][0])
	return st.commit()


## Most common vertex colour of a mesh (the poncho's main cloth colour).
static func main_color(mi: MeshInstance3D, fallback: Color) -> Color:
	if mi == null or mi.mesh == null:
		return fallback
	var counts := {}
	for si in mi.mesh.get_surface_count():
		var cols = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_COLOR]
		if cols == null:
			continue
		for c in cols:
			var k := Color(snappedf(c.r, 0.04), snappedf(c.g, 0.04), snappedf(c.b, 0.04))
			counts[k] = int(counts.get(k, 0)) + 1
	var best := fallback
	var n := 0
	for k in counts:
		if counts[k] > n:
			n = counts[k]
			best = k
	return best


## Daraa as a poncho: a wide drape from the shoulders, squarer from the
## front, hem at mid-thigh so the child's legs show. Colours kept.
static func poncho(mi: MeshInstance3D) -> void:
	if mi == null or not (mi.mesh is ArrayMesh):
		return
	var src := mi.mesh as ArrayMesh
	var top := -INF
	var bottom := INF
	for si in src.get_surface_count():
		for v in src.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			top = maxf(top, v.y)
			bottom = minf(bottom, v.y)
	var span := maxf(top - bottom, 0.01)
	var dst := ArrayMesh.new()
	for si in src.get_surface_count():
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(src, si) != OK:
			return
		for i in mdt.get_vertex_count():
			var v := mdt.get_vertex(i)
			var t := clampf((top - v.y) / span, 0.0, 1.0)
			var s := 0.74 + 0.26 * sqrt(t)
			mdt.set_vertex(i, Vector3(v.x * s, top - (top - v.y) * 0.7, v.z * s * 0.95))
		mdt.commit_to_surface(dst)
	mi.mesh = dst
