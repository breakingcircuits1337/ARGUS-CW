## CausalNode3D.gd
## Attached to: MeshInstance3D (sphere) for each causal variable
##
## Visual encoding:
##   • Sphere radius   → current variable value (scaled)
##   • Emission color  → variable color (dim = low, bright = high)
##   • Ring glow       → intervention active (gold pulse)
##   • Particle trail  → high causal influence (outgoing edge strength)
##   • Label billboard → variable name + live value
##   • Orbit ring      → shows parent count

extends Node3D

# ── Config ─────────────────────────────────────────────────────────────────────
@export var variable_id: String = ""
@export var base_radius: float = 0.22
@export var value_scale_range: Vector2 = Vector2(0.16, 0.40)
@export var glow_intensity_range: Vector2 = Vector2(0.4, 3.8)

# ── Node References ────────────────────────────────────────────────────────────
@onready var sphere_mesh:    MeshInstance3D = $SphereMesh
@onready var label_3d:       Label3D        = $Label3D
@onready var value_label:    Label3D        = $ValueLabel
@onready var ring_mesh:      MeshInstance3D = $RingMesh
@onready var particles:      GPUParticles3D = $InfluenceParticles
@onready var intervene_ring: MeshInstance3D = $InterventionRing
@onready var anim_player:    AnimationPlayer = $AnimationPlayer
@onready var area:           Area3D          = $InteractionArea

# ── Material refs (created in _ready) ─────────────────────────────────────────
var sphere_mat: StandardMaterial3D
var ring_mat:   StandardMaterial3D
var intervene_mat: StandardMaterial3D

# ── Runtime State ──────────────────────────────────────────────────────────────
var current_value:    float = 0.0
var target_value:     float = 0.0
var smoothed_value:   float = 0.0
var is_hovered:       bool  = false
var is_selected:      bool  = false
var is_intervened:    bool  = false
var pulse_phase:      float = 0.0
var base_color:       Color = Color.CYAN
var var_ref:          CausalEngine.CausalVariable

const SMOOTH_SPEED := 6.0
const PULSE_SPEED  := 2.8
const HOVER_SCALE  := 1.25

# ── Signals ────────────────────────────────────────────────────────────────────
signal node_hovered(var_id: String)
signal node_selected(var_id: String)
signal intervention_requested(var_id: String, value: float)

func _ready() -> void:
	assert(variable_id != "", "CausalNode3D: variable_id must be set")
	var_ref = CausalEngine.get_var(variable_id)
	assert(var_ref != null, "CausalNode3D: unknown variable_id '%s'" % variable_id)
	base_color = var_ref.color

	_build_materials()
	_build_label()
	_connect_signals()

	# Initial sync
	current_value  = var_ref.value
	smoothed_value = var_ref.value
	_apply_value(smoothed_value)

# ── Material Construction ──────────────────────────────────────────────────────
func _build_materials() -> void:
	sphere_mat = StandardMaterial3D.new()
	sphere_mat.shading_mode        = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	sphere_mat.metallic            = 0.25
	sphere_mat.roughness           = 0.35
	sphere_mat.emission_enabled    = true
	sphere_mat.emission            = base_color
	sphere_mat.emission_energy_multiplier = 1.2
	sphere_mat.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mat.albedo_color        = Color(base_color.r, base_color.g, base_color.b, 0.82)
	sphere_mesh.material_override  = sphere_mat

	ring_mat = StandardMaterial3D.new()
	ring_mat.emission_enabled   = true
	ring_mat.emission           = base_color * 0.6
	ring_mat.emission_energy_multiplier = 0.8
	ring_mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color       = Color(base_color.r, base_color.g, base_color.b, 0.4)
	ring_mesh.material_override = ring_mat

	intervene_mat = StandardMaterial3D.new()
	intervene_mat.emission_enabled = true
	intervene_mat.emission         = Color(1.0, 0.85, 0.1)
	intervene_mat.emission_energy_multiplier = 3.0
	intervene_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	intervene_mat.albedo_color     = Color(1.0, 0.85, 0.1, 0.0)  # invisible until needed
	intervene_ring.material_override = intervene_mat
	intervene_ring.visible = false

func _build_label() -> void:
	label_3d.text              = var_ref.label
	label_3d.font_size         = 18
	label_3d.modulate          = Color.WHITE
	label_3d.billboard         = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.double_sided      = true
	label_3d.position          = Vector3(0, base_radius + 0.28, 0)

	value_label.font_size      = 14
	value_label.modulate       = base_color
	value_label.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	value_label.position       = Vector3(0, base_radius + 0.10, 0)
	value_label.double_sided   = true

# ── Signal Wiring ──────────────────────────────────────────────────────────────
func _connect_signals() -> void:
	CausalEngine.model_updated.connect(_on_model_updated)
	CausalEngine.intervention_applied.connect(_on_intervention_applied)
	area.mouse_entered.connect(_on_hovered)
	area.mouse_exited.connect(_on_unhovered)
	area.input_event.connect(_on_input_event)

func _on_model_updated(var_id: String, new_value: float) -> void:
	if var_id == variable_id:
		target_value = new_value

func _on_intervention_applied(var_id: String, value: float) -> void:
	if var_id == variable_id:
		is_intervened = true
		intervene_ring.visible = true
		_flash_intervention()

# ── Per-Frame Update ───────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	pulse_phase += delta * PULSE_SPEED
	smoothed_value = lerpf(smoothed_value, target_value, SMOOTH_SPEED * delta)
	_apply_value(smoothed_value)
	_update_pulse(delta)
	_update_hover_scale(delta)

func _apply_value(v: float) -> void:
	# Sphere size
	var r := lerpf(value_scale_range.x, value_scale_range.y, v)
	sphere_mesh.scale = Vector3.ONE * r / base_radius

	# Emission brightness
	var glow := lerpf(glow_intensity_range.x, glow_intensity_range.y, v)
	sphere_mat.emission_energy_multiplier = glow

	# Albedo alpha
	sphere_mat.albedo_color = Color(
		base_color.r, base_color.g, base_color.b,
		lerpf(0.55, 0.92, v)
	)

	# Value label
	value_label.text = "%.3f" % v

	# Color shift on extreme values (red-tint when attacker_success is high)
	if variable_id == "attacker_success":
		var danger := Color(1.0, 0.2, 0.2)
		sphere_mat.emission = base_color.lerp(danger, v)

func _update_pulse(delta: float) -> void:
	if is_intervened:
		var pulse := (sin(pulse_phase * 1.8) * 0.5 + 0.5)
		intervene_mat.emission_energy_multiplier = lerpf(1.5, 5.0, pulse)
		intervene_ring.scale = Vector3.ONE * lerpf(1.0, 1.3, pulse)

		# Check if intervention was lifted
		if not CausalEngine.get_var(variable_id).intervened:
			is_intervened = false
			intervene_ring.visible = false

	# Subtle idle breathing pulse
	if not is_intervened and not is_selected:
		var breathe := sin(pulse_phase * 0.7) * 0.05 + 1.0
		ring_mesh.scale = Vector3.ONE * breathe

func _update_hover_scale(delta: float) -> void:
	var target_scale := HOVER_SCALE if (is_hovered or is_selected) else 1.0
	var current := sphere_mesh.scale.x / (base_radius * 1.0)  # approximate
	# We manage hover scaling via a separate scale on the root node's visual child
	var root_scale := scale
	var target_root := Vector3.ONE * (1.15 if is_selected else (1.08 if is_hovered else 1.0))
	scale = root_scale.lerp(target_root, 8.0 * delta)

# ── Interaction ────────────────────────────────────────────────────────────────
func _on_hovered() -> void:
	is_hovered = true
	node_hovered.emit(variable_id)
	ring_mat.emission_energy_multiplier = 2.5

func _on_unhovered() -> void:
	is_hovered = false
	ring_mat.emission_energy_multiplier = 0.8

func _on_input_event(_camera, event: InputEvent, _pos, _normal, _shape) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_selected = !is_selected
			node_selected.emit(variable_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click opens intervention slider (handled by HUD)
			intervention_requested.emit(variable_id, var_ref.value)

func _flash_intervention() -> void:
	var tween := create_tween()
	tween.tween_property(intervene_mat, "emission_energy_multiplier", 8.0, 0.12)
	tween.tween_property(intervene_mat, "emission_energy_multiplier", 3.0, 0.30)

func set_selected(v: bool) -> void:
	is_selected = v
	if v:
		sphere_mat.emission_energy_multiplier = glow_intensity_range.y * 1.5
	else:
		_apply_value(smoothed_value)

# ── Public API ─────────────────────────────────────────────────────────────────
func get_world_center() -> Vector3:
	return global_position

func get_variable_value() -> float:
	return smoothed_value

func highlight_as_parent(child_color: Color) -> void:
	var tween := create_tween()
	tween.tween_property(sphere_mat, "emission", child_color * 1.5, 0.25)
	tween.tween_property(sphere_mat, "emission", base_color,         0.50)

func highlight_as_child(parent_color: Color) -> void:
	highlight_as_parent(parent_color)

func show_counterfactual(cf_value: float) -> void:
	# Display counterfactual value as a ghost sphere
	var ghost := sphere_mesh.duplicate() as MeshInstance3D
	add_child(ghost)
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.25)
	ghost_mat.emission_enabled = true
	ghost_mat.emission = Color.WHITE * 0.3
	ghost.material_override = ghost_mat
	var r := lerpf(value_scale_range.x, value_scale_range.y, cf_value)
	ghost.scale = Vector3.ONE * r / base_radius * 1.05
	# Auto-remove after 3s
	var tween := create_tween()
	tween.tween_property(ghost_mat, "albedo_color:a", 0.0, 2.5)
	tween.tween_callback(ghost.queue_free)
