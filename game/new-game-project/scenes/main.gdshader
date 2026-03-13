shader_type spatial;
render_mode unshaded, fog_disabled;

uniform sampler2D screen_tex : source_color;

uniform float curvature = 0.12;
uniform float barrel = 0.08;

uniform float scanline_strength = 1;
uniform float glow_strength = 0.9;

void vertex() {
	float dist = length(VERTEX.xz);
	VERTEX.y += dist * dist * curvature;
}

vec3 sample_screen(vec2 uv){
	if(uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0){
		return vec3(0.0);
	}
	return texture(screen_tex, uv).rgb;
}

void fragment(){

	vec2 uv = UV;

	// barrel distortion
	vec2 p = uv * 2.0 - 1.0;
	float r2 = dot(p,p);
	p *= 1.0 + barrel * r2;
	uv = p * 0.5 + 0.5;

	vec3 col = sample_screen(uv);

	// ---- SCANLINES ----
// ---- STRONGER SCANLINES ----
	float line = step(0.5, fract(UV.y * 120.0));
	col *= mix(0.55, 1.0, line);
// ---- PHOSPHOR TRIADS ----

float triad = fract(UV.x * 400.0);

vec3 mask;

if (triad < 0.333)
	mask = vec3(1.0, 0.7, 0.7); // red
else if (triad < 0.666)
	mask = vec3(0.7, 1.0, 0.7); // green
else
	mask = vec3(0.7, 0.7, 1.0); // blue

col *= mask;
vec2 t = 1.0 / VIEWPORT_SIZE;

vec3 glow =
    sample_screen(uv + vec2( t.x * 2.0, 0.0)) +
    sample_screen(uv + vec2(-t.x * 2.0, 0.0)) +
    sample_screen(uv + vec2(0.0,  t.y)) +
    sample_screen(uv + vec2(0.0, -t.y));

glow /= 4.0;

col += glow * glow_strength;
float vignette = 1.0 - length(UV * 2.0 - 1.0) * 0.35;
col *= vignette;
	ALBEDO = col;
	ALPHA = 1.0;
}