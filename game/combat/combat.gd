class_name Combat
extends RefCounted
## Shared combat rules. Kept free of node references so the same code can run
## on a headless server later.

enum Element { NONE, WIND, FIRE, WATER, EARTH }

## Order deliberately excludes NONE: players cycle four elemental disciplines.
const PLAYABLE_ELEMENTS: Array[int] = [Element.WIND, Element.FIRE, Element.WATER, Element.EARTH]
const ELEMENT_NAMES := {
	Element.NONE: "Steel", Element.WIND: "Wind", Element.FIRE: "Fire",
	Element.WATER: "Water/Ice", Element.EARTH: "Earth",
}
const ELEMENT_COLORS := {
	Element.NONE: Color(0.95, 0.95, 0.9),
	Element.WIND: Color(0.55, 0.9, 1.0),
	Element.FIRE: Color(1.0, 0.45, 0.12),
	Element.WATER: Color(0.43, 0.7, 1.0),
	Element.EARTH: Color(0.75, 0.82, 0.49),
}

## Physics layers.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_JINN := 4


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## True if `target` is within `radius` of `origin` and inside a horizontal arc
## of `arc_deg` degrees centred on `forward`.
static func in_arc(origin: Vector3, forward: Vector3, target: Vector3, radius: float, arc_deg: float) -> bool:
	var to := flat(target - origin)
	var dist := to.length()
	if dist > radius:
		return false
	if dist < 0.35 or arc_deg >= 359.0:
		return true
	var f := flat(forward).normalized()
	return rad_to_deg(f.angle_to(to / dist)) <= arc_deg * 0.5


## Yaw (rotation.y) that makes a node's -Z axis point along `dir`.
static func yaw_for(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
