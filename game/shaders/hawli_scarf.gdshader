// Hawli ribbon: indigo cloth with gold edge lines and a repeating lozenge
// embroidery, drawn as pixel art at the world texel density (32 px/m along
// the band, 5 texels across). Lit like the characters (soft cel step,
// warm shadow) with a little sunlight through the thin cloth.
shader_type spatial;
render_mode cull_disabled;
#include "res://game/shaders/pixel_common.gdshaderinc"

uniform vec4 base : source_color = vec4(0.2, 0.26, 0.55, 1.0);
uniform vec4 gold : source_color = vec4(0.95, 0.78, 0.4, 1.0);
uniform vec4 pale : source_color = vec4(0.93, 0.9, 0.82, 1.0);
uniform float length = 2.3;

void fragment() {
	float u = floor(UV.x * PIXELS_PER_METRE);         // texel along the band
	float v = floor(clamp(UV.y, 0.0, 0.999) * 5.0);   // 0..4 across (0.2 m ~ 6 texels, drawn as 5 bands)
	vec3 c = base.rgb;
	if (v == 0.0 || v == 4.0) {
		c = gold.rgb;                                    // edge lines
	}
	// lozenge every 10 texels: rows 1-3 form a small diamond
	float m = mod(u, 10.0);
	float dx = abs(m - 5.0);
	if (v >= 1.0 && v <= 3.0 && dx + abs(v - 2.0) <= 1.0) {
		c = (dx + abs(v - 2.0)) < 0.5 ? pale.rgb : gold.rgb;
	}
	// tassel end: last texels fray into gold fringe
	float end_t = length * PIXELS_PER_METRE - u;
	if (end_t < 4.0) {
		if (mod(v + u, 2.0) < 1.0 && end_t < 2.0) {
			discard;
		}
		c = gold.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = abs(dot(NORMAL, LIGHT));
	float band = smoothstep(0.3, 0.36, ndl) * ATTENUATION;
	vec3 cel = mix(vec3(0.8, 0.67, 0.63), vec3(1.0, 0.94, 0.86), band);
	DIFFUSE_LIGHT += LIGHT_COLOR * cel / PI;
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * vec3(1.0, 0.8, 0.6) * back * 0.25 * ATTENUATION / PI;
}
