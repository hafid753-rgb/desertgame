class_name Exaggerate
extends SkeletonModifier3D
## Cartoon exaggeration for combat: after the animation runs, pushes the
## spine, chest and sword-arm rotations further from a neutral pose
## (the idle clip's first frame) by `amount` x gain. Big sweeps get bigger,
## stabs reach further, without authoring new clips.

const GAINS := {
	"hips": 0.12, "spine": 0.55, "chest": 0.55, "head": -0.35,
	"upperarm.r": 0.8, "lowerarm.r": 0.6, "wrist.r": 0.4,
	"upperarm.l": 0.4,
}

var amount := 0.0
var _bones: Array[int] = []
var _gains: Array[float] = []
var _ref: Array[Quaternion] = []


func setup(anim: AnimationPlayer, neutral_clip: String) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var a: Animation = anim.get_animation(neutral_clip) if anim.has_animation(neutral_clip) else null
	for b in GAINS:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var q := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		if a:
			for tr in a.get_track_count():
				if a.track_get_type(tr) == Animation.TYPE_ROTATION_3D and str(a.track_get_path(tr)).ends_with(":" + b):
					q = a.rotation_track_interpolate(tr, 0.0)
					break
		_bones.append(i)
		_gains.append(float(GAINS[b]))
		_ref.append(q)


func _process_modification_with_delta(_delta: float) -> void:
	if amount <= 0.001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	for k in _bones.size():
		var i := _bones[k]
		var pose := sk.get_bone_pose_rotation(i)
		var d := _ref[k].inverse() * pose
		if d.w < 0.0:
			d = -d
		var ang := d.get_angle()
		if ang < 0.0005:
			continue
		var scaled := Quaternion(d.get_axis().normalized(), ang * (1.0 + _gains[k] * amount))
		sk.set_bone_pose_rotation(i, _ref[k] * scaled)
