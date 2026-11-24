// Journey-style desert sand, after Alan Zucconi's "Journey Sand Shader"
// series (diffuse contrast, sand grain normals, slope-blended ripples, rim +
// ocean specular combined with max(), glitter). Procedural (no textures),
// tuned for the storybook palette and for mobile.
// https://www.alanzucconi.com/2019/10/08/journey-sand-shader-1/
shader_type spatial;
render_mode cull_back;

uniform vec4 sand_color : source_color = vec4(0.93, 0.74, 0.5, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.74, 0.5, 0.46, 1.0);
// grain: random micro-normals blended into the surface normal (nlerp)
uniform float grain_density = 38.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.22;
// ripples: shallow (flat, wind-aligned) vs steep (dune flanks)
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.7;
uniform float sun_scale : hint_range(0.0, 1.5) = 0.62;
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
uniform float glitter_threshold : hint_range(0.9, 1.0) = 0.992;
uniform float glitter_strength = 2.2;
// keep the old parameter so existing materials stay valid
uniform float ripple_frequency = 5.0;

varying vec3 world_p;
varying vec3 world_n;

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
	// Steepness: 1 on flat sand, 0 on vertical flanks; sharpened.
	float s = pow(clamp(n.y, 0.0, 1.0), steepness_sharpness);
	vec2 wind = normalize(wind_dir);
	vec2 slope_dir = length(n.xz) > 0.01 ? normalize(n.xz) : wind;
	vec2 g_shallow = ripple_grad(world_p.xz, wind, shallow_freq);
	vec2 g_steep = ripple_grad(world_p.xz, slope_dir, steep_freq) * 1.4;
	vec2 g = mix(g_steep, g_shallow, s) * ripple_strength;
	vec3 rn = normalize(n + vec3(-g.x, 0.0, -g.y) * 0.6);
	// Sand grain: random normals per grain cell, nlerp with the surface normal.
	vec3 cell = floor(world_p * grain_density);
	vec3 gr = normalize(hash33(cell) * 2.0 - 1.0);
	vec3 nn = normalize(mix(rn, gr, grain_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(nn, 0.0)).xyz);
	// Large-scale tonal variation so the floor is not flat colour.
	float vary = sin(world_p.x * 0.31 + world_p.z * 0.17) * 0.5 + 0.5;
	ALBEDO = sand_color.rgb * mix(0.94, 1.04, vary);
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
	nc.y *= 0.3;
	float ndl = clamp(4.0 * dot(nc, l_w), 0.0, 1.0) * ATTENUATION;
	vec3 shade = mix(shadow_color.rgb / max(sand_color.rgb, vec3(0.01)), vec3(1.0), ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * shade * sun_scale / PI;
	// Rim and ocean specular, combined with max() so overlaps don't over-shine.
	float rim = clamp(pow(1.0 - clamp(dot(n_w, v_w), 0.0, 1.0), rim_power) * rim_strength, 0.0, 1.0);
	vec3 h = normalize(l_w + v_w);
	float ocean = pow(max(0.0, dot(n_w, h)), ocean_power) * ocean_strength;
	vec3 spec = clamp(max(rim * rim_color.rgb, ocean * ocean_color.rgb), 0.0, 1.0) * ATTENUATION;
	// Glitter: a random grain mirror; sparkle only when its reflection of the
	// sun lines up with the eye. Stable as the camera moves.
	vec3 gcell = floor(world_p * glitter_density);
	vec3 gn = normalize(hash33(gcell + 17.0) * 2.0 - 1.0);
	float rdv = max(0.0, dot(reflect(-l_w, gn), v_w));
	float glitter = rdv > glitter_threshold ? (rdv - glitter_threshold) / (1.0 - glitter_threshold) : 0.0;
	glitter *= max(dot(l_w, vec3(0.0, 1.0, 0.0)), 0.0) * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR * (spec * sun_scale + vec3(glitter * glitter_strength)) / PI;
}
