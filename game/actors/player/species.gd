class_name Species
extends RefCounted
## The playable characters are children in a daraa poncho; the cat, fennec
## and rabbit are MASKS they wear. Each mask grants its physical trade-offs
## (multipliers on player.gd base values) and a special ability:
##   cat     double jump (one extra jump in the air)
##   fennec  sand-runner: slower, cheaper glide and faster sand surfing
##   rabbit  high jump (+80 % jump height)
## Physical trade-offs per mask. Multipliers on the shared base values in
## player.gd. Starting values from the feasibility report; tune in playtests.
## The spread is kept narrow so no species is unkillable in full-loot PvP.

const DATA := {
	"cat": {
		"name": "Cat", "speed": 1.15, "climb": 1.3, "stamina": 0.7,
		"mask": "Cat Mask", "ability": "Double jump", "ribbon": Color(0.17, 0.22, 0.52),
		"jump": 1.0, "air_jumps": 1, "glide_fall": 1.0, "glide_cost": 1.0, "surf": 1.0,
		"fur": Color(0.95, 0.58, 0.22), "accent": Color(1.0, 0.92, 0.8), "ears": "pointed",
		"sleeve": Color(0.3, 0.5, 0.78), "sirwal": Color(0.16, 0.18, 0.3),
	},
	"fennec": {
		"name": "Fennec", "speed": 1.0, "climb": 1.0, "stamina": 1.0,
		"mask": "Fennec Mask", "ability": "Sand runner: long glide, fast surf", "ribbon": Color(0.74, 0.3, 0.16),
		"jump": 1.0, "air_jumps": 0, "glide_fall": 0.55, "glide_cost": 0.5, "surf": 1.25,
		"fur": Color(0.93, 0.8, 0.58), "accent": Color(1.0, 0.97, 0.9), "ears": "large",
		"sleeve": Color(0.74, 0.76, 0.8), "sirwal": Color(0.62, 0.52, 0.38),
	},
	"rabbit": {
		"name": "Rabbit", "speed": 0.9, "climb": 0.8, "stamina": 1.4,
		"mask": "Rabbit Mask", "ability": "High jump", "ribbon": Color(0.9, 0.86, 0.76),
		"jump": 1.8, "air_jumps": 0, "glide_fall": 1.0, "glide_cost": 1.0, "surf": 1.0,
		"fur": Color(0.72, 0.6, 0.46), "accent": Color(0.97, 0.95, 0.9), "ears": "long",
		"sleeve": Color(0.14, 0.18, 0.42), "sirwal": Color(0.2, 0.16, 0.13),
	},
}


static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["cat"])
