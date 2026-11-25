// Shared body of the toon shaders (see toon.gdshader).

uniform vec4 tint : source_color = vec4(1.0);
#include "res://game/shaders/toon_common_light.gdshaderinc"
// Bazin damask: tone-on-tone woven lozenge pattern for the daraa fabric
// (0 = off). Two-plane projection in object space, so no UVs are needed.
uniform float damask_strength : hint_range(0.0, 0.3) = 0.0;
uniform float damask_scale = 26.0;

// Phase 1 pixel-art detail: grayscale cluster map (fur / fabric / leather)
// on the object-space texel grid modulates the vertex colour.
uniform sampler2D pixel_detail : filter_nearest_mipmap, repeat_enable, hint_default_white;
uniform float pixel_detail_size = 32.0;
uniform float pixel_detail_strength : hint_range(0.0, 1.0) = 0.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

#ifdef CLOTH_WIND
// Daraa sail as cloth (owner: "move with the wind, not stiff, fall a bit
// downward"). Object space of each wing: x runs from the shoulder seam
// (|x| ~ 0.22) to the cuff (|x| ~ 1.0), z front (-) to back (+).
//   droop     the free edge hangs: a quadratic sag toward the cuff and the
//             trailing edge, more when the wearer falls faster
//   billow    travelling waves along the span and the chord, driven by the
//             shared wind field (gusts) and the wearer's air speed
//   trail     the back edge streams backward and lifts in the airflow
#include "res://game/shaders/wind.gdshaderinc"
uniform float cloth_droop = 0.32;
uniform float cloth_flutter = 0.07;
uniform float cloth_speed = 1.0;
uniform float cloth_trail = 0.08;

vec3 cloth_offset(vec3 v, mat4 model) {
	float span = clamp((abs(v.x) - 0.2) / 0.82, 0.0, 1.0);
	float back = clamp((v.z + 0.36) / 0.72, 0.0, 1.0);
	float free_ = clamp(span * 0.75 + back * 0.45, 0.0, 1.0);
	float t = wind_time * (6.0 + 5.0 * cloth_speed);
	float gust = wind_gust * wind_gust_at((model * vec4(v, 1.0)).xyz);
	float w1 = sin(t - abs(v.x) * 7.5 - v.z * 4.0);
	float w2 = sin(t * 1.7 - abs(v.x) * 13.0 + v.z * 9.0 + 1.3);
	vec3 o = vec3(0.0);
	o.y -= cloth_droop * (span * span * 0.8 + back * back * 0.35);
	o.y += (w1 * 0.7 + w2 * 0.3) * cloth_flutter * free_ * (1.0 + gust * 1.5 + cloth_speed * 0.5);
	o.z += cloth_trail * back * span * (0.6 + 0.4 * w1) * (0.5 + cloth_speed);
	o.x -= sign(v.x) * 0.06 * span * span * cloth_droop;        // sagging edge pulls in
	return o;
}
#endif

#ifdef ROBE_WIND
#include "res://game/shaders/robe_cloth.gdshaderinc"
#endif

void vertex() {
#ifdef ROBE_WIND
	vec3 ro = robe_offset(VERTEX, MODEL_MATRIX);
	vec3 rox = robe_offset(VERTEX + vec3(0.03, 0.0, 0.0), MODEL_MATRIX);
	vec3 roz = robe_offset(VERTEX + vec3(0.0, 0.0, 0.03), MODEL_MATRIX);
	vec3 roy = robe_offset(VERTEX + vec3(0.0, 0.03, 0.0), MODEL_MATRIX);
	// fold shading: bend the normal by the deformation's Jacobian
	vec3 jt = vec3(dot(rox - ro, NORMAL), dot(roy - ro, NORMAL), dot(roz - ro, NORMAL)) / 0.03;
	NORMAL = normalize(NORMAL - jt + dot(NORMAL, jt) * NORMAL);
	VERTEX += ro;
#endif
#ifdef CLOTH_WIND
	vec3 o = cloth_offset(VERTEX, MODEL_MATRIX);
	float e = 0.03;
	vec3 ox = cloth_offset(VERTEX + vec3(e, 0.0, 0.0), MODEL_MATRIX);
	vec3 oz = cloth_offset(VERTEX + vec3(0.0, 0.0, e), MODEL_MATRIX);
	// tilt the normal by the deformation slope so the folds catch light
	NORMAL = normalize(NORMAL + vec3(-(ox.y - o.y) / e, 0.0, -(oz.y - o.y) / e) * sign(NORMAL.y + 1e-4));
	VERTEX += o;
#endif
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

float damask(vec2 p) {
	vec2 g = fract(p) - 0.5;
	float d = abs(g.x) + abs(g.y);                         // lozenge
	float ring = smoothstep(0.06, 0.0, abs(d - 0.32));     // lozenge outline
	float dotc = smoothstep(0.09, 0.05, length(g));        // centre dot
	vec2 h = fract(p + 0.5) - 0.5;
	float flower = smoothstep(0.12, 0.07, abs(length(h) - 0.12));
	return max(max(ring, dotc), flower * 0.7);
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (!vertex_color_linear) {
		c = pow(c, vec3(2.2));
	}
	float ao = mix(1.0, COLOR.a, ao_strength);
	ALBEDO = c * tint.rgb * mix(0.62, 1.0, ao);
	if (pixel_detail_strength > 0.0) {
		vec3 an = abs(normalize(obj_nrm));
		vec2 q = an.y >= an.x && an.y >= an.z ? obj_pos.xz : (an.x >= an.z ? vec2(obj_pos.z, -obj_pos.y) : vec2(obj_pos.x, -obj_pos.y));
		float d = texture(pixel_detail, q * 32.0 / pixel_detail_size).r;
		ALBEDO *= 1.0 + (d - 0.5) * 2.0 * pixel_detail_strength;
	}
	if (damask_strength > 0.0) {
		vec3 an = abs(normalize(obj_nrm));
		float m = mix(damask(obj_pos.xy * damask_scale), damask(obj_pos.zy * damask_scale), smoothstep(0.4, 0.8, an.x));
		// On pale cloth the pattern brightens (a woven sheen) instead of
		// darkening, so white bazin stays clean.
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		float k = damask_strength * mix(1.0, 0.45, smoothstep(0.5, 0.85, lum));
		ALBEDO *= 1.0 + k * (m - mix(0.35, 0.0, smoothstep(0.5, 0.85, lum)));
	}
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
#ifdef DOUBLE_SIDED
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = flash_color.rgb * flash;
}

