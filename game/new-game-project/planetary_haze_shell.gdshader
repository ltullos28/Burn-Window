shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_draw_never;

uniform vec4 haze_color : source_color = vec4(1.0, 0.7, 0.45, 1.0);
uniform float rim_exponent : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.0;
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.5;
uniform float emission_strength : hint_range(0.0, 4.0) = 0.5;
uniform vec3 light_dir_world = vec3(0.0, 1.0, 0.0);
uniform float terminator_softness : hint_range(0.01, 1.0) = 0.18;
uniform float terminator_bias : hint_range(-0.5, 0.5) = 0.0;
uniform float night_floor : hint_range(0.0, 1.0) = 0.02;
uniform float radial_falloff : hint_range(0.5, 6.0) = 2.0;

varying vec3 shell_dir_world;

void vertex() {
	vec3 world_center = MODEL_MATRIX[3].xyz;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shell_dir_world = normalize(world_pos - world_center);
}

void fragment() {
	vec3 shell_normal = normalize(shell_dir_world);
	float ndv = clamp(abs(dot(shell_normal, normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_exponent) * rim_strength;
	rim = clamp(rim, 0.0, 1.0);
	float edge_falloff = pow(rim, radial_falloff);
	float light_amount = dot(shell_normal, normalize(light_dir_world));
	float lit = smoothstep(terminator_bias, terminator_bias + terminator_softness, light_amount);
	lit = max(lit, night_floor);

	ALBEDO = haze_color.rgb;
	EMISSION = haze_color.rgb * edge_falloff * emission_strength * lit;
	ALPHA = edge_falloff * alpha_scale * haze_color.a * lit;
}
