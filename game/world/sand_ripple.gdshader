// Hafid sand: Journey-inspired, after John Edwards' GDC 2013 talk and Alan
// Zucconi's breakdown (parts 2-6), implemented from the owner's "Sand
// Rendering Master Specification". Original code; no Journey source.
//
// Material stack (all direct terms x light x shadow attenuation):
//   diffuse   warm albedo, Zucconi diffuse contrast (squashed normal y),
//             mauve-peach shadow tone; ambient handled by the scene
//   ripples   meso normal from a warped wind-aligned sinusoid (~0.55 m),
//             damped on steep slip faces and on damp ground
//   sheen     broad "ocean" lobe pow(N.H, ~14), restrained, dielectric
//   rim       grazing (1 - N.V)^3 on sunlit crests
//   glitter   stable world-space grain cells (never seeded by time/screen);
//             each grain tilts the normal in the tangent plane; narrow
//             lobe pow(M.H, ~260); faded where grains get sub-pixel, that
//             energy moved into the broad sheen
// Pixel-art: only the faint albedo micro-detail uses the 32 px/m texture;
// geometry and lighting stay smooth (spec: no beige checkerboard).
shader_type spatial;
render_mode cull_back;
#include "res://game/shaders/pixel_common.gdshaderinc"

uniform vec4 sand_color : source_color = vec4(0.89, 0.65, 0.54, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.78, 0.54, 0.47, 1.0);
uniform sampler2D sand_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform float detail = 0.25;              // pixel texture influence on albedo
// diffuse contrast (Zucconi part 2)
uniform float y_squash = 0.3;
uniform float lambert_gain = 4.0;
uniform float sun_scale : hint_range(0.0, 1.5) = 0.62;
// ripples (Zucconi part 6)
uniform vec2 wind_dir = vec2(0.92, 0.38);
uniform float ripple_freq = 11.5;         // rad/m along the wind (~0.55 m)
uniform float steep_freq = 16.0;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.32;
uniform float steepness_sharpness = 3.0;
// broad sheen + rim
uniform vec4 ocean_color : source_color = vec4(1.0, 0.86, 0.74, 1.0);
uniform float ocean_power = 6.0;
uniform float ocean_strength = 0.3;
uniform vec4 rim_color : source_color = vec4(1.0, 0.88, 0.76, 1.0);
uniform float rim_strength = 0.3;
// glitter (Zucconi part 5 / spec section 04)
uniform float grains_per_metre = 26.0;
uniform float grain_spread = 1.4;      // wide: glints at any view, not only toward the sun
uniform float glitter_power = 220.0;
uniform float glitter_strength = 9.0;
uniform vec4 glitter_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
// near-oasis ground (global soil_zone = centre x, z, inner, outer radius)
uniform vec4 soil : source_color = vec4(0.68, 0.52, 0.42, 1.0);
uniform vec4 moss : source_color = vec4(0.66, 0.6, 0.42, 1.0);
global uniform vec4 soil_zone;
// kept for older materials (ignored unless > 0)
uniform float mottle = 0.0;
uniform vec4 tone_dark : source_color = vec4(0.95, 0.93, 0.92, 1.0);
uniform vec4 tone_light : source_color = vec4(1.04, 1.03, 1.02, 1.0);
uniform vec4 pebble_light : source_color = vec4(0.85, 0.75, 0.7, 1.0);
uniform vec4 pebble_dark : source_color = vec4(0.66, 0.52, 0.48, 1.0);
uniform float pebble_density = 0.0;
uniform bool pixel_mode = true;
// debug: 1 shows (N.L, N.H, grain visibility) as colour
uniform float debug_spec = 0.0;

varying vec3 world_p;
varying vec3 world_n;
varying vec3 v_macro;      // macro+ripple normal, world space (fragment -> light)
varying vec3 v_micro;      // grain normal, world space
varying float v_grain;     // 0..1 grain visibility (sub-pixel fade)
varying float v_wet;

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// slope of a gently warped, slightly asymmetric ripple field along d
vec2 ripple_grad(vec2 p, vec2 d, float freq) {
	float warp = vnoise(p * 0.35) * 2.2 + sin(dot(p, vec2(-d.y, d.x)) * 0.8) * 1.1;
	float phase = dot(p, d) * freq + warp;
	float s = sin(phase);
	return d * cos(phase) * (1.0 + 0.4 * s);
}

void vertex() {
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_n);
	vec2 wind = normalize(wind_dir);
	// damp ground near the oasis: darker, no ripples, no glitter
	float wet = 0.0;
	if (soil_zone.w > 0.0) {
		float d = distance(world_p.xz, soil_zone.xy) + (vnoise(world_p.xz * 0.9) - 0.5) * 2.0;
		wet = 1.0 - smoothstep(soil_zone.z, soil_zone.w, d);
	}
	v_wet = wet;
	// meso ripples: wind-aligned on flats, following the slope on flanks,
	// faded on steep slip faces, gone on damp ground
	float flat_ = pow(clamp(n.y, 0.0, 1.0), steepness_sharpness);
	vec2 slope_dir = length(n.xz) > 0.01 ? normalize(n.xz) : wind;
	vec2 g = mix(ripple_grad(world_p.xz, slope_dir, steep_freq) * 0.6,
		ripple_grad(world_p.xz, wind, ripple_freq), flat_);
	// filter: ripples fade out before they alias into zebra noise
	float fp = length(fwidth(world_p));
	float wl = 6.2831853 / ripple_freq;
	float ripple_vis = 1.0 - smoothstep(wl * 0.1, wl * 0.3, fp);
	g *= ripple_strength * ripple_vis * (1.0 - wet) * (0.35 + 0.65 * smoothstep(0.55, 0.85, n.y));
	vec3 mn = normalize(n + vec3(-g.x, 0.0, -g.y) * 0.5);
	v_macro = mn;
	// grains: stable world cells; tilt the normal inside the tangent plane
	vec3 t = normalize(cross(vec3(0.0, 0.0, 1.0), mn) + vec3(1e-4));
	vec3 b = normalize(cross(mn, t));
	vec3 cell = floor(world_p * grains_per_metre);
	vec3 j = hash33(cell) * 2.0 - 1.0;
	v_micro = normalize(mn + (t * j.x + b * j.y) * grain_spread);
	float footprint = length(fwidth(world_p)) * grains_per_metre;
	v_grain = (1.0 - smoothstep(1.0, 2.6, footprint)) * (1.0 - wet);
	// albedo: smooth warm sand, faint pixel micro-detail, broad soft drifts
	vec3 base = sand_color.rgb;
	if (pixel_mode) {
		vec3 tex = texture(sand_tex, pixel_uv(world_p, vec3(0.0, 1.0, 0.0), 128.0)).rgb / vec3(0.839, 0.745, 0.58);
		base *= mix(vec3(1.0), tex, detail);
	}
	base *= mix(0.96, 1.03, vnoise(world_p.xz * 0.06));
	if (wet > 0.0) {
		float m = vnoise(world_p.xz * 0.55 + 41.0);
		vec3 ground = mix(soil.rgb, moss.rgb, smoothstep(0.55, 0.7, m));
		base = mix(base, ground, smoothstep(0.0, 0.7, wet));
	}
	if (pebble_density > 0.0) {
		vec2 tc = floor(world_p.xz * PIXELS_PER_METRE);
		vec2 pc = floor(tc / 6.0);
		vec3 hp = hash33(vec3(pc, 7.0));
		if (hp.x < pebble_density) {
			vec2 lp = tc - pc * 6.0 - floor(1.0 + hp.yz * 3.0);
			if (abs(lp.x) + abs(lp.y) <= 0.0 || (lp.x >= 0.0 && lp.x <= 1.0 && lp.y == 0.0)) {
				base = lp.y < 0.0 ? pebble_light.rgb : pebble_dark.rgb;
			}
		}
	}
	ALBEDO = base;
	NORMAL = normalize((VIEW_MATRIX * vec4(mn, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	vec3 l = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 n = normalize(v_macro);
	vec3 h = normalize(l + v);
	// diffuse contrast: squash N.y, steep Lambert, lerp shadow -> lit
	vec3 nc = n;
	nc.y *= y_squash;
	float ndl = clamp(lambert_gain * dot(normalize(nc), l), 0.0, 1.0) * ATTENUATION;
	vec3 shade = mix(shadow_color.rgb / max(sand_color.rgb, vec3(0.01)), vec3(1.0), ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * shade * sun_scale / PI;
	float nl = clamp(dot(n, l), 0.0, 1.0) * ATTENUATION;
	float nv = clamp(dot(n, v), 0.0, 1.0);
	// broad sheen (takes over the glitter energy where grains are sub-pixel)
	float dry = 1.0 - v_wet * 0.7;
	float ocean = pow(clamp(dot(n, h), 0.0, 1.0), ocean_power) * (ocean_strength + (1.0 - v_grain) * 0.06) * dry;
	float rim = pow(1.0 - nv, 3.0) * rim_strength;
	vec3 spec = max(ocean * ocean_color.rgb, rim * rim_color.rgb) * nl;
	// glitter: narrow lobe on the grain normal, only in direct light
	float glint = pow(clamp(dot(normalize(v_micro), h), 0.0, 1.0), glitter_power) * glitter_strength * v_grain;
	spec += glitter_color.rgb * glint * nl;
	SPECULAR_LIGHT += LIGHT_COLOR * spec * sun_scale / PI;
	DIFFUSE_LIGHT += vec3(debug_spec) * vec3(nl, clamp(dot(n, h), 0.0, 1.0), v_grain);
}
