// Stylized shell fur for Hafid's furry species (sand cat, fennec).
// Each shell is a copy of the base mesh; UV2.x = shell height (0..1],
// UV2.y = local fur length multiplier (short on the face, long on tails).
// Strands are 3D-hashed cones in object space, clumped by low-frequency
// noise, darkened at the root and toon-lit like the rest of the character.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
#include "res://game/shaders/toon_common_light.gdshaderinc"

uniform float fur_length = 0.035;
uniform float density = 90.0;
uniform float thickness : hint_range(0.1, 1.0) = 0.75;
uniform float droop = 0.35;
uniform float wind = 0.12;
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 base_pos;
varying float shell_h;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	base_pos = VERTEX;
	shell_h = UV2.x;
	float len = fur_length * UV2.y;
	vec3 down = (inverse(MODEL_MATRIX) * vec4(0.0, -1.0, 0.0, 0.0)).xyz;
	float sway = sin(TIME * 2.3 + VERTEX.x * 9.0 + VERTEX.y * 7.0) * wind;
	VERTEX += NORMAL * len * shell_h + (down * droop + vec3(sway, 0.0, sway * 0.5)) * len * shell_h * shell_h;
}

void fragment() {
	vec3 p = base_pos * density;
	vec3 cell = floor(p);
	vec3 local = fract(p) - 0.5 - (vec3(hash13(cell), hash13(cell + 7.1), hash13(cell + 3.7)) - 0.5) * 0.3;
	float clump = value3(base_pos * density * 0.18);
	float strand_len = mix(0.45, 1.0, hash13(cell + 11.0)) * mix(0.6, 1.15, clump);
	float h = shell_h / max(strand_len, 0.001);
	if (h > 1.0 || length(local) > thickness * pow(1.0 - h, 0.7) * 0.9) {
		discard;
	}
	vec3 c = COLOR.rgb;
	if (!vertex_color_linear) {
		c = pow(c, vec3(2.2));
	}
	float root = mix(0.84, 1.06, shell_h);
	ALBEDO = c * tint.rgb * root * mix(0.62, 1.0, COLOR.a);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = flash_color.rgb * flash;
}
