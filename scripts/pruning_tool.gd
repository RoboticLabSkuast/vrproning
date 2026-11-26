class_name PruningTool
extends Node3D

## Manages the 3D articulated pruning tools (Secateurs, Loppers, Japanese Pruning Saw),
## realistic blade closing animation, saw velocity cutting, and angled collar-cut plane guide.

signal tool_changed(tool_id: String)

const SECATEURS_SCENE := preload("res://assets/models/secateurs.glb")
const LOPPERS_SCENE := preload("res://assets/models/loppers.glb")
const SAW_SCENE := preload("res://assets/models/pruning_saw.glb")
const CUT_GUIDE_SHADER := preload("res://shaders/cut_guide.gdshader")

const TOOL_ORDER := ["secateurs", "loppers", "saw"]
const TOOL_INFO := {
	"secateurs": {"label": "Bypass Secateurs", "max_cm": 2.4, "reach_z": -0.095, "cut_rad": 0.085},
	"loppers": {"label": "Long-Reach Loppers", "max_cm": 5.0, "reach_z": -0.39, "cut_rad": 0.095},
	"saw": {"label": "Japanese Pull Saw", "max_cm": 20.0, "reach_z": -0.17, "cut_rad": 0.075},
}

var current_tool: String = "secateurs"
var tree_rig: TreeRig
var audio_fx: AudioFX

var _tool_holder: Node3D
var _models: Dictionary = {}
var _pivots: Dictionary = {}
var _cut_point_marker: Marker3D
var _cut_guide_ring: MeshInstance3D
var _cut_plane_disc: MeshInstance3D
var _cut_guide_mat: ShaderMaterial
var _cut_plane_mat: ShaderMaterial
var _cut_tooltip: Label3D

var _trigger_val: float = 0.0
var _was_snipped: bool = false
var _prev_saw_world_pos: Vector3 = Vector3.ZERO
var _saw_stroke_accum: float = 0.0
var _saw_sound_cooldown: float = 0.0
var _current_candidate: Dictionary = {}
var _override_candidate: Dictionary = {}


func _ready() -> void:
	_tool_holder = Node3D.new()
	_tool_holder.name = "ToolHolder"
	add_child(_tool_holder)

	_cut_point_marker = Marker3D.new()
	_cut_point_marker.name = "CutPoint"
	_tool_holder.add_child(_cut_point_marker)

	_load_tool_models()
	_build_cut_guide()
	select_tool("secateurs")


func _load_tool_models() -> void:
	var sec := SECATEURS_SCENE.instantiate()
	_tool_holder.add_child(sec)
	_models["secateurs"] = sec
	_pivots["secateurs"] = sec.find_child("BladePivot", true, false)

	var lop := LOPPERS_SCENE.instantiate()
	_tool_holder.add_child(lop)
	_models["loppers"] = lop
	_pivots["loppers"] = lop.find_child("BladePivot", true, false)

	var saw := SAW_SCENE.instantiate()
	_tool_holder.add_child(saw)
	_models["saw"] = saw


func _build_cut_guide() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.017
	torus.outer_radius = 0.022
	torus.rings = 28
	torus.ring_segments = 10

	_cut_guide_mat = ShaderMaterial.new()
	_cut_guide_mat.shader = CUT_GUIDE_SHADER
	_cut_guide_mat.set_shader_parameter("ring_color", Color(0.2, 0.95, 0.45, 0.90))

	_cut_guide_ring = MeshInstance3D.new()
	_cut_guide_ring.name = "CollarCutGuide"
	_cut_guide_ring.mesh = torus
	_cut_guide_ring.material_override = _cut_guide_mat
	_cut_guide_ring.top_level = true
	_cut_guide_ring.visible = false
	add_child(_cut_guide_ring)

	# Translucent arborist cut-plane slice disc inside the ring
	var disc := CylinderMesh.new()
	disc.height = 0.002
	disc.top_radius = 0.019
	disc.bottom_radius = 0.019
	_cut_plane_mat = ShaderMaterial.new()
	_cut_plane_mat.shader = CUT_GUIDE_SHADER
	_cut_plane_mat.set_shader_parameter("ring_color", Color(0.2, 0.95, 0.45, 0.28))
	_cut_plane_disc = MeshInstance3D.new()
	_cut_plane_disc.mesh = disc
	_cut_plane_disc.material_override = _cut_plane_mat
	_cut_guide_ring.add_child(_cut_plane_disc)

	_cut_tooltip = Label3D.new()
	_cut_tooltip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cut_tooltip.no_depth_test = true
	_cut_tooltip.font_size = 24
	_cut_tooltip.pixel_size = 0.0020
	_cut_tooltip.outline_size = 7
	_cut_tooltip.position = Vector3(0.0, 0.075, 0.0)
	_cut_guide_ring.add_child(_cut_tooltip)


func select_tool(tool_id: String) -> void:
	if not TOOL_INFO.has(tool_id):
		return
	current_tool = tool_id
	for k in _models:
		_models[k].visible = (k == tool_id)
	_cut_point_marker.position = Vector3(0.0, 0.0, TOOL_INFO[tool_id].reach_z)
	_was_snipped = false
	_saw_stroke_accum = 0.0
	emit_signal("tool_changed", tool_id)


func cycle_tool() -> String:
	var idx := TOOL_ORDER.find(current_tool)
	var next_id: String = TOOL_ORDER[(idx + 1) % TOOL_ORDER.size()]
	select_tool(next_id)
	return next_id


func get_cut_point_world() -> Vector3:
	return _cut_point_marker.global_position


func set_override_candidate(cand: Dictionary) -> void:
	_override_candidate = cand


func update_tool(delta: float, trigger_val: float, trigger_just_pressed: bool,
		haptic_cb: Callable = Callable()) -> void:
	_trigger_val = clampf(trigger_val, 0.0, 1.0)
	_saw_sound_cooldown = maxf(0.0, _saw_sound_cooldown - delta)

	if current_tool in ["secateurs", "loppers"]:
		var pivot: Node3D = _pivots.get(current_tool)
		if is_instance_valid(pivot):
			var target_y := lerpf(0.24, -0.34, _trigger_val)
			pivot.rotation.y = lerpf(pivot.rotation.y, target_y, clampf(delta * 26.0, 0.0, 1.0))

	if not _override_candidate.is_empty():
		_current_candidate = _override_candidate
	else:
		_current_candidate = {}
		if is_instance_valid(tree_rig):
			var search_rad: float = TOOL_INFO[current_tool].cut_rad
			_current_candidate = tree_rig.find_cut_candidate(get_cut_point_world(), search_rad)

	_update_cut_guide_visual()

	if _current_candidate.is_empty():
		_prev_saw_world_pos = get_cut_point_world()
		return

	var branch: PrunableBranch = _current_candidate.branch
	var t_cut: float = float(_current_candidate.t)

	if current_tool in ["secateurs", "loppers"]:
		var triggered := trigger_just_pressed or (_trigger_val >= 0.76 and not _was_snipped)
		if _trigger_val < 0.35:
			_was_snipped = false
		if triggered:
			_was_snipped = true
			var res := tree_rig.try_cut_branch(branch, t_cut, current_tool)
			if haptic_cb.is_valid():
				if res.get("cut", false):
					haptic_cb.call(0.85, 0.12)
				elif res.get("jammed", false):
					haptic_cb.call(0.45, 0.22)
	elif current_tool == "saw":
		var cur_pos := get_cut_point_world()
		var move_dist := cur_pos.distance_to(_prev_saw_world_pos)
		_prev_saw_world_pos = cur_pos

		var saw_effort := 0.0
		if move_dist > 0.0025:
			saw_effort += move_dist * 2.5
		if _trigger_val > 0.5:
			saw_effort += delta * 0.75

		if saw_effort > 0.004:
			_saw_stroke_accum += saw_effort
			if _saw_sound_cooldown <= 0.0 and _saw_stroke_accum > 0.045:
				_saw_stroke_accum = 0.0
				_saw_sound_cooldown = 0.18
				if audio_fx:
					audio_fx.play_at("saw_stroke", cur_pos, 0.12, -3.0)
				if haptic_cb.is_valid():
					haptic_cb.call(0.32, 0.08)
			var res := tree_rig.try_cut_branch(branch, t_cut, "saw", saw_effort)
			if res.get("cut", false) and haptic_cb.is_valid():
				haptic_cb.call(1.0, 0.20)
	else:
		_prev_saw_world_pos = get_cut_point_world()


func _update_cut_guide_visual() -> void:
	if _current_candidate.is_empty():
		_cut_guide_ring.visible = false
		return
	var branch: PrunableBranch = _current_candidate.branch
	var t_cut: float = float(_current_candidate.t)
	var w_pos: Vector3 = _current_candidate.world_pos
	var w_dir: Vector3 = _current_candidate.world_dir
	var rad: float = float(_current_candidate.radius)
	var dia_cm := rad * 200.0

	_cut_guide_ring.visible = true
	var up := (w_dir + Vector3(0.18, 0.08, 0.0)).normalized()
	var x_ax := up.cross(Vector3.FORWARD)
	if x_ax.length_squared() < 0.001:
		x_ax = up.cross(Vector3.RIGHT)
	x_ax = x_ax.normalized()
	var z_ax := x_ax.cross(up).normalized()
	_cut_guide_ring.global_transform = Transform3D(Basis(x_ax, up, z_ax), w_pos)
	var ring_scale := clampf(rad / 0.015, 0.55, 2.8)
	_cut_guide_ring.scale = Vector3(ring_scale, 1.0, ring_scale)

	var qual := branch.evaluate_cut_quality(t_cut)
	var col: Color = qual.color
	var tip_txt := ""
	var max_cm: float = TOOL_INFO[current_tool].max_cm
	if branch.kind == TreeSpecies.BranchKind.TRUNK:
		col = Color(0.95, 0.20, 0.20)
		tip_txt = "%.1f cm • Trunk (Protected)" % dia_cm
	elif dia_cm > max_cm:
		col = Color(0.98, 0.45, 0.15)
		tip_txt = "%.1f cm — Too thick for %s!" % [dia_cm, TOOL_INFO[current_tool].label]
	elif current_tool == "saw" and branch.saw_progress > 0.02:
		tip_txt = "Sawing %.0f%% • %s" % [branch.saw_progress * 100.0, TreeSpecies.kind_label(branch.kind)]
	else:
		tip_txt = "%.1f cm • %s • %s" % [dia_cm, qual.grade, TreeSpecies.kind_label(branch.kind)]

	_cut_guide_mat.set_shader_parameter("ring_color", Color(col.r, col.g, col.b, 0.92))
	_cut_plane_mat.set_shader_parameter("ring_color", Color(col.r, col.g, col.b, 0.26))
	_cut_tooltip.text = tip_txt
	_cut_tooltip.modulate = col
