class_name ArmSpread
extends SkeletonModifier3D
## Runs after the animation each frame: pushes the shoulders outward (and a
## touch forward) so the floating mittens clear Hafid's wide daraa, and
## lifts the hands slightly so idle/walk poses read in silhouette.

@export var outward := 0.2
@export var forward := 0.06

var _bones: Array[int] = []
var _sign: Array[float] = []


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["upperarm.l", "upperarm.r"]:
		var i := sk.find_bone(b)
		if i >= 0:
			_bones.append(i)
			# Outward along the bone's parent-space x, sign from rest side.
			_sign.append(signf(sk.get_bone_global_rest(i).origin.x))


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for k in _bones.size():
		var i := _bones[k]
		var parent := sk.get_bone_parent(i)
		# Offset expressed in skeleton space, converted into the parent's
		# space (the chest may be rotated by the animation).
		var off := Vector3(outward * _sign[k], 0.0, forward)
		if parent >= 0:
			off = sk.get_bone_global_pose(parent).basis.inverse() * off
		sk.set_bone_pose_position(i, sk.get_bone_pose_position(i) + off)
