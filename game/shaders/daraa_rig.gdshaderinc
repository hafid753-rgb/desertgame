// Runtime garment rig for the daraa (shared by the cloth pass and its
// outline so they never separate). Applied AFTER the blend shapes
// (GatherL / GatherR / GatherBoth / Spread), in the character's model space.
//
// Rig weights (side chains, freedom from the shoulders down) are computed
// from position in daraa_weights(); see the note there. The CPU side
// (DaraaGarment) runs damped springs for the side chains and the hem
// (inertia on run / turn / jump / land / dodge, hidden arm support) and
// passes their offsets here; the shared Wind field adds GPU wind on top.
#include "res://game/shaders/wind.gdshaderinc"

uniform vec3 side_l_off = vec3(0.0);   // model-space offset of the left chain
uniform vec3 side_r_off = vec3(0.0);
uniform vec3 hem_off = vec3(0.0);      // whole lower garment (lag, lift)
uniform float gather_l = 0.0;          // 0..1, how gathered each side is
uniform float gather_r = 0.0;
uniform float spread = 0.0;            // glide: sides held out as wings
uniform float daraa_wind = 0.07;
uniform float daraa_flutter = 0.014;
uniform float wind_speed_k = 0.0;      // set from speed: stronger flutter
// collision proxies (model space): xyz centre, w radius
uniform vec4 col_hand_l = vec4(0.0, -9.0, 0.0, 0.0);
uniform vec4 col_hand_r = vec4(0.0, -9.0, 0.0, 0.0);
uniform vec4 col_foot_l = vec4(0.0, -9.0, 0.0, 0.0);
uniform vec4 col_foot_r = vec4(0.0, -9.0, 0.0, 0.0);
uniform vec3 hip_l = vec3(-0.14, 0.44, 0.0);
uniform vec3 hip_r = vec3(0.14, 0.44, 0.0);
uniform vec4 col_legs = vec4(0.0, 0.3, 0.0, 0.15);

vec3 daraa_wind_term(vec3 v, float free, float side, mat4 model) {
	vec3 p = (model * vec4(v, 1.0)).xyz;
	float gust = wind_gust * wind_gust_at(p);
	vec3 w = wind_at(p, v.x * 2.5 + v.y * 1.5, 1.1) * daraa_wind * (1.0 + gust);
	float shelter = 1.0 - 0.6 * spread;
	// world -> model direction: transpose of the rotation (cheaper than
	// inverse() per vertex on mobile; the model has no shear)
	mat3 r = mat3(normalize(model[0].xyz), normalize(model[1].xyz), normalize(model[2].xyz));
	vec3 local = (transpose(r) * w) * free * shelter;
	// flutter: travelling waves down the open edges and around the hem.
	// The phase depends on height and x only, never on z, so front, back
	// and folded-over layers at the same place move together and cannot
	// pass through each other.
	float ph = wind_time * (5.5 + wind_speed_k * 4.0) - v.y * 7.0 - v.x * 3.0;
	float flut = (sin(ph) + 0.45 * sin(ph * 1.9 + v.x * 9.0)) * daraa_flutter * (1.0 + gust + wind_speed_k);
	local.z += flut * free * free;
	local.x += flut * 0.5 * side * clamp(v.x * 8.0, -1.0, 1.0);
	return local;
}

vec3 push_out(vec3 p, vec4 s) {
	vec3 d = p - s.xyz;
	float l = length(d);
	if (l < s.w && l > 1e-4) {
		p = s.xyz + d / l * s.w;
	}
	return p;
}

// leg proxy: capsule along the boot + sirwal (hip_* holds its top point),
// so a striding foot pushes the front panel ahead instead of poking through
// The cloth hangs OUTSIDE the leg, so a vertex caught inside is moved
// outward from the body's axis (not merely away from the capsule centre,
// which would drop it behind a striding leg).
vec3 push_out_segment(vec3 p, vec3 a, vec3 b, float r) {
	vec3 ab = b - a;
	float k = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
	vec3 d = p - (a + ab * k);
	float cc = dot(d, d) - r * r;
	if (cc >= 0.0) {
		return p;
	}
	vec2 h = p.xz;
	vec3 dir = length(h) > 1e-3 ? vec3(h.x, 0.0, h.y) / length(h) : vec3(0.0, 0.0, -1.0);
	float bb = dot(d, dir);
	return p + dir * (-bb + sqrt(max(bb * bb - cc, 0.0)));
}

// The rig weights are a smooth function of POSITION, not of the pattern:
// two layers of cloth at the same place (front panel, a folded sleeve
// flap, the back) always get the same offset, so the deformation is a
// smooth near-identity warp of space and cannot push one layer through
// another. (The pattern-derived COLOR weights are kept in the mesh for
// tools; the runtime no longer reads them.)
vec4 daraa_weights(vec3 v) {
	float t = clamp((1.08 - v.y) / 1.0, 0.0, 1.0);
	float free = t * t * (3.0 - 2.0 * t);
	float sl = smoothstep(0.1, 0.42, -v.x);
	float sr = smoothstep(0.1, 0.42, v.x);
	return vec4(sl, sr, free, 0.0);
}

vec3 daraa_deform(vec3 v, vec4 col_unused, mat4 model) {
	vec4 wgt = daraa_weights(v);
	float sl = wgt.r * (1.0 - 0.75 * gather_l) * (1.0 - 0.6 * spread);
	float sr = wgt.g * (1.0 - 0.75 * gather_r) * (1.0 - 0.6 * spread);
	float free = wgt.b;
	vec3 o = side_l_off * sl * free + side_r_off * sr * free + hem_off * free * free;
	o += daraa_wind_term(v, free, max(sl, sr), model);
	vec3 p = v + o;
	// collision proxies: floating hands and boots, invisible legs
	p = push_out(p, col_hand_l);
	p = push_out(p, col_hand_r);
	p = push_out_segment(p, hip_l, col_foot_l.xyz, col_foot_l.w);
	p = push_out_segment(p, hip_r, col_foot_r.xyz, col_foot_r.w);
	vec2 dl = p.xz - col_legs.xz;
	if (p.y < col_legs.y && length(dl) < col_legs.w * free) {
		p.xz = col_legs.xz + normalize(dl + vec2(0.0, 1e-4)) * col_legs.w * free;
	}
	return p;
}
