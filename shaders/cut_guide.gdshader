shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 ring_color : source_color = vec4(0.20, 0.95, 0.45, 0.85);
uniform float pulse_speed = 4.0;

void fragment() {
	float pulse = 0.72 + 0.28 * sin(TIME * pulse_speed);
	ALBEDO = ring_color.rgb;
	ALPHA = ring_color.a * pulse;
}

