// Individual pixel-art vegetation surfaces: grass blades, flowers, acacia
// leaflets, palm frond leaflets. Each instance is its own deformable,
// subdivided quad (root at UV.y = 1) driven by the shared wind field.
//   INSTANCE_CUSTOM.r = atlas cell / cell count, .g = phase,
//   .b = stiffness (higher = stiffer), .a = position along a frond (0..1)
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
#include "res://game/shaders/pixel_common.gdshaderinc"
#include "res://game/shaders/wind.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform float atlas_cols = 6.0;
uniform float atlas_rows = 2.0;
uniform int kind = 0;                  // 0 grass/flower, 1 leaf, 2 frond leaflet
uniform float card_height = 1.0;       // local height of the quad (m)
uniform float bend = 0.9;
uniform float response = 1.0;          // grass 1.0, leaves 1.4, fronds 0.7
uniform float push_radius = 0.9;
uniform vec4 tint : source_color = vec4(1.0);
// whole-plant sway (palms, acacia canopy)
uniform vec3 sway_root = vec3(0.0);
uniform float sway_height = 1.0;
uniform float sway_amount = 0.0;
// camera-aware fade: foliage between the lens and the player dissolves in
// a 4x4 ordered-dither pattern (pixel-art screen door) instead of blocking.
uniform float fade_near = 2.6;

varying float h;

void vertex() {
	h = clamp(1.0 - UV.y, 0.0, 1.0);
	float phase = INSTANCE_CUSTOM.g * 6.2831853;
	float stiff = max(INSTANCE_CUSTOM.b, 0.2);
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 w = wind_at(root, phase, response);
	float t = wind_time * response;
	vec3 off = vec3(0.0);
	float len = card_height * length(MODEL_MATRIX[1].xyz);
	if (kind == 0) {
		// blade: root fixed, bend grows with h^2, tip flutter, parts underfoot
		vec3 push = player_push(root, push_radius) * 0.9;
		off = (w * bend / stiff + push) * h * h * len;
		vec2 perp = normalize(vec2(-wind_dir.y, wind_dir.x));
		off.xz += perp * sin(t * 7.0 + phase * 3.0) * 0.05 * h * h * len * (0.3 + length(w));
		off.y -= dot(off.xz, off.xz) * 0.5 / max(len, 0.01);   // keep the blade length
	} else {
		// leaf / leaflet: hinge at the stem, flap + drift with the field
		float along = kind == 2 ? (0.25 + INSTANCE_CUSTOM.a) : 1.0;
		vec3 n = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
		float flap = sin(t * 6.0 + phase * 5.0) * (0.25 + length(w)) * 0.12;
		off = n * flap * h * len + w * bend * 0.25 * along * (0.4 + h);
		off.y -= length(w) * 0.12 * along * h * len;
	}
	if (sway_amount > 0.0) {
		off += plant_sway(wpos, sway_root, sway_height, sway_amount);
	}
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	float cells = atlas_cols * atlas_rows;
	float cell = floor(INSTANCE_CUSTOM.r * cells + 0.5);
	cell = mod(cell, cells);
	UV = (vec2(mod(cell, atlas_cols), floor(cell / atlas_cols)) + UV) / vec2(atlas_cols, atlas_rows);
}

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	float cam_d = -VERTEX.z;
	if (cam_d < fade_near) {
		ivec2 px = ivec2(FRAGCOORD.xy) % 4;
		float thr = (BAYER[px.y * 4 + px.x] + 0.5) / 16.0;
		if (smoothstep(0.6, fade_near, cam_d) < thr) {
			discard;
		}
	}
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * tint.rgb * (kind == 0 ? mix(0.72, 1.0, h) : 1.0);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// cards light like the ground they grow from (no harsh two-sided flips)
	NORMAL = normalize(mix(NORMAL * (FRONT_FACING ? 1.0 : -1.0), (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.65));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.7 + 0.3;
	DIFFUSE_LIGHT += LIGHT_COLOR * pixel_light_ramp(ndl, ATTENUATION) / PI;
}
