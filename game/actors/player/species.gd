class_name Species
extends RefCounted
## Physical trade-offs per species. Multipliers on the shared base values in
## player.gd. Starting values from the feasibility report; tune in playtests.
## The spread is kept narrow so no species is unkillable in full-loot PvP.

const DATA := {
	"cat": {
		"name": "Cat", "speed": 1.15, "climb": 1.3, "stamina": 0.7,
		"fur": Color(0.95, 0.58, 0.22), "accent": Color(1.0, 0.92, 0.8), "ears": "pointed",
	},
	"fennec": {
		"name": "Fennec", "speed": 1.0, "climb": 1.0, "stamina": 1.0,
		"fur": Color(0.93, 0.8, 0.58), "accent": Color(1.0, 0.97, 0.9), "ears": "large",
	},
	"lizard": {
		"name": "Lizard", "speed": 0.9, "climb": 0.8, "stamina": 1.4,
		"fur": Color(0.42, 0.68, 0.4), "accent": Color(0.85, 0.9, 0.55), "ears": "none",
	},
}


static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["cat"])
