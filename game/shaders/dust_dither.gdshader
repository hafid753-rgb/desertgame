// Pixel-art dust puff for CPUParticles3D: a camera-facing disc quantised to
// world-sized texels (32 px/m) and made transparent only through a 4x4
// ordered dither on those texels. Two sand tones: lit top, shaded base.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://game/shaders/pixel_common.gdshaderinc"

uniform vec4 lit : source_color = vec4(0.95, 0.87, 0.71, 1.0);
uniform vec4 shade : source_color = vec4(0.72, 0.62, 0.55, 1.0);
uniform float quad_size = 0.32;

varying float sz;
varying flat int iid;

void vertex() {
	sz = length(MODEL_MATRIX[0].xyz);
	iid = INSTANCE_ID;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sz, INV_VIEW_MATRIX[1] * sz,
		INV_VIEW_MATRIX[2] * sz, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float n = max(2.0, floor(quad_size * sz * PIXELS_PER_METRE + 0.5));
	vec2 cellp = floor(UV * n);
	vec2 p = (cellp + 0.5) / n * 2.0 - 1.0;
	float r2 = dot(p, p);
	float a = COLOR.a * clamp(1.0 - r2, 0.0, 1.0) * 1.6;
	if (a < bayer4(ivec2(cellp) + ivec2(iid * 3, iid * 5))) {
		discard;
	}
	ALBEDO = mix(shade.rgb, lit.rgb, step(p.y, 0.15)) * COLOR.rgb;
}
