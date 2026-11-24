// Shared world-space wind field (mirrors Wind.gd). Include in any material
// that should move with the environment.
global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_gust;
global uniform float wind_gust_freq;
global uniform float wind_wavelength;
global uniform float wind_turbulence;
global uniform float wind_time;
global uniform vec3 player_pos;

float wind_gust_at(vec3 p) {
	vec2 d = normalize(wind_dir);
	float ph = (dot(p.xz, d) / wind_wavelength - wind_time * wind_gust_freq) * 6.2831853;
	float g = 0.5 + 0.5 * sin(ph);
	return g * g * g;
}

// Horizontal wind (x, z); `response` scales how fast the material reacts
// (grass 1.0, leaves 1.4, heavy branches 0.4) by stretching time.
vec3 wind_at(vec3 p, float phase, float response) {
	vec2 d = normalize(wind_dir);
	float t = wind_time * response + phase;
	float w = wind_strength + wind_gust * wind_gust_at(p);
	float turb = sin(p.x * 0.7 + t * 1.7) * cos(p.z * 0.6 - t * 1.3) * wind_turbulence;
	return vec3(d.x, 0.0, d.y) * w + vec3(-d.y, 0.0, d.x) * turb * 0.5;
}

// Push away from the player (grass parting underfoot).
vec3 player_push(vec3 p, float radius) {
	vec3 to = p - player_pos;
	to.y = 0.0;
	float dist = length(to);
	float k = 1.0 - smoothstep(radius * 0.4, radius, dist);
	return dist > 0.001 ? normalize(to) * k * step(abs(p.y - player_pos.y), 1.5) : vec3(0.0);
}

// Whole-plant sway (palm trunks + their crowns move together): world offset
// for a point `p` on a plant rooted at `root` of height `height`.
vec3 plant_sway(vec3 p, vec3 root, float height, float amount) {
	float rel = clamp((p.y - root.y) / max(height, 0.01), 0.0, 1.5);
	return wind_at(root, root.x * 0.37, 0.4) * amount * rel * rel;
}
