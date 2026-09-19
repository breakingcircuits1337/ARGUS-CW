## CausalWorldModel.gd
## Main Scene Controller
##
## Responsibilities:
##   • Build the physical room environment (DARPA ops-center aesthetic)
##   • Instantiate CausalNode3D + CausalEdge3D for every variable/edge
##   • Wire together CausalEngine ↔ GameTheoryEngine ↔ UI
##   • Handle scene-level input (camera control, node selection, interventions)
##   • Drive the ambient simulation loop

extends Node3D

# ── Scene References ───────────────────────────────────────────────────────────
@onready var camera_pivot:     Node3D        = $CameraPivot
@onready var camera:           Camera3D      = $CameraPivot/Camera3D
@onready var dag_root:         Node3D        = $DAGRoot
@onready var hud:              CanvasLayer   = $HUD
@onready var intervention_ui:  Control       = $HUD/InterventionConsole
@onready var room_env:         WorldEnvironment = $WorldEnvironment
@onready var ambient_light:    DirectionalLight3D = $DirectionalLight3D
@onready var scan_line_overlay: MeshInstance3D    = $ScanLineOverlay
@onready var room_builder:     Node3D        = $RoomGeometry

# ── Runtime Collections ────────────────────────────────────────────────────────
var node_map:   Dictionary = {}   # variable_id -> CausalNode3D
var edge_map:   Dictionary = {}   # "from->to"   -> CausalEdge3D
var selected_id: String    = ""

# ── Prefabs (set via @export or code) ─────────────────────────────────────────
var causal_node_scene := preload("res://scenes/CausalNode.tscn")
var causal_edge_scene := preload("res://scenes/CausalEdge.tscn")

# ── Camera Orbit State ─────────────────────────────────────────────────────────
var cam_yaw:   float = 0.0
var cam_pitch: float = -20.0
var cam_dist:  float = 14.0
var cam_target: Vector3 = Vector3.ZERO
var orbiting:  bool = false
var last_mouse: Vector2 = Vector2.ZERO

const CAM_PITCH_MIN := -55.0
const CAM_PITCH_MAX :=  15.0
const CAM_DIST_MIN  :=   5.0
const CAM_DIST_MAX  :=  28.0
const CAM_ORBIT_SPEED := 0.3
const CAM_PAN_SPEED   := 0.012

# ── Simulation ─────────────────────────────────────────────────────────────────
var sim_time:    float = 0.0
var threat_pulse_timer: float = 0.0

func _ready() -> void:
	_build_room()
	_build_dag_nodes()
	_build_dag_edges()
	_setup_environment()
	_connect_engine_signals()
	_init_camera()
	hud.get_node("InterventionConsole").visible = false
	print("[CWM] Causal World Model initialized. Variables: %d  Edges: %d" % [
		node_map.size(), edge_map.size()])

# ─────────────────────────────────────────────────────────────────────────────
# ROOM GEOMETRY
# ─────────────────────────────────────────────────────────────────────────────
func _build_room() -> void:
	var rm := room_builder

	# Floor — dark brushed metal grid
	_add_box(rm, Vector3(0, -1.2, 0), Vector3(26.0, 0.12, 22.0),
		Color(0.04, 0.06, 0.10), "floor")

	# Ceiling
	_add_box(rm, Vector3(0, 6.2, 0), Vector3(26.0, 0.12, 22.0),
		Color(0.03, 0.04, 0.07), "ceiling")

	# Back wall
	_add_box(rm, Vector3(0, 2.5, -11.0), Vector3(26.0, 10.0, 0.12),
		Color(0.04, 0.06, 0.12), "wall_back")

	# Front wall
	_add_box(rm, Vector3(0, 2.5, 11.0), Vector3(26.0, 10.0, 0.12),
		Color(0.04, 0.06, 0.12), "wall_front")

	# Side walls
	_add_box(rm, Vector3(-13.0, 2.5, 0), Vector3(0.12, 10.0, 22.0),
		Color(0.04, 0.06, 0.12), "wall_left")
	_add_box(rm, Vector3( 13.0, 2.5, 0), Vector3(0.12, 10.0, 22.0),
		Color(0.04, 0.06, 0.12), "wall_right")

	# Floor grid lines (thin emissive strips)
	for i in range(-5, 6):
		_add_emissive_strip(rm,
			Vector3(float(i) * 2.2, -1.13, 0),
			Vector3(0.015, 0.01, 22.0),
			Color(0.1, 0.4, 0.9) * 0.18)
		_add_emissive_strip(rm,
			Vector3(0, -1.13, float(i) * 2.0),
			Vector3(26.0, 0.01, 0.015),
			Color(0.1, 0.4, 0.9) * 0.18)

	# Ceiling track lights
	for i in range(-2, 3):
		_add_point_light(rm,
			Vector3(float(i) * 4.5, 5.6, 0),
			Color(0.35, 0.55, 1.0), 0.6, 12.0)

	# Wall accent lights (blue strip along base of walls)
	for z in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_add_emissive_strip(rm, Vector3(-12.8, -0.5, z), Vector3(0.02, 0.08, 1.8),
			Color(0.1, 0.3, 1.0) * 0.7)
		_add_emissive_strip(rm, Vector3( 12.8, -0.5, z), Vector3(0.02, 0.08, 1.8),
			Color(0.1, 0.3, 1.0) * 0.7)

	# Console desks (back wall)
	for x in [-6.0, 0.0, 6.0]:
		_add_console_desk(rm, Vector3(x, -0.9, -8.0))

	# Central holographic platform
	_add_holo_platform(rm, Vector3(0, -1.08, 0))

	# Status screens on back wall
	for i in range(3):
		_add_wall_screen(rm, Vector3(-5.5 + i * 5.5, 3.2, -10.85),
			Vector3(4.5, 2.8, 0.06))

func _add_box(parent: Node3D, pos: Vector3, size: Vector3,
			   color: Color, name_: String) -> MeshInstance3D:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh  = box
	mi.position = pos
	mi.name  = name_
	var mat  := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.85
	mat.metallic     = 0.4
	mi.material_override = mat
	parent.add_child(mi)
	# Add static body for collision
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	(cs.shape as BoxShape3D).size = size
	sb.add_child(cs)
	sb.position = pos
	parent.add_child(sb)
	return mi

func _add_emissive_strip(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size;  mi.mesh = box;  mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.0
	mat.albedo_color = color * 0.3
	mi.material_override = mat
	parent.add_child(mi)

func _add_point_light(parent: Node3D, pos: Vector3, color: Color,
					   energy: float, range_: float) -> void:
	var light := OmniLight3D.new()
	light.position         = pos
	light.light_color      = color
	light.light_energy     = energy
	light.omni_range       = range_
	light.shadow_enabled   = false
	parent.add_child(light)

func _add_console_desk(parent: Node3D, pos: Vector3) -> void:
	# Desk surface
	_add_box(parent, pos + Vector3(0, 0, 0),   Vector3(3.8, 0.08, 1.2), Color(0.06, 0.08, 0.14), "desk")
	_add_box(parent, pos + Vector3(0, -0.4, 0), Vector3(3.6, 0.7, 1.0), Color(0.04, 0.06, 0.10), "desk_body")
	# Monitor (emissive face)
	var mon_pos := pos + Vector3(0, 0.6, 0.2)
	_add_box(parent, mon_pos, Vector3(3.2, 0.9, 0.04), Color(0.02, 0.04, 0.08), "monitor")
	_add_emissive_strip(parent, mon_pos + Vector3(0, 0, 0.03),
		Vector3(3.0, 0.7, 0.01),
		Color(0.1, 0.6, 1.0) * 0.25)

func _add_holo_platform(parent: Node3D, pos: Vector3) -> void:
	# Octagonal base
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius    = 3.5
	cyl_mesh.bottom_radius = 3.5
	cyl_mesh.height        = 0.12
	cyl_mesh.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = cyl_mesh;  mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.05, 0.08, 0.15)
	mat.metallic      = 0.7
	mat.roughness     = 0.2
	mat.emission_enabled = true
	mat.emission      = Color(0.1, 0.4, 1.0) * 0.4
	mi.material_override = mat
	parent.add_child(mi)

	# Ring glow at platform edge
	var ring := CylinderMesh.new()
	ring.top_radius    = 3.48
	ring.bottom_radius = 3.48
	ring.height        = 0.06
	ring.radial_segments = 64
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring;  ring_mi.position = pos + Vector3(0, 0.09, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.2, 0.6, 1.0)
	ring_mat.emission_energy_multiplier = 2.5
	ring_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.6)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mi.material_override = ring_mat
	parent.add_child(ring_mi)

func _add_wall_screen(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	_add_box(parent, pos, size, Color(0.02, 0.03, 0.06), "screen_frame")
	var screen_pos := pos + Vector3(0, 0, size.z * 0.55)
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size * Vector3(0.9, 0.85, 0.01)
	mi.mesh  = box;  mi.position = screen_pos
	var mat  := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.25, 0.5) * 0.5
	mat.albedo_color = Color(0.02, 0.05, 0.1)
	mi.material_override = mat
	parent.add_child(mi)

# ─────────────────────────────────────────────────────────────────────────────
# DAG INSTANTIATION
# ─────────────────────────────────────────────────────────────────────────────
func _build_dag_nodes() -> void:
	for var_id in CausalEngine.variables:
		var v: CausalEngine.CausalVariable = CausalEngine.variables[var_id]

		var node_instance: Node3D
		if ResourceLoader.exists("res://scenes/CausalNode.tscn"):
			node_instance = causal_node_scene.instantiate()
		else:
			node_instance = _build_node_fallback(v)

		node_instance.name = "Node_" + var_id
		node_instance.position = v.position_3d
		if node_instance.has_method("set"):
			node_instance.set("variable_id", var_id)

		dag_root.add_child(node_instance)
		node_map[var_id] = node_instance

		# Connect interaction signals
		if node_instance.has_signal("node_selected"):
			node_instance.node_selected.connect(_on_node_selected)
		if node_instance.has_signal("node_hovered"):
			node_instance.node_hovered.connect(_on_node_hovered)
		if node_instance.has_signal("intervention_requested"):
			node_instance.intervention_requested.connect(_on_intervention_requested)

func _build_node_fallback(v: CausalEngine.CausalVariable) -> Node3D:
	# Fallback for when the .tscn isn't loaded — builds node procedurally
	var root := Node3D.new()

	var sphere_mi := MeshInstance3D.new()
	var sphere_m  := SphereMesh.new()
	sphere_m.radius = 0.22;  sphere_m.height = 0.44;  sphere_m.radial_segments = 24
	sphere_mi.mesh  = sphere_m
	root.add_child(sphere_mi)

	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = v.color
	mat.emission_energy_multiplier = 1.5
	mat.albedo_color = Color(v.color.r, v.color.g, v.color.b, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mi.material_override = mat

	var lbl := Label3D.new()
	lbl.text = v.label
	lbl.font_size = 16
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position  = Vector3(0, 0.38, 0)
	lbl.modulate  = v.color
	root.add_child(lbl)

	var val_lbl := Label3D.new()
	val_lbl.name = "ValueLabel"
	val_lbl.font_size = 13
	val_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	val_lbl.position  = Vector3(0, 0.22, 0)
	val_lbl.modulate  = Color.WHITE * 0.8
	root.add_child(val_lbl)

	# Area3D for interaction
	var area := Area3D.new()
	var cs   := CollisionShape3D.new()
	cs.shape  = SphereShape3D.new()
	(cs.shape as SphereShape3D).radius = 0.38
	area.add_child(cs)
	root.add_child(area)
	root.set_meta("sphere_mat", mat)
	root.set_meta("val_label",  val_lbl)
	root.set_meta("var_id",     v.id)
	return root

func _build_dag_edges() -> void:
	for key in CausalEngine.edges:
		var e: CausalEngine.CausalEdge = CausalEngine.edges[key]
		if not node_map.has(e.from_id) or not node_map.has(e.to_id): continue

		var edge_instance: Node3D
		if ResourceLoader.exists("res://scenes/CausalEdge.tscn"):
			edge_instance = causal_edge_scene.instantiate()
		else:
			edge_instance = _build_edge_fallback(e)

		if edge_instance.has_method("set"):
			edge_instance.set("from_id", e.from_id)
			edge_instance.set("to_id",   e.to_id)
		if edge_instance.has_method("init"):
			edge_instance.init(node_map[e.from_id], node_map[e.to_id])

		dag_root.add_child(edge_instance)
		edge_map[key] = edge_instance

func _build_edge_fallback(e: CausalEngine.CausalEdge) -> Node3D:
	# Inline edge renderer — draws with ImmediateMesh each frame
	var root := Node3D.new()
	root.set_script(load("res://scripts/world/CausalEdge3D.gd"))
	root.set_meta("from_id", e.from_id)
	root.set_meta("to_id",   e.to_id)
	return root

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT / LIGHTING
# ─────────────────────────────────────────────────────────────────────────────
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode    = Environment.BG_COLOR
	env.background_color   = Color(0.012, 0.018, 0.035)
	env.ambient_light_color  = Color(0.08, 0.12, 0.22)
	env.ambient_light_energy = 0.35
	env.glow_enabled       = true
	env.glow_intensity     = 1.2
	env.glow_bloom         = 0.12
	env.glow_blend_mode    = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_levels[2]     = true
	env.glow_levels[3]     = true
	env.ssao_enabled       = true
	env.ssao_radius        = 1.2
	env.ssao_intensity     = 2.0
	env.tonemap_mode       = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure   = 1.1
	env.fog_enabled        = true
	env.fog_density        = 0.006
	env.fog_light_color    = Color(0.05, 0.08, 0.18)
	room_env.environment   = env

	ambient_light.light_color   = Color(0.5, 0.65, 1.0)
	ambient_light.light_energy  = 0.25
	ambient_light.shadow_enabled = true
	ambient_light.rotation_degrees = Vector3(-45, 30, 0)

# ─────────────────────────────────────────────────────────────────────────────
# CAMERA
# ─────────────────────────────────────────────────────────────────────────────
func _init_camera() -> void:
	camera.fov = 62.0
	_apply_camera()

func _apply_camera() -> void:
	var yaw_rad   := deg_to_rad(cam_yaw)
	var pitch_rad := deg_to_rad(cam_pitch)
	camera_pivot.position = cam_target
	camera.position = Vector3(
		cam_dist * cos(pitch_rad) * sin(yaw_rad),
		cam_dist * sin(pitch_rad),
		cam_dist * cos(pitch_rad) * cos(yaw_rad)
	)
	camera.look_at(cam_target, Vector3.UP)

# ─────────────────────────────────────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	# Orbit drag
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			orbiting = event.pressed
			last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = max(CAM_DIST_MIN, cam_dist - 0.8)
			_apply_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = min(CAM_DIST_MAX, cam_dist + 0.8)
			_apply_camera()

	if event is InputEventMouseMotion and orbiting:
		var delta := event.position - last_mouse
		last_mouse = event.position
		cam_yaw   -= delta.x * CAM_ORBIT_SPEED
		cam_pitch  = clamp(cam_pitch + delta.y * CAM_ORBIT_SPEED,
						   CAM_PITCH_MIN, CAM_PITCH_MAX)
		_apply_camera()

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				CausalEngine.running = !CausalEngine.running
			KEY_R:
				CausalEngine.lift_all_interventions()
				_on_interventions_cleared()
			KEY_ESCAPE:
				_deselect_all()
			KEY_F1:
				_focus_on_variable("attacker_success")
			KEY_F2:
				_focus_on_variable("defender_payoff")
			KEY_F3:
				_focus_on_variable("stackelberg_gain")
			KEY_1, KEY_2, KEY_3, KEY_4:
				var idx := event.keycode - KEY_1
				_trigger_scenario(idx)

# ─────────────────────────────────────────────────────────────────────────────
# ENGINE SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────────────────────
func _connect_engine_signals() -> void:
	CausalEngine.model_updated.connect(_on_model_updated)
	CausalEngine.intervention_applied.connect(_on_intervention_applied)
	GameTheoryEngine.ne_computed.connect(_on_ne_computed)
	GameTheoryEngine.sse_computed.connect(_on_sse_computed)
	GameTheoryEngine.equilibrium_shifted.connect(_on_equilibrium_shifted)

func _on_model_updated(var_id: String, new_value: float) -> void:
	# Update fallback label if CausalNode3D script not in use
	if node_map.has(var_id):
		var n := node_map[var_id]
		if n.has_meta("val_label"):
			var lbl := n.get_meta("val_label") as Label3D
			if lbl: lbl.text = "%.3f" % new_value
		if n.has_meta("sphere_mat"):
			var mat := n.get_meta("sphere_mat") as StandardMaterial3D
			if mat:
				var v: CausalEngine.CausalVariable = CausalEngine.get_var(var_id)
				mat.emission_energy_multiplier = lerpf(0.5, 3.5, new_value)

func _on_intervention_applied(var_id: String, _value: float) -> void:
	# Flash all outgoing edges from this variable
	for key in edge_map:
		if key.begins_with(var_id + "->"):
			if edge_map[key].has_method("flash"):
				edge_map[key].flash()

func _on_ne_computed(eq: GameTheoryEngine.EquilibriumResult) -> void:
	if hud.has_method("update_ne"):
		hud.update_ne(eq)

func _on_sse_computed(eq: GameTheoryEngine.EquilibriumResult) -> void:
	if hud.has_method("update_sse"):
		hud.update_sse(eq)

func _on_equilibrium_shifted(old_eq: Dictionary, new_eq: Dictionary) -> void:
	# Visual alert when equilibrium changes significantly
	_trigger_alert_flash(Color(0.9, 0.7, 0.1))
	print("[GT] Equilibrium shift: %.3f → %.3f" % [old_eq["def_payoff"], new_eq["def_payoff"]])

func _on_interventions_cleared() -> void:
	for key in node_map:
		if node_map[key].has_method("set_selected"):
			node_map[key].set_selected(false)

# ─────────────────────────────────────────────────────────────────────────────
# NODE INTERACTION
# ─────────────────────────────────────────────────────────────────────────────
func _on_node_selected(var_id: String) -> void:
	if selected_id == var_id:
		_deselect_all()
		return
	_deselect_all()
	selected_id = var_id
	if node_map[var_id].has_method("set_selected"):
		node_map[var_id].set_selected(true)
	_highlight_causal_neighborhood(var_id)
	if hud.has_method("show_variable_detail"):
		hud.show_variable_detail(CausalEngine.get_var(var_id))

func _on_node_hovered(var_id: String) -> void:
	if hud.has_method("show_tooltip"):
		hud.show_tooltip(var_id, CausalEngine.get_var(var_id))

func _on_intervention_requested(var_id: String, current_val: float) -> void:
	if hud.has_method("open_intervention_slider"):
		hud.open_intervention_slider(var_id, current_val)

func _deselect_all() -> void:
	for key in node_map:
		if node_map[key].has_method("set_selected"):
			node_map[key].set_selected(false)
	for key in edge_map:
		if edge_map[key].has_method("set_highlighted"):
			edge_map[key].set_highlighted(false)
	selected_id = ""
	if hud.has_method("hide_variable_detail"):
		hud.hide_variable_detail()

func _highlight_causal_neighborhood(var_id: String) -> void:
	var v: CausalEngine.CausalVariable = CausalEngine.get_var(var_id)
	# Highlight parent nodes
	for pid in v.parents:
		if node_map.has(pid) and node_map[pid].has_method("highlight_as_parent"):
			node_map[pid].highlight_as_parent(v.color)
		var ekey := "%s->%s" % [pid, var_id]
		if edge_map.has(ekey) and edge_map[ekey].has_method("set_highlighted"):
			edge_map[ekey].set_highlighted(true)
	# Highlight child nodes
	for cid in v.children:
		if node_map.has(cid) and node_map[cid].has_method("highlight_as_child"):
			node_map[cid].highlight_as_child(v.color)
		var ekey := "%s->%s" % [var_id, cid]
		if edge_map.has(ekey) and edge_map[ekey].has_method("set_highlighted"):
			edge_map[ekey].set_highlighted(true)

func _focus_on_variable(var_id: String) -> void:
	if not node_map.has(var_id): return
	var target := node_map[var_id].position
	var tween  := create_tween()
	tween.tween_property(camera_pivot, "position", target, 0.6).set_ease(Tween.EASE_OUT)
	cam_target = target
	_on_node_selected(var_id)

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO PRESETS
# ─────────────────────────────────────────────────────────────────────────────
func _trigger_scenario(idx: int) -> void:
	CausalEngine.lift_all_interventions()
	match idx:
		0:  # Nation-state APT
			CausalEngine.intervene("atk_cap",      0.95)
			CausalEngine.intervene("net_exposure",  0.70)
			print("[SCENARIO] Nation-State APT: high capability, moderate exposure")
		1:  # Zero-day campaign
			CausalEngine.intervene("atk_cap",      0.85)
			CausalEngine.intervene("def_budget",    0.40)
			CausalEngine.intervene("net_exposure",  0.90)
			print("[SCENARIO] Zero-Day Campaign: budget-constrained defender")
		2:  # Well-funded defender
			CausalEngine.intervene("def_budget",    0.95)
			CausalEngine.intervene("honeypot_density", 0.45)
			print("[SCENARIO] Stackelberg Defender: maximum honeypot coverage")
		3:  # Ransomware
			CausalEngine.intervene("atk_cap",      0.70)
			CausalEngine.intervene("net_exposure",  0.85)
			CausalEngine.intervene("def_budget",    0.55)
			print("[SCENARIO] Ransomware: broad exposure, opportunistic attacker")

# ─────────────────────────────────────────────────────────────────────────────
# PER-FRAME
# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	sim_time += delta
	threat_pulse_timer += delta

	# Pulsing platform glow based on threat level
	var threat := CausalEngine.get_var("threat_level")
	if threat:
		var pulse_speed := lerpf(0.5, 3.0, threat.value)
		var pulse_intensity := sin(sim_time * pulse_speed) * 0.5 + 0.5
		# (Platform glow updated via material property — accessed via scene path)

	# Auto-rotate DAG slowly for fly-through feel when idle
	if not orbiting and Input.get_mouse_button_mask() == 0:
		dag_root.rotation_degrees.y += 0.02 * delta * 60.0

func _trigger_alert_flash(color: Color) -> void:
	# Flash room lights briefly on equilibrium shift
	var orig_color := ambient_light.light_color
	var tween := create_tween()
	tween.tween_property(ambient_light, "light_color",  color,      0.1)
	tween.tween_property(ambient_light, "light_energy", 1.2,        0.1)
	tween.tween_property(ambient_light, "light_color",  orig_color, 0.6)
	tween.tween_property(ambient_light, "light_energy", 0.25,       0.6)
