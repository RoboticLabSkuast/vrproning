shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.36;
uniform float wind_speed = 1.75;
uniform float wind_strength = 0.022;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 backlight_color : source_color = vec4(0.32, 0.44, 0.12, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.42;

void vertex() {
	// UV.y = 1.0 at petiole/twig anchor, UV.y = 0.0 at outer leaf tips
	float tip_weight = clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = world_pos.x * 3.4 + world_pos.y * 2.5 + world_pos.z * 2.9;
	float wave = sin(TIME * wind_speed + phase) * 0.65 + cos(TIME * (wind_speed * 1.65) + phase * 1.4) * 0.35;
	VERTEX.x += wave * wind_strength * tip_weight * tip_weight;
	VERTEX.y += cos(TIME * wind_speed * 1.2 + phase) * (wind_strength * 0.45) * tip_weight;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	if (tex.a < alpha_scissor) {
		discard;
	}
	// Vertex color R carries ambient-occlusion/sunlight depth across the bough
	float ao = clamp(COLOR.r, 0.58, 1.08);
	ALBEDO = tex.rgb * tint_color.rgb * ao;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.95;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.48;
	BACKLIGHT = backlight_color.rgb;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
