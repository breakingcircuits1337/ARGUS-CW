## HUD.gd
## Heads-Up Display — DARPA ops-center interface
##
## Panels:
##   TOP-LEFT    Threat Status Bar (live causal values)
##   TOP-RIGHT   Game Theory readout (Nash / SSE / Regret)
##   BOTTOM-LEFT Variable detail card (on node select)
##   BOTTOM-CENTER Intervention console (on right-click)
##   TOP-CENTER  Alert ticker

extends CanvasLayer

# ── Panel refs ────────────────────────────────────────────────────────────────
@onready var threat_panel:      Control    = $ThreatPanel
@onready var gt_panel:          Control    = $GTPanel
@onready var detail_panel:      Control    = $DetailPanel
@onready var alert_ticker:      Label      = $AlertTicker
@onready var intervention_console: Control = $InterventionConsole
@onready var mini_graph:        Control    = $MiniGraph
@onready var scanline:          ColorRect  = $ScanlineOverlay
@onready var corner_deco:       Control    = $CornerDecorations

# Threat panel labels
@onready var lbl_threat:    Label = $ThreatPanel/VBox/ThreatRow/Val
@onready var lbl_detection: Label = $ThreatPanel/VBox/DetectionRow/Val
@onready var lbl_honeypot:  Label = $ThreatPanel/VBox/HoneypotRow/Val
@onready var lbl_atk_cap:   Label = $ThreatPanel/VBox/AtkCapRow/Val
@onready var lbl_atk_succ:  Label = $ThreatPanel/VBox/AtkSuccRow/Val
@onready var lbl_def_payoff:Label = $ThreatPanel/VBox/DefPayoffRow/Val
@onready var bar_threat:    ProgressBar = $ThreatPanel/VBox/ThreatRow/Bar
@onready var bar_atk_succ:  ProgressBar = $ThreatPanel/VBox/AtkSuccRow/Bar

# GT panel labels
@onready var lbl_nash_d:    Label = $GTPanel/VBox/NashRow/DefVal
@onready var lbl_nash_a:    Label = $GTPanel/VBox/NashRow/AtkVal
@onready var lbl_sse_d:     Label = $GTPanel/VBox/SSERow/DefVal
@onready var lbl_sse_a:     Label = $GTPanel/VBox/SSERow/AtkVal
@onready var lbl_se_gain:   Label = $GTPanel/VBox/GainRow/Val
@onready var lbl_recommendation: Label = $GTPanel/Recommendation
@onready var ne_strategy_bars: Control = $GTPanel/StrategyBars

# Detail panel
@onready var detail_title:  Label = $DetailPanel/Title
@onready var detail_desc:   Label = $DetailPanel/Description
@onready var detail_value:  Label = $DetailPanel/ValueRow/Val
@onready var detail_kind:   Label = $DetailPanel/KindRow/Val
@onready var detail_parents:Label = $DetailPanel/ParentsRow/Val
@onready var detail_children:Label= $DetailPanel/ChildrenRow/Val
@onready var ate_label:     Label = $DetailPanel/ATERow/Val
@onready var cf_button:     Button= $DetailPanel/CFButton

# Intervention console
@onready var ic_title:      Label       = $InterventionConsole/Title
@onready var ic_slider:     HSlider     = $InterventionConsole/Slider
@onready var ic_value_lbl:  Label       = $InterventionConsole/ValueLabel
@onready var ic_apply_btn:  Button      = $InterventionConsole/ApplyBtn
@onready var ic_lift_btn:   Button      = $InterventionConsole/LiftBtn
@onready var ic_cf_btn:     Button      = $InterventionConsole/CFBtn

# Mini graph (time-series sparklines)
@onready var sparkline_canvas: Control  = $MiniGraph/SparklineCanvas

# ── Runtime State ──────────────────────────────────────────────────────────────
var current_var_id: String = ""
var intervention_var_id: String = ""
var tick_timer: float = 0.0
var alert_queue: Array[String] = []
var alert_timer: float = 0.0
var scanline_phase: float = 0.0
var current_ne:  GameTheoryEngine.EquilibriumResult
var current_sse: GameTheoryEngine.EquilibriumResult

const UPDATE_INTERVAL   := 0.08   # 12.5 Hz UI refresh
const ALERT_DISPLAY_SEC := 3.5
const SCANLINE_SPEED    := 0.18

# ── Styling constants ──────────────────────────────────────────────────────────
const COLOR_SAFE    := Color(0.2, 1.0, 0.5)
const COLOR_WARN    := Color(1.0, 0.75, 0.1)
const COLOR_DANGER  := Color(1.0, 0.25, 0.25)
const COLOR_DIM     := Color(0.45, 0.55, 0.70)
const COLOR_BLUE    := Color(0.35, 0.75, 1.00)
const PANEL_DARK    := Color(0.04, 0.07, 0.14, 0.92)

func _ready() -> void:
	_build_ui()
	_connect_signals()
	detail_panel.visible = false
	intervention_console.visible = false
	_push_alert("SYSTEM ONLINE — Causal World Model initialized", COLOR_BLUE)
	_push_alert("Game-theoretic equilibrium solver active", COLOR_BLUE)

# ─────────────────────────────────────────────────────────────────────────────
# UI CONSTRUCTION (procedural — no .tscn dependency)
# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_build_threat_panel()
	_build_gt_panel()
	_build_detail_panel()
	_build_alert_ticker()
	_build_intervention_console()
	_build_mini_graph()
	_build_scanline()
	_build_corner_decorations()

func _build_threat_panel() -> void:
	var panel := _make_panel(Vector2(0, 0), Vector2(310, 310))
	panel.name = "ThreatPanel"
	add_child(panel)

	var header := _make_label("// THREAT STATUS", 11, COLOR_BLUE)
	header.position = Vector2(14, 12)
	panel.add_child(header)

	var sep := _make_separator(Vector2(14, 28), 282)
	panel.add_child(sep)

	var y := 38.0
	for item in [
		["THREAT LEVEL",     "threat_level",     "ThreatRow"],
		["ATTACKER CAP.",    "atk_cap",           "AtkCapRow"],
		["DETECTION RATE",   "detection_rate",    "DetectionRow"],
		["HONEYPOT DENSITY", "honeypot_density",  "HoneypotRow"],
		["ATTACKER SUCCESS", "attacker_success",  "AtkSuccRow"],
		["DEFENDER PAYOFF",  "defender_payoff",   "DefPayoffRow"],
		["INFO ASYMMETRY",   "info_asymmetry",    "InfoAsymRow"],
		["STACKELBERG Δ",    "stackelberg_gain",  "StackRow"],
	]:
		_build_metric_row(panel, item[0], item[2], y)
		y += 32.0

func _build_metric_row(parent: Control, label_text: String,
					   row_name: String, y: float) -> void:
	var row := Control.new()
	row.name = row_name
	row.position = Vector2(14, y)
	row.size = Vector2(282, 28)
	parent.add_child(row)

	var lbl := _make_label(label_text, 10, COLOR_DIM)
	lbl.position = Vector2(0, 5)
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.size = Vector2(130, 6)
	bar.position = Vector2(110, 10)
	bar.min_value = 0.0;  bar.max_value = 1.0;  bar.value = 0.5
	bar.show_percentage = false
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.1, 0.15, 0.25);  bar_style.corner_radius_top_left = 3
	bar_style.corner_radius_top_right = 3;  bar_style.corner_radius_bottom_left = 3
	bar_style.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bar_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COLOR_BLUE;  fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	bar.add_theme_stylebox_override("fill", fill_style)
	row.add_child(bar)

	var val_lbl := _make_label("0.000", 11, Color.WHITE)
	val_lbl.name = "Val"
	val_lbl.position = Vector2(248, 4)
	row.add_child(val_lbl)

func _build_gt_panel() -> void:
	var panel := _make_panel(Vector2(get_viewport().size.x - 330, 0), Vector2(326, 340))
	panel.name = "GTPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -330;  panel.offset_right = 0
	panel.offset_top = 0;  panel.offset_bottom = 340
	add_child(panel)

	var header := _make_label("// GAME THEORY ENGINE", 11, COLOR_BLUE)
	header.position = Vector2(14, 12)
	panel.add_child(header)
	_make_separator(Vector2(14, 28), 298).reparent(panel)

	_gt_section(panel, "NASH EQUILIBRIUM", "NashRow", 38)
	_gt_section(panel, "STACKELBERG SSE",  "SSERow",  100)

	var gain_row := Control.new()
	gain_row.name = "GainRow";  gain_row.position = Vector2(14, 164)
	panel.add_child(gain_row)
	var gain_lbl := _make_label("STACKELBERG GAIN Δ", 10, COLOR_DIM)
	gain_lbl.position = Vector2(0, 4);  gain_row.add_child(gain_lbl)
	var gain_val := _make_label("+0.000", 12, COLOR_BLUE)
	gain_val.name = "Val";  gain_val.position = Vector2(200, 2)
	gain_row.add_child(gain_val)

	var strat_header := _make_label("DEFENDER MIXED STRATEGY (SSE)", 10, COLOR_DIM)
	strat_header.position = Vector2(14, 192);  panel.add_child(strat_header)

	var bars_root := Control.new()
	bars_root.name = "StrategyBars"
	bars_root.position = Vector2(14, 210);  bars_root.size = Vector2(298, 80)
	panel.add_child(bars_root)
	for i in range(GameTheoryEngine.defender_actions.size()):
		var act_lbl := _make_label(GameTheoryEngine.defender_actions[i], 9, COLOR_DIM)
		act_lbl.position = Vector2(0, i * 18)
		bars_root.add_child(act_lbl)
		var bar := ProgressBar.new()
		bar.name = "Bar%d" % i
		bar.size = Vector2(100, 7);  bar.position = Vector2(128, i * 18 + 3)
		bar.min_value = 0.0;  bar.max_value = 1.0;  bar.value = 0.25
		bar.show_percentage = false
		bars_root.add_child(bar)
		var pval := _make_label("25%", 9, Color.WHITE)
		pval.name = "PVal%d" % i;  pval.position = Vector2(236, i * 18)
		bars_root.add_child(pval)

	var rec_lbl := _make_label("→ Awaiting computation...", 10, COLOR_BLUE)
	rec_lbl.name = "Recommendation"
	rec_lbl.position = Vector2(14, 302);  rec_lbl.size.x = 298
	rec_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(rec_lbl)

func _gt_section(parent: Control, title: String, row_name: String, y: float) -> void:
	var title_lbl := _make_label(title, 10, COLOR_DIM)
	title_lbl.position = Vector2(14, y);  parent.add_child(title_lbl)
	var row := Control.new()
	row.name = row_name;  row.position = Vector2(14, y + 16);  row.size = Vector2(298, 38)
	parent.add_child(row)
	_make_label("DEF:", 9, COLOR_DIM).reparent(row)
	(row.get_child(0) as Control).position = Vector2(0, 4)
	var dv := _make_label("0.000", 13, COLOR_SAFE)
	dv.name = "DefVal";  dv.position = Vector2(28, 0);  row.add_child(dv)
	_make_label("ATK:", 9, COLOR_DIM).reparent(row)
	(row.get_child(2) as Control).position = Vector2(110, 4)
	var av := _make_label("0.000", 13, COLOR_DANGER)
	av.name = "AtkVal";  av.position = Vector2(138, 0);  row.add_child(av)

func _build_detail_panel() -> void:
	var panel := _make_panel(Vector2(0, 0), Vector2(310, 280))
	panel.name = "DetailPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_top = -290;  panel.offset_bottom = -10
	panel.offset_left = 10;  panel.offset_right = 320
	panel.visible = false
	add_child(panel)

	var title := _make_label("Variable Detail", 13, Color.WHITE)
	title.name = "Title";  title.position = Vector2(14, 12);  panel.add_child(title)
	_make_separator(Vector2(14, 32), 282).reparent(panel)

	var desc := _make_label("", 11, COLOR_DIM)
	desc.name = "Description";  desc.position = Vector2(14, 42);  desc.size = Vector2(282, 48)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;  panel.add_child(desc)

	for row_data in [
		["VALUE",    "ValueRow",   "0.000"],
		["KIND",     "KindRow",    "—"],
		["PARENTS",  "ParentsRow", "—"],
		["CHILDREN", "ChildrenRow","—"],
		["ATE →Y",   "ATERow",     "computing..."],
	]:
		_detail_row(panel, row_data[0], row_data[1], row_data[2])

	var cf_btn := Button.new()
	cf_btn.name = "CFButton";  cf_btn.text = "Run Counterfactual"
	cf_btn.position = Vector2(14, 246);  cf_btn.size = Vector2(180, 28)
	cf_btn.pressed.connect(_on_cf_requested)
	panel.add_child(cf_btn)

func _detail_row(parent: Control, label: String, row_name: String, default_val: String) -> void:
	var row := Control.new()
	row.name = row_name;  row.size = Vector2(282, 22)
	parent.add_child(row)
	# Position stacked inside panel — use VBox logic manually
	var lbl := _make_label(label + ":", 10, COLOR_DIM)
	lbl.position = Vector2(0, 4);  row.add_child(lbl)
	var val := _make_label(default_val, 11, Color.WHITE)
	val.name = "Val";  val.position = Vector2(90, 2);  row.add_child(val)

func _build_alert_ticker() -> void:
	var bg := ColorRect.new()
	bg.name = "AlertBG"
	bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bg.offset_top = 0;  bg.offset_bottom = 26
	bg.offset_left = 310;  bg.offset_right = -330
	bg.color = Color(0.02, 0.04, 0.10, 0.85)
	add_child(bg)

	var ticker := Label.new()
	ticker.name = "AlertTicker"
	ticker.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ticker.offset_top = 4;  ticker.offset_bottom = 26
	ticker.offset_left = 320;  ticker.offset_right = -340
	ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ticker.add_theme_font_size_override("font_size", 11)
	ticker.add_theme_color_override("font_color", COLOR_BLUE)
	add_child(ticker)

func _build_intervention_console() -> void:
	var panel := _make_panel(Vector2(0, 0), Vector2(340, 195))
	panel.name = "InterventionConsole"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -170;  panel.offset_right = 170
	panel.offset_top = -205;  panel.offset_bottom = -10
	panel.visible = false
	add_child(panel)

	var title := _make_label("// INTERVENTION  do(X = x)", 11, Color(1.0, 0.85, 0.1))
	title.name = "Title";  title.position = Vector2(14, 12);  panel.add_child(title)
	_make_separator(Vector2(14, 30), 312).reparent(panel)

	var var_lbl := _make_label("Variable: —", 11, Color.WHITE)
	var_lbl.name = "VarLabel";  var_lbl.position = Vector2(14, 40);  panel.add_child(var_lbl)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = 0.0;  slider.max_value = 1.0;  slider.step = 0.001
	slider.value = 0.5;  slider.size = Vector2(312, 20);  slider.position = Vector2(14, 68)
	slider.value_changed.connect(_on_slider_changed)
	panel.add_child(slider)

	var val_lbl := _make_label("0.500", 18, Color(1.0, 0.85, 0.1))
	val_lbl.name = "ValueLabel";  val_lbl.position = Vector2(140, 92)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(val_lbl)

	var apply_btn := Button.new()
	apply_btn.name = "ApplyBtn";  apply_btn.text = "APPLY do(X)"
	apply_btn.position = Vector2(14, 130);  apply_btn.size = Vector2(94, 36)
	apply_btn.pressed.connect(_on_apply_intervention)
	panel.add_child(apply_btn)

	var lift_btn := Button.new()
	lift_btn.name = "LiftBtn";  lift_btn.text = "LIFT"
	lift_btn.position = Vector2(116, 130);  lift_btn.size = Vector2(60, 36)
	lift_btn.pressed.connect(_on_lift_intervention)
	panel.add_child(lift_btn)

	var cf_btn := Button.new()
	cf_btn.name = "CFBtn";  cf_btn.text = "COUNTERFACTUAL"
	cf_btn.position = Vector2(184, 130);  cf_btn.size = Vector2(142, 36)
	cf_btn.pressed.connect(_on_cf_from_console)
	panel.add_child(cf_btn)

func _build_mini_graph() -> void:
	var panel := _make_panel(Vector2(0, 0), Vector2(310, 140))
	panel.name = "MiniGraph"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -320;  panel.offset_right = -10
	panel.offset_top = -150;  panel.offset_bottom = -10
	add_child(panel)

	var header := _make_label("// TEMPORAL TRACE", 10, COLOR_BLUE)
	header.position = Vector2(14, 10);  panel.add_child(header)

	var canvas := Control.new()
	canvas.name = "SparklineCanvas"
	canvas.position = Vector2(14, 28);  canvas.size = Vector2(282, 100)
	canvas.draw.connect(_draw_sparklines.bind(canvas))
	panel.add_child(canvas)

func _build_scanline() -> void:
	var cr := ColorRect.new()
	cr.name = "ScanlineOverlay"
	cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cr.color = Color.TRANSPARENT
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Scanline effect handled in _process via shader (assigned in _ready)
	add_child(cr)

func _build_corner_decorations() -> void:
	var c := Control.new()
	c.name = "CornerDecorations"
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(_draw_corner_deco.bind(c))
	add_child(c)

# ─────────────────────────────────────────────────────────────────────────────
# PER-FRAME UPDATE
# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	tick_timer += delta
	scanline_phase = fmod(scanline_phase + delta * SCANLINE_SPEED, 1.0)

	if tick_timer >= UPDATE_INTERVAL:
		tick_timer = 0.0
		_refresh_threat_panel()
		_refresh_gt_panel()
		if mini_graph: mini_graph.get_node("SparklineCanvas").queue_redraw()

	# Alert ticker
	alert_timer -= delta
	if alert_timer <= 0.0 and alert_queue.size() > 0:
		var msg := alert_queue.pop_front()
		alert_ticker.text = "[ %s ]" % msg
		alert_timer = ALERT_DISPLAY_SEC

	if corner_deco: corner_deco.queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
# DATA REFRESH
# ─────────────────────────────────────────────────────────────────────────────
func _refresh_threat_panel() -> void:
	var var_ids := ["threat_level","atk_cap","detection_rate","honeypot_density",
					"attacker_success","defender_payoff","info_asymmetry","stackelberg_gain"]
	var row_names := ["ThreatRow","AtkCapRow","DetectionRow","HoneypotRow",
					  "AtkSuccRow","DefPayoffRow","InfoAsymRow","StackRow"]
	var colors    := [COLOR_DANGER, COLOR_DANGER, COLOR_SAFE, COLOR_BLUE,
					  COLOR_DANGER, COLOR_SAFE, COLOR_BLUE, COLOR_BLUE]

	var tp := get_node_or_null("ThreatPanel")
	if not tp: return

	for i in range(var_ids.size()):
		var v := CausalEngine.get_var(var_ids[i])
		if v == null: continue
		var row := tp.get_node_or_null(row_names[i])
		if row == null: continue
		var val_lbl := row.get_node_or_null("Val") as Label
		var bar     := row.get_node_or_null("Bar") as ProgressBar
		if val_lbl:
			val_lbl.text = "%.3f" % v.value
			val_lbl.add_theme_color_override("font_color",
				_value_to_color(v.value, colors[i]))
		if bar:
			bar.value = v.value
			var fill := StyleBoxFlat.new()
			fill.bg_color = _value_to_color(v.value, colors[i])
			fill.corner_radius_top_left = 3;  fill.corner_radius_top_right = 3
			bar.add_theme_stylebox_override("fill", fill)

func _refresh_gt_panel() -> void:
	var gtp := get_node_or_null("GTPanel")
	if not gtp: return

	if current_ne:
		var nr := gtp.get_node_or_null("NashRow")
		if nr:
			(nr.get_node("DefVal") as Label).text = "%.3f" % current_ne.defender_payoff
			(nr.get_node("AtkVal") as Label).text = "%.3f" % current_ne.attacker_payoff

	if current_sse:
		var sr := gtp.get_node_or_null("SSERow")
		if sr:
			(sr.get_node("DefVal") as Label).text = "%.3f" % current_sse.defender_payoff
			(sr.get_node("AtkVal") as Label).text = "%.3f" % current_sse.attacker_payoff

		var gain_v := gtp.get_node_or_null("GainRow/Val") as Label
		var gain   := GameTheoryEngine.stackelberg_advantage()
		if gain_v:
			gain_v.text = "%+.3f" % gain
			gain_v.add_theme_color_override("font_color",
				COLOR_SAFE if gain > 0.0 else COLOR_DANGER)

		# Strategy bars
		var bars := gtp.get_node_or_null("StrategyBars")
		if bars and current_sse.defender_strategy.size() > 0:
			for i in range(current_sse.defender_strategy.size()):
				var b := bars.get_node_or_null("Bar%d" % i) as ProgressBar
				var p := bars.get_node_or_null("PVal%d" % i) as Label
				var prob := current_sse.defender_strategy[i]
				if b: b.value = prob
				if p: p.text = "%d%%" % roundi(prob * 100)

		var rec := gtp.get_node_or_null("Recommendation") as Label
		if rec: rec.text = "→ " + GameTheoryEngine.get_action_recommendation()

# ─────────────────────────────────────────────────────────────────────────────
# DRAW CALLBACKS
# ─────────────────────────────────────────────────────────────────────────────
func _draw_sparklines(canvas: Control) -> void:
	var w := canvas.size.x
	var h := canvas.size.y
	canvas.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.04, 0.08, 0.6))

	var tracked := ["threat_level","detection_rate","attacker_success","defender_payoff"]
	var colors   := [COLOR_DANGER, COLOR_SAFE, Color(1,0.3,0.3), COLOR_BLUE]

	for si in range(tracked.size()):
		var v := CausalEngine.get_var(tracked[si])
		if v == null or v.history.size() < 2: continue
		var hist := v.history
		var n := hist.size()
		var col := colors[si]
		for i in range(1, n):
			var x0 := (float(i - 1) / (n - 1)) * w
			var x1 := (float(i) / (n - 1)) * w
			var y0 := h - hist[i - 1] * h
			var y1 := h - hist[i]     * h
			canvas.draw_line(Vector2(x0, y0), Vector2(x1, y1), col * 0.85, 1.2)

	# Labels
	for i in range(tracked.size()):
		canvas.draw_string(ThemeDB.fallback_font,
			Vector2(4, 12 + i * 16),
			tracked[i].substr(0, 12),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, colors[i])

func _draw_corner_deco(canvas: Control) -> void:
	var s := canvas.size
	var c := Color(0.25, 0.55, 1.0, 0.55)
	var l := 28.0;  var t := 2.0
	# Top-left
	canvas.draw_line(Vector2(0, 0), Vector2(l, 0), c, t)
	canvas.draw_line(Vector2(0, 0), Vector2(0, l), c, t)
	# Top-right
	canvas.draw_line(Vector2(s.x, 0), Vector2(s.x - l, 0), c, t)
	canvas.draw_line(Vector2(s.x, 0), Vector2(s.x, l),     c, t)
	# Bottom-left
	canvas.draw_line(Vector2(0, s.y), Vector2(l, s.y),     c, t)
	canvas.draw_line(Vector2(0, s.y), Vector2(0, s.y - l), c, t)
	# Bottom-right
	canvas.draw_line(Vector2(s.x, s.y), Vector2(s.x - l, s.y),     c, t)
	canvas.draw_line(Vector2(s.x, s.y), Vector2(s.x,     s.y - l), c, t)
	# Scan line
	var scan_y := scanline_phase * s.y
	canvas.draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y),
		Color(0.3, 0.6, 1.0, 0.06), 2.0)

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API (called by CausalWorldModel.gd)
# ─────────────────────────────────────────────────────────────────────────────
func update_ne(eq: GameTheoryEngine.EquilibriumResult) -> void:
	current_ne = eq

func update_sse(eq: GameTheoryEngine.EquilibriumResult) -> void:
	current_sse = eq

func show_variable_detail(v: CausalEngine.CausalVariable) -> void:
	current_var_id = v.id
	var panel := get_node_or_null("DetailPanel")
	if not panel: return
	panel.visible = true
	(panel.get_node("Title") as Label).text = v.label
	(panel.get_node("Description") as Label).text = v.description
	_set_detail_row(panel, "ValueRow",    "%.4f" % v.value)
	_set_detail_row(panel, "KindRow",     "Exogenous" if v.kind == CausalEngine.VarKind.EXOGENOUS else "Endogenous")
	_set_detail_row(panel, "ParentsRow",  ", ".join(v.parents)  if v.parents.size()  > 0 else "none")
	_set_detail_row(panel, "ChildrenRow", ", ".join(v.children) if v.children.size() > 0 else "none")
	_set_detail_row(panel, "ATERow", "computing...")
	# Async ATE computation
	var thr := Thread.new()
	thr.start(func():
		if v.children.size() > 0:
			var ate := CausalEngine.compute_ate(v.id, v.children[0], 100)
			call_deferred("_set_detail_row", panel, "ATERow",
				"%.4f → %s" % [ate, v.children[0]])
	)

func hide_variable_detail() -> void:
	var panel := get_node_or_null("DetailPanel")
	if panel: panel.visible = false
	current_var_id = ""

func show_tooltip(var_id: String, v: CausalEngine.CausalVariable) -> void:
	_push_alert("%s = %.3f  |  %d parents, %d children" % [
		v.label, v.value, v.parents.size(), v.children.size()], COLOR_DIM)

func open_intervention_slider(var_id: String, current_val: float) -> void:
	intervention_var_id = var_id
	var ic := get_node_or_null("InterventionConsole")
	if not ic: return
	ic.visible = true
	(ic.get_node("Title") as Label).text = "// INTERVENTION  do(%s = x)" % var_id
	var slider := ic.get_node("Slider") as HSlider
	slider.value = current_val
	(ic.get_node("ValueLabel") as Label).text = "%.3f" % current_val

func _set_detail_row(panel: Control, row_name: String, text: String) -> void:
	var row := panel.get_node_or_null(row_name)
	if row:
		var lbl := row.get_node_or_null("Val") as Label
		if lbl: lbl.text = text

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTION HANDLERS
# ─────────────────────────────────────────────────────────────────────────────
func _on_slider_changed(value: float) -> void:
	var ic := get_node_or_null("InterventionConsole")
	if ic: (ic.get_node("ValueLabel") as Label).text = "%.3f" % value

func _on_apply_intervention() -> void:
	if intervention_var_id == "": return
	var ic := get_node_or_null("InterventionConsole")
	var val := (ic.get_node("Slider") as HSlider).value
	CausalEngine.intervene(intervention_var_id, val)
	_push_alert("Intervention: do(%s = %.3f) applied" % [intervention_var_id, val],
		Color(1.0, 0.85, 0.1))
	ic.visible = false

func _on_lift_intervention() -> void:
	if intervention_var_id == "": return
	CausalEngine.lift_intervention(intervention_var_id)
	_push_alert("Intervention on %s lifted" % intervention_var_id, COLOR_SAFE)
	var ic := get_node_or_null("InterventionConsole")
	if ic: ic.visible = false

func _on_cf_from_console() -> void:
	if intervention_var_id == "": return
	var ic := get_node_or_null("InterventionConsole")
	var val := (ic.get_node("Slider") as HSlider).value
	# Counterfactual: what would defender_payoff be if we intervened here?
	var cf := CausalEngine.counterfactual("defender_payoff",
		{intervention_var_id: val},
		{intervention_var_id: CausalEngine.get_var(intervention_var_id).value})
	_push_alert("CF: defender_payoff = %.3f under do(%s=%.3f)" % [cf, intervention_var_id, val],
		Color(0.7, 0.4, 1.0))

func _on_cf_requested() -> void:
	if current_var_id == "": return
	var v := CausalEngine.get_var(current_var_id)
	if v.children.size() == 0: return
	var cf := CausalEngine.counterfactual(v.children[0],
		{current_var_id: 1.0 - v.value},  # flip the value
		{current_var_id: v.value})
	_push_alert("CF[%s flipped]: %s → %.3f" % [v.label, v.children[0], cf],
		Color(0.7, 0.4, 1.0))

# ─────────────────────────────────────────────────────────────────────────────
# ALERT SYSTEM
# ─────────────────────────────────────────────────────────────────────────────
func _push_alert(msg: String, color: Color = COLOR_BLUE) -> void:
	alert_queue.append(msg)
	if alert_ticker:
		alert_ticker.add_theme_color_override("font_color", color)

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
func _make_panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos;  p.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_DARK
	style.border_color = Color(0.15, 0.35, 0.7, 0.8)
	style.border_width_left   = 1;  style.border_width_right  = 1
	style.border_width_top    = 1;  style.border_width_bottom = 1
	style.corner_radius_top_left     = 3;  style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left  = 3;  style.corner_radius_bottom_right = 3
	p.add_theme_stylebox_override("panel", style)
	return p

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _make_separator(pos: Vector2, width: float) -> ColorRect:
	var cr := ColorRect.new()
	cr.position = pos;  cr.size = Vector2(width, 1)
	cr.color = Color(0.15, 0.35, 0.7, 0.5)
	return cr

func _value_to_color(v: float, base_color: Color) -> Color:
	if base_color == COLOR_DANGER:
		return COLOR_SAFE.lerp(COLOR_DANGER, v)
	elif base_color == COLOR_SAFE:
		return COLOR_DIM.lerp(COLOR_SAFE, v)
	return base_color

func _connect_signals() -> void:
	CausalEngine.model_updated.connect(_on_causal_update)
	GameTheoryEngine.ne_computed.connect(func(eq): current_ne = eq)
	GameTheoryEngine.sse_computed.connect(func(eq): current_sse = eq)
	GameTheoryEngine.equilibrium_shifted.connect(func(old, new_eq):
		_push_alert("EQ SHIFT: def_payoff %+.3f → %+.3f" % [old["def_payoff"], new_eq["def_payoff"]],
			COLOR_WARN))
	CausalEngine.intervention_applied.connect(func(vid, val):
		_push_alert("do(%s = %.3f)" % [vid, val], Color(1.0, 0.85, 0.1)))
	CausalEngine.counterfactual_computed.connect(func(_q, result):
		_push_alert("Counterfactual result: %.4f" % result, Color(0.7, 0.4, 1.0)))

func _on_causal_update(_id: String, _val: float) -> void:
	pass  # Batched refresh via tick_timer
