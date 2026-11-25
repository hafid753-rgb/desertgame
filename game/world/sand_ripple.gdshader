// Journey-style desert sand, after Alan Zucconi's "Journey Sand Shader"
// series (diffuse contrast, sand grain normals, slope-blended ripples, rim +
// ocean specular combined with max(), glitter). Procedural (no textures),
// tuned for the storybook palette and for mobile.
// https://www.alanzucconi.com/2019/10/08/journey-sand-shader-1/
shader_type spatial;
render_mode cull_back;
#include "res://game/shaders/pixel_common.gdshaderinc"

uniform vec4 sand_color : source_color = vec4(0.93, 0.74, 0.5, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.74, 0.5, 0.46, 1.0);
// grain: random micro-normals blended into the surface normal (nlerp)
uniform float grain_density = 38.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.22;
// ripples: shallow (flat, wind-aligned) vs steep (dune flanks)
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.7;
uniform float sun_scale : hint_range(0.0, 1.5) = 0.55;
// diffuse contrast (Zucconi): squash of the normal's y, Lambert gain.
// Big far dunes use a weaker squash so lit and shaded flanks separate.
uniform float y_squash = 0.3;
uniform float lambert_gain = 4.0;
uniform float shallow_freq = 3.2;
uniform float steep_freq = 6.5;
uniform float steepness_sharpness = 3.0;
uniform vec2 wind_dir = vec2(0.92, 0.38);
// specular
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.78, 1.0);
uniform float rim_power = 4.0;
uniform float rim_strength = 0.18;
uniform vec4 ocean_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float ocean_power = 48.0;
uniform float ocean_strength = 0.16;
// glitter: rare, very bright sparkles from randomly oriented grains
uniform float glitter_density = 70.0;
uniform float glitter_threshold : hint_range(0.9, 1.0) = 0.985;
uniform float glitter_strength = 2.2;
// keep the old parameter so existing materials stay valid
uniform float ripple_frequency = 5.0;
// Phase 1 pixel-art: base colour is a pixel-art sand texture on the world
// texel grid; ripple, grain and glitter are evaluated per texel, so every
// sparkle is a single stable texel that turns on/off with view and light.
uniform sampler2D sand_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool pixel_mode = true;
// Garbage Country-style ground: large tonal patches in 3 flat tones whose
// borders dither on the texel grid, small pebbles painted into the texels,
// and (near the oasis) damp earth with moss patches. soil_zone is a global
// set by Oasis: centre x, z, inner radius (full soil), outer radius.
uniform float mottle = 1.0;
uniform vec4 tone_dark : source_color = vec4(0.72, 0.55, 0.42, 1.0);
uniform vec4 tone_light : source_color = vec4(1.0, 0.86, 0.66, 1.0);
uniform vec4 pebble_light : source_color = vec4(0.78, 0.74, 0.76, 1.0);
uniform vec4 pebble_dark : source_color = vec4(0.48, 0.42, 0.48, 1.0);
uniform float pebble_density = 0.11;
uniform vec4 soil : source_color = vec4(0.68, 0.52, 0.38, 1.0);
uniform vec4 soil_dark : source_color = vec4(0.6, 0.46, 0.34, 1.0);
uniform vec4 moss : source_color = vec4(0.66, 0.6, 0.4, 1.0);
global uniform vec4 soil_zone;

varying vec3 world_p;
varying vec3 world_n;

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 0..1 field, posterised to flat bands with ordered-dither borders
float dithered_band(float v, float edge, float soft, ivec2 c) {
	return step(bayer4(c), smoothstep(edge - soft, edge + soft, v));
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void vertex() {
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Ripple slope (gradient of a wavy height field) along direction d.
vec2 ripple_grad(vec2 p, vec2 d, float freq) {
	float phase = dot(p, d) * freq + sin(dot(p, vec2(-d.y, d.x)) * 0.9) * 1.3;
	// asymmetric profile: gentle windward side, sharper lee side
	float s = sin(phase);
	float g = cos(phase) * (1.0 + 0.45 * s);
	return d * g;
}

void fragment() {
	vec3 n = normalize(world_n);
	vec3 wp = world_p;
	if (pixel_mode) {
		wp = (floor(world_p * PIXELS_PER_METRE) + 0.5) / PIXELS_PER_METRE;
	}
	// Steepness: 1 on flat sand, 0 on vertical flanks; sharpened.
	float s = pow(clamp(n.y, 0.0, 1.0), steepness_sharpness);
	vec2 wind = normalize(wind_dir);
	vec2 slope_dir = length(n.xz) > 0.01 ? normalize(n.xz) : wind;
	vec2 g_shallow = ripple_grad(wp.xz, wind, shallow_freq);
	vec2 g_steep = ripple_grad(wp.xz, slope_dir, steep_freq) * 1.4;
	vec2 g = mix(g_steep, g_shallow, s) * ripple_strength;
	vec3 rn = normalize(n + vec3(-g.x, 0.0, -g.y) * 0.6);
	// Sand grain: random normals per grain cell, nlerp with the surface normal.
	vec3 cell = floor(wp * (pixel_mode ? PIXELS_PER_METRE : grain_density));
	vec3 gr = normalize(hash33(cell) * 2.0 - 1.0);
	vec3 nn = normalize(mix(rn, gr, grain_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(nn, 0.0)).xyz);
	// Large-scale tonal variation so the floor is not flat colour.
	float vary = sin(wp.x * 0.31 + wp.z * 0.17) * 0.5 + 0.5;
	vec3 base = sand_color.rgb;
	if (pixel_mode) {
		base = texture(sand_tex, pixel_uv(world_p, vec3(0.0, 1.0, 0.0), 128.0)).rgb * sand_color.rgb / vec3(0.839, 0.745, 0.58);
	}
	vec3 albedo = base * mix(0.94, 1.04, vary);
	if (pixel_mode && mottle > 0.0) {
		vec2 tex = floor(world_p.xz * PIXELS_PER_METRE);
		ivec2 ic = ivec2(tex);
		vec2 q = (tex + 0.5) / PIXELS_PER_METRE;
		// two scales of patches: broad drifts (~6 m) and clumps (~1.5 m)
		float n = vnoise(q * 0.17) * 0.6 + vnoise(q * 0.7 + 13.0) * 0.4;
		float dark = dithered_band(1.0 - n, 0.62, 0.05, ic);
		float light = dithered_band(n, 0.64, 0.05, ic + ivec2(2, 1));
		vec3 col = mix(albedo, base * tone_dark.rgb, dark * mottle);
		col = mix(col, base * tone_light.rgb, light * mottle);
		// soil + moss near the oasis
		if (soil_zone.w > 0.0) {
			float d = distance(q, soil_zone.xy) + (vnoise(q * 0.9) - 0.5) * 2.2;
			float wet = 1.0 - smoothstep(soil_zone.z, soil_zone.w, d);
			if (wet > bayer4(ic + ivec2(1, 3))) {
				float m = vnoise(q * 0.55 + 41.0) * 0.7 + vnoise(q * 2.3) * 0.3;
				col = soil.rgb;
				col = mix(col, soil_dark.rgb, dithered_band(1.0 - m, 0.6, 0.05, ic));
				col = mix(col, moss.rgb, dithered_band(m, 0.62, 0.04, ic + ivec2(3, 0)) * smoothstep(0.2, 0.7, wet));
			}
		}
		// pebbles: in each 6x6-texel cell, maybe a 2-4 texel stone with a lit
		// top texel and a shadowed bottom one
		vec2 pc = floor(tex / 6.0);
		vec3 hp = hash33(vec3(pc, 7.0));
		if (hp.x < pebble_density) {
			vec2 lp = tex - pc * 6.0 - floor(1.0 + hp.yz * 3.0);
			float big = step(0.5, fract(hp.x * 37.0));
			bool inside = abs(lp.x) + abs(lp.y) <= big || (lp.x >= 0.0 && lp.x <= 1.0 && lp.y == 0.0);
			if (inside) {
				col = lp.y < 0.0 ? pebble_light.rgb : (lp.y > 0.0 ? pebble_dark.rgb : mix(pebble_light.rgb, pebble_dark.rgb, 0.4));
			}
		}
		albedo = col;
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 l_w = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
	vec3 v_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	// Diffuse contrast: squash the normal's y, steep 4x Lambert, then
	// lerp from the shadow colour to the terrain colour.
	vec3 nc = n_w;
	nc.y *= y_squash;
	float ndl = clamp(lambert_gain * dot(nc, l_w), 0.0, 1.0) * ATTENUATION;
	vec3 shade = mix(shadow_color.rgb / max(sand_color.rgb, vec3(0.01)), vec3(1.0), ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * shade * sun_scale / PI;
	// Rim and ocean specular, combined with max() so overlaps don't over-shine.
	float rim = clamp(pow(1.0 - clamp(dot(n_w, v_w), 0.0, 1.0), rim_power) * rim_strength, 0.0, 1.0);
	vec3 h = normalize(l_w + v_w);
	float ocean = pow(max(0.0, dot(n_w, h)), ocean_power) * ocean_strength;
	vec3 spec = clamp(max(rim * rim_color.rgb, ocean * ocean_color.rgb), 0.0, 1.0) * ATTENUATION;
	// Glitter: a random grain mirror; sparkle only when its reflection of the
	// sun lines up with the eye. Stable as the camera moves.
	vec3 gcell = floor(world_p * (pixel_mode ? PIXELS_PER_METRE : glitter_density));
	vec3 gn = normalize(hash33(gcell + 17.0) * 2.0 - 1.0);
	float rdv = max(0.0, dot(reflect(-l_w, gn), v_w));
	float glitter = rdv > glitter_threshold ? (rdv - glitter_threshold) / (1.0 - glitter_threshold) : 0.0;
	glitter *= max(dot(l_w, vec3(0.0, 1.0, 0.0)), 0.0) * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR * (spec * sun_scale + vec3(glitter * glitter_strength)) / PI;
}
