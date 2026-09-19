// causal_edge.gdshader
// Animated directed-edge shader for causal DAG arrows
//
// Features:
//   • Directional flow animation (parent → child)
//   • Strength-driven thickness via emission
//   • Sign-coded color (positive=teal, negative=red)
//   • Dashed pattern with animated offset
//   • Surgical cut: fades when do-intervention removes the edge

shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled,
            unshaded, shadows_disabled;

uniform vec4  color_positive : source_color = vec4(0.15, 0.9, 0.6, 1.0);
uniform vec4  color_negative : source_color = vec4(0.95, 0.25, 0.25, 1.0);
uniform float edge_sign      : hint_range(-1.0, 1.0) = 1.0;
uniform float strength       : hint_range(0.0, 1.0) = 0.5;
uniform float flow_speed     = 1.4;
uniform float dash_frequency = 6.0;
uniform float dash_duty      = 0.55;
uniform bool  is_active      = true;
uniform float cut_progress   : hint_range(0.0, 1.0) = 0.0;  // 1.0 = fully cut (do-surgery)

void fragment() {
	if (!is_active) {
		ALBEDO = vec3(0.15);
		ALPHA  = 0.08;
		return;
	}

	// ── Base color from edge sign ─────────────────────────────────────────────
	vec3 col = mix(color_negative.rgb, color_positive.rgb,
				   clamp(edge_sign * 0.5 + 0.5, 0.0, 1.0));

	// ── Animated flow along UV.x (0=parent, 1=child) ─────────────────────────
	float flow_phase = UV.x * dash_frequency - TIME * flow_speed;
	float dash_val   = fract(flow_phase);
	float dash_mask  = step(1.0 - dash_duty, dash_val);

	// ── Cross-axis falloff (thin center bright, fade at edges) ───────────────
	float edge_falloff = 1.0 - abs(UV.y * 2.0 - 1.0);  // UV.y in [0,1]
	edge_falloff = pow(edge_falloff, 1.4);

	// ── Strength modulation ───────────────────────────────────────────────────
	float intensity = strength * (0.6 + 0.4 * dash_mask) * edge_falloff;

	// ── Do-surgery cut effect ─────────────────────────────────────────────────
	// When an intervention removes this edge, it visually "cuts" from center out
	if (cut_progress > 0.0) {
		float cut_zone  = abs(UV.x - 0.5) * 2.0;
		float cut_mask  = step(cut_zone, cut_progress);
		vec3 cut_color  = vec3(1.0, 0.3, 0.05);
		col             = mix(col, cut_color, cut_mask * 0.8);
		intensity       = mix(intensity, 0.0, cut_progress * cut_mask);
	}

	// ── Arrowhead brightening at child end (UV.x → 1) ────────────────────────
	float arrow_zone   = smoothstep(0.80, 0.95, UV.x);
	float arrow_pulse  = sin(TIME * 3.0) * 0.5 + 0.5;
	intensity += arrow_zone * arrow_pulse * 0.4 * strength;

	ALBEDO = col * intensity * 2.5;
	ALPHA  = clamp(intensity * 1.5, 0.0, 1.0);
}
