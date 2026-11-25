// Outline hull for the daraa: same rig deformation as daraa.gdshader.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
#include "res://game/shaders/daraa_rig.gdshaderinc"

// thin: a thick inverted hull pokes through closely stacked cloth layers
uniform float thickness = 0.0045;
uniform vec4 outline_color : source_color = vec4(0.14, 0.08, 0.07, 1.0);

void vertex() {
	VERTEX = daraa_deform(VERTEX, COLOR, MODEL_MATRIX) + NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
