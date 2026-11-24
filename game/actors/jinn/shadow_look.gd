class_name ShadowLook
extends RefCounted
## ICO-style shadow body for the hostile jinn (after Team Ico's shadow
## creatures): an animated humanoid rendered as a frayed, unlit black
## silhouette, black smoke boiling off it, two glowing white eyes deep in
## the hood, a shadow pool underfoot and the golden rings that carry the
## attack tells. Same skeletal animation pipeline as the player.
##
## build() returns {"visual", "rig", "skel", "anim", "smoke_mat", "ring_mat",
## "rings", "wisps", "emitters", "eyes", "eye_mat", "pool", "pool_mat", "exag"}.

const PATH := "res://game/art/rig/shadow.glb"
const LOOPS: Array[String] = ["Unarmed_Idle", "Idle", "Walking_A", "Walking_B", "Walking_C", "Running_A",
	"Running_Strafe_Left", "Running_Strafe_Right", "Sit_Floor_Idle", "Spellcasting", "Blocking"]

static var _smoke_tex: GradientTexture2D
static var _pool_tex: GradientTexture2D


static func _radial(inner: Color, outer: Color, mid: float = 0.4) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	g.add_point(mid, inner.lerp(outer, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


static func _model_xform(root: Node, n: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			x = (cur as Node3D).transform * x
		cur = cur.get_parent()
	return x


static func _attach(skel: Skeleton3D, bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	skel.add_child(a)
	return a


static func build(parent: Node3D, scale: float, ring_count: int, ring_color: Color = JinnLook.GOLD) -> Dictionary:
	var visual := Node3D.new()
	visual.name = "Visual"
	parent.add_child(visual)
	var rig: Node3D = (load(PATH) as PackedScene).instantiate()
	visual.add_child(rig)
	# KayKit rigs face +Z; jinn face -Z. ~2.3 m tall at scale 1.
	rig.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * scale * 0.85), Vector3.ZERO)
	var skel: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
	var anim: AnimationPlayer = rig.find_children("*", "AnimationPlayer", true, false)[0]
	skel.reset_bone_poses()
	for n in LOOPS:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR

	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/shaders/shadow_being.gdshader")
	mat.set_shader_parameter("noise_scale", 1.0 / maxf(scale, 0.5))
	mat.set_shader_parameter("body_tex", load("res://game/art/pixel/jinn_shadow_32.png"))
	var head_aabb := AABB()
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if str(mi.name).contains("Head"):
			head_aabb = (mi as MeshInstance3D).get_aabb()

	var prop := ShadowProportions.new()
	skel.add_child(prop)
	var exag := Exaggerate.new()
	skel.add_child(exag)
	exag.setup(anim, "Unarmed_Idle")

	# Eyes: deep in the hood, pure white with a soft halo.
	var head_att := _attach(skel, "head")
	var head_rest := _model_xform(visual, skel) * skel.get_bone_global_rest(skel.find_bone("head"))
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1, 1, 1)
	eye_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	eye_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	eye_mat.albedo_texture = JinnLook.glow_texture()
	eye_mat.no_depth_test = false
	var eyes: Array[MeshInstance3D] = []
	# head mesh AABB is in KayKit space; centre of the face, slightly in
	var face_c := head_aabb.get_center()
	var face_front := head_aabb.position.z + head_aabb.size.z
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.14, 0.14) * scale
		e.mesh = q
		e.material_override = eye_mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head_att.add_child(e)
		# in head-bone space (rig units): deep in the hood, at the face
		e.position = Vector3(sx * 0.2, 0.4, 0.6)
		eyes.append(e)

	# Black smoke boiling off the body (world space so it trails).
	if _smoke_tex == null:
		_smoke_tex = _radial(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 0.35)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = _smoke_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5) * scale
	quad.material = smat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.02, 0.01, 0.03, 0.0))
	ramp.set_color(1, Color(0.02, 0.01, 0.03, 0.0))
	ramp.add_point(0.15, Color(0.02, 0.01, 0.04, 0.75))
	ramp.add_point(0.6, Color(0.03, 0.02, 0.05, 0.4))
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.5))
	var emitters: Array[CPUParticles3D] = []
	for b in ["head", "chest", "hips", "hand.l", "hand.r"]:
		var at := _attach(skel, b)
		var p := CPUParticles3D.new()
		p.mesh = quad
		p.amount = 10 if b in ["chest", "head"] else 6
		p.lifetime = 1.3
		p.local_coords = false
		p.direction = Vector3(0, 1, 0)
		p.spread = 35.0
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.6
		p.gravity = Vector3(0, 0.9, 0)
		p.damping_min = 0.5
		p.damping_max = 1.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.22 * scale
		p.scale_amount_curve = grow
		p.color_ramp = ramp
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		at.add_child(p)
		emitters.append(p)

	# Shadow pool underfoot (ICO shadows rise from and sink into these).
	if _pool_tex == null:
		_pool_tex = _radial(Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.0), 0.55)
	var pool_mat := StandardMaterial3D.new()
	pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.85)
	pool_mat.albedo_texture = _pool_tex
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.2, 2.2) * scale
	pool.mesh = pm
	pool.material_override = pool_mat
	pool.position = Vector3(0, 0.03, 0)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pool)

	# Golden rings (attack tells) orbiting the torso.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = ring_color
	var rings: Array[Node3D] = []
	var chest_att := _attach(skel, "spine")
	for i in ring_count:
		var tm := TorusMesh.new()
		var r := (0.55 + 0.1 * (i % 2)) * scale
		tm.inner_radius = r
		tm.outer_radius = r + 0.022 * scale
		tm.rings = 40
		tm.ring_segments = 4
		var ri := MeshInstance3D.new()
		ri.mesh = tm
		ri.material_override = ring_mat
		ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.position = Vector3(0, (1.25 + 0.3 * i) * scale * 0.85, 0)
		holder.rotation = Vector3(0.35 * (1 if i % 2 == 0 else -1), i * 1.3, 0.2 * (i - 1))
		visual.add_child(holder)
		holder.add_child(ri)
		rings.append(holder)
	chest_att.queue_free()

	return {"visual": visual, "rig": rig, "skel": skel, "anim": anim, "smoke_mat": mat, "ring_mat": ring_mat,
		"rings": rings, "wisps": emitters[1], "emitters": emitters, "eyes": eyes, "eye_mat": eye_mat,
		"pool": pool, "pool_mat": pool_mat, "exag": exag, "prop": prop}
