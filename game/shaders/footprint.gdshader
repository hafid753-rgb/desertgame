// Footprints pressed into sand. Each print is resampled onto the world
// 32 px/m texel grid (the same grid as the sand), so prints at any heading
// stay pixel-aligned with the ground. They erode with age and faster in
// gusts, dissolving through an ordered dither.
//   INSTANCE_CUSTOM.r = birth (wind_time), .g = cell (0 right, 1 left),
//   .b = depth 0..1
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
#include "res://game/shaders/pixel_common.gdshaderinc"
#include "res://game/shaders/wind.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform float print_size = 0.3125; // metres covered by one 10x10 cell (32 px/m)
uniform float life = 40.0;

varying vec3 wp;
varying vec3 centre;
varying vec2 axis_x;
varying float age01;
varying float cell;
varying float depth;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	axis_x = normalize((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xz);
	float erode = 1.0 + wind_gust_at(centre) * 0.6;
	age01 = clamp((wind_time - INSTANCE_CUSTOM.r) * erode / life, 0.0, 1.0);
	if (INSTANCE_CUSTOM.r <= 0.0) {
		age01 = 1.0;
	}
	cell = INSTANCE_CUSTOM.g;
	depth = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec2 c = floor(wp.xz * PIXELS_PER_METRE);
	vec2 q = (c + 0.5) / PIXELS_PER_METRE - centre.xz;
	vec2 ay = vec2(-axis_x.y, axis_x.x);
	vec2 uv = vec2(dot(q, axis_x), -dot(q, ay)) / print_size + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		discard;
	}
	vec4 t = texture(tex, vec2((uv.x + cell) * 0.5, uv.y));
	float keep = (1.0 - age01) * depth;
	if (t.a < 0.5 || keep < bayer4(ivec2(c))) {
		discard;
	}
	ALBEDO = t.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * pixel_light_ramp(dot(NORMAL, LIGHT), ATTENUATION) / PI;
}
