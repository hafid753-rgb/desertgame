// Physically-styled lens flare over the 3D view (additive). Elements, all
// analytic and smooth (no sprites):
//   veiling glare   wide exponential bloom around the sun
//   starburst       diffraction spikes from a 6-blade aperture, slowly
//                   rotating with the camera's view of the sun
//   halo            thin chromatic ring around the sun (dispersion: the
//                   red, green and blue rings sit at slightly different radii)
//   ghosts          hexagonal aperture reflections on the line from the sun
//                   through the image centre, each with chromatic fringes
//   streak          faint horizontal anamorphic streak
// `intensity` already includes occlusion and on-screen fade (LensFlare).
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 sun_uv = vec2(0.5, 0.3);
uniform float intensity = 0.0;
uniform float aspect = 1.7778;
uniform vec3 tint = vec3(1.0, 0.86, 0.68);

float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(0.866025, 0.5)), p.y);
}

vec3 ghost(vec2 uv, vec2 c, float r, vec3 col, float soft) {
	vec3 o;
	// dispersion: each channel's aperture image is a little larger
	for (int ch = 0; ch < 3; ch++) {
		float rr = r * (1.0 + float(ch) * 0.035);
		float d = hex_dist((uv - c) / rr);
		float disc = 1.0 - smoothstep(1.0 - soft, 1.0, d);
		float rim = smoothstep(0.8, 0.98, d) * (1.0 - smoothstep(0.98, 1.04, d));
		o[ch] = disc * 0.55 + rim * 0.6;
	}
	return o * col;
}

void fragment() {
	if (intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = UV;
		vec2 a = vec2(aspect, 1.0);
		vec2 d = (uv - sun_uv) * a;
		float r = length(d);
		vec3 col = vec3(0.0);
		// veiling glare + hot core
		col += tint * (exp(-r * 6.5) * 0.18 + exp(-r * 32.0) * 0.6);
		// starburst: 6 blades -> 12 spikes, thin and fading with distance
		float ang = atan(d.y, d.x);
		float spikes = pow(abs(cos(ang * 6.0 + sun_uv.x * 2.0)), 60.0) + pow(abs(cos(ang * 6.0 + 0.26 + sun_uv.x * 2.0)), 120.0) * 0.6;
		col += tint * spikes * exp(-r * 9.0) * 0.16;
		// chromatic halo ring
		float hr = 0.24;
		vec3 ring = vec3(
			exp(-pow((r - hr * 1.03) / 0.006, 2.0)),
			exp(-pow((r - hr) / 0.006, 2.0)),
			exp(-pow((r - hr * 0.97) / 0.006, 2.0)));
		col += ring * 0.06;
		// ghosts along sun -> centre (and beyond)
		vec2 axis = vec2(0.5) - sun_uv;
		vec2 ua = uv * a;
		col += ghost(ua, (sun_uv + axis * 0.45) * a, 0.035, vec3(1.0, 0.8, 0.45), 0.25) * 0.10;
		col += ghost(ua, (sun_uv + axis * 0.8) * a, 0.075, vec3(0.55, 0.85, 0.7), 0.4) * 0.07;
		col += ghost(ua, (sun_uv + axis * 1.15) * a, 0.02, vec3(1.0, 0.95, 0.85), 0.2) * 0.14;
		col += ghost(ua, (sun_uv + axis * 1.45) * a, 0.12, vec3(0.75, 0.6, 1.0), 0.55) * 0.05;
		col += ghost(ua, (sun_uv + axis * 1.8) * a, 0.055, vec3(1.0, 0.6, 0.4), 0.35) * 0.08;
		col += ghost(ua, (sun_uv + axis * 2.1) * a, 0.16, vec3(0.6, 0.8, 1.0), 0.6) * 0.035;
		// anamorphic streak
		col += vec3(0.85, 0.9, 1.0) * exp(-abs(d.y) * 320.0) * exp(-abs(d.x) * 3.0) * 0.12;
		COLOR = vec4(col * intensity, 1.0);
	}
}
