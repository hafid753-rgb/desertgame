// Original Ico-inspired spectral ribbons: a single inexpensive mesh.
// The fading silhouette uses geometric strips and UV transparency,
// not particle simulation or any extracted game assets.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 veil_color : source_color = vec4(0.10, 0.075, 0.18, 1.0);
uniform vec4 rim_color : source_color = vec4(0.32, 0.22, 0.49, 1.0);
uniform float dissolve = 0.0;
uniform float agitation = 0.0;

void vertex() {
    // Distinct movements across strips, anchored at their base.
    float phase = VERTEX.x * 9.0 + VERTEX.z * 7.0 + UV.y * 4.5;
    float wind = sin(TIME * (1.25 + agitation) + phase);
    VERTEX.x += wind * (0.025 + UV.y * 0.11);
    VERTEX.z += cos(TIME * 1.1 + phase) * (0.02 + UV.y * 0.08);
}

void fragment() {
    float feather = smoothstep(0.0, 0.28, UV.x) * (1.0 - smoothstep(0.72, 1.0, UV.x));
    float tip = 1.0 - smoothstep(0.55, 1.0, UV.y);
    float root = smoothstep(0.0, 0.10, UV.y);
    float flicker = 0.75 + 0.25 * sin(TIME * 2.6 + UV.y * 13.0 + UV.x * 5.0);
    float edge = abs(UV.x - 0.5) * 2.0;
    ALBEDO = mix(veil_color.rgb, rim_color.rgb, edge * 0.45 + UV.y * 0.1);
    ALPHA = feather * root * tip * flicker * 0.68 * (1.0 - dissolve);
}
