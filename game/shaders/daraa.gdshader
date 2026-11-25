// The daraa: one broad sheet of bazin (tools/garment), pixel-art texture on
// the flat-pattern UVs, toon lighting, double-sided (the lateral openings
// show the inside), runtime rig deformation (daraa_rig.gdshaderinc).
shader_type spatial;
render_mode cull_disabled;
#include "res://game/shaders/toon_common_light.gdshaderinc"
#include "res://game/shaders/daraa_rig.gdshaderinc"

uniform sampler2D daraa_tex : source_color, filter_nearest_mipmap, repeat_disable;
uniform vec4 inside_color : source_color = vec4(0.2, 0.36, 0.7, 1.0);
uniform float inside_dark = 0.62;
uniform bool debug_uv = false;

varying float v_free;

void vertex() {
	vec3 p = daraa_deform(VERTEX, COLOR, MODEL_MATRIX);
	// fold shading: bend the normal by how the wind term varies across
	// the surface (the spring terms are smooth and barely change it)
	float e = 0.03;
	vec3 w0 = daraa_wind_term(VERTEX, COLOR.b, 0.0, MODEL_MATRIX);
	vec3 wx = daraa_wind_term(VERTEX + vec3(e, 0.0, 0.0), COLOR.b, 0.0, MODEL_MATRIX);
	vec3 wy = daraa_wind_term(VERTEX + vec3(0.0, e, 0.0), COLOR.b, 0.0, MODEL_MATRIX);
	vec3 wz = daraa_wind_term(VERTEX + vec3(0.0, 0.0, e), COLOR.b, 0.0, MODEL_MATRIX);
	vec3 jt = vec3(dot(wx - w0, NORMAL), dot(wy - w0, NORMAL), dot(wz - w0, NORMAL)) / e;
	NORMAL = normalize(NORMAL - jt + dot(NORMAL, jt) * NORMAL);
	VERTEX = p;
	v_free = COLOR.b;
}

void fragment() {
	vec3 c = texture(daraa_tex, UV).rgb;
	if (debug_uv) { c = vec3(UV, 0.0); }
	if (!FRONT_FACING) {
		// inside: plain cloth (embroidery is front-only), in shadow
		c = inside_color.rgb * inside_dark;
		NORMAL = -NORMAL;
	}
	// cloth hanging into the body's shade near the yoke folds
	ALBEDO = c * mix(0.9, 1.0, smoothstep(0.0, 0.3, v_free));
	AO = 1.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = flash_color.rgb * flash;
}
