// Journey-like stylized dune ripples with a single material and no simulation.
// Original procedural shader; two trigonometric bands and sunlight shading.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec4 sand_color : source_color = vec4(0.79, 0.62, 0.40, 1.0);
uniform float ripple_strength : hint_range(0.0, 0.3) = 0.045;
uniform float ripple_frequency = 5.0;
varying vec3 world_p;

void vertex() {
    world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float bands = sin(world_p.x * ripple_frequency + sin(world_p.z * 2.1) * 0.65);
    bands += sin(world_p.z * ripple_frequency * 0.42 + world_p.x * 1.2) * 0.35;
    float dunes = sin(world_p.x * 0.37 + world_p.z * 0.22);
    float ripple = bands * ripple_strength;
    ALBEDO = sand_color.rgb * (0.98 + ripple + dunes * 0.045);
    ROUGHNESS = 0.92;
}
