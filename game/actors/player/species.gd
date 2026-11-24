class_name Species
extends RefCounted
## Physical trade-offs per species. Multipliers on the shared base values in
## player.gd. Starting values from the feasibility report; tune in playtests.
## The spread is kept narrow so no species is unkillable in full-loot PvP.

const DATA := {
	"cat": {
		"name": "Cat", "speed": 1.15, "climb": 1.3, "stamina": 0.7,
		"fur": Color(0.95, 0.58, 0.22), "accent": Color(1.0, 0.92, 0.8), "ears": "pointed",
		"sleeve": Color(0.3, 0.5, 0.78), "sirwal": Color(0.16, 0.18, 0.3),
	},
	"fennec": {
		"name": "Fennec", "speed": 1.0, "climb": 1.0, "stamina": 1.0,
		"fur": Color(0.93, 0.8, 0.58), "accent": Color(1.0, 0.97, 0.9), "ears": "large",
		"sleeve": Color(0.74, 0.76, 0.8), "sirwal": Color(0.62, 0.52, 0.38),
	},
	"rabbit": {
		"name": "Rabbit", "speed": 0.9, "climb": 0.8, "stamina": 1.4,
		"fur": Color(0.72, 0.6, 0.46), "accent": Color(0.97, 0.95, 0.9), "ears": "long",
		"sleeve": Color(0.14, 0.18, 0.42), "sirwal": Color(0.2, 0.16, 0.13),
	},
}


static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["cat"])
