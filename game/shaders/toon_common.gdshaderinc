// Shared body of the toon shaders (see toon.gdshader).

uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.36, 0.55, 1.0);
uniform float band_softness : hint_range(0.0, 0.5) = 0.06;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.22;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.08;
// Vertex colours are authored as display (sRGB) colours in Blender.
uniform bool vertex_color_linear = false;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);

void fragment() {
	vec3 c = COLOR.rgb;
	if (!vertex_color_linear) {
		c = pow(c, vec3(2.2));
	}
	ALBEDO = c * tint.rgb;
#ifdef DOUBLE_SIDED
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = flash_color.rgb * flash;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, band_softness, ndl) * ATTENUATION;
	vec3 ramp = mix(shadow_tint.rgb, vec3(1.0), lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * ramp / PI;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	SPECULAR_LIGHT += LIGHT_COLOR * rim * rim_strength * (0.3 + 0.7 * lit) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float sp = smoothstep(0.975, 0.99, dot(NORMAL, h)) * lit;
	SPECULAR_LIGHT += LIGHT_COLOR * sp * spec_strength / PI;
}
