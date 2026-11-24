// ICO-style shadow creature: an unlit, pitch-black silhouette whose edges
// fray into smoke. Depth comes from the silhouette, not from shading.
// - vertex boil: the surface churns slowly (noise along the normal)
// - ragged edge: pixels near the silhouette are cut away by scrolling noise,
//   so the outline is never clean and always moving
// - warning glow creeps in from the edges during a telegraph
// Parameters keep the old smoke shader's names (flash, warning, dissolve,
// burn, core/rim colours) so the jinn code drives either.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 core_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.1, 0.05, 0.16, 1.0);
uniform vec4 warning_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float warning : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float fuzz : hint_range(0.0, 1.5) = 0.95;
uniform float wobble : hint_range(0.0, 0.2) = 0.045;
uniform float noise_scale = 1.0;
uniform bool debug_fres = false;
// Phase 1 pixel-art: charcoal/purple pixel-cluster body; the fraying edge and
// the dissolve cut whole texels, so the form breaks into pixel clusters.
uniform sampler2D body_tex : source_color, filter_nearest_mipmap, repeat_enable, hint_default_black;
uniform bool pixel_mode = true;
uniform float texels_per_unit = 24.0;

varying vec3 obj_p;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	obj_p = VERTEX * noise_scale;
	float n = noise3(VERTEX * 5.0 * noise_scale + vec3(0.0, TIME * 1.6, 0.0)) - 0.5;
	VERTEX += NORMAL * n * wobble * 2.0;
}

void fragment() {
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	vec3 q = pixel_mode ? (floor(obj_p * texels_per_unit) + 0.5) / texels_per_unit : obj_p;
	float n = noise3(q * 9.0 + vec3(0.0, -TIME * 2.4, 0.0)) * 0.65
		+ noise3(q * 24.0 + vec3(TIME * 1.3, 0.0, TIME * 0.7)) * 0.35;
	// frayed, moving silhouette
	float edge = smoothstep(0.5, 1.0, fres);
	if (edge * fuzz > n * 0.95 + 0.04) {
		discard;
	}
	if (dissolve > 0.0 && n < dissolve * 1.08) {
		discard;
	}
	vec3 c = core_color.rgb;
	if (pixel_mode) {
		vec3 an = abs(normalize(NORMAL));
		c = texture(body_tex, (abs(dot(an, vec3(0, 1, 0))) > 0.6 ? q.xz : q.xy) * texels_per_unit / 32.0).rgb;
	}
	c = mix(c, rim_color.rgb, pow(fres, 2.5) * 0.9);
	c += warning_color.rgb * warning * pow(fres, 4.0) * 1.8;
	c = mix(c, vec3(1.0, 0.45, 0.15), burn * 0.35 * n);
	c = mix(c, vec3(1.0), flash);
	ALBEDO = debug_fres ? vec3(fres) : c;
}
