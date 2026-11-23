// Shadow-smoke body for ordinary jinn. Original look: dark core, violet rim,
// wobbling silhouette, dissolve on death. Works on Mobile and Compatibility.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 core_color : source_color = vec4(0.03, 0.02, 0.06, 1.0);
uniform vec4 rim_color : source_color = vec4(0.42, 0.24, 0.66, 1.0);
uniform float wobble = 0.07;
uniform float flash = 0.0;
uniform float dissolve = 0.0;
uniform float burn = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

varying vec3 local_pos;

void vertex() {
	float n = noise(VERTEX * 3.0 + vec3(0.0, TIME * 1.6, 0.0));
	VERTEX += NORMAL * (n - 0.5) * wobble * 2.0;
	local_pos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float n = noise(local_pos * 5.0 + vec3(0.0, -TIME * 2.0, 0.0));
	if (dissolve > 0.0 && n < dissolve) {
		discard;
	}
	vec3 col = mix(core_color.rgb, rim_color.rgb, fres + n * 0.15);
	col = mix(col, vec3(1.0, 0.45, 0.1), burn * fres);
	col = mix(col, vec3(1.0), flash);
	ALBEDO = col;
}
