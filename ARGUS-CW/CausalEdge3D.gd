## CausalEdge3D.gd
## Renders a directed causal edge between two CausalNode3D instances.
##
## Visual encoding:
##   • Line thickness    → causal strength (|dY/dX|)
##   • Color             → sign (+1 cyan/green, -1 red/orange)
##   • Animated dashes   → information flow direction (parent → child)
##   • Opacity           → edge active vs. do-surgery removed
##   • Arrowhead         → direction indicator at child end
##   • Particles         → high-strength edges get flowing particles

extends Node3D

@export var from_id: String = ""
@export var to_id:   String = ""

var from_node: Node3D
var to_node:   Node3D

var line_mesh:     ImmediateMesh
var line_instance: MeshInstance3D
var arrow_mesh:    MeshInstance3D
var particles:     GPUParticles3D

var edge_mat:      StandardMaterial3D
var arrow_mat:     StandardMaterial3D

var current_strength: float = 0.5
var current_sign:     int   = 1
var is_active:        bool  = true
var flow_phase:       float = 0.0
var highlight_timer:  float = 0.0

const BASE_WIDTH     := 0.012
const MAX_WIDTH      := 0.048
const FLOW_SPEED     := 1.4
const POS_COLOR      := Color(0.15, 0.85, 0.6)   # teal-green for promoting edges
const NEG_COLOR      := Color(0.95, 0.25, 0.25)   # red for inhibiting edges
const INACTIVE_COLOR := Color(0.3, 0.3, 0.3)

signal edge_clicked(from_id: String, to_id: String)

func _ready() -> void:
	_build_geometry()
	CausalEngine.model_updated.connect(_on_model_updated)

func init(from: Node3D, to: Node3D) -> void:
	from_node = from;  to_node = to

func _build_geometry() -> void:
	# --- Line (ImmediateMesh, rebuilt each frame) ---
	line_mesh     = ImmediateMesh.new()
	line_instance = MeshInstance3D.new()
	line_instance.mesh = line_mesh
	add_child(line_instance)

	edge_mat = StandardMaterial3D.new()
	edge_mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.vertex_color_use_as_albedo = true
	edge_mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.emission_enabled   = true
	edge_mat.no_depth_test      = false
	line_instance.material_override = edge_mat

	# --- Arrowhead (small cone) ---
	var cone := CylinderMesh.new()
	cone.top_radius    = 0.0
	cone.bottom_radius = 0.06
	cone.height        = 0.14
	cone.radial_segments = 8
	arrow_mesh = MeshInstance3D.new()
	arrow_mesh.mesh = cone
	add_child(arrow_mesh)

	arrow_mat = StandardMaterial3D.new()
	arrow_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.emission_enabled = true
	arrow_mat.emission         = POS_COLOR
	arrow_mat.albedo_color     = POS_COLOR
	arrow_mesh.material_override = arrow_mat

func _process(delta: float) -> void:
	if from_node == null or to_node == null: return
	flow_phase += delta * FLOW_SPEED * (2.0 if current_strength > 0.6 else 1.0)
	if highlight_timer > 0.0: highlight_timer -= delta

	var from_pos: Vector3 = from_node.global_position
	var to_pos:   Vector3 = to_node.global_position

	# Sync strength from causal engine
	var edge := CausalEngine.get_edge(from_id, to_id)
	if edge != null:
		current_strength = lerpf(current_strength, edge.strength, 4.0 * delta)
		current_sign     = edge.sign
		is_active        = edge.is_active

	_draw_tube(from_pos, to_pos)
	_update_arrow(from_pos, to_pos)

func _draw_tube(from_pos: Vector3, to_pos: Vector3) -> void:
	line_mesh.clear_surfaces()
	if not is_active: return

	var color := _get_color()
	if highlight_timer > 0.0:
		color = color.lerp(Color.WHITE, highlight_timer * 2.0)

	var dir       := (to_pos - from_pos)
	var length    := dir.length()
	if length < 0.01: return
	var dir_norm  := dir / length

	# Perpendicular for quad width
	var cam_dir   := Vector3(0, 1, 0.3).normalized()
	var perp      := dir_norm.cross(cam_dir).normalized()

	var width := lerpf(BASE_WIDTH, MAX_WIDTH, current_strength)

	# Draw dashed flow quads along the edge
	var n_segments := 20
	var dash_len   := 0.06
	var gap_len    := 0.04

	line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg_len := length / n_segments
	for i in range(n_segments):
		var t0 := float(i) / n_segments
		var t1 := float(i + 1) / n_segments

		# Animated offset for flow
		var phase_offset := fmod(t0 * length + flow_phase * 0.3, dash_len + gap_len)
		if phase_offset > dash_len: continue   # gap

		var p0 := from_pos.lerp(to_pos, t0)
		var p1 := from_pos.lerp(to_pos, t1)
		var alpha := lerpf(0.3, 0.9, current_strength) * (1.0 if is_active else 0.2)
		var c := Color(color.r, color.g, color.b, alpha)

		# Two triangles forming a quad
		var v0 := p0 + perp * width * 0.5
		var v1 := p0 - perp * width * 0.5
		var v2 := p1 - perp * width * 0.5
		var v3 := p1 + perp * width * 0.5

		line_mesh.surface_set_color(c);  line_mesh.surface_add_vertex(v0)
		line_mesh.surface_set_color(c);  line_mesh.surface_add_vertex(v1)
		line_mesh.surface_set_color(c);  line_mesh.surface_add_vertex(v2)
		line_mesh.surface_set_color(c);  line_mesh.surface_add_vertex(v0)
		line_mesh.surface_set_color(c);  line_mesh.surface_add_vertex(v2)
		line_mesh.surface_set_color(c);  line_mesh.surface_add_vertex(v3)

	line_mesh.surface_end()

	# Update emission
	edge_mat.emission = color * current_strength * 1.5

func _update_arrow(from_pos: Vector3, to_pos: Vector3) -> void:
	var dir      := to_pos - from_pos
	var dist     := dir.length()
	if dist < 0.1: return

	# Place arrow at 85% along the edge (just before child sphere)
	var t        := 0.85
	var arrow_pos := from_pos.lerp(to_pos, t)
	arrow_mesh.global_position = arrow_pos

	# Orient cone to point along edge direction
	var dir_norm := dir.normalized()
	var up       := Vector3.UP if absf(dir_norm.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	arrow_mesh.basis = Basis.looking_at(dir_norm, up).rotated(
		arrow_mesh.basis.x.normalized(), -PI * 0.5
	)

	var color := _get_color()
	arrow_mat.emission   = color * 1.8
	arrow_mat.albedo_color = color
	arrow_mesh.visible   = is_active

func _get_color() -> Color:
	if not is_active:
		return INACTIVE_COLOR
	var base := POS_COLOR if current_sign > 0 else NEG_COLOR
	# Strength-modulate brightness
	return base * lerpf(0.5, 1.2, current_strength)

func flash() -> void:
	highlight_timer = 0.6

func set_highlighted(v: bool) -> void:
	if v: highlight_timer = 99.0
	else: highlight_timer = 0.0
