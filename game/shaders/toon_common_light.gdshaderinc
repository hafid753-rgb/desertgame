// Uniforms + light() shared by toon and fur shaders.

// Soft "storybook" lighting (Animal Crossing / Wind Waker feel): wrapped
// diffuse with a gentle cel step, light lavender shadows, a warm soft rim,
// velvet sheen for cloth, and specular only where the material wants it.
uniform vec4 shadow_tint : source_color = vec4(0.8, 0.67, 0.63, 1.0);
uniform float band_softness : hint_range(0.0, 0.5) = 0.1;
uniform float wrap : hint_range(0.0, 1.0) = 0.45;
uniform float toon_amount : hint_range(0.0, 1.0) = 0.95;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float spec_strength : hint_range(0.0, 2.0) = 0.12;
uniform float spec_power : hint_range(1.0, 512.0) = 28.0;
uniform float spec_sharp : hint_range(0.0, 1.0) = 0.0;
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.0;
// Vertex colours are authored as display (sRGB) colours in Blender.
uniform bool vertex_color_linear = false;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
// Baked ambient occlusion lives in vertex alpha (1 = open).
uniform float ao_strength : hint_range(0.0, 1.0) = 0.8;
// Third tone between shadow and light: a soft "core" band.
uniform vec4 light_warmth : source_color = vec4(0.78, 0.75, 0.7, 1.0);

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float step_lit = smoothstep(0.42 - band_softness * 0.5, 0.42 + band_softness * 0.5, w);
	float lit = mix(w, step_lit, toon_amount) * ATTENUATION;
	vec3 ramp = mix(shadow_tint.rgb, light_warmth.rgb, lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * ramp / PI;
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// soft warm rim on the lit side, a faint cool one in shadow
	float rim = smoothstep(0.5, 0.95, fres);
	SPECULAR_LIGHT += LIGHT_COLOR * rim_color.rgb * rim * rim_strength * (0.25 + 0.75 * lit) / PI;
	// cloth: velvet-like sheen at grazing angles
	SPECULAR_LIGHT += LIGHT_COLOR * light_warmth.rgb * pow(fres, 3.0) * sheen_strength * (0.4 + 0.6 * lit) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float sp = pow(ndh, spec_power);
	sp = mix(sp, smoothstep(0.5, 0.6, sp), spec_sharp) * lit;
	SPECULAR_LIGHT += LIGHT_COLOR * sp * spec_strength / PI;
}
