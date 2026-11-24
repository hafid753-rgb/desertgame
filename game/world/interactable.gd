class_name Interactable
extends Node3D
## Something the player can use with the ACT button when close enough.
## Subclass or set the callables. Keep the decision in can_interact() so the
## HUD can show why it is unavailable ("Need 10 bricks").

@export var radius: float = 2.2
## Show the prompt even when it can't be used (e.g. "Need 10 bricks").
@export var show_when_unavailable: bool = false
var prompt: Callable = func() -> String: return "Use"
var available: Callable = func() -> bool: return true
var action: Callable = func(_p: Player) -> void: pass


func _ready() -> void:
	add_to_group("interactables")


func prompt_text() -> String:
	return prompt.call()


func can_interact() -> bool:
	return available.call()


func interact(player: Player) -> void:
	if can_interact():
		action.call(player)
