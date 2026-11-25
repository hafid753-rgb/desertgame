// Outline hull for the daraa: same cloth deformation as toon_robe so the
// line follows the moving cloth.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
#include "res://game/shaders/robe_cloth.gdshaderinc"

uniform float thickness = 0.012;
uniform vec4 outline_color : source_color = vec4(0.14, 0.08, 0.07, 1.0);

void vertex() {
	VERTEX += robe_offset(VERTEX, MODEL_MATRIX) + NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
