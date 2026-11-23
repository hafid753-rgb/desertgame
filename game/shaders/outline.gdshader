// Inverted-hull outline, used as next_pass of the toon material.
// Adapted from GDQuest godot-shaders (outline3D.gdshader), MIT licence:
// https://github.com/gdquest-demos/godot-shaders
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform float thickness = 0.012;
uniform vec4 outline_color : source_color = vec4(0.14, 0.08, 0.07, 1.0);

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
