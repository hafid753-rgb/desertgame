// Leaves shed by palms and acacias. Each instance is a pixel leaf card on a
// looping life: detach in the canopy, tumble and drift downwind with the
// shared Wind field, settle flat on the ground, slide a little in gusts,
// then dissolve through an ordered dither. Stateless (no CPU per frame).
//   INSTANCE_CUSTOM.r = atlas cell / cells, .g = phase, .b = rate, .a = spin
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
#include "res://game/shaders/pixel_common.gdshaderinc"
#include "res://game/shaders/wind.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform float atlas_cols = 6.0;
uniform float ground_y = 0.0;
uniform float cycle = 16.0;          // seconds per life
uniform float fall_speed = 0.55;     // m/s
uniform vec4 tint : source_color = vec4(1.0);
uniform float pivot = 0.1;

varying float fade;
varying vec3 wp;

mat3 rot(vec3 axis, float a) {
	axis = normalize(axis);
	float s = sin(a), c = cos(a), oc = 1.0 - c;
	return mat3(vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * s, oc * axis.z * axis.x - axis.y * s),
		vec3(oc * axis.x * axis.y - axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * s),
		vec3(oc * axis.z * axis.x + axis.y * s, oc * axis.y * axis.z - axis.x * s, oc * axis.z * axis.z + c));
}

void vertex() {
	vec3 spawn = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = INSTANCE_CUSTOM.g;
	float life = fract(wind_time / (cycle * (0.7 + INSTANCE_CUSTOM.b)) + ph);
	float t = life * cycle;
	float drop = spawn.y - ground_y;
	float t_land = drop / fall_speed;
	float ta = min(t, t_land);
	vec2 d = normalize(wind_dir);
	vec3 w = wind_at(spawn, ph * 6.28, 1.4);
	// drift downwind while airborne, side-to-side flutter, slower near the top
	vec3 p = spawn;
	p.xz += vec2(w.x, w.z) * ta * 0.9;
	p.xz += vec2(-d.y, d.x) * sin(ta * 2.6 + ph * 9.0) * 0.35;
	p.y -= ta * fall_speed;
	float on_ground = step(t_land, t);
	// on the ground: slide a little downwind during gusts
	p.xz += d * on_ground * wind_gust_at(p) * min(t - t_land, 3.0) * 0.25;
	p.y = max(p.y, ground_y + 0.015);
	float spin = (INSTANCE_CUSTOM.a * 2.0 - 1.0) * 5.0;
	mat3 r = on_ground > 0.5 ? rot(vec3(1.0, 0.0, 0.0), -1.5708) * rot(vec3(0.0, 0.0, 1.0), ph * 6.28)
		: rot(vec3(sin(ph * 17.0), 0.6, cos(ph * 11.0)), ta * spin + ph * 6.28);
	vec3 local = r * (VERTEX - vec3(0.0, pivot, 0.0));
	wp = p + local;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(r * vec3(0.0, 0.0, 1.0), 0.0)).xyz;
	// hidden while "attached" (first 4 %), dissolve over the last 25 %
	fade = smoothstep(0.0, 0.04, life) * (1.0 - smoothstep(0.75, 1.0, life));
	float cell = floor(INSTANCE_CUSTOM.r * atlas_cols + 0.5);
	UV = vec2((mod(cell, atlas_cols) + UV.x) / atlas_cols, UV.y);
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5 || fade < bayer4(ivec2(floor(wp.xz * PIXELS_PER_METRE)))) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb;
	NORMAL = normalize(mix(NORMAL * (FRONT_FACING ? 1.0 : -1.0), (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * pixel_light_ramp(dot(NORMAL, LIGHT) * 0.7 + 0.3, ATTENUATION) / PI;
}
