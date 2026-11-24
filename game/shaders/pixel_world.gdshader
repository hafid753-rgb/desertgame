// Pixel-art surface for architecture, ground and props: a palette texture on
// the world texel grid, palette light ramp, no gloss.
shader_type spatial;
render_mode cull_back;
#include "res://game/shaders/pixel_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform float tex_size = 128.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool object_space = false;

varying vec3 sample_p;
varying vec3 sample_n;

void vertex() {
	if (object_space) {
		sample_p = VERTEX;
		sample_n = NORMAL;
	} else {
		sample_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		sample_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
}

void fragment() {
	ALBEDO = texture(tex, pixel_uv(sample_p, sample_n, tex_size)).rgb * tint.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += LIGHT_COLOR * pixel_light_ramp(ndl, ATTENUATION) / PI;
}
