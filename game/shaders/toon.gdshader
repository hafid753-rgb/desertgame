// Hafid character shader: two-tone cel lighting with cool shadow tint,
// a soft rim and a small specular blob. Colour comes from vertex colours,
// so one material covers a whole character. Works on Mobile and Compatibility.
shader_type spatial;
render_mode cull_back;
#include "res://game/shaders/toon_common.gdshaderinc"
