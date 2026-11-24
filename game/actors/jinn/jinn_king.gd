class_name JinnKing
extends Jinn
## A Jinn King rules one abandoned village. Bigger, slower, crowned.
## Attacks: the three jinn moves at a larger scale plus
##   summon (gold eyes, 1.4 s): calls two shadow jinn (max 3 alive)
##   slam   (white eyes, 1.0 s): shockwave in a long line ahead
## At half health it rages: telegraphs 25% faster, summons more often.
## Defeating it is what grants the village (see Village and WorldState).

signal summon_requested(king: JinnKing, count: int)
signal raged(king: JinnKing)

var raging: bool = false
var minions_alive: Callable = func() -> int: return 0
var _crown_mat: ShaderMaterial


func _init() -> void:
	max_hp = 650.0
	radius = 1.05
	visual_scale = 2.1
	ring_count = 5
	chase_speed = 2.4
	attacks = Jinn.ATTACKS.duplicate(true)
	attacks["swipe"]["range"] = 3.9
	attacks["swipe"]["damage"] = 22.0
	attacks["swipe"]["telegraph"] = 0.75
	attacks["burst"]["range"] = 5.5
	attacks["burst"]["damage"] = 30.0
	attacks["burst"]["telegraph"] = 1.35
	attacks["lunge"]["damage"] = 26.0
	attacks["lunge"]["range"] = 2.2
	attacks["summon"] = {"telegraph": 1.4, "active": 0.3, "recovery": 1.0, "damage": 0.0, "range": 0.0, "arc": 0.0,
		"color": Color(1.0, 0.82, 0.25), "stun": 0.0, "knockback": 0.0}
	attacks["slam"] = {"telegraph": 1.0, "active": 0.2, "recovery": 1.1, "damage": 28.0, "range": 9.0, "arc": 28.0,
		"color": Color(1.0, 1.0, 1.0), "stun": 0.7, "knockback": 8.0}


func _ready() -> void:
	super._ready()
	add_to_group("jinn_king")
	_build_crown()


func take_damage(info: Dictionary) -> void:
	# Kings shrug off light staggers; only heavy (2+) interrupts them.
	if int(info.get("stagger", 0)) < 2:
		info = info.duplicate()
		info["stagger"] = 0
	super.take_damage(info)
	if not raging and hp > 0.0 and hp <= max_hp * 0.5:
		raging = true
		tempo = 1.25
		chase_speed = 3.0
		raged.emit(self)
		Juice.shake(0.5)
		Fx.ring(fx_parent, global_position, Color(1.0, 0.8, 0.3, 0.7), 7.0, 0.6)


func _choose_attack(dist: float) -> String:
	var alive: int = minions_alive.call()
	var summon_chance := 0.35 if raging else 0.2
	var last: String = "" if _recent.is_empty() else _recent.back()
	if alive < 2 and last != "summon" and _rng.randf() < summon_chance:
		_recent.append("summon")
		return "summon"
	if dist > 5.0:
		var p := "slam" if _rng.randf() < 0.6 else "lunge"
		_recent.append(p)
		return p
	return super._choose_attack(dist)


func _tick_attack(delta: float) -> Vector3:
	match current:
		"summon":
			if not attack_hit_done:
				attack_hit_done = true
				var n := 3 if raging else 2
				n = mini(n, 3 - int(minions_alive.call()))
				if n > 0:
					summon_requested.emit(self, n)
				Fx.ring(fx_parent, global_position, Color(1.0, 0.8, 0.3, 0.6), 4.0, 0.5)
			if state_time >= float(attacks["summon"]["active"]):
				_enter(S.RECOVER)
			return Vector3.ZERO
		"slam":
			if not attack_hit_done:
				attack_hit_done = true
				var f := _forward()
				for i in 5:
					Fx.burst(fx_parent, global_position + f * (1.5 + i * 1.6) + Vector3(0, 0.3, 0), Color(0.9, 0.85, 1.0, 0.6), 1.1, 0.35, Vector3(1, 0.4, 1))
				Juice.shake(0.35)
				_try_hit(attacks["slam"])
			if state_time >= float(attacks["slam"]["active"]):
				_enter(S.RECOVER)
			return Vector3.ZERO
	return super._tick_attack(delta)


func _build_crown() -> void:
	# Gold crown of spikes above the smoke head; rides on the visual so it scales.
	var crown := Node3D.new()
	crown.position = Vector3(0, 1.78, -0.25)
	_visual.add_child(crown)
	_crown_mat = CharacterArt.toon_material(Color(0.25, 0.15, 0.02), 0.006)
	_crown_mat.set_shader_parameter("tint", Color(1.0, 0.78, 0.25))
	var band := CylinderMesh.new()
	band.top_radius = 0.24
	band.bottom_radius = 0.26
	band.height = 0.07
	band.radial_segments = 16
	var bmi := MeshInstance3D.new()
	bmi.mesh = band
	bmi.material_override = _crown_mat
	crown.add_child(bmi)
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.05
	spike.height = 0.18
	spike.radial_segments = 6
	for i in 7:
		var a := i * TAU / 7.0
		var smi := MeshInstance3D.new()
		smi.mesh = spike
		smi.material_override = _crown_mat
		smi.position = Vector3(sin(a) * 0.24, 0.12, cos(a) * 0.24)
		crown.add_child(smi)
