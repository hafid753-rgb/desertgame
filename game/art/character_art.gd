class_name CharacterArt
extends RefCounted
## Loads the Blender-built character parts (tools/blender/build_characters.py)
## and gives them the toon + outline look.

const TOON := preload("res://game/shaders/toon.gdshader")
const TOON_DOUBLE := preload("res://game/shaders/toon_double.gdshader")
const OUTLINE := preload("res://game/shaders/outline.gdshader")
const FUR := preload("res://game/shaders/fur_shell.gdshader")
## Per-species fur look: [length, density, thickness, droop].
const FUR_STYLE := {
	"cat": [0.022, 80.0, 0.9, 0.3],
	"fennec": [0.026, 74.0, 0.9, 0.4],
	"rabbit": [0.024, 78.0, 0.9, 0.35],
}
## Global switch: vinyl (false) or flocked-fur (true) finish.
static var fur_enabled := false


## Shell fur material for a species, or null for scaly ones.
static func fur_material(species: String) -> ShaderMaterial:
	if not fur_enabled or not FUR_STYLE.has(species):
		return null
	var st: Array = FUR_STYLE[species]
	var m := ShaderMaterial.new()
	m.shader = FUR
	m.set_shader_parameter("fur_length", st[0])
	m.set_shader_parameter("density", st[1])
	m.set_shader_parameter("thickness", st[2])
	m.set_shader_parameter("droop", st[3])
	return m


## Thin cloth: both faces lit correctly, no outline hull.
static func cloth_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://game/shaders/toon_cloth.gdshader")
	preset(m, "fabric")
	return m


## Material presets for the soft storybook look.
##   skin   satin, small soft highlight (heads, hands, ears, tails)
##   fabric matte with a velvet sheen (daraa, hawli, sarouel)
##   gloss  sharp highlight (eyes, boots' polish is "leather")
##   leather a little sheen and a soft highlight
const PRESETS := {
	# Phase 1 pixel-art: no artificial gloss, pixel cluster detail instead.
	"skin": {"spec_strength": 0.0, "spec_power": 22.0, "spec_sharp": 0.0, "sheen_strength": 0.0, "rim_strength": 0.12,
		"pixel": "res://game/art/pixel/fur_detail_32.png", "pixel_strength": 0.55},
	"fabric": {"spec_strength": 0.0, "spec_power": 8.0, "spec_sharp": 0.0, "sheen_strength": 0.0, "rim_strength": 0.06, "damask_strength": 0.0,
		"pixel": "res://game/art/pixel/fabric_detail_32.png", "pixel_strength": 0.5},
	"gloss": {"spec_strength": 0.5, "spec_power": 90.0, "spec_sharp": 1.0, "sheen_strength": 0.0, "rim_strength": 0.0},
	"leather": {"spec_strength": 0.0, "spec_power": 30.0, "spec_sharp": 0.0, "sheen_strength": 0.0, "rim_strength": 0.08,
		"pixel": "res://game/art/pixel/leather_detail_32.png", "pixel_strength": 0.5},
}


static func preset(m: ShaderMaterial, kind: String) -> ShaderMaterial:
	var p: Dictionary = PRESETS.get(kind, PRESETS["skin"])
	for k in p:
		if k == "pixel":
			m.set_shader_parameter("pixel_detail", load(p[k]))
		elif k == "pixel_strength":
			m.set_shader_parameter("pixel_detail_strength", p[k])
		else:
			m.set_shader_parameter(k, p[k])
	return m


static func toon_material(outline_color: Color = Color(0.14, 0.08, 0.07), thickness: float = 0.007, kind: String = "skin") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	preset(m, kind)
	if thickness > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("thickness", thickness)
		o.set_shader_parameter("outline_color", outline_color)
		m.next_pass = o
	return m


## Instantiates a .glb and returns {node_name: MeshInstance3D}, detached from
## the imported root so the caller can parent them anywhere.
static func load_parts(path: String) -> Dictionary:
	var out := {}
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("CharacterArt: cannot load %s" % path)
		return out
	var root := scene.instantiate()
	for mi in _meshes(root):
		var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else _accum(mi)
		mi.get_parent().remove_child(mi)
		mi.transform = xf
		mi.owner = null
		out[str(mi.name)] = mi
	root.free()
	return out


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var arr: Array[MeshInstance3D] = []
	for c in n.get_children():
		if c is MeshInstance3D:
			arr.append(c)
		arr.append_array(_meshes(c))
	return arr


static func _accum(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
