// Uniforms + light() shared by toon and fur shaders.

uniform vec4 shadow_tint : source_color = vec4(0.42, 0.36, 0.55, 1.0);
uniform float band_softness : hint_range(0.0, 0.5) = 0.06;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.22;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.22;
// Vertex colours are authored as display (sRGB) colours in Blender.
uniform bool vertex_color_linear = false;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
// Baked ambient occlusion lives in vertex alpha (1 = open).
uniform float ao_strength : hint_range(0.0, 1.0) = 0.8;
// Third tone between shadow and light: a soft "core" band.
uniform float mid_band : hint_range(0.0, 1.0) = 0.5;
uniform vec4 light_warmth : source_color = vec4(0.8, 0.77, 0.72, 1.0);

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Two stepped bands (shadow -> core -> lit), shadow cast respected.
	float b1 = smoothstep(-0.15, -0.15 + band_softness, ndl);
	float b2 = smoothstep(0.25, 0.25 + band_softness, ndl);
	float lit = mix(b1 * mid_band, 1.0, b2) * ATTENUATION;
	vec3 ramp = mix(shadow_tint.rgb, light_warmth.rgb, lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * ramp / PI;
	// Rim only on the lit side so silhouettes read without glowing shadows.
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(0.62, 0.72, fres) * smoothstep(-0.2, 0.4, ndl);
	SPECULAR_LIGHT += LIGHT_COLOR * rim * rim_strength * (0.25 + 0.75 * ATTENUATION) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float sp = smoothstep(0.955, 0.985, dot(NORMAL, h)) * b2 * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR * sp * spec_strength / PI;
}
