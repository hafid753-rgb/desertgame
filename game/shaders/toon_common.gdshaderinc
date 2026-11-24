// Shared body of the toon shaders (see toon.gdshader).

uniform vec4 tint : source_color = vec4(1.0);
#include "res://game/shaders/toon_common_light.gdshaderinc"
// Bazin damask: tone-on-tone woven lozenge pattern for the daraa fabric
// (0 = off). Two-plane projection in object space, so no UVs are needed.
uniform float damask_strength : hint_range(0.0, 0.3) = 0.0;
uniform float damask_scale = 26.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
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
	if (damask_strength > 0.0) {
		vec3 an = abs(normalize(obj_nrm));
		float m = mix(damask(obj_pos.xy * damask_scale), damask(obj_pos.zy * damask_scale), smoothstep(0.4, 0.8, an.x));
		ALBEDO *= 1.0 + damask_strength * (m - 0.35);
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

