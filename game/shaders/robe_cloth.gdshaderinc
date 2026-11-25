// Daraa body as hanging cloth (owner: "the daraa is too stiff, it should move
// with the wind and fall downward"). Object-space deformation shared by the
// robe's toon pass and its outline pass so the two never separate.
//   weight   0 at the shoulders, 1 at the hem (t^1.6): the yoke stays put
//   wind     the shared wind field pushes the lower robe, gusts billow it
//   lag      a spring-smoothed copy of the wearer's velocity (set from
//            GDScript): the hem trails and lifts when moving, swings past
//            when stopping
//   flutter  travelling waves around the hem, stronger with speed and gusts
//   hang     the hem falls in and down a little (heavy cloth), less when
//            the cloth is blown out
#include "res://game/shaders/wind.gdshaderinc"
uniform float robe_top = 0.6;
uniform float robe_bottom = -0.6;
uniform vec3 robe_lag = vec3(0.0);       // world m/s
uniform float robe_wind = 0.09;
uniform float robe_flutter = 0.022;
uniform float robe_hang = 0.05;

vec3 robe_offset(vec3 v, mat4 model) {
	float t = clamp((robe_top - v.y) / max(robe_top - robe_bottom, 0.01), 0.0, 1.0);
	float w = pow(t, 1.6);
	vec3 p = (model * vec4(v, 1.0)).xyz;
	vec3 wind = wind_at(p, v.x * 3.0 + v.z * 2.0, 1.0);
	float gust = wind_gust * wind_gust_at(p);
	vec3 lag = robe_lag;
	float speed = length(lag.xz);
	vec3 drag = -vec3(lag.x, 0.0, lag.z) * 0.032;
	if (length(drag) > 0.28) {
		drag = normalize(drag) * 0.28;
	}
	vec3 o = (wind * robe_wind * (1.0 + gust) + drag) * w;
	o.y += length(drag) * 0.35 * w;                       // trailing hem lifts
	vec2 radial = length(v.xz) > 1e-3 ? normalize(v.xz) : vec2(0.0, 1.0);
	float ang = atan(v.x, v.z);
	float wave = sin(wind_time * (6.0 + speed * 0.6) - ang * 3.0 - t * 5.0)
		+ 0.5 * sin(wind_time * 11.0 + ang * 5.0 + t * 3.0);
	float flut = wave * robe_flutter * t * t * (1.0 + speed * 0.25 + gust * 1.5);
	// hang: heavy hem falls inward/downward, relieved by wind and motion
	float relief = clamp(length(o) * 4.0, 0.0, 1.0);
	float hang = robe_hang * t * t * (1.0 - 0.7 * relief);
	vec3 local = (inverse(model) * vec4(o, 0.0)).xyz;
	local.xz += radial * (flut - hang * 0.6);
	local.y -= hang * 0.4;
	return local;
}
