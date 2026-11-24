// Pixel-art pond (Mobile-friendly, no screen-space effects): everything is
// evaluated on the 32 px/m world texel grid.
//  - shallow -> deep palette gradient from COLOR.r (0 shore .. 1 centre)
//  - wind-driven ripple bands quantised to 3 tones
//  - stylised sky reflection at grazing angles
//  - animated shoreline foam band
//  - single-texel sun glints (stable per texel, depend on view + light)
shader_type spatial;
render_mode cull_back;
#include "res://game/shaders/pixel_common.gdshaderinc"
#include "res://game/shaders/wind.gdshaderinc"

uniform vec4 shallow : source_color = vec4(0.42, 0.62, 0.58, 1.0);
uniform vec4 mid : source_color = vec4(0.3, 0.48, 0.5, 1.0);
uniform vec4 deep : source_color = vec4(0.17, 0.3, 0.36, 1.0);
uniform vec4 sky : source_color = vec4(0.62, 0.74, 0.78, 1.0);
uniform vec4 foam : source_color = vec4(0.93, 0.92, 0.86, 1.0);

varying vec3 wp;
varying float depth01;

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth01 = COLOR.r;
}

void fragment() {
	vec2 cell = floor(wp.xz * PIXELS_PER_METRE);
	vec2 q = (cell + 0.5) / PIXELS_PER_METRE;
	vec2 d = normalize(wind_dir);
	float t = wind_time;
	// ripples travelling downwind + a cross set, quantised
	float r = sin(dot(q, d) * 9.0 - t * 2.2 + sin(dot(q, vec2(-d.y, d.x)) * 2.0) * 1.2)
		+ 0.6 * sin(dot(q, vec2(-d.y, d.x)) * 13.0 + t * 1.3);
	float band = r > 1.0 ? 1.0 : (r < -0.9 ? -1.0 : 0.0);
	float dd = clamp(depth01, 0.0, 1.0);
	// dithered band edges (2x2 ordered) so the steps read as pixel art
	float dith = (mod(cell.x, 2.0) + mod(cell.y, 2.0) * 2.0) / 4.0 - 0.375;
	float de = dd + dith * 0.06;
	vec3 c = de < 0.18 ? shallow.rgb : (de < 0.55 ? mid.rgb : deep.rgb);
	c *= 1.0 + band * 0.07;
	// stylised reflection toward the horizon
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	c = mix(c, sky.rgb, step(0.6, fres + band * 0.08) * 0.35);
	// shoreline foam: an animated band of texels near the edge
	float f = dd + 0.035 * sin(t * 1.6 + (q.x + q.y) * 6.0);
	if (f < 0.022 || (f < 0.05 && hash12(cell + floor(t * 2.0)) > 0.6)) {
		c = foam.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * mix(vec3(0.7, 0.68, 0.76), vec3(1.0), ATTENUATION) / PI;
	// glints: a random micro-facet per texel; sparkle when it mirrors the sun
	vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 l_w = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
	vec3 v_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec2 cell = floor(wp.xz * PIXELS_PER_METRE);
	float a = hash12(cell) * 6.2831853;
	vec3 g = normalize(vec3(cos(a) * 0.25, 1.0, sin(a) * 0.25) + vec3(sin(wind_time * 2.0 + a) * 0.08, 0.0, 0.0));
	float rv = max(0.0, dot(reflect(-l_w, g), v_w));
	float glint = step(0.996, rv) * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR * glint * 1.6;
}
