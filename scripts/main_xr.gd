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
var _trigger_val_right: float = 0.0
var _trigger_just_pressed: bool = false
var _hand_pinch_val: float = 0.0
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


func _ready() -> void:
	tree_rig.set_audio_fx(audio_fx)
	tree_rig.tree_updated.connect(_on_tree_updated)
	tree_rig.feedback_emitted.connect(_on_feedback)
	hud_panel.action_requested.connect(_on_hud_action)

	pruning_tool = PruningTool.new()
	pruning_tool.name = "PruningTool"
	pruning_tool.tree_rig = tree_rig
	pruning_tool.audio_fx = audio_fx
	pruning_tool.tool_changed.connect(func(tid): hud_panel.set_active_tool(tid))

	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		_init_openxr_session()
	else:
		_init_desktop_preview()

	tree_rig.emit_stats()
	hud_panel.set_active_tool(pruning_tool.current_tool)
	hud_panel.set_active_species(tree_rig.species_id)
	hud_panel.set_hints_state(tree_rig.hints_enabled)


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
	right_ctrl.button_pressed.connect(_on_right_ctrl_btn_pressed)
	right_ctrl.input_float_changed.connect(_on_right_ctrl_float)

	right_hand_aim.button_pressed.connect(_on_right_hand_btn_pressed)
	right_hand_aim.input_float_changed.connect(_on_right_hand_float)
	left_hand_aim.button_pressed.connect(_on_left_hand_btn_pressed)

	set_passthrough_enabled(true)


func _on_xr_session_begun() -> void:
	var rates: Array = xr_interface.get_available_display_refresh_rates()
	var best := 90.0
	if rates.size() > 0:
		best = float(rates[0])
		for r in rates:
			if float(r) > best and float(r) <= 90.0:
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
	_desk_bar_label.text = "Laptop Preview | Left-Click: Cut (Hold for Saw) | Arrows or Right-Drag: Look | WASD/Scroll: Move"
	_desk_bar_label.add_theme_font_size_override("font_size", 14)
	_desk_bar_label.add_theme_color_override("font_color", Color(0.86, 0.96, 0.88))
	hbox.add_child(_desk_bar_label)

	var quick_actions := [
		["1: Secateurs", func(): pruning_tool.select_tool("secateurs")],
		["2: Loppers", func(): pruning_tool.select_tool("loppers")],
		["3: Pull Saw", func(): pruning_tool.select_tool("saw")],
		["Z: Undo", func(): tree_rig.undo_last_cut()],
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

	# Room-scale tree repositioning via Left Grip
	if _grabbing_tree and left_ctrl.get_is_active():
		var target_pos := left_ctrl.global_position + _grab_offset
		target_pos.y = maxf(0.0, target_pos.y)
		tree_rig.global_position = tree_rig.global_position.lerp(target_pos, clampf(delta * 14.0, 0.0, 1.0))
		tree_rig.rotation.y = left_ctrl.global_rotation.y + _grab_yaw_offset

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

	# Update ray visualizers for UI interaction
	_update_ray_visual(left_ray)
	_update_ray_visual(right_ray)

	var eff_trigger := _hand_pinch_val if using_hand else _trigger_val_right
	var eff_just := _hand_pinch_just_pressed if using_hand else _trigger_just_pressed
	_trigger_just_pressed = false
	_hand_pinch_just_pressed = false

	# Don't snip branches when pointing ray directly at UI panel
	var pointing_ui := (right_ray.is_colliding() and right_ray.get_collider() and right_ray.get_collider().has_meta("ui_panel"))
	if not pointing_ui:
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

	if _desk_click_pending:
		_desk_click_pending = false
		if not hit_ui.is_empty():
			hud_panel.click_at_world(hit_ui.position)
			audio_fx.play_at("ui_click", hit_ui.position)

	# Snap accurately to nearest branch along mouse ray (no pixel-hunting thin twigs!)
	var snap_cand := {}
	if hit_ui.is_empty():
		snap_cand = tree_rig.find_closest_to_ray(ray_orig, ray_dir, 0.045)
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
				tree_rig.set_hints_enabled(not tree_rig.hints_enabled)
				hud_panel.set_hints_state(tree_rig.hints_enabled)
			KEY_Z: tree_rig.undo_last_cut()
			KEY_R:
				tree_seed += 1
				tree_rig.generate_tree(tree_rig.species_id, tree_seed)


func _on_right_ctrl_float(btn_name: String, val: float) -> void:
	if btn_name == "trigger":
		_trigger_val_right = val


func _on_right_ctrl_btn_pressed(btn_name: String) -> void:
	match btn_name:
		"trigger_click":
			if right_ray.is_colliding() and right_ray.get_collider() and right_ray.get_collider().has_meta("ui_panel"):
				hud_panel.click_at_world(right_ray.get_collision_point())
				audio_fx.play_at("ui_click", right_ray.get_collision_point())
				_pulse_right_haptic(0.35, 0.04)
			else:
				_trigger_just_pressed = true
		"ax_button":
			pruning_tool.cycle_tool()
			audio_fx.play_at("ui_click", pruning_tool.global_position)
			_pulse_right_haptic(0.4, 0.05)
		"by_button":
			if tree_rig.undo_last_cut():
				_pulse_right_haptic(0.35, 0.06)


func _on_left_ctrl_btn_pressed(btn_name: String) -> void:
	match btn_name:
		"trigger_click":
			if left_ray.is_colliding() and left_ray.get_collider() and left_ray.get_collider().has_meta("ui_panel"):
				hud_panel.click_at_world(left_ray.get_collision_point())
				audio_fx.play_at("ui_click", left_ray.get_collision_point())
		"grip_click":
			_grabbing_tree = true
			_grab_offset = tree_rig.global_position - left_ctrl.global_position
			_grab_yaw_offset = tree_rig.rotation.y - left_ctrl.global_rotation.y
		"ax_button":
			set_passthrough_enabled(not passthrough_enabled)
		"by_button":
			recenter_tree_in_front()


func _on_left_ctrl_btn_released(btn_name: String) -> void:
	if btn_name == "grip_click":
		_grabbing_tree = false


func _on_right_hand_float(btn_name: String, val: float) -> void:
	if btn_name == "index_pinch_strength":
		_hand_pinch_val = val


func _on_right_hand_btn_pressed(btn_name: String) -> void:
	if btn_name == "index_pinch":
		if right_hand_ray.is_colliding() and right_hand_ray.get_collider() and right_hand_ray.get_collider().has_meta("ui_panel"):
			hud_panel.click_at_world(right_hand_ray.get_collision_point())
		else:
			_hand_pinch_just_pressed = true


func _on_left_hand_btn_pressed(btn_name: String) -> void:
	if btn_name == "index_pinch":
		if left_hand_ray.is_colliding() and left_hand_ray.get_collider() and left_hand_ray.get_collider().has_meta("ui_panel"):
			hud_panel.click_at_world(left_hand_ray.get_collision_point())


func _pulse_right_haptic(amp: float, dur: float) -> void:
	if xr_active and right_ctrl.get_is_active():
		right_ctrl.trigger_haptic_pulse("haptic", 120.0, amp, dur, 0.0)


func recenter_tree_in_front() -> void:
	var cam := xr_camera if xr_active else desktop_cam
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var pos := cam.global_position + fwd * 1.10
	pos.y = 0.0
	tree_rig.global_position = pos
	hud_panel.global_position = pos + cam.global_transform.basis.x * (-0.82) + Vector3(0.0, 1.25, 0.0)
	hud_panel.look_at(Vector3(cam.global_position.x, hud_panel.global_position.y, cam.global_position.z), Vector3.UP)
	hud_panel.rotate_y(PI)


func _on_tree_updated(stats: Dictionary) -> void:
	hud_panel.update_stats(stats)


func _on_feedback(text: String, color: Color) -> void:
	hud_panel.show_feedback(text, color)


func _on_hud_action(action_id: String, payload: String) -> void:
	match action_id:
		"tool":
			pruning_tool.select_tool(payload)
		"species":
			tree_seed += 1
			tree_rig.generate_tree(payload, tree_seed)
			hud_panel.set_active_species(payload)
		"toggle_passthrough":
			set_passthrough_enabled(not passthrough_enabled)
		"toggle_hints":
			tree_rig.set_hints_enabled(not tree_rig.hints_enabled)
			hud_panel.set_hints_state(tree_rig.hints_enabled)
		"recenter_tree":
			recenter_tree_in_front()
		"height_up":
			tree_rig.global_position.y += 0.15
		"height_down":
			tree_rig.global_position.y = maxf(0.0, tree_rig.global_position.y - 0.15)
		"scale_up":
			tree_rig.scale = (tree_rig.scale * 1.12).clamp(Vector3.ONE * 0.55, Vector3.ONE * 1.8)
		"scale_down":
			tree_rig.scale = (tree_rig.scale * 0.89).clamp(Vector3.ONE * 0.55, Vector3.ONE * 1.8)
		"undo":
			tree_rig.undo_last_cut()
		"new_tree":
			tree_seed += 1
			tree_rig.generate_tree(tree_rig.species_id, tree_seed)

