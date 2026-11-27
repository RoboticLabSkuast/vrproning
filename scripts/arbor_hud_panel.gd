class_name ArborHudPanel
extends Node3D

## Diegetic 3D Mixed-Reality Control Board rendered via SubViewport + clickable StaticBody3D
## so Quest 3 laser pointers, hand pinch rays, and desktop clicks operate all controls seamlessly.

signal action_requested(action_id: String, payload: String)

const PANEL_W := 740
const PANEL_H := 1100
const QUAD_W := 0.62
const QUAD_H := 0.92

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
var _density_buttons: Dictionary = {}
var _shape_value_labels: Dictionary = {}
var _btn_tab_prune: Button
var _btn_tab_shape: Button
var _tab_prune_box: VBoxContainer
var _tab_shape_box: VBoxContainer
var _leaf_slider: HSlider
var _lbl_leaves: Label
var _btn_passthrough: Button
var _btn_hints: Button
var _btn_add_tree: Button
var _btn_remove_tree: Button

var _pointer_was_down: bool = false
var _last_vp_pos: Vector2 = Vector2(-1.0, -1.0)


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

	var credit := Label.new()
	credit.text = "Built & Developed by CAIML, SKUAST Kashmir"
	credit.add_theme_font_size_override("font_size", 18)
	credit.add_theme_color_override("font_color", Color(0.58, 0.88, 0.74))
	vbox.add_child(credit)

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

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tab_row)
	_btn_tab_prune = _make_button("Prune Lab", func(): show_tab("prune"))
	_btn_tab_prune.custom_minimum_size = Vector2(0, 42)
	tab_row.add_child(_btn_tab_prune)
	_btn_tab_shape = _make_button("Tree Builder (Shape)", func(): show_tab("shape"))
	_btn_tab_shape.custom_minimum_size = Vector2(0, 42)
	tab_row.add_child(_btn_tab_shape)

	_tab_prune_box = VBoxContainer.new()
	_tab_prune_box.add_theme_constant_override("separation", 9)
	vbox.add_child(_tab_prune_box)

	_tab_prune_box.add_child(_make_section_label("PRUNING TOOL (Right A / Scroll)"))
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 10)
	_tab_prune_box.add_child(tool_row)
	for pair in [["secateurs", "Secateurs\n<= 2.4 cm"], ["loppers", "Loppers\n<= 5.0 cm"], ["saw", "Pull Saw\nAny Limb"]]:
		var btn := _make_button(pair[1], func(): emit_signal("action_requested", "tool", pair[0]))
		tool_row.add_child(btn)
		_tool_buttons[pair[0]] = btn

	_tab_prune_box.add_child(_make_section_label("TREE SPECIES"))
	var sp_row := HBoxContainer.new()
	sp_row.add_theme_constant_override("separation", 10)
	_tab_prune_box.add_child(sp_row)
	for pair in [["apple", "Apple\nOrchard"], ["maple", "Japanese\nMaple"], ["olive", "Garden\nOlive"]]:
		var btn := _make_button(pair[1], func(): emit_signal("action_requested", "species", pair[0]))
		sp_row.add_child(btn)
		_species_buttons[pair[0]] = btn

	_lbl_leaves = _make_section_label("LEAVES: 35%  (Drag 0% Zero -> 100% Max)")
	_tab_prune_box.add_child(_lbl_leaves)
	var den_row := HBoxContainer.new()
	den_row.add_theme_constant_override("separation", 10)
	_tab_prune_box.add_child(den_row)

	var b_zero := _make_button("0%", func(): emit_signal("action_requested", "leaf_amount", "0.0"))
	b_zero.size_flags_horizontal = Control.SIZE_FILL
	b_zero.custom_minimum_size = Vector2(76, 46)
	den_row.add_child(b_zero)

	_leaf_slider = HSlider.new()
	_leaf_slider.min_value = 0.0
	_leaf_slider.max_value = 100.0
	_leaf_slider.step = 1.0
	_leaf_slider.value = 35.0
	_leaf_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leaf_slider.custom_minimum_size = Vector2(0, 46)
	var tr_style := StyleBoxFlat.new()
	tr_style.bg_color = Color(0.18, 0.25, 0.21)
	tr_style.set_corner_radius_all(8)
	tr_style.content_margin_top = 10
	tr_style.content_margin_bottom = 10
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.30, 0.78, 0.44)
	fill_style.set_corner_radius_all(8)
	_leaf_slider.add_theme_stylebox_override("slider", tr_style)
	_leaf_slider.add_theme_stylebox_override("grabber_area", fill_style)
	_leaf_slider.add_theme_stylebox_override("grabber_area_highlight", fill_style)
	_leaf_slider.value_changed.connect(func(v: float): emit_signal("action_requested", "leaf_amount", str(v / 100.0)))
	den_row.add_child(_leaf_slider)

	var b_max := _make_button("100%", func(): emit_signal("action_requested", "leaf_amount", "1.0"))
	b_max.size_flags_horizontal = Control.SIZE_FILL
	b_max.custom_minimum_size = Vector2(88, 46)
	den_row.add_child(b_max)

	_tab_prune_box.add_child(_make_section_label("ORCHARD TREES & PLACEMENT"))
	var orchard_row := HBoxContainer.new()
	orchard_row.add_theme_constant_override("separation", 10)
	_tab_prune_box.add_child(orchard_row)
	_btn_add_tree = _make_button("+ Add Tree (1/6)", func(): emit_signal("action_requested", "add_tree", ""))
	_btn_add_tree.custom_minimum_size = Vector2(0, 44)
	orchard_row.add_child(_btn_add_tree)
	_btn_remove_tree = _make_button("- Remove Tree", func(): emit_signal("action_requested", "remove_tree", ""))
	_btn_remove_tree.custom_minimum_size = Vector2(0, 44)
	_btn_remove_tree.disabled = true
	orchard_row.add_child(_btn_remove_tree)

	var mr_row := HBoxContainer.new()
	mr_row.add_theme_constant_override("separation", 10)
	_tab_prune_box.add_child(mr_row)
	_btn_passthrough = _make_button("MR Passthrough: ON", func(): emit_signal("action_requested", "toggle_passthrough", ""))
	mr_row.add_child(_btn_passthrough)
	_btn_hints = _make_button("Arborist Hints: ON", func(): emit_signal("action_requested", "toggle_hints", ""))
	mr_row.add_child(_btn_hints)

	var pos_row := HBoxContainer.new()
	pos_row.add_theme_constant_override("separation", 10)
	_tab_prune_box.add_child(pos_row)
	pos_row.add_child(_make_button("Center Tree\nIn Front", func(): emit_signal("action_requested", "recenter_tree", "")))
	pos_row.add_child(_make_button("Tree Height\n+15 cm", func(): emit_signal("action_requested", "height_up", "")))
	pos_row.add_child(_make_button("Tree Height\n-15 cm", func(): emit_signal("action_requested", "height_down", "")))

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 10)
	_tab_prune_box.add_child(act_row)
	act_row.add_child(_make_button("Undo Cut\n(B / Z)", func(): emit_signal("action_requested", "undo", "")))
	act_row.add_child(_make_button("New Tree\n(R)", func(): emit_signal("action_requested", "new_tree", "")))
	act_row.add_child(_make_button("Scale +", func(): emit_signal("action_requested", "scale_up", "")))
	act_row.add_child(_make_button("Scale -", func(): emit_signal("action_requested", "scale_down", "")))

	_tab_shape_box = VBoxContainer.new()
	_tab_shape_box.visible = false
	_tab_shape_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_tab_shape_box)

	_tab_shape_box.add_child(_make_section_label("SHAPE PRESETS"))
	var pre_row := HBoxContainer.new()
	pre_row.add_theme_constant_override("separation", 8)
	_tab_shape_box.add_child(pre_row)
	for pr in [["apple_dome", "Apple Dome"], ["weeping", "Weeping"], ["upright", "Upright"], ["bonsai", "Bonsai"], ["reset", "Reset"]]:
		var pb := _make_button(pr[1], func(): emit_signal("action_requested", "shape_preset", pr[0]))
		pb.custom_minimum_size = Vector2(0, 42)
		pre_row.add_child(pb)

	_tab_shape_box.add_child(_make_section_label("CUSTOM BRANCH & SIZE GENERATOR"))
	for spec in [
		["trunk_height", "Trunk Height", 0.10],
		["trunk_radius", "Trunk Thickness", 0.008],
		["scaffold_count", "Main Branches", 1],
		["lateral_count", "Sub-Branches", 1],
		["twig_count", "Twig Forks", 1],
		["branch_spread", "Crown Spread", 0.10],
		["branch_angle_deg", "Branch Angle", 8.0],
		["droop", "Droop / Arch", 0.04],
		["gnarl", "Gnarl / Curve", 0.015],
		["leaf_scale", "Leaf Size", 0.03],
	]:
		_add_shape_stepper(_tab_shape_box, spec[0], spec[1], float(spec[2]))

	var sh_bot := HBoxContainer.new()
	sh_bot.add_theme_constant_override("separation", 10)
	_tab_shape_box.add_child(sh_bot)
	var b_seed := _make_button("Random Seed (R)", func(): emit_signal("action_requested", "new_tree", ""))
	b_seed.custom_minimum_size = Vector2(0, 44)
	sh_bot.add_child(b_seed)
	var b_back := _make_button("Back to Prune Lab", func(): show_tab("prune"))
	b_back.custom_minimum_size = Vector2(0, 44)
	sh_bot.add_child(b_back)

	var foot := Label.new()
	foot.text = "Quest 3: Right Trigger=Cut | A=Tool | B=Undo | Left Grip=Move Tree | X=MR"
	foot.add_theme_font_size_override("font_size", 16)
	foot.add_theme_color_override("font_color", Color(0.65, 0.72, 0.68))
	vbox.add_child(foot)
	show_tab("prune")


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
	b.custom_minimum_size = Vector2(0, 52)
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


func update_pointer(has_hit: bool, world_hit: Vector3, is_pressed: bool) -> bool:
	## Forwards continuous hover, press, drag, and release into SubViewport so HSliders drag smoothly in VR & Desktop.
	var pressed_now := false
	if has_hit:
		var local_hit := to_local(world_hit)
		var u := clampf((local_hit.x / QUAD_W) + 0.5, 0.0, 1.0)
		var v := clampf(0.5 - (local_hit.y / QUAD_H), 0.0, 1.0)
		var vp_pos := Vector2(u * PANEL_W, v * PANEL_H)
		if _last_vp_pos.x < 0.0 or vp_pos.distance_squared_to(_last_vp_pos) > 0.25:
			var ev_move := InputEventMouseMotion.new()
			ev_move.position = vp_pos
			ev_move.global_position = vp_pos
			ev_move.relative = Vector2.ZERO if _last_vp_pos.x < 0.0 else (vp_pos - _last_vp_pos)
			ev_move.button_mask = MOUSE_BUTTON_MASK_LEFT if _pointer_was_down else 0
			_viewport.push_input(ev_move)
			_last_vp_pos = vp_pos
		if is_pressed and not _pointer_was_down:
			var ev_down := InputEventMouseButton.new()
			ev_down.button_index = MOUSE_BUTTON_LEFT
			ev_down.pressed = true
			ev_down.position = vp_pos
			ev_down.global_position = vp_pos
			_viewport.push_input(ev_down)
			_pointer_was_down = true
			pressed_now = true
		elif not is_pressed and _pointer_was_down:
			var ev_up := InputEventMouseButton.new()
			ev_up.button_index = MOUSE_BUTTON_LEFT
			ev_up.pressed = false
			ev_up.position = vp_pos
			ev_up.global_position = vp_pos
			_viewport.push_input(ev_up)
			_pointer_was_down = false
	elif _pointer_was_down and not is_pressed:
		var rel_pos := _last_vp_pos if _last_vp_pos.x >= 0.0 else Vector2.ZERO
		var ev_up := InputEventMouseButton.new()
		ev_up.button_index = MOUSE_BUTTON_LEFT
		ev_up.pressed = false
		ev_up.position = rel_pos
		ev_up.global_position = rel_pos
		_viewport.push_input(ev_up)
		_pointer_was_down = false
	return pressed_now


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


func set_leaf_amount_state(amount: float) -> void:
	var pct := int(round(clampf(amount, 0.0, 1.0) * 100.0))
	if is_instance_valid(_lbl_leaves):
		var suffix := "Bare Winter" if pct == 0 else ("Full Canopy" if pct == 100 else "Live Foliage")
		_lbl_leaves.text = "LEAVES: %d%%  (%s)" % [pct, suffix]
	if is_instance_valid(_leaf_slider) and absf(_leaf_slider.value - float(pct)) > 0.5:
		_leaf_slider.set_value_no_signal(float(pct))


func set_leaf_density_state(density_id: String) -> void:
	match density_id:
		"none": set_leaf_amount_state(0.0)
		"sparse": set_leaf_amount_state(0.25)
		"medium": set_leaf_amount_state(0.60)
		"dense": set_leaf_amount_state(1.0)


func set_passthrough_state(enabled: bool) -> void:
	_btn_passthrough.text = "MR Passthrough: ON" if enabled else "Garden Sky: ON"


func set_hints_state(enabled: bool) -> void:
	_btn_hints.text = "Arborist Hints: ON" if enabled else "Arborist Hints: OFF"


func set_orchard_count_state(count: int, max_trees: int) -> void:
	if is_instance_valid(_btn_add_tree):
		_btn_add_tree.text = "+ Add Tree (%d/%d)" % [count, max_trees]
		_btn_add_tree.disabled = (count >= max_trees)
	if is_instance_valid(_btn_remove_tree):
		_btn_remove_tree.disabled = (count <= 1)


func show_tab(tab_id: String) -> void:
	var is_shape := (tab_id == "shape")
	if is_instance_valid(_tab_prune_box):
		_tab_prune_box.visible = not is_shape
	if is_instance_valid(_tab_shape_box):
		_tab_shape_box.visible = is_shape
	if is_instance_valid(_btn_tab_prune):
		_btn_tab_prune.modulate = Color.WHITE if is_shape else Color(0.65, 1.0, 0.72)
	if is_instance_valid(_btn_tab_shape):
		_btn_tab_shape.modulate = Color(0.65, 1.0, 0.72) if is_shape else Color.WHITE


func toggle_shape_tab() -> void:
	if is_instance_valid(_tab_shape_box) and _tab_shape_box.visible:
		show_tab("prune")
	else:
		show_tab("shape")


func _add_shape_stepper(parent_box: VBoxContainer, key: String, title_txt: String, step_val: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent_box.add_child(row)

	var lbl := Label.new()
	lbl.text = title_txt
	lbl.custom_minimum_size = Vector2(220, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.93, 0.89))
	row.add_child(lbl)

	var b_minus := _make_button("-", func(): emit_signal("action_requested", "shape_step", "%s:%s" % [key, str(-step_val)]))
	b_minus.custom_minimum_size = Vector2(105, 38)
	row.add_child(b_minus)

	var val_lbl := Label.new()
	val_lbl.text = "--"
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_lbl.custom_minimum_size = Vector2(140, 0)
	val_lbl.add_theme_font_size_override("font_size", 18)
	val_lbl.add_theme_color_override("font_color", Color(0.58, 0.96, 0.68))
	row.add_child(val_lbl)
	_shape_value_labels[key] = val_lbl

	var b_plus := _make_button("+", func(): emit_signal("action_requested", "shape_step", "%s:%s" % [key, str(step_val)]))
	b_plus.custom_minimum_size = Vector2(105, 38)
	row.add_child(b_plus)


func update_shape_ui(sh: Dictionary) -> void:
	for k in _shape_value_labels:
		var lbl: Label = _shape_value_labels[k]
		if not is_instance_valid(lbl) or not sh.has(k):
			continue
		match k:
			"trunk_height", "branch_spread":
				lbl.text = "%.2f m" % float(sh[k])
			"trunk_radius":
				lbl.text = "%.1f cm" % (float(sh[k]) * 200.0)
			"scaffold_count", "lateral_count", "twig_count":
				lbl.text = "%d" % int(sh[k])
			"branch_angle_deg":
				lbl.text = "%.0f deg" % float(sh[k])
			"droop", "leaf_scale":
				lbl.text = "%.2f" % float(sh[k])
			"gnarl":
				lbl.text = "%.3f" % float(sh[k])
			_:
				lbl.text = str(sh[k])

