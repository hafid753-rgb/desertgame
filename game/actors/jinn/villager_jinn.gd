class_name VillagerJinn
extends Node3D
## A recruited jinn living in a restored village. Restored colours (deep
## blue core, pale turquoise rim), a job, and a simple routine:
##   guard     walks a beat between the village gate posts
##   merchant  waits by the well and turns to face the player
##   builder   works at the mosque, bobbing over the walls
## No combat: guards are visual for now (offline defence comes with sieges).

const JOB_LABELS := {"guard": "Guard", "merchant": "Merchant", "builder": "Builder"}

var job: String = "guard"
var route: Array[Vector3] = []
var _route_i: int = 0
var _visual: Node3D
var _mat: ShaderMaterial
var _label: Label3D
var _t: float = 0.0


func _ready() -> void:
	add_to_group("villagers")
	_visual = Node3D.new()
	_visual.scale = Vector3.ONE * 1.0
	add_child(_visual)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://game/actors/jinn/jinn_smoke.gdshader")
	_mat.set_shader_parameter("core_color", Color(0.06, 0.12, 0.28))
	_mat.set_shader_parameter("rim_color", Color(0.45, 0.9, 0.95))
	_mat.set_shader_parameter("wobble", 0.04)
	var parts := CharacterArt.load_parts("res://game/art/characters/jinn.glb")
	for n in ["Body", "ArmR", "ArmL"]:
		if parts.has(n):
			var mi: MeshInstance3D = parts[n]
			mi.material_override = _mat
			_visual.add_child(mi)
	if parts.has("Mask"):
		var mask: MeshInstance3D = parts["Mask"]
		mask.material_override = CharacterArt.toon_material(Color(0.05, 0.08, 0.12), 0.008)
		_visual.add_child(mask)
	_label = Label3D.new()
	_label.text = JOB_LABELS.get(job, job)
	_label.font_size = 40
	_label.outline_size = 8
	_label.pixel_size = 0.008
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(0.75, 0.95, 1.0)
	_label.position = Vector3(0, 2.25, 0)
	add_child(_label)


func _physics_process(delta: float) -> void:
	_t += delta
	_visual.position.y = 0.3 + sin(_t * 2.0 + get_instance_id()) * 0.06
	match job:
		"guard":
			if route.size() >= 2:
				var goal := route[_route_i]
				var to := Combat.flat(goal - global_position)
				if to.length() < 0.3:
					_route_i = (_route_i + 1) % route.size()
				else:
					global_position += to.normalized() * minf(1.4 * delta, to.length())
					rotation.y = lerp_angle(rotation.y, Combat.yaw_for(to), 1.0 - exp(-5.0 * delta))
		"merchant":
			var p := get_tree().get_first_node_in_group("player") as Node3D
			if p and global_position.distance_to(p.global_position) < 8.0:
				var to2 := Combat.flat(p.global_position - global_position)
				rotation.y = lerp_angle(rotation.y, Combat.yaw_for(to2), 1.0 - exp(-4.0 * delta))
		"builder":
			_visual.position.y = 0.3 + absf(sin(_t * 3.0)) * 0.4
			rotation.y += delta * 0.4
