// Pixel-art effect shells (bursts, shockwave rings, puffs): flat colour with
// a lighter rim band facing the camera, transparency only through a 4x4
// ordered dither on 2x2-pixel cells, so effects read as pixel art.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://game/shaders/pixel_common.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0);
uniform float alpha = 1.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = color.a * alpha * mix(0.55, 1.0, facing);
	ivec2 cell = ivec2(FRAGCOORD.xy * 0.5);
	if (a < bayer4(cell)) {
		discard;
	}
	ALBEDO = mix(color.rgb, vec3(1.0), step(facing, 0.35) * 0.35);
}
