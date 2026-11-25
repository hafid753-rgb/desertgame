// Shared pixel-art sampling for Hafid (Phase 1 rendering lab).
// One world texel density everywhere (PIXELS_PER_METRE): textures are
// sampled on an axis-aligned texel grid in world or object space, choosing
// the dominant axis (no triplanar blending, which would smear pixels), with
// nearest filtering + mipmaps to avoid distant shimmer.
const float PIXELS_PER_METRE = 32.0;

vec2 pixel_uv(vec3 p, vec3 n, float tex_size) {
	vec3 a = abs(n);
	vec2 q;
	if (a.y >= a.x && a.y >= a.z) {
		q = p.xz;
	} else if (a.x >= a.z) {
		q = vec2(p.z, -p.y);
	} else {
		q = vec2(p.x, -p.y);
	}
	return q * PIXELS_PER_METRE / tex_size;
}

// Palette lighting ramp: deep shadow -> lavender ambient -> lit -> sunlight.
// Few steps, soft edges kept to one texel by the low-res render layer.
const vec3 PAL_DEEP = vec3(0.286, 0.263, 0.310);     // #49434F
const vec3 PAL_LAVENDER = vec3(0.510, 0.471, 0.553); // #82788D
const vec3 PAL_SUN = vec3(0.945, 0.867, 0.714);      // #F1DDB6

vec3 pixel_light_ramp(float ndl, float atten) {
	float lit = smoothstep(0.0, 0.08, ndl) * atten;
	float bright = smoothstep(0.55, 0.62, ndl) * atten;
	vec3 shadow = mix(PAL_DEEP, PAL_LAVENDER, 0.72) * 1.25;
	vec3 mid = vec3(0.86, 0.80, 0.74);
	return mix(mix(shadow, mid, lit), PAL_SUN * 1.05, bright * 0.6);
}

// 4x4 ordered-dither threshold (0..1) for an integer cell. Used for every
// pixel-art transparency (dust, fades, prints) instead of alpha blending.
float bayer4(ivec2 c) {
	ivec2 m = ivec2(((c.x % 4) + 4) % 4, ((c.y % 4) + 4) % 4);
	int i = m.y * 4 + m.x;
	float b[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (b[i] + 0.5) / 16.0;
}
