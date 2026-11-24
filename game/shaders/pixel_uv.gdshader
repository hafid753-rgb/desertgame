// Pixel-art surface for meshes built with pixel-aligned UVs (trunks,
// branches, rocks): UV units are texels / tex_size, sampled nearest.
// Optional whole-plant sway from the shared wind field.
shader_type spatial;
render_mode cull_back;
#include "res://game/shaders/pixel_common.gdshaderinc"
#include "res://game/shaders/wind.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 sway_root = vec3(0.0);
uniform float sway_height = 1.0;
uniform float sway_amount = 0.0;

void vertex() {
	if (sway_amount > 0.0) {
		vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(plant_sway(wpos, sway_root, sway_height, sway_amount), 0.0)).xyz;
	}
}

void fragment() {
	ALBEDO = texture(tex, UV).rgb * tint.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * pixel_light_ramp(dot(NORMAL, LIGHT), ATTENUATION) / PI;
}
