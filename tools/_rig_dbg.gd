extends SceneTree
var m: CreatureModel
var f := 0
func _init() -> void:
	m = CreatureModel.new()
	root.add_child(m)
	m.build(Species.get_data("cat"))
func _process(_d: float) -> bool:
	f += 1
	m.animate(0.016, {"state": "MOVE", "move": 0.3})
	if f % 5 == 0:
		print(f, " cur=", m.anim.current_animation, " pos=", snappedf(m.anim.current_animation_position, 0.01), " speed=", m.anim.speed_scale, " playing=", m.anim.is_playing(), " active=", m.anim.active, " hand.r=", m.hand_r.global_position.snapped(Vector3.ONE*0.01))
	return f > 30
