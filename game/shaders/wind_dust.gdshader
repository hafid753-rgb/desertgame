// Wind-blown sand (the "dithered dust" of 3D pixel-art wastelands).
//  mode 0  drift sheet: a ground-hugging plane that follows the player; in
//          world texels, streaks stretched along the wind travel downwind,
//          thickening when a gust front passes. Transparency is an ordered
//          dither on the world texel grid only (no alpha blending).
//  mode 1  motes: tiny 2-3 texel grains (MultiMesh) advected by the same
//          field, wrapped in a box around the player.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://game/shaders/pixel_common.gdshaderinc"
#include "res://game/shaders/wind.gdshaderinc"

uniform int mode = 0;
uniform vec4 lit : source_color = vec4(0.97, 0.86, 0.7, 1.0);
uniform vec4 shade : source_color = vec4(0.9, 0.77, 0.63, 1.0);
uniform vec4 grain : source_color = vec4(0.78, 0.66, 0.52, 1.0);
uniform float amount = 1.0;
uniform float radius = 22.0;          // sheet fade radius around the player
uniform float speed = 3.2;            // m/s of blown sand per unit wind
uniform vec4 water_mask = vec4(0.0, 0.0, 0.0, 0.0);  // x, z, r (no drift on water)
uniform vec3 box = vec3(28.0, 3.0, 28.0);
uniform float ground_half = 1000.0;   // no blown sand past the edge of the ground

varying vec3 wp;
varying float mote_a;
varying flat int iid;
varying float tone;

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

void vertex() {
	iid = INSTANCE_ID;
	tone = INSTANCE_CUSTOM.g;
	if (mode == 1) {
		// stateless advection: origin + wind travel, wrapped around the player
		vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;   // 0..box
		float ph = INSTANCE_CUSTOM.r;
		vec2 d = normalize(wind_dir);
		float w = wind_strength + wind_gust * 0.6;
		vec2 travel = d * wind_time * speed * w * (0.7 + 0.6 * INSTANCE_CUSTOM.g);
		vec2 lo = player_pos.xz - box.xz * 0.5;
		vec2 xz = lo + mod(o.xz + travel - lo, box.xz);
		vec3 p3 = vec3(xz.x, 0.0, xz.y);
		float g = wind_gust_at(p3);
		float hop = abs(sin(wind_time * (2.0 + INSTANCE_CUSTOM.g * 2.0) + ph * 6.28));
		p3.y = player_pos.y + 0.05 + o.y * (0.25 + g) * 0.6 + hop * 0.12;
		vec3 wv = wind_at(p3, ph, 1.6);
		p3.xz += vec2(-d.y, d.x) * dot(wv, vec3(-d.y, 0.0, d.x)) * 0.6;
		vec2 e = abs(xz - player_pos.xz) / (box.xz * 0.5);
		mote_a = (0.1 + g * 0.9) * amount * (1.0 - smoothstep(0.7, 1.0, max(e.x, e.y)));
		wp = p3;
		// camera-facing grain, size snapped to whole texels
		float s = (1.0 + floor(INSTANCE_CUSTOM.b * 1.99)) / PIXELS_PER_METRE;
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		vec3 world = p3 + (right * VERTEX.x + up * VERTEX.y) * s;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	} else {
		wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		mote_a = 1.0;
	}
}

void fragment() {
	if (mode == 1) {
		if (mote_a < bayer4(ivec2(iid, iid * 7)) || max(abs(wp.x), abs(wp.z)) > ground_half) {
			discard;
		}
		ALBEDO = tone > 0.5 ? grain.rgb : lit.rgb;
	} else {
		vec2 cell = floor(wp.xz * PIXELS_PER_METRE);
		vec2 q = (cell + 0.5) / PIXELS_PER_METRE;
		vec2 d = normalize(wind_dir);
		vec2 pd = vec2(-d.y, d.x);
		float w = wind_strength + wind_gust * wind_gust_at(vec3(q.x, 0.0, q.y));
		float along = dot(q, d) - wind_time * speed * (0.6 + w);
		float across = dot(q, pd);
		// long thin streaks along the wind, with a second faster finer layer
		float n = vnoise(vec2(along * 0.45, across * 4.0));
		n = n * 0.65 + 0.35 * vnoise(vec2((along - wind_time * speed * 0.6) * 1.1, across * 9.0));
		float g = wind_gust_at(vec3(q.x, 0.0, q.y));
		float dens = smoothstep(0.52, 0.82, n) * (0.18 + g * 1.1) * amount;
		dens *= 1.0 - smoothstep(radius * 0.6, radius, distance(q, player_pos.xz));
		if (water_mask.z > 0.0) {
			dens *= smoothstep(water_mask.z - 0.3, water_mask.z + 1.2, distance(q, water_mask.xy));
		}
		if (max(abs(q.x), abs(q.y)) > ground_half) {
			discard;
		}
		if (dens < bayer4(ivec2(cell))) {
			discard;
		}
		ALBEDO = n > 0.74 ? lit.rgb : shade.rgb;
	}
}
