// causal_node.gdshader
// Holographic sphere shader for CausalNode3D
//
// Features:
//   • Fresnel edge glow (stronger at silhouette)
//   • Animated scanline pattern (vertical bands)
//   • Pulsing interior hexagonal grid
//   • Value-driven emission intensity
//   • Intervention state: gold shimmer overlay
//   • Depth fog blend for depth cueing

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ── Uniforms ──────────────────────────────────────────────────────────────────
uniform vec4  base_color       : source_color = vec4(0.2, 0.8, 1.0, 0.85);
uniform vec4  emission_color   : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 6.0) = 1.5;
uniform float variable_value   : hint_range(0.0, 1.0) = 0.5;
uniform float time_offset      = 0.0;
uniform bool  is_intervened    = false;
uniform bool  is_selected      = false;
uniform vec4  intervention_color : source_color = vec4(1.0, 0.85, 0.1, 1.0);

// ── Vertex ────────────────────────────────────────────────────────────────────
void vertex() {
	// Subtle vertex displacement — "breathing" wobble on high-value nodes
	float wobble_amp   = variable_value * 0.018;
	float wobble_speed = 1.4 + variable_value * 2.0;
	float phase        = TIME * wobble_speed + time_offset;
	VERTEX += NORMAL * (sin(phase + VERTEX.y * 4.0) * wobble_amp);
}

// ── Fragment ──────────────────────────────────────────────────────────────────
void fragment() {
	vec3 normal   = normalize(NORMAL);
	vec3 view_dir = normalize(VIEW);

	// ── Fresnel ───────────────────────────────────────────────────────────────
	float fresnel = pow(1.0 - clamp(dot(normal, view_dir), 0.0, 1.0), 3.2);
	float fresnel_strength = 0.55 + variable_value * 0.45;

	// ── Scanlines (horizontal bands across sphere surface) ────────────────────
	float scan_v   = UV.y * 28.0 + TIME * 0.6;
	float scanline = smoothstep(0.38, 0.42, fract(scan_v)) * 0.18;

	// ── Interior hex grid ─────────────────────────────────────────────────────
	// Simple repeating grid approximation using UV
	vec2 grid_uv = UV * 12.0;
	vec2 grid_id = floor(grid_uv);
	vec2 grid_f  = fract(grid_uv);
	float grid_line = max(
		smoothstep(0.92, 1.0, grid_f.x),
		smoothstep(0.92, 1.0, grid_f.y)
	);
	float grid_intensity = grid_line * (0.10 + variable_value * 0.12);

	// Animated pulse outward from center
	float dist_from_center = length(UV - vec2(0.5)) * 2.0;
	float pulse_wave = sin(dist_from_center * 8.0 - TIME * 3.0) * 0.5 + 0.5;
	float pulse      = pulse_wave * (1.0 - dist_from_center) * 0.15 * variable_value;

	// ── Core albedo ───────────────────────────────────────────────────────────
	vec3 albedo = base_color.rgb;
	albedo = mix(albedo, albedo * 1.4, fresnel * fresnel_strength);
	albedo += vec3(grid_intensity);
	albedo += vec3(scanline * 0.5);
	albedo += emission_color.rgb * pulse;

	// ── Intervention shimmer ─────────────────────────────────────────────────
	if (is_intervened) {
		float shimmer_wave = sin(UV.x * 20.0 + TIME * 4.0) * 0.5 + 0.5;
		float shimmer      = shimmer_wave * fresnel * 0.7;
		albedo = mix(albedo, intervention_color.rgb, shimmer * 0.55);
	}

	// ── Selection highlight ───────────────────────────────────────────────────
	if (is_selected) {
		float sel_pulse = sin(TIME * 3.5) * 0.5 + 0.5;
		albedo += emission_color.rgb * sel_pulse * 0.3;
	}

	// ── Emission ──────────────────────────────────────────────────────────────
	vec3 emission = emission_color.rgb * emission_strength;
	emission += emission_color.rgb * fresnel * fresnel_strength * 1.8;
	emission += emission_color.rgb * pulse * 2.0;
	if (is_intervened) {
		float int_pulse = sin(TIME * 5.0) * 0.5 + 0.5;
		emission = mix(emission, intervention_color.rgb * 4.0, int_pulse * 0.4);
	}

	// ── Alpha ─────────────────────────────────────────────────────────────────
	float alpha = base_color.a;
	alpha = mix(alpha * 0.7, alpha, fresnel * 0.5 + 0.5);
	alpha += grid_intensity * 0.3;

	ALBEDO     = clamp(albedo, vec3(0.0), vec3(1.0));
	EMISSION   = clamp(emission, vec3(0.0), vec3(8.0));
	ALPHA      = clamp(alpha, 0.0, 1.0);
	METALLIC   = 0.2;
	ROUGHNESS  = 0.3 - variable_value * 0.1;
	SPECULAR   = 0.6;
}
