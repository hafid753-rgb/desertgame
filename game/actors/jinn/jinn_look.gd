class_name JinnLook
extends RefCounted
## The look of every jinn: a body of smoke with rising wisps, two glowing
## white dot eyes and golden rings orbiting the smoke. No mask, no solid
## face. The rings carry the attack tells (they flare to the attack colour
## and spin faster), so the eyes can stay pure white.
##
## build() returns {"visual", "smoke_mat", "ring_mat", "rings", "arms",
## "wisps", "eyes"} for the owner to animate.

const GOLD := Color(1.0, 0.8, 0.32)
const EYE_WHITE := Color(1.0, 1.0, 1.0)

static var _glow_tex: GradientTexture2D


static func glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 64
		_glow_tex.height = 64
	return _glow_tex


static func build(parent: Node3D, scale: float, ring_count: int, core: Color, rim: Color,
		ring_color: Color = GOLD, wisp_color: Color = Color(0.16, 0.08, 0.26, 0.55)) -> Dictionary:
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.scale = Vector3.ONE * scale
	parent.add_child(visual)

	var smoke := ShaderMaterial.new()
	smoke.shader = preload("res://game/actors/jinn/jinn_smoke.gdshader")
	smoke.set_shader_parameter("core_color", core)
	smoke.set_shader_parameter("rim_color", rim)
	smoke.set_shader_parameter("wobble", 0.09)
	var parts := CharacterArt.load_parts("res://game/art/characters/jinn.glb")
	var arms := {}
	for n in ["Body", "ArmR", "ArmL"]:
		if parts.has(n):
			var mi: MeshInstance3D = parts[n]
			mi.material_override = smoke
			visual.add_child(mi)
			arms[n] = mi
	if parts.has("Mask"):
		(parts["Mask"] as Node).free()  # the old bone mask is retired

	# Two glowing white dots with soft halos.
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = EYE_WHITE
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.albedo_texture = glow_texture()
	halo_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.9)
	halo_mat.no_depth_test = false
	var dot := SphereMesh.new()
	dot.radius = 0.04
	dot.height = 0.08
	dot.radial_segments = 8
	dot.rings = 4
	var halo := QuadMesh.new()
	halo.size = Vector2(0.3, 0.3)
	var eyes: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = dot
		e.material_override = dot_mat
		e.position = Vector3(0.11 * side, 1.4, -0.47)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(e)
		var h := MeshInstance3D.new()
		h.mesh = halo
		h.material_override = halo_mat
		h.position = e.position + Vector3(0, 0, -0.02)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(h)
		eyes.append(e)

	# Golden rings orbiting the smoke at different heights and tilts.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = ring_color
	var rings: Array[Node3D] = []
	var layout := [
		[0.55, 0.62, Vector3(0.25, 0.0, 0.1)], [1.0, 0.7, Vector3(-0.2, 0.0, -0.25)],
		[1.35, 0.52, Vector3(0.1, 0.0, 0.3)], [0.8, 0.85, Vector3(0.45, 0.0, -0.1)],
		[1.75, 0.38, Vector3(0.0, 0.0, 0.0)],
	]
	for i in mini(ring_count, layout.size()):
		var spec: Array = layout[i]
		var t := TorusMesh.new()
		var r: float = spec[1]
		t.inner_radius = r - 0.025
		t.outer_radius = r
		t.rings = 40
		t.ring_segments = 6
		var pivot := Node3D.new()
		pivot.position = Vector3(0, float(spec[0]), 0)
		pivot.rotation = spec[2]
		visual.add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = ring_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
		rings.append(mi)

	# Smoke wisps rising off the body (world-space trail, 14 soft puffs).
	var wisps := CPUParticles3D.new()
	wisps.amount = 14
	wisps.lifetime = 1.5
	wisps.local_coords = false
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	wisps.emission_sphere_radius = 0.45
	wisps.direction = Vector3.UP
	wisps.spread = 25.0
	wisps.gravity = Vector3(0, 0.9, 0)
	wisps.initial_velocity_min = 0.2
	wisps.initial_velocity_max = 0.6
	wisps.scale_amount_min = 0.6
	wisps.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 0.2))
	wisps.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.2, Color(1, 1, 1, 1.0))
	wisps.color_ramp = ramp
	var puff := QuadMesh.new()
	puff.size = Vector2(0.55, 0.55)
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.albedo_texture = glow_texture()
	puff_mat.albedo_color = wisp_color
	puff.material = puff_mat
	wisps.mesh = puff
	wisps.position = Vector3(0, 0.9, 0)
	visual.add_child(wisps)

	return {
		"visual": visual, "smoke_mat": smoke, "ring_mat": ring_mat, "rings": rings,
		"arms": arms, "wisps": wisps, "eyes": eyes, "dot_mat": dot_mat,
	}


## Spin the rings; `excite` 0..1 speeds them up (telegraphs).
static func spin(rings: Array, delta: float, excite: float) -> void:
	for i in rings.size():
		var r: Node3D = rings[i]
		var dir := 1.0 if i % 2 == 0 else -1.0
		r.rotate_object_local(Vector3.UP, dir * delta * (0.8 + i * 0.35 + excite * 6.0))
