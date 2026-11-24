class_name MeshBatcher
extends RefCounted
## Merges many small static meshes into one mesh per (parent, colour), so a
## village of a hundred boxes costs a handful of draw calls on mobile.
## Usage: add() every piece, then build() once.

var _groups: Dictionary = {}


func add(mesh: Mesh, xform: Transform3D, color: Color, parent: Node3D) -> void:
	var key := "%d|%s" % [parent.get_instance_id(), color.to_html()]
	if not _groups.has(key):
		_groups[key] = {"st": SurfaceTool.new(), "color": color, "parent": parent}
	(_groups[key]["st"] as SurfaceTool).append_from(mesh, 0, xform)


## material_for(color) -> Material
func build(material_for: Callable) -> int:
	var made := 0
	for key in _groups:
		var g: Dictionary = _groups[key]
		var mi := MeshInstance3D.new()
		mi.mesh = (g["st"] as SurfaceTool).commit()
		mi.material_override = material_for.call(g["color"])
		(g["parent"] as Node3D).add_child(mi)
		made += 1
	_groups.clear()
	return made
