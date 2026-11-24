extends Node
## The persistent world record, written by one owner only (this node).
## Mirrors the server-side model from the feasibility report: villages with
## a stage and an owner, recruited NPCs, the player's materials, and an
## append-only event log. Saved to user://world.json after every change.
## In multiplayer this becomes the world service; callers already go through
## request-style methods that return whether the change was accepted.

signal changed(kind: String, payload: Dictionary)

const VERSION := 1
const STAGES: Array[String] = ["haunted", "claimed", "mosque_rebuilt"]

var path: String = "user://world.json"
var data: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_world()


## Tests and the pause menu use this: switch file, optionally start fresh.
func use_path(p: String, reset: bool = false) -> void:
	path = p
	if reset:
		reset_world()
	else:
		load_world()


func reset_world() -> void:
	data = _empty()
	save_world()
	changed.emit("reset", {})


func load_world() -> void:
	data = _empty()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and int(parsed.get("version", 0)) == VERSION:
		data = parsed


func save_world() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


# --- Queries ----------------------------------------------------------------

func village(id: String) -> Dictionary:
	var v: Dictionary = data["villages"].get(id, {})
	if v.is_empty():
		v = {"stage": "haunted", "owner": "", "salvaged": [], "npcs": []}
		data["villages"][id] = v
	return v


func stage(id: String) -> String:
	return str(village(id)["stage"])


func bricks() -> int:
	return int(data["player"]["bricks"])


# --- Requests (return true if accepted) ----------------------------------

## Claiming from the environment works once: only a haunted, unowned village.
func claim_village(id: String, owner: String) -> bool:
	var v := village(id)
	if v["stage"] != "haunted" or v["owner"] != "":
		return false
	v["stage"] = "claimed"
	v["owner"] = owner
	_commit("village_claimed", {"village": id, "owner": owner})
	return true


func salvage(id: String, pile: String, amount: int) -> bool:
	var v := village(id)
	if (v["salvaged"] as Array).has(pile):
		return false
	(v["salvaged"] as Array).append(pile)
	data["player"]["bricks"] = bricks() + amount
	_commit("salvaged", {"village": id, "pile": pile, "amount": amount})
	return true


func rebuild_mosque(id: String, cost: int) -> bool:
	var v := village(id)
	if v["stage"] != "claimed" or bricks() < cost:
		return false
	data["player"]["bricks"] = bricks() - cost
	v["stage"] = "mosque_rebuilt"
	_commit("mosque_rebuilt", {"village": id, "cost": cost})
	return true


func recruit(id: String, job: String) -> bool:
	var v := village(id)
	if v["stage"] == "haunted":
		return false
	(v["npcs"] as Array).append({"job": job})
	_commit("recruited", {"village": id, "job": job})
	return true


func _commit(kind: String, payload: Dictionary) -> void:
	var ev := payload.duplicate()
	ev["kind"] = kind
	ev["at"] = Time.get_datetime_string_from_system(true)
	(data["events"] as Array).append(ev)
	save_world()
	changed.emit(kind, payload)


func _empty() -> Dictionary:
	return {"version": VERSION, "villages": {}, "player": {"bricks": 0}, "events": []}
