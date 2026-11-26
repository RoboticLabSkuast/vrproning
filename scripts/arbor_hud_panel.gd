class_name ArborHudPanel
extends Node3D

## Diegetic 3D Mixed-Reality Control Board rendered via SubViewport + clickable StaticBody3D
## so Quest 3 laser pointers, hand pinch rays, and desktop clicks operate all controls seamlessly.

signal action_requested(action_id: String, payload: String)

const PANEL_W := 740
const PANEL_H := 920
const QUAD_W := 0.62
const QUAD_H := 0.77

var _viewport: SubViewport
var _screen_mesh: MeshInstance3D
var _collider: StaticBody3D

var _lbl_species: Label
var _lbl_health: Label
var _lbl_stats: Label
var _lbl_feedback: Label
var _progress_health: ProgressBar
var _tool_buttons: Dictionary = {}
var _species_buttons: Dictionary = {}
var _btn_passthrough: Button
var _btn_hints: Button


func _ready() -> void:
	_build_ui_viewport()
	_build_3d_board()


func _build_ui_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(PANEL_W, PANEL_H)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var root_panel := PanelContainer.new()
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.10, 0.96)
	style.border_color = Color(0.38, 0.76, 0.48, 0.90)
	style.set_border_width_all(4)
	style.set_corner_radius_all(22)
	style.set_content_margin_all(24)
	root_panel.add_theme_stylebox_override("panel", style)
	_viewport.add_child(root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	root_panel.add_child(vbox)

	var title := Label.new()
	title.text = "VR Pruning  •  Quest 3 Lab"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.76, 0.96, 0.74))
	vbox.add_child(title)

	_lbl_species = Label.new()
	_lbl_species.text = "Honeycrisp Apple (Orchard)"
	_lbl_species.add_theme_font_size_override("font_size", 22)
	_lbl_species.add_theme_color_override("font_color", Color(0.92, 0.94, 0.90))
	vbox.add_child(_lbl_species)

	_lbl_health = Label.new()
	_lbl_health.text = "Canopy Health: 0%  •  Score: 0"
	_lbl_health.add_theme_font_size_override("font_size", 22)
	_lbl_health.add_theme_color_override("font_color", Color(0.45, 0.92, 0.55))
	vbox.add_child(_lbl_health)

	_progress_health = ProgressBar.new()
	_progress_health.min_value = 0
	_progress_health.max_value = 100
	_progress_health.value = 0
	_progress_health.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(_progress_health)

	_lbl_stats = Label.new()
	_lbl_stats.text = "Targets left: 0  |  Collar Cuts: 0  |  Mistakes: 0"
	_lbl_stats.add_theme_font_size_override("font_size", 19)
	_lbl_stats.add_theme_color_override("font_color", Color(0.80, 0.85, 0.82))
	vbox.add_child(_lbl_stats)

	_lbl_feedback = Label.new()
	_lbl_feedback.text = "Aim tool jaw at dead, crossing, or vertical shoots & squeeze trigger."
	_lbl_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_feedback.custom_minimum_size = Vector2(0, 56)
	_lbl_feedback.add_theme_font_size_override("font_size", 20)
	_lbl_feedback.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
	vbox.add_child(_lbl_feedback)

	vbox.add_child(_make_section_label("PRUNING TOOL (Right A / Scroll)"))
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tool_row)
	for pair in [["secateurs", "Secateurs\n<= 2.4 cm"], ["loppers", "Loppers\n<= 5.0 cm"], ["saw", "Pull Saw\nAny Limb"]]:
		var btn := _make_button(pair[1], func(): emit_signal("action_requested", "tool", pair[0]))
		tool_row.add_child(btn)
		_tool_buttons[pair[0]] = btn

	vbox.add_child(_make_section_label("TREE SPECIES"))
	var sp_row := HBoxContainer.new()
	sp_row.add_theme_constant_override("separation", 10)
	vbox.add_child(sp_row)
	for pair in [["apple", "Apple\nOrchard"], ["maple", "Japanese\nMaple"], ["olive", "Garden\nOlive"]]:
		var btn := _make_button(pair[1], func(): emit_signal("action_requested", "species", pair[0]))
		sp_row.add_child(btn)
		_species_buttons[pair[0]] = btn

	vbox.add_child(_make_section_label("MIXED REALITY & TREE PLACEMENT"))
	var mr_row := HBoxContainer.new()
	mr_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mr_row)
	_btn_passthrough = _make_button("MR Passthrough: ON", func(): emit_signal("action_requested", "toggle_passthrough", ""))
	mr_row.add_child(_btn_passthrough)
	_btn_hints = _make_button("Arborist Hints: ON", func(): emit_signal("action_requested", "toggle_hints", ""))
	mr_row.add_child(_btn_hints)

	var pos_row := HBoxContainer.new()
	pos_row.add_theme_constant_override("separation", 10)
	vbox.add_child(pos_row)
	pos_row.add_child(_make_button("Center Tree\nIn Front", func(): emit_signal("action_requested", "recenter_tree", "")))
	pos_row.add_child(_make_button("Tree Height\n+15 cm", func(): emit_signal("action_requested", "height_up", "")))
	pos_row.add_child(_make_button("Tree Height\n-15 cm", func(): emit_signal("action_requested", "height_down", "")))

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 10)
	vbox.add_child(act_row)
	act_row.add_child(_make_button("Undo Cut\n(B / Z)", func(): emit_signal("action_requested", "undo", "")))
	act_row.add_child(_make_button("New Tree\n(R)", func(): emit_signal("action_requested", "new_tree", "")))
	act_row.add_child(_make_button("Scale +", func(): emit_signal("action_requested", "scale_up", "")))
	act_row.add_child(_make_button("Scale -", func(): emit_signal("action_requested", "scale_down", "")))

	var foot := Label.new()
	foot.text = "Quest 3: Right Trigger=Cut | A=Tool | B=Undo | Left Grip=Move Tree | X=MR"
	foot.add_theme_font_size_override("font_size", 16)
	foot.add_theme_color_override("font_color", Color(0.65, 0.72, 0.68))
	vbox.add_child(foot)


func _make_section_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.55, 0.82, 0.62))
	return l


func _make_button(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 62)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func _build_3d_board() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(QUAD_W, QUAD_H)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	mat.roughness = 1.0

	_screen_mesh = MeshInstance3D.new()
	_screen_mesh.mesh = quad
	_screen_mesh.material_override = mat
	add_child(_screen_mesh)

	# Backing frame
	var frame := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(QUAD_W + 0.03, QUAD_H + 0.03, 0.018)
	frame.mesh = fbox
	frame.position = Vector3(0.0, 0.0, -0.012)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.10, 0.14, 0.11)
	fmat.roughness = 0.6
	frame.material_override = fmat
	add_child(frame)

	_collider = StaticBody3D.new()
	_collider.name = "UIPanelCollider"
	_collider.collision_layer = 4
	_collider.collision_mask = 0
	_collider.set_meta("ui_panel", self)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(QUAD_W, QUAD_H, 0.02)
	col.shape = shape
	_collider.add_child(col)
	add_child(_collider)


func click_at_world(world_hit: Vector3) -> bool:
	var local_hit := to_local(world_hit)
	var u := (local_hit.x / QUAD_W) + 0.5
	var v := 0.5 - (local_hit.y / QUAD_H)
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return false
	var vp_pos := Vector2(u * PANEL_W, v * PANEL_H)
	var ev_down := InputEventMouseButton.new()
	ev_down.button_index = MOUSE_BUTTON_LEFT
	ev_down.pressed = true
	ev_down.position = vp_pos
	ev_down.global_position = vp_pos
	_viewport.push_input(ev_down)

	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.position = vp_pos
	ev_up.global_position = vp_pos
	_viewport.push_input(ev_up)
	return true


func update_stats(stats: Dictionary) -> void:
	_lbl_species.text = stats.get("species_title", "")
	_lbl_health.text = "Canopy Health: %d%%  •  Score: %d" % [int(stats.get("health_pct", 0)), int(stats.get("score", 0))]
	_progress_health.value = float(stats.get("health_pct", 0))
	_lbl_stats.text = "Targets left: %d / %d  |  Clean Cuts: %d  |  Mistakes: %d" % [
		int(stats.get("targets_remaining", 0)),
		int(stats.get("targets_total", 0)),
		int(stats.get("perfect_cuts", 0)),
		int(stats.get("mistakes", 0)),
	]


func show_feedback(text: String, color: Color) -> void:
	_lbl_feedback.text = text
	_lbl_feedback.add_theme_color_override("font_color", color)


func set_active_tool(tool_id: String) -> void:
	for k in _tool_buttons:
		var b: Button = _tool_buttons[k]
		b.modulate = Color(0.65, 1.0, 0.72) if k == tool_id else Color.WHITE


func set_active_species(sp_id: String) -> void:
	for k in _species_buttons:
		var b: Button = _species_buttons[k]
		b.modulate = Color(0.65, 1.0, 0.72) if k == sp_id else Color.WHITE


func set_passthrough_state(enabled: bool) -> void:
	_btn_passthrough.text = "MR Passthrough: ON" if enabled else "Garden Sky: ON"


func set_hints_state(enabled: bool) -> void:
	_btn_hints.text = "Arborist Hints: ON" if enabled else "Arborist Hints: OFF"

