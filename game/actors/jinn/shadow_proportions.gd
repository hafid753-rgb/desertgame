class_name ShadowProportions
extends SkeletonModifier3D
## Turns the borrowed chibi humanoid rig into a tall, spindly shadow: long
## thin legs and dangling arms, a stretched torso and neck, a small head,
## a forward hunch and a slow head cock. Bone lengths change by moving child
## joints (no non-uniform scale is inherited), limbs thin by local scale.

@export var arm_length := 1.75
@export var leg_length := 1.9
@export var torso_stretch := 1.45
@export var neck_stretch := 1.6
@export var head_scale := 0.5
@export var thin := 0.72
@export var arm_thin := 0.7
@export var hunch := 0.34
@export var head_drop := 0.24

var _arms: Array[int] = []
var _legs: Array[int] = []
var _chest := -1
var _spine := -1
var _head := -1
var _hips := -1
var _leg_rest := 0.0


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["upperarm.l", "upperarm.r", "lowerarm.l", "lowerarm.r"]:
		var i := sk.find_bone(b)
		if i >= 0:
			_arms.append(i)
	for b in ["upperleg.l", "upperleg.r", "lowerleg.l", "lowerleg.r"]:
		var i := sk.find_bone(b)
		if i >= 0:
			_legs.append(i)
	_chest = sk.find_bone("chest")
	_spine = sk.find_bone("spine")
	_head = sk.find_bone("head")
	_hips = sk.find_bone("hips")
	_leg_rest = sk.get_bone_global_rest(_hips).origin.y if _hips >= 0 else 0.4


func _bend(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0:
		return
	var parent := sk.get_bone_parent(bone)
	var pg := Quaternion.IDENTITY
	if parent >= 0:
		pg = sk.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var r := pg.inverse() * Quaternion(axis, angle) * pg
	sk.set_bone_pose_rotation(bone, r * sk.get_bone_pose_rotation(bone))


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for i in _arms:
		sk.set_bone_pose_scale(i, Vector3(arm_thin, arm_length, arm_thin))
	for i in _legs:
		sk.set_bone_pose_scale(i, Vector3(thin, leg_length, thin))
	if _hips >= 0:
		var hp := sk.get_bone_pose_position(_hips)
		sk.set_bone_pose_position(_hips, hp + Vector3(0, _leg_rest * (leg_length - 1.0) * 0.92, 0))
	if _chest >= 0:
		sk.set_bone_pose_position(_chest, sk.get_bone_pose_position(_chest) * torso_stretch)
	if _spine >= 0:
		sk.set_bone_pose_scale(_spine, Vector3(0.8, 1.0, 0.8))
	if _head >= 0:
		sk.set_bone_pose_position(_head, sk.get_bone_pose_position(_head) * neck_stretch)
		sk.set_bone_pose_scale(_head, Vector3.ONE * head_scale / 0.8)
	# skeleton space: +Z is the rig's forward, so +X rotation leans forward
	_bend(sk, _chest, Vector3.RIGHT, hunch)
	var t := Time.get_ticks_msec() * 0.001
	_bend(sk, _head, Vector3.RIGHT, head_drop)
	_bend(sk, _head, Vector3.BACK, 0.2 + sin(t * 0.7) * 0.07)
