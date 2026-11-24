// Shared body of the toon shaders (see toon.gdshader).

uniform vec4 tint : source_color = vec4(1.0);
#include "res://game/shaders/toon_common_light.gdshaderinc"

void fragment() {
	vec3 c = COLOR.rgb;
	if (!vertex_color_linear) {
		c = pow(c, vec3(2.2));
	}
	float ao = mix(1.0, COLOR.a, ao_strength);
	ALBEDO = c * tint.rgb * mix(0.62, 1.0, ao);
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
#ifdef DOUBLE_SIDED
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = flash_color.rgb * flash;
}

