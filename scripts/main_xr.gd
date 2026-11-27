extends Node3D

## Main orchestrator for VR Pruning: initializes Meta Quest 3 OpenXR + Color Passthrough +
## Hand Tracking + Touch Controllers, with automatic Desktop 3D preview fallback.

var xr_interface: OpenXRInterface
var xr_active: bool = false
var passthrough_enabled: bool = true
var tree_seed: int = 101

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $SunLight
@onready var garden_env: Node3D = $GardenBackdrop
@onready var tree_rig: TreeRig = $TreeRig
@onready var audio_fx: AudioFX = $AudioFX
@onready var hud_panel: ArborHudPanel = $ArborHudPanel

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_ctrl: XRController3D = $XROrigin3D/LeftController
@onready var right_ctrl: XRController3D = $XROrigin3D/RightController
@onready var left_ray: RayCast3D = $XROrigin3D/LeftController/LeftRay
@onready var right_ray: RayCast3D = $XROrigin3D/RightController/RightRay
@onready var right_hand_aim: XRController3D = $XROrigin3D/RightHandAim
@onready var left_hand_aim: XRController3D = $XROrigin3D/LeftHandAim
@onready var left_hand_ray: RayCast3D = $XROrigin3D/LeftHandAim/LeftHandRay
@onready var right_hand_ray: RayCast3D = $XROrigin3D/RightHandAim/RightHandRay

@onready var desktop_rig: Node3D = $DesktopPreview
@onready var desktop_cam: Camera3D = $DesktopPreview/DesktopCamera

var pruning_tool: PruningTool
var _trees: Array[TreeRig] = []
var _active_tree: TreeRig
var _grabbed_tree: TreeRig
var _undo_tree_history: Array[TreeRig] = []
var _trigger_val_right: float = 0.0
var _trigger_val_left: float = 0.0
var _trigger_just_pressed: bool = false
var _hand_pinch_val: float = 0.0
var _hand_pinch_val_left: float = 0.0
var _hand_pinch_just_pressed: bool = false

var _grabbing_tree: bool = false
var _grab_offset: Vector3 = Vector3.ZERO
var _grab_yaw_offset: float = 0.0
var _recenter_frames: int = 3

# Desktop fallback state
var _desk_yaw: float = 0.08
var _desk_pitch: float = -0.16
var _desk_tool_depth: float = 1.65
var _desk_looking: bool = false
var _desk_click_pending: bool = false
var _desk_bar_label: Label


const MAX_ORCHARD_TREES := 6


func _ready() -> void:
	_active_tree = tree_rig
	_register_tree_rig(tree_rig)
	hud_panel.action_requested.connect(_on_hud_action)

	pruning_tool = PruningTool.new()
	pruning_tool.name = "PruningTool"
	pruning_tool.tree_rig = tree_rig
	pruning_tool.tree_rigs = _trees
	pruning_tool.audio_fx = audio_fx
	pruning_tool.tool_changed.connect(func(tid): hud_panel.set_active_tool(tid))

	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		_init_openxr_session()
	else:
		_init_desktop_preview()

	_emit_orchard_stats()
	hud_panel.set_active_tool(pruning_tool.current_tool)
	hud_panel.set_active_species(tree_rig.species_id)
	hud_panel.set_leaf_amount_state(tree_rig.leaf_amount)
	hud_panel.set_hints_state(tree_rig.hints_enabled)
	hud_panel.set_orchard_count_state(_trees.size(), MAX_ORCHARD_TREES)
	hud_panel.update_shape_ui(tree_rig.get_effective_shape())


func _init_openxr_session() -> void:
	xr_active = true
	desktop_rig.visible = false
	desktop_cam.current = false
	xr_camera.current = true

	var vp := get_viewport()
	vp.use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if RenderingServer.get_rendering_device():
		vp.vrs_mode = Viewport.VRS_XR

	xr_interface.session_begun.connect(_on_xr_session_begun)
	right_ctrl.add_child(pruning_tool)
	# Ergonomic wrist tilt for holding secateurs/loppers/saw naturally in Quest 3
	pruning_tool.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	pruning_tool.position = Vector3(0.0, -0.015, -0.025)

	left_ctrl.button_pressed.connect(_on_left_ctrl_btn_pressed)
	left_ctrl.button_released.connect(_on_left_ctrl_btn_released)
	left_ctrl.input_float_changed.connect(_on_left_ctrl_float)
	right_ctrl.button_pressed.connect(_on_right_ctrl_btn_pressed)
	right_ctrl.input_float_changed.connect(_on_right_ctrl_float)

	right_hand_aim.button_pressed.connect(_on_right_hand_btn_pressed)
	right_hand_aim.input_float_changed.connect(_on_right_hand_float)
	left_hand_aim.button_pressed.connect(_on_left_hand_btn_pressed)
	left_hand_aim.input_float_changed.connect(_on_left_hand_float)

	set_passthrough_enabled(true)


func _on_xr_session_begun() -> void:
	var rates: Array = xr_interface.get_available_display_refresh_rates()
	# Cap standalone Quest 3 MR refresh rate at 80 Hz so GPU/thermal headroom stays steady without dynamic blur.
	var best := 72.0
	if rates.size() > 0:
		best = float(rates[0])
		for r in rates:
			if float(r) > best and float(r) <= 80.0:
				best = float(r)
		xr_interface.set_display_refresh_rate(best)
	Engine.physics_ticks_per_second = int(best)


func _init_desktop_preview() -> void:
	xr_active = false
	xr_origin.visible = false
	xr_camera.current = false
	desktop_rig.visible = true
	desktop_cam.current = true
	desktop_cam.rotation = Vector3(_desk_pitch, _desk_yaw, 0.0)
	add_child(pruning_tool)
	set_passthrough_enabled(false)
	_build_laptop_overlay()
	hud_panel.show_feedback("Laptop Mode: Hover branch & Left-Click to prune! Arrows/Right-Drag to look.", Color(0.55, 0.90, 1.0))


func _build_laptop_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LaptopOverlay"
	add_child(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	layer.add_child(margin)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.11, 0.09, 0.86)
	sb.border_color = Color(0.35, 0.72, 0.46, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	_desk_bar_label = Label.new()
	_desk_bar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desk_bar_label.text = "Built & Developed by CAIML, SKUAST Kashmir  |  Click: Cut | Arrows/Right-Drag: Look | WASD/Scroll: Move"
	_desk_bar_label.add_theme_font_size_override("font_size", 14)
	_desk_bar_label.add_theme_color_override("font_color", Color(0.86, 0.96, 0.88))
	hbox.add_child(_desk_bar_label)

	var quick_actions := [
		["1: Secateurs", func(): pruning_tool.select_tool("secateurs")],
		["2: Loppers", func(): pruning_tool.select_tool("loppers")],
		["3: Pull Saw", func(): pruning_tool.select_tool("saw")],
		["L: Leaves", func(): _on_hud_action("leaf_density", _cycle_orchard_leaf_density())],
		["B: Shape", func(): hud_panel.toggle_shape_tab()],
		["T: +Tree", func(): _on_hud_action("add_tree", "")],
		["-Tree", func(): _on_hud_action("remove_tree", "")],
		["Z: Undo", func(): undo_orchard_cut()],
		["R: New Tree", func(): _on_hud_action("new_tree", "")],
	]
	for qa in quick_actions:
		var b := Button.new()
		b.text = qa[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(qa[1])
		hbox.add_child(b)


func set_passthrough_enabled(enabled: bool) -> void:
	passthrough_enabled = enabled
	var vp := get_viewport()
	if xr_active:
		var supported_modes: Array = xr_interface.get_supported_environment_blend_modes()
		if enabled and XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in supported_modes:
			vp.transparent_bg = true
			world_env.environment.background_mode = Environment.BG_COLOR
			world_env.environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
			garden_env.visible = false
		else:
			vp.transparent_bg = false
			world_env.environment.background_mode = Environment.BG_SKY
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
			garden_env.visible = true
	else:
		vp.transparent_bg = false
		world_env.environment.background_mode = Environment.BG_SKY if not enabled else Environment.BG_COLOR
		if enabled:
			world_env.environment.background_color = Color(0.18, 0.21, 0.23, 1.0)
		garden_env.visible = not enabled
	hud_panel.set_passthrough_state(enabled)


func _process(delta: float) -> void:
	if xr_active:
		if _recenter_frames > 0:
			_recenter_frames -= 1
			if _recenter_frames == 0:
				XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
				recenter_tree_in_front()
		_process_xr(delta)
	else:
		_process_desktop(delta)


func _process_xr(delta: float) -> void:
	# Smoothly move tool to hand tracking palm if controller isn't active & hand tracking is active
	var right_hand_tracker: XRHandTracker = XRServer.get_tracker("/user/hand_tracker/right")
	var using_hand := (not right_ctrl.get_is_active()) and right_hand_tracker and right_hand_tracker.has_tracking_data
	if using_hand:
		if pruning_tool.get_parent() != right_hand_aim:
			pruning_tool.reparent(right_hand_aim, false)
			pruning_tool.position = Vector3(0.0, -0.02, -0.05)
			pruning_tool.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	else:
		if pruning_tool.get_parent() != right_ctrl:
			pruning_tool.reparent(right_ctrl, false)
			pruning_tool.position = Vector3(0.0, -0.015, -0.025)
			pruning_tool.rotation_degrees = Vector3(-32.0, 0.0, 0.0)

	# Room-scale tree repositioning via Left Grip (moves whichever tree was grabbed)
	if _grabbing_tree and left_ctrl.get_is_active() and is_instance_valid(_grabbed_tree):
		var target_pos := left_ctrl.global_position + _grab_offset
		target_pos.y = maxf(0.0, target_pos.y)
		_grabbed_tree.global_position = _grabbed_tree.global_position.lerp(target_pos, clampf(delta * 14.0, 0.0, 1.0))
		_grabbed_tree.rotation.y = left_ctrl.global_rotation.y + _grab_yaw_offset

	# Thumbstick locomotion on Left Controller
	if left_ctrl.get_is_active():
		var stick := left_ctrl.get_vector2("primary")
		if stick.length() > 0.18:
			var fwd := -xr_camera.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var rgt := xr_camera.global_transform.basis.x
			rgt.y = 0.0
			rgt = rgt.normalized()
			xr_origin.global_position += (fwd * stick.y + rgt * stick.x) * delta * 1.4

	# Right thumbstick smooth/snap yaw
	if right_ctrl.get_is_active():
		var rstick := right_ctrl.get_vector2("primary")
		if absf(rstick.x) > 0.25:
			xr_origin.rotate_y(-rstick.x * delta * 1.6)

	# Update ray visualizers and forward pointer hover/drag to the 3D HUD panel
	_update_ray_visual(left_ray)
	_update_ray_visual(right_ray)

	var eff_trigger := _hand_pinch_val if using_hand else _trigger_val_right
	var eff_just := _hand_pinch_just_pressed if using_hand else _trigger_just_pressed
	_trigger_just_pressed = false
	_hand_pinch_just_pressed = false

	var ui_hit := false
	var ui_pos := Vector3.ZERO
	var ui_pressed := false
	var r_ray := right_hand_ray if using_hand else right_ray
	var l_ray := left_hand_ray if using_hand else left_ray
	if r_ray.is_colliding() and r_ray.get_collider() and r_ray.get_collider().has_meta("ui_panel"):
		ui_hit = true
		ui_pos = r_ray.get_collision_point()
		ui_pressed = eff_trigger > 0.55
	elif l_ray.is_colliding() and l_ray.get_collider() and l_ray.get_collider().has_meta("ui_panel"):
		ui_hit = true
		ui_pos = l_ray.get_collision_point()
		ui_pressed = (_hand_pinch_val_left if using_hand else _trigger_val_left) > 0.55

	if hud_panel.update_pointer(ui_hit, ui_pos, ui_pressed):
		audio_fx.play_at("ui_click", ui_pos)
		_pulse_right_haptic(0.35, 0.04)

	# Don't snip branches when pointing ray directly at UI panel
	if not ui_hit:
		pruning_tool.update_tool(delta, eff_trigger, eff_just, _pulse_right_haptic)
	else:
		pruning_tool.update_tool(delta, 0.0, false)


func _update_ray_visual(ray: RayCast3D) -> void:
	if not is_instance_valid(ray):
		return
	var beam := ray.get_node_or_null("Beam") as MeshInstance3D
	if not beam:
		return
	var hit_ui := ray.is_colliding() and ray.get_collider() and ray.get_collider().has_meta("ui_panel")
	beam.visible = hit_ui
	if hit_ui:
		var dist := ray.global_position.distance_to(ray.get_collision_point())
		beam.scale.y = maxf(0.05, dist)
		beam.position.z = -dist * 0.5


func _process_desktop(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if Input.is_key_pressed(KEY_E): move.y += 1.0
	if Input.is_key_pressed(KEY_Q): move.y -= 1.0

	if move.length_squared() > 0.0:
		var basis_cam := desktop_cam.global_transform.basis
		var dir := (basis_cam.z * move.z + basis_cam.x * move.x + Vector3.UP * move.y).normalized()
		desktop_cam.global_position += dir * delta * 1.45

	# Trackpad-friendly Arrow Key look/turn
	var key_yaw := 0.0
	var key_pitch := 0.0
	if Input.is_key_pressed(KEY_LEFT): key_yaw += 1.0
	if Input.is_key_pressed(KEY_RIGHT): key_yaw -= 1.0
	if Input.is_key_pressed(KEY_UP): key_pitch += 1.0
	if Input.is_key_pressed(KEY_DOWN): key_pitch -= 1.0
	if key_yaw != 0.0 or key_pitch != 0.0:
		_desk_yaw += key_yaw * delta * 1.45
		_desk_pitch = clampf(_desk_pitch + key_pitch * delta * 1.15, -1.2, 1.1)
		desktop_cam.rotation = Vector3(_desk_pitch, _desk_yaw, 0.0)

	# Aim pruning tool under cursor ray in desktop preview
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_orig := desktop_cam.project_ray_origin(mouse_pos)
	var ray_dir := desktop_cam.project_ray_normal(mouse_pos)
	var target_pt := ray_orig + ray_dir * _desk_tool_depth

	# Check if cursor points at UI panel first
	var space_state := get_world_3d().direct_space_state
	var q_ui := PhysicsRayQueryParameters3D.create(ray_orig, ray_orig + ray_dir * 6.0, 4)
	var hit_ui := space_state.intersect_ray(q_ui)

	var desk_lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _desk_click_pending
	_desk_click_pending = false
	if hud_panel.update_pointer(not hit_ui.is_empty(), hit_ui.position if not hit_ui.is_empty() else Vector3.ZERO, desk_lmb):
		audio_fx.play_at("ui_click", hit_ui.position)

	# Snap accurately to nearest branch along mouse ray across all orchard trees!
	var snap_cand := {}
	if hit_ui.is_empty():
		snap_cand = _find_closest_to_ray_orchard(ray_orig, ray_dir, 0.045)
	if not snap_cand.is_empty():
		var snap_pt: Vector3 = snap_cand.world_pos
		_desk_tool_depth = clampf(ray_orig.distance_to(snap_pt), 0.35, 2.6)
		target_pt = snap_pt
	pruning_tool.set_override_candidate(snap_cand)

	# Natural 3/4 hand angle from lower-right toward hovered branch point
	var cam_xf := desktop_cam.global_transform
	var hand_origin := cam_xf.origin + cam_xf.basis.x * 0.24 - cam_xf.basis.y * 0.16 - cam_xf.basis.z * 0.32
	var tool_dir := (target_pt - hand_origin).normalized()
	if tool_dir.length_squared() < 0.001:
		tool_dir = ray_dir
	var up_ref := Vector3.UP
	if not snap_cand.is_empty():
		# Align blade opening perpendicular to branch axis so jaws straddle the wood cleanly!
		var b_dir: Vector3 = (snap_cand.world_dir as Vector3).normalized()
		var jaw_up := b_dir
		if absf(jaw_up.dot(tool_dir)) < 0.92:
			up_ref = jaw_up
	var reach: float = absf(PruningTool.TOOL_INFO[pruning_tool.current_tool].reach_z)
	pruning_tool.global_position = target_pt - tool_dir * reach
	pruning_tool.look_at(target_pt + tool_dir, up_ref)

	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and hit_ui.is_empty()
	var trig := 0.9 if lmb else 0.0
	pruning_tool.update_tool(delta, trig, _trigger_just_pressed and hit_ui.is_empty())
	_trigger_just_pressed = false


func _input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_desk_looking = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_desk_click_pending = true
			_trigger_just_pressed = true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			desktop_cam.global_position += (-desktop_cam.global_transform.basis.z) * 0.14
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			desktop_cam.global_position -= (-desktop_cam.global_transform.basis.z) * 0.14
	elif event is InputEventMouseMotion and _desk_looking:
		var mm := event as InputEventMouseMotion
		_desk_yaw -= mm.relative.x * 0.004
		_desk_pitch = clampf(_desk_pitch - mm.relative.y * 0.004, -1.2, 1.1)
		desktop_cam.rotation = Vector3(_desk_pitch, _desk_yaw, 0.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: pruning_tool.select_tool("secateurs")
			KEY_2: pruning_tool.select_tool("loppers")
			KEY_3: pruning_tool.select_tool("saw")
			KEY_TAB: pruning_tool.cycle_tool()
			KEY_M: set_passthrough_enabled(not passthrough_enabled)
			KEY_H:
				_on_hud_action("toggle_hints", "")
			KEY_L:
				_on_hud_action("leaf_density", _cycle_orchard_leaf_density())
			KEY_B:
				hud_panel.toggle_shape_tab()
			KEY_T:
				_on_hud_action("add_tree", "")
			KEY_Z: undo_orchard_cut()
			KEY_R:
				_on_hud_action("new_tree", "")


func _on_right_ctrl_float(btn_name: String, val: float) -> void:
	if btn_name == "trigger":
		_trigger_val_right = val


func _on_left_ctrl_float(btn_name: String, val: float) -> void:
	if btn_name == "trigger":
		_trigger_val_left = val


func _on_right_ctrl_btn_pressed(btn_name: String) -> void:
	match btn_name:
		"trigger_click":
			if not (right_ray.is_colliding() and right_ray.get_collider() and right_ray.get_collider().has_meta("ui_panel")):
				_trigger_just_pressed = true
		"ax_button":
			pruning_tool.cycle_tool()
			audio_fx.play_at("ui_click", pruning_tool.global_position)
			_pulse_right_haptic(0.4, 0.05)
		"by_button":
			if undo_orchard_cut():
				_pulse_right_haptic(0.35, 0.06)


func _on_left_ctrl_btn_pressed(btn_name: String) -> void:
	match btn_name:
		"grip_click":
			_grabbed_tree = _find_closest_tree(left_ctrl.global_position)
			if is_instance_valid(_grabbed_tree):
				_grabbing_tree = true
				_active_tree = _grabbed_tree
				_grab_offset = _grabbed_tree.global_position - left_ctrl.global_position
				_grab_yaw_offset = _grabbed_tree.rotation.y - left_ctrl.global_rotation.y
		"ax_button":
			set_passthrough_enabled(not passthrough_enabled)
		"by_button":
			recenter_tree_in_front()


func _on_left_ctrl_btn_released(btn_name: String) -> void:
	if btn_name == "grip_click":
		_grabbing_tree = false
		_grabbed_tree = null


func _on_right_hand_float(btn_name: String, val: float) -> void:
	if btn_name == "index_pinch_strength":
		_hand_pinch_val = val


func _on_left_hand_float(btn_name: String, val: float) -> void:
	if btn_name == "index_pinch_strength":
		_hand_pinch_val_left = val


func _on_right_hand_btn_pressed(btn_name: String) -> void:
	if btn_name == "index_pinch":
		if not (right_hand_ray.is_colliding() and right_hand_ray.get_collider() and right_hand_ray.get_collider().has_meta("ui_panel")):
			_hand_pinch_just_pressed = true


func _on_left_hand_btn_pressed(_btn_name: String) -> void:
	pass


func _pulse_right_haptic(amp: float, dur: float) -> void:
	if xr_active and right_ctrl.get_is_active():
		right_ctrl.trigger_haptic_pulse("haptic", 120.0, amp, dur, 0.0)


func recenter_tree_in_front() -> void:
	var cam := xr_camera if xr_active else desktop_cam
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	var pos := cam.global_position + fwd * 1.10
	pos.y = 0.0
	for i in range(_trees.size()):
		var r := _trees[i]
		if not is_instance_valid(r):
			continue
		r.global_position = _orchard_slot_position(pos, right, fwd, i)
	hud_panel.global_position = pos + cam.global_transform.basis.x * (-0.82) + Vector3(0.0, 1.25, 0.0)
	hud_panel.look_at(Vector3(cam.global_position.x, hud_panel.global_position.y, cam.global_position.z), Vector3.UP)
	hud_panel.rotate_y(PI)


func _on_tree_updated(_stats: Dictionary) -> void:
	_emit_orchard_stats()


func _on_feedback(text: String, color: Color) -> void:
	hud_panel.show_feedback(text, color)


func _on_hud_action(action_id: String, payload: String) -> void:
	var target := _active_tree if is_instance_valid(_active_tree) else tree_rig
	match action_id:
		"tool":
			pruning_tool.select_tool(payload)
		"species":
			tree_seed += 1
			target.clear_custom_shape()
			target.generate_tree(payload, tree_seed)
			hud_panel.set_active_species(payload)
			hud_panel.update_shape_ui(target.get_effective_shape())
		"shape_step":
			var parts := payload.split(":")
			if parts.size() == 2:
				var updated := target.step_shape_param(parts[0], float(parts[1]))
				hud_panel.update_shape_ui(updated)
		"shape_preset":
			var updated := target.apply_shape_preset(payload)
			hud_panel.update_shape_ui(updated)
		"leaf_amount":
			var amt := float(payload)
			for r in _trees:
				if is_instance_valid(r):
					r.set_leaf_amount(amt, r == target)
			hud_panel.set_leaf_amount_state(target.leaf_amount)
		"leaf_density":
			for r in _trees:
				if is_instance_valid(r):
					r.set_leaf_density(payload)
			hud_panel.set_leaf_amount_state(target.leaf_amount)
		"add_tree":
			add_orchard_tree()
		"remove_tree":
			remove_last_orchard_tree()
		"toggle_passthrough":
			set_passthrough_enabled(not passthrough_enabled)
		"toggle_hints":
			var next_hints := not target.hints_enabled
			for r in _trees:
				if is_instance_valid(r):
					r.set_hints_enabled(next_hints)
			hud_panel.set_hints_state(next_hints)
		"recenter_tree":
			recenter_tree_in_front()
		"height_up":
			for r in _trees:
				if is_instance_valid(r):
					r.global_position.y += 0.15
		"height_down":
			for r in _trees:
				if is_instance_valid(r):
					r.global_position.y = maxf(0.0, r.global_position.y - 0.15)
		"scale_up":
			for r in _trees:
				if is_instance_valid(r):
					r.scale = (r.scale * 1.12).clamp(Vector3.ONE * 0.55, Vector3.ONE * 1.8)
		"scale_down":
			for r in _trees:
				if is_instance_valid(r):
					r.scale = (r.scale * 0.89).clamp(Vector3.ONE * 0.55, Vector3.ONE * 1.8)
		"undo":
			undo_orchard_cut()
		"new_tree":
			tree_seed += 1
			target.generate_tree(target.species_id, tree_seed)


func _register_tree_rig(rig: TreeRig) -> void:
	rig.set_audio_fx(audio_fx)
	if not rig.tree_updated.is_connected(_on_tree_updated):
		rig.tree_updated.connect(_on_tree_updated)
	if not rig.feedback_emitted.is_connected(_on_feedback):
		rig.feedback_emitted.connect(_on_feedback)
	if not rig.cut_recorded.is_connected(_on_rig_cut_recorded):
		rig.cut_recorded.connect(_on_rig_cut_recorded.bind(rig))
	if not _trees.has(rig):
		_trees.append(rig)
	if is_instance_valid(pruning_tool):
		pruning_tool.tree_rigs = _trees


func _on_rig_cut_recorded(_branch: PrunableBranch, _res: Dictionary, rig: TreeRig) -> void:
	_active_tree = rig
	_undo_tree_history.append(rig)


func _orchard_slot_position(base_pos: Vector3, right: Vector3, fwd: Vector3, idx: int) -> Vector3:
	if idx == 0:
		return base_pos
	var ring_step := int((idx + 1) / 2)
	var side := 1.0 if (idx % 2 == 1) else -1.0
	var lat_offset := side * float(ring_step) * 1.18
	var depth_curve := -float(ring_step) * 0.24
	return Vector3(base_pos.x, maxf(0.0, base_pos.y), base_pos.z) + right * lat_offset + fwd * depth_curve


func add_orchard_tree() -> TreeRig:
	if _trees.size() >= MAX_ORCHARD_TREES:
		hud_panel.show_feedback("Orchard max reached (%d trees)." % MAX_ORCHARD_TREES, Color(0.96, 0.72, 0.26))
		return null
	tree_seed += 1
	var ref := _active_tree if is_instance_valid(_active_tree) else tree_rig
	var new_rig := TreeRig.new()
	new_rig.name = "TreeRig_%d" % (_trees.size() + 1)
	new_rig.species_id = ref.species_id
	new_rig.leaf_density = ref.leaf_density
	new_rig.leaf_amount = ref.leaf_amount
	new_rig.hints_enabled = ref.hints_enabled
	new_rig.custom_shape = ref.custom_shape.duplicate()
	new_rig.tree_seed = tree_seed
	new_rig.scale = ref.scale

	var parent_node := tree_rig.get_parent()
	parent_node.add_child(new_rig)

	var cam := xr_camera if xr_active else desktop_cam
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	new_rig.global_position = _orchard_slot_position(tree_rig.global_position, right, fwd, _trees.size())

	_register_tree_rig(new_rig)
	_active_tree = new_rig
	hud_panel.set_orchard_count_state(_trees.size(), MAX_ORCHARD_TREES)
	_emit_orchard_stats()
	hud_panel.show_feedback("Added Tree #%d (%s)" % [_trees.size(), TreeSpecies.SPECIES_CONFIG[new_rig.species_id].title], Color(0.45, 0.94, 0.58))
	return new_rig


func remove_last_orchard_tree() -> bool:
	if _trees.size() <= 1:
		return false
	var removed: TreeRig = _trees.pop_back()
	var filtered_hist: Array[TreeRig] = []
	for h in _undo_tree_history:
		if is_instance_valid(h) and h != removed:
			filtered_hist.append(h)
	_undo_tree_history = filtered_hist
	if _active_tree == removed:
		_active_tree = _trees[_trees.size() - 1]
	if _grabbed_tree == removed:
		_grabbed_tree = null
		_grabbing_tree = false
	if is_instance_valid(removed):
		removed.queue_free()
	if is_instance_valid(pruning_tool):
		pruning_tool.tree_rigs = _trees
	hud_panel.set_orchard_count_state(_trees.size(), MAX_ORCHARD_TREES)
	_emit_orchard_stats()
	hud_panel.show_feedback("Removed tree (%d in orchard)." % _trees.size(), Color(0.75, 0.88, 0.98))
	return true


func undo_orchard_cut() -> bool:
	while _undo_tree_history.size() > 0:
		var rig: TreeRig = _undo_tree_history.pop_back()
		if is_instance_valid(rig) and rig.undo_last_cut():
			_active_tree = rig
			_emit_orchard_stats()
			return true
	for r in _trees:
		if is_instance_valid(r) and r.undo_last_cut():
			_active_tree = r
			_emit_orchard_stats()
			return true
	return false


func _cycle_orchard_leaf_density() -> String:
	var ref := _active_tree if is_instance_valid(_active_tree) else tree_rig
	if ref.leaf_amount < 0.10:
		return "sparse"
	elif ref.leaf_amount < 0.45:
		return "medium"
	elif ref.leaf_amount < 0.90:
		return "dense"
	return "none"


func _find_closest_tree(world_pos: Vector3) -> TreeRig:
	var best: TreeRig = _active_tree if is_instance_valid(_active_tree) else tree_rig
	var best_d := 1e9
	for r in _trees:
		if not is_instance_valid(r):
			continue
		var d := r.global_position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = r
	return best


func _find_closest_to_ray_orchard(ray_orig: Vector3, ray_dir: Vector3, max_snap_radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := max_snap_radius
	for r in _trees:
		if not is_instance_valid(r):
			continue
		var cand := r.find_closest_to_ray(ray_orig, ray_dir, best_dist)
		if not cand.is_empty() and float(cand.ray_dist) < best_dist:
			best_dist = float(cand.ray_dist)
			cand["rig"] = r
			best = cand
	return best


func _emit_orchard_stats() -> void:
	var ref := _active_tree if is_instance_valid(_active_tree) else tree_rig
	if _trees.size() <= 1 and is_instance_valid(ref) and not ref.last_stats.is_empty():
		hud_panel.update_stats(ref.last_stats)
		return
	var targets_rem := 0
	var targets_tot := 0
	var healthy_rem := 0
	var cuts := 0
	var perfect := 0
	var mistakes := 0
	var score := 0
	var leaves := 0
	for r in _trees:
		if not is_instance_valid(r) or r.last_stats.is_empty():
			continue
		targets_rem += int(r.last_stats.get("targets_remaining", 0))
		targets_tot += int(r.last_stats.get("targets_total", 0))
		healthy_rem += int(r.last_stats.get("healthy_remaining", 0))
		cuts += int(r.last_stats.get("cuts_made", 0))
		perfect += int(r.last_stats.get("perfect_cuts", 0))
		mistakes += int(r.last_stats.get("mistakes", 0))
		score += int(r.last_stats.get("score", 0))
		leaves += int(r.last_stats.get("visible_leaves", 0))
	var tot_safe := maxi(1, targets_tot)
	var cleared := maxi(0, targets_tot - targets_rem)
	var health_pct := int(round(clampf(float(cleared) / float(tot_safe) * 100.0 - float(mistakes) * 8.0, 0.0, 100.0)))
	var sp_title: String = TreeSpecies.SPECIES_CONFIG[ref.species_id].title
	if _trees.size() > 1:
		sp_title = "%s  (%d Trees)" % [sp_title, _trees.size()]
	hud_panel.update_stats({
		"species_title": sp_title,
		"species_subtitle": TreeSpecies.SPECIES_CONFIG[ref.species_id].subtitle,
		"leaf_density": ref.leaf_density,
		"visible_leaves": leaves,
		"targets_remaining": targets_rem,
		"targets_total": targets_tot,
		"healthy_remaining": healthy_rem,
		"cuts_made": cuts,
		"perfect_cuts": perfect,
		"mistakes": mistakes,
		"score": score,
		"health_pct": health_pct,
	})

