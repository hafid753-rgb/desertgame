class_name ElementalProp
extends RigidBody3D
## Original BOTW-inspired physical interaction test prop. All interaction
## decisions belong to the simulation, not to the camera/FX layer.

@export var wooden: bool = false
@export var size: float = 0.65

var burning: float = 0.0
var chilled: float = 0.0
var _base_color: Color
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("elemental_props")
	collision_layer = Combat.LAYER_WORLD
	collision_mask = Combat.LAYER_WORLD | Combat.LAYER_PLAYER | Combat.LAYER_JINN
	mass = 8.0 if wooden else 35.0
	linear_damp = 0.6
	angular_damp = 1.2
	_base_color = Color(0.48, 0.31, 0.16) if wooden else Color(0.55, 0.49, 0.43)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _base_color
	_mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	if wooden:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * size
		mi.mesh = mesh
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * size
		var col := CollisionShape3D.new()
		col.shape = box
		add_child(col)
	else:
		var mesh := SphereMesh.new()
		mesh.radius = size * 0.5
		mesh.height = size
		mesh.radial_segments = 12
		mesh.rings = 6
		mi.mesh = mesh
		var shape := SphereShape3D.new()
		shape.radius = size * 0.5
		var col := CollisionShape3D.new()
		col.shape = shape
		add_child(col)
	mi.material_override = _mat
	add_child(mi)


func receive_element(element: int, direction: Vector3, power: float) -> void:
	match element:
		Combat.Element.WIND:
			apply_central_impulse(direction.normalized() * power * (2.0 if wooden else 1.0))
		Combat.Element.FIRE:
			if wooden:
				burning = 4.0
				apply_central_impulse(direction.normalized() * power * 0.2)
		Combat.Element.WATER:
			burning = 0.0
			chilled = 2.0
			linear_velocity *= 0.3
			angular_velocity *= 0.3
		Combat.Element.EARTH:
			apply_central_impulse(Vector3.UP * power * 0.5)


func _physics_process(delta: float) -> void:
	burning = maxf(0.0, burning - delta)
	chilled = maxf(0.0, chilled - delta)
	if burning > 0.0:
		_mat.albedo_color = Color(0.9, 0.32, 0.12)
		_mat.emission_enabled = true
		_mat.emission = Color(0.8, 0.23, 0.05)
	else:
		_mat.emission_enabled = false
		_mat.albedo_color = _base_color.lerp(Color(0.53, 0.75, 0.89), 0.52 if chilled > 0.0 else 0.0)
