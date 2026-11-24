// Depth-edge pass for the low-res render layer (adapted from Leo Peltola's
// MIT "pixelart_stylizer", depth part only: its normal-edge highlights need
// the normal-roughness buffer, which the Mobile renderer does not provide).
// Draws a darker line on the near side of depth steps, one low-res texel
// wide, and is transparent everywhere else so later transparent effects
// (smoke, fire, trails) still show.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform vec3 edge_color : source_color = vec3(0.286, 0.263, 0.310); // #49434F
uniform float depth_threshold = 0.35;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(DEPTH_TEXTURE, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 e = 1.0 / VIEWPORT_SIZE;
	float d = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float diff = 0.0;
	diff += clamp(lin_depth(SCREEN_UV + vec2(e.x, 0.0), INV_PROJECTION_MATRIX) - d, 0.0, 10.0);
	diff += clamp(lin_depth(SCREEN_UV - vec2(e.x, 0.0), INV_PROJECTION_MATRIX) - d, 0.0, 10.0);
	diff += clamp(lin_depth(SCREEN_UV + vec2(0.0, e.y), INV_PROJECTION_MATRIX) - d, 0.0, 10.0);
	diff += clamp(lin_depth(SCREEN_UV - vec2(0.0, e.y), INV_PROJECTION_MATRIX) - d, 0.0, 10.0);
	// scale threshold with distance so far geometry doesn't outline everything
	float edge = step(depth_threshold * (1.0 + d * 0.15), diff);
	vec3 base = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	ALBEDO = mix(base, edge_color, strength);
	ALPHA = edge * (d < 60.0 ? 1.0 : 0.0);
}
