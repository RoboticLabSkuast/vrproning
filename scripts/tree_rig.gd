class_name TreeRig
extends Node3D

## Manages the complete Mixed Reality tree: planter pot + soil + contact shadow,
## multi-level botanical canopy (Trunk -> Scaffolds -> Laterals -> Twigs -> Leaf Boughs),
## real-time branch severing into falling RigidBody3D debris, sawdust/leaf particles, and undo.

signal tree_updated(stats: Dictionary)
signal feedback_emitted(text: String, color: Color)

const PLANTER_SCENE := preload("res://assets/models/planter_pot.glb")
const FOLIAGE_SHADER := preload("res://shaders/foliage_sway.gdshader")

var species_id: String = "apple"
var tree_seed: int = 101
var hints_enabled: bool = true

var _planter_holder: Node3D
var _tree_root: Node3D
var _debris_holder: Node3D
var _particles_holder: Node3D
var _trunk: PrunableBranch
var _all_branches: Array[PrunableBranch] = []
var _undo_stack: Array[Dictionary] = []
var _audio_fx: AudioFX

var _score: int = 0
var _cuts_made: int = 0
var _perfect_cuts: int = 0
var _mistakes: int = 0
var _initial_targets: int = 1
var _next_branch_id: int = 1


func _ready() -> void:
	_planter_holder = Node3D.new()
	_planter_holder.name = "PlanterHolder"
	add_child(_planter_holder)

	_tree_root = Node3D.new()
	_tree_root.name = "TreeCanopy"
	_tree_root.position = Vector3(0.0, 0.355, 0.0)
	add_child(_tree_root)

	_debris_holder = Node3D.new()
	_debris_holder.name = "SeveredDebris"
	add_child(_debris_holder)

	_particles_holder = Node3D.new()
	_particles_holder.name = "CutParticles"
	add_child(_particles_holder)

	_build_planter_and_shadow()
	generate_tree("apple", tree_seed)


func set_audio_fx(fx: AudioFX) -> void:
	_audio_fx = fx


func _build_planter_and_shadow() -> void:
	var shadow_mesh := QuadMesh.new()
	shadow_mesh.size = Vector2(1.55, 1.55)
	shadow_mesh.orientation = PlaneMesh.FACE_Y
	var shadow_mi := MeshInstance3D.new()
	shadow_mi.mesh = shadow_mesh
	shadow_mi.position = Vector3(0.0, 0.003, 0.0)
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.albedo_texture = load("res://assets/textures/contact_shadow.png")
	shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.85)
	shadow_mi.material_override = shadow_mat
	_planter_holder.add_child(shadow_mi)

	var pot := PLANTER_SCENE.instantiate()
	_planter_holder.add_child(pot)
	var tc_mat := StandardMaterial3D.new()
	tc_mat.albedo_texture = load("res://assets/textures/terracotta_albedo.png")
	tc_mat.normal_enabled = true
	tc_mat.normal_texture = load("res://assets/textures/terracotta_normal.png")
	tc_mat.roughness = 0.78
	tc_mat.uv1_scale = Vector3(2.0, 1.5, 1.0)

	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_texture = load("res://assets/textures/soil_albedo.png")
	soil_mat.normal_enabled = true
	soil_mat.normal_texture = load("res://assets/textures/soil_normal.png")
	soil_mat.roughness = 0.96
	soil_mat.uv1_scale = Vector3(2.4, 2.4, 1.0)

	_apply_planter_mats(pot, tc_mat, soil_mat)

	var sb := StaticBody3D.new()
	var pot_col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.28
	cyl.height = 0.39
	pot_col.shape = cyl
	pot_col.position = Vector3(0.0, 0.195, 0.0)
	sb.add_child(pot_col)

	var floor_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.10, 10.0)
	floor_col.shape = box
	floor_col.position = Vector3(0.0, -0.05, 0.0)
	sb.add_child(floor_col)
	_planter_holder.add_child(sb)


func _apply_planter_mats(node: Node, tc_mat: Material, soil_mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh and mi.mesh.get_surface_count() >= 2:
			mi.set_surface_override_material(0, tc_mat)
			mi.set_surface_override_material(1, soil_mat)
	for child in node.get_children():
		_apply_planter_mats(child, tc_mat, soil_mat)


func generate_tree(p_species: String, p_seed: int) -> void:
	species_id = p_species if TreeSpecies.SPECIES_CONFIG.has(p_species) else "apple"
	tree_seed = p_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed

	for c in _tree_root.get_children():
		c.queue_free()
	for d in _debris_holder.get_children():
		d.queue_free()
	_all_branches.clear()
	_undo_stack.clear()
	_score = 0
	_cuts_made = 0
	_perfect_cuts = 0
	_mistakes = 0
	_next_branch_id = 1

	var cfg: Dictionary = TreeSpecies.SPECIES_CONFIG[species_id]

	var bark_live := _make_bark_material(cfg.bark_albedo, cfg.bark_normal, cfg.bark_roughness, Color.WHITE)
	var bark_dead := _make_bark_material("res://assets/textures/bark_dead_albedo.png",
		"res://assets/textures/bark_dead_normal.png", "res://assets/textures/bark_dead_roughness.png", Color(0.92, 0.90, 0.86))
	var bark_diseased := _make_bark_material(cfg.bark_albedo, cfg.bark_normal, cfg.bark_roughness, Color(0.54, 0.45, 0.36))

	var cut_live := _make_cut_material("res://assets/textures/wood_cut_albedo.png", "res://assets/textures/wood_cut_normal.png")
	var cut_dead := _make_cut_material("res://assets/textures/wood_cut_dead_albedo.png", "res://assets/textures/wood_cut_dead_normal.png")

	var leaf_live := _make_leaf_material(cfg.leaf_albedo, cfg.leaf_normal, cfg.leaf_tint, cfg.backlight)
	var leaf_dead := _make_leaf_material("res://assets/textures/leaf_dead_albedo.png", "res://assets/textures/leaf_dead_normal.png", Color(0.95, 0.88, 0.78), Color(0.22, 0.14, 0.06))

	var bud_tint := Color(0.96, 0.76, 0.78)
	if species_id == "maple":
		bud_tint = Color(0.84, 0.24, 0.20)
	elif species_id == "olive":
		bud_tint = Color(0.76, 0.86, 0.66)
	var bud_live := _make_bud_material(bud_tint, 0.42)
	var bud_dead := _make_bud_material(Color(0.42, 0.38, 0.35), 0.88)

	# 1. Gnarled Organic Main Trunk (7-point S-curve with root flare!)
	var th: float = cfg.trunk_height
	var tr: float = cfg.trunk_radius
	var lean_x := rng.randf_range(-0.06, 0.06)
	var lean_z := rng.randf_range(-0.06, 0.06)
	var trunk_pts := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(lean_x * 0.2, th * 0.14, lean_z * 0.2),
		Vector3(lean_x * 0.7, th * 0.32, -lean_z * 0.3),
		Vector3(lean_x * 1.1, th * 0.52, lean_z * 0.5),
		Vector3(-lean_x * 0.3, th * 0.72, lean_z * 0.9),
		Vector3(-lean_x * 0.6, th * 0.88, lean_z * 0.6),
		Vector3(-lean_x * 0.4, th, lean_z * 0.4),
	])
	var trunk_rads := PackedFloat32Array([
		tr * 1.15, tr * 0.96, tr * 0.86, tr * 0.76, tr * 0.64, tr * 0.52, tr * 0.40
	])
	_trunk = _spawn_branch(TreeSpecies.BranchKind.TRUNK, trunk_pts, trunk_rads, bark_live, cut_live, leaf_live, bud_live)
	_tree_root.add_child(_trunk)

	# 2. Basal Suckers emerging from rootstock flare
	var sucker_count := 2 if species_id != "maple" else 1
	for s_idx in range(sucker_count):
		var ang := rng.randf_range(0.0, TAU)
		var base_p := Vector3(cos(ang) * tr * 0.82, rng.randf_range(0.02, 0.11), sin(ang) * tr * 0.82)
		var out_dir := Vector3(cos(ang) * 0.45, 0.92, sin(ang) * 0.45).normalized()
		var s_len := rng.randf_range(0.32, 0.46)
		var s_pts := _build_organic_polyline(Vector3.ZERO, out_dir, s_len, Vector3.UP * 0.14, 6, 0.02, rng)
		var s_rads := _tapered_radii(0.0085, 0.0025, 6)
		var sucker := _spawn_branch(TreeSpecies.BranchKind.SUCKER, s_pts, s_rads, bark_live, cut_live, leaf_live, bud_live)
		sucker.position = base_p
		_trunk.add_attached_branch(0.10, sucker)
		_attach_foliage_along(sucker, 0.55, 0.98, 2, cfg.leaf_scale * 0.68, rng)
		_attach_buds_along(sucker, 0.25, 0.96, 4, 0.011, false, rng)

	# 3. Primary Scaffolds -> Secondary Limbs -> Tertiary Twigs -> Dense Boughs & Buds
	var sc_count: int = cfg.scaffold_count
	for i in range(sc_count):
		var t_trunk := lerpf(0.50, 0.96, float(i) / maxf(1.0, float(sc_count - 1)))
		var attach := _trunk.sample_at_t(t_trunk)
		var azim := (float(i) / float(sc_count)) * TAU + rng.randf_range(-0.28, 0.28)
		var elev := rng.randf_range(0.42, 0.72) if species_id != "maple" else rng.randf_range(0.24, 0.54)
		var dir := Vector3(cos(azim) * cos(elev), sin(elev), sin(azim) * cos(elev)).normalized()
		var sc_len: float = cfg.branch_spread * rng.randf_range(0.90, 1.16)
		var droop := Vector3(0.0, -0.06 if species_id == "maple" else 0.04, 0.0)
		var sc_pts := _build_organic_polyline(Vector3.ZERO, dir, sc_len, droop, 7, 0.045, rng)
		var sc_rads := _tapered_radii(float(attach.radius) * 0.64, 0.0065, 7)

		var sc := _spawn_branch(TreeSpecies.BranchKind.SCAFFOLD, sc_pts, sc_rads, bark_live, cut_live, leaf_live, bud_live)
		sc.position = attach.pos as Vector3
		_trunk.add_attached_branch(t_trunk, sc)
		_attach_buds_along(sc, 0.30, 0.98, 5, 0.014, species_id == "maple", rng)

		# Secondary healthy limbs (4 per scaffold) + Tertiary leafy twigs!
		var lat_count := 4
		for l_idx in range(lat_count):
			var t_lat := lerpf(0.28, 0.88, float(l_idx) / float(lat_count - 1))
			var l_samp := sc.sample_at_t(t_lat)
			var side := 1.0 if (l_idx % 2 == 0) else -1.0
			var l_dir_base: Vector3 = l_samp.dir as Vector3
			var lat_dir := (l_dir_base.rotated(Vector3.UP, side * rng.randf_range(0.48, 0.92)) + Vector3(0, rng.randf_range(0.04, 0.26), 0)).normalized()
			var lat_len := rng.randf_range(0.26, 0.42)
			var lat_pts := _build_organic_polyline(Vector3.ZERO, lat_dir, lat_len, Vector3(0, -0.03, 0), 6, 0.03, rng)
			var lat_rads := _tapered_radii(maxf(0.0065, float(l_samp.radius) * 0.66), 0.0025, 6)
			var lat := _spawn_branch(TreeSpecies.BranchKind.LATERAL, lat_pts, lat_rads, bark_live, cut_live, leaf_live, bud_live)
			lat.position = l_samp.pos as Vector3
			sc.add_attached_branch(t_lat, lat)
			_attach_buds_along(lat, 0.16, 0.96, 5, 0.013, species_id == "maple", rng)

			# Fine tertiary twigs forked from each secondary limb!
			for tw_idx in range(2):
				var t_tw := lerpf(0.45, 0.82, float(tw_idx))
				var tw_samp := lat.sample_at_t(t_tw)
				var tw_side := -side if tw_idx == 0 else side
				var tw_dir := ((tw_samp.dir as Vector3).rotated(Vector3.UP, tw_side * rng.randf_range(0.42, 0.82)) + Vector3(0, rng.randf_range(0.05, 0.22), 0)).normalized()
				var tw_len := rng.randf_range(0.14, 0.22)
				var tw_pts := _build_organic_polyline(Vector3.ZERO, tw_dir, tw_len, Vector3(0, -0.02, 0), 4, 0.015, rng)
				var tw_rads := _tapered_radii(maxf(0.0032, float(tw_samp.radius) * 0.68), 0.0015, 4)
				var twig := _spawn_branch(TreeSpecies.BranchKind.LATERAL, tw_pts, tw_rads, bark_live, cut_live, leaf_live, bud_live)
				twig.position = tw_samp.pos as Vector3
				lat.add_attached_branch(t_tw, twig)
				_attach_foliage_along(twig, 0.45, 1.0, 2, cfg.leaf_scale * 0.92, rng)
				_attach_buds_along(twig, 0.22, 1.0, 3, 0.011, species_id == "maple", rng)

			_attach_foliage_along(lat, 0.58, 1.0, 3, cfg.leaf_scale, rng)

		_attach_foliage_along(sc, 0.72, 1.0, 3, cfg.leaf_scale * 1.08, rng)

		# Inject realistic pruning defects cleanly along scaffolds
		if i % 2 == 0:
			var t_bad := rng.randf_range(0.22, 0.46)
			var b_samp := sc.sample_at_t(t_bad)
			var is_dis := (i == 2)
			var b_kind := TreeSpecies.BranchKind.DISEASED if is_dis else TreeSpecies.BranchKind.DEADWOOD
			var b_dir := ((b_samp.dir as Vector3).rotated(Vector3.UP, rng.randf_range(-1.05, 1.05)) + Vector3(0, -0.26, 0)).normalized()
			var b_len := rng.randf_range(0.28, 0.42)
			var b_pts := _build_organic_polyline(Vector3.ZERO, b_dir, b_len, Vector3(0, -0.08, 0), 6, 0.025, rng)
			var b_r0 := clampf(float(b_samp.radius) * 0.78, 0.011, 0.024)
			var b_rads := _tapered_radii(b_r0, 0.0032, 6)
			var bad_b := _spawn_branch(b_kind, b_pts, b_rads, bark_diseased if is_dis else bark_dead, cut_dead, leaf_dead, bud_dead)
			bad_b.position = b_samp.pos as Vector3
			sc.add_attached_branch(t_bad, bad_b)
			_attach_buds_along(bad_b, 0.25, 0.92, 3, 0.009, false, rng)
			if is_dis:
				_attach_foliage_along(bad_b, 0.55, 0.95, 2, cfg.leaf_scale * 0.65, rng)
		else:
			var t_ws := rng.randf_range(0.26, 0.54)
			var w_samp := sc.sample_at_t(t_ws)
			var w_dir := Vector3(rng.randf_range(-0.14, 0.14), 1.0, rng.randf_range(-0.14, 0.14)).normalized()
			var w_len := rng.randf_range(0.36, 0.52)
			var w_pts := _build_organic_polyline(Vector3.ZERO, w_dir, w_len, Vector3.ZERO, 6, 0.018, rng)
			var w_rads := _tapered_radii(0.0085, 0.0028, 6)
			var ws := _spawn_branch(TreeSpecies.BranchKind.WATERSPROUT, w_pts, w_rads, bark_live, cut_live, leaf_live, bud_live)
			ws.position = w_samp.pos as Vector3
			sc.add_attached_branch(t_ws, ws)
			_attach_foliage_along(ws, 0.55, 1.0, 2, cfg.leaf_scale * 0.72, rng)
			_attach_buds_along(ws, 0.22, 0.98, 4, 0.012, false, rng)

		if i == 1 or i == 3:
			var t_cr := rng.randf_range(0.28, 0.46)
			var c_samp := sc.sample_at_t(t_cr)
			var c_pos: Vector3 = c_samp.pos as Vector3
			var inward := (-Vector3(c_pos.x + sc.position.x, -0.18, c_pos.z + sc.position.z)).normalized()
			var c_len := rng.randf_range(0.30, 0.44)
			var c_pts := _build_organic_polyline(Vector3.ZERO, inward, c_len, Vector3(0, 0.04, 0), 6, 0.025, rng)
			var c_rads := _tapered_radii(0.015, 0.004, 6)
			var cr := _spawn_branch(TreeSpecies.BranchKind.CROSSING, c_pts, c_rads, bark_live, cut_live, leaf_live, bud_live)
			cr.position = c_pos
			sc.add_attached_branch(t_cr, cr)
			_attach_foliage_along(cr, 0.50, 1.0, 2, cfg.leaf_scale * 0.82, rng)
			_attach_buds_along(cr, 0.22, 0.95, 4, 0.012, species_id == "maple", rng)

	# 4. Heavy dead lower limb (4.4 cm diameter — ideal for Japanese Pruning Saw!)
	var low_samp := _trunk.sample_at_t(0.42)
	var low_ang := rng.randf_range(0.0, TAU)
	var low_dir := Vector3(cos(low_ang) * 0.9, 0.22, sin(low_ang) * 0.9).normalized()
	var low_pts := _build_organic_polyline(Vector3.ZERO, low_dir, 0.46, Vector3(0, -0.10, 0), 6, 0.028, rng)
	var low_rads := _tapered_radii(0.022, 0.0065, 6)
	var heavy_dead := _spawn_branch(TreeSpecies.BranchKind.DEADWOOD, low_pts, low_rads, bark_dead, cut_dead, leaf_dead, bud_dead)
	heavy_dead.position = low_samp.pos as Vector3
	_trunk.add_attached_branch(0.42, heavy_dead)
	_attach_buds_along(heavy_dead, 0.30, 0.92, 3, 0.010, false, rng)

	var counts := _trunk.count_remaining_targets()
	_initial_targets = maxi(1, counts.targets)
	refresh_hints()
	emit_stats()


func _spawn_branch(p_kind: TreeSpecies.BranchKind, p_pts: PackedVector3Array,
		p_rads: PackedFloat32Array, p_bark: StandardMaterial3D,
		p_cut: StandardMaterial3D, p_leaf: ShaderMaterial, p_bud: StandardMaterial3D = null) -> PrunableBranch:
	var b := PrunableBranch.new()
	b.name = "Branch_%d" % _next_branch_id
	b.setup(_next_branch_id, p_kind, species_id, p_pts, p_rads, p_bark, p_cut, p_leaf, p_bud)
	_next_branch_id += 1
	_all_branches.append(b)
	return b


func _attach_foliage_along(branch: PrunableBranch, t_min: float, t_max: float,
		count: int, card_scale: float, rng: RandomNumberGenerator) -> void:
	for k in range(count):
		var t := lerpf(t_min, t_max, float(k) / maxf(1.0, float(count - 1)))
		var s := branch.sample_at_t(t)
		var b_basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		b_basis = b_basis * Basis(Vector3.RIGHT, rng.randf_range(-0.30, 0.35))
		branch.add_foliage_cluster(t, s.pos as Vector3, b_basis, card_scale * rng.randf_range(0.85, 1.18))


func _attach_buds_along(branch: PrunableBranch, t_min: float, t_max: float,
		count: int, bud_scale: float, opposite_pairs: bool, rng: RandomNumberGenerator) -> void:
	for k in range(count):
		var t := lerpf(t_min, t_max, float(k) / maxf(1.0, float(count - 1)))
		var s := branch.sample_at_t(t)
		var tang: Vector3 = (s.dir as Vector3).normalized()
		var base_pos: Vector3 = s.pos as Vector3
		var rad: float = float(s.radius)
		var ref_right := tang.cross(Vector3.UP)
		if ref_right.length_squared() < 0.01:
			ref_right = tang.cross(Vector3.RIGHT)
		ref_right = ref_right.normalized()

		# Spiral phyllotaxis (137.5 deg golden angle) or opposite decussate pairs (Maple)
		var azim := float(k) * 2.39996 + rng.randf_range(-0.25, 0.25)
		if opposite_pairs:
			azim = (PI * 0.5 if (k % 2 == 1) else 0.0) + rng.randf_range(-0.15, 0.15)
		var sides := [-1, 1] if opposite_pairs else [1]
		for side in sides:
			var radial := ref_right.rotated(tang, azim + (PI if side < 0 else 0.0)).normalized()
			var bud_up := (tang * 0.72 + radial * 0.69).normalized()
			var bx := bud_up.cross(tang).normalized()
			if bx.length_squared() < 0.001:
				bx = Vector3.RIGHT
			var bz := bx.cross(bud_up).normalized()
			var bud_basis := Basis(bx, bud_up, bz)
			var attach_pos := base_pos + radial * (rad * 0.86)
			# Evaluate outward facing relative to trunk vertical center
			var tree_rel := branch.position + attach_pos
			var out_horiz := Vector3(tree_rel.x, 0.0, tree_rel.z)
			var is_outward := out_horiz.dot(Vector3(radial.x, 0.0, radial.z)) >= 0.0
			branch.add_bud(t, attach_pos, bud_basis, bud_scale * rng.randf_range(0.85, 1.25), is_outward)
	# Add terminal apical bud at branch tip
	var tip := branch.sample_at_t(1.0)
	var t_dir: Vector3 = (tip.dir as Vector3).normalized()
	var tx := t_dir.cross(Vector3.FORWARD)
	if tx.length_squared() < 0.001:
		tx = t_dir.cross(Vector3.RIGHT)
	tx = tx.normalized()
	var tz := tx.cross(t_dir).normalized()
	branch.add_bud(1.0, tip.pos as Vector3, Basis(tx, t_dir, tz), bud_scale * 1.22, true)


func _build_organic_polyline(start: Vector3, dir: Vector3, length: float,
		bend: Vector3, steps: int, gnarl: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var d := dir.normalized()
	var perp1 := d.cross(Vector3.UP)
	if perp1.length_squared() < 0.01:
		perp1 = d.cross(Vector3.RIGHT)
	perp1 = perp1.normalized()
	var perp2 := d.cross(perp1).normalized()
	var phase := rng.randf_range(0.0, TAU)
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		var wave := sin(t * PI * 1.5 + phase) * gnarl * sin(t * PI)
		var wave2 := cos(t * PI * 2.1 + phase) * (gnarl * 0.65) * sin(t * PI)
		var p := start + d * (length * t) + bend * (t * t) + perp1 * wave + perp2 * wave2
		pts.append(p)
	return pts


func _tapered_radii(r_start: float, r_end: float, steps: int) -> PackedFloat32Array:
	var rads := PackedFloat32Array()
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		rads.append(lerpf(r_start, r_end, pow(t, 0.85)))
	return rads


func set_hints_enabled(enabled: bool) -> void:
	hints_enabled = enabled
	refresh_hints()


func refresh_hints() -> void:
	for b in _all_branches:
		if not is_instance_valid(b):
			continue
		var show := hints_enabled and not b.is_cut and not b.is_severed_debris and TreeSpecies.should_prune(b.kind)
		b.set_hint_beacon(show, TreeSpecies.kind_hint_color(b.kind))


func find_cut_candidate(world_pos: Vector3, max_dist: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := max_dist
	for b in _all_branches:
		if not is_instance_valid(b) or b.is_severed_debris:
			continue
		if b.is_cut and b.get_total_length() < 0.045:
			continue
		var res := b.closest_t_to_world(world_pos)
		if float(res.dist) < best_dist:
			best_dist = float(res.dist)
			best = res
			best["branch"] = b
	return best


func find_closest_to_ray(ray_orig: Vector3, ray_dir: Vector3, max_snap_radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := max_snap_radius
	for b in _all_branches:
		if not is_instance_valid(b) or b.is_severed_debris:
			continue
		if b.is_cut and b.get_total_length() < 0.045:
			continue
		var res := b.closest_to_ray_world(ray_orig, ray_dir)
		if float(res.ray_dist) < best_dist:
			best_dist = float(res.ray_dist)
			best = res
			best["branch"] = b
	return best


func try_cut_branch(branch: PrunableBranch, t_cut: float, tool_id: String, saw_delta: float = 0.0) -> Dictionary:
	if not is_instance_valid(branch) or branch.is_severed_debris or branch.points.size() < 2:
		return {"cut": false, "reason": "invalid"}
	if branch.is_cut and branch.get_total_length() < 0.045:
		return {"cut": false, "reason": "collar_stub_minimum"}

	var samp := branch.sample_at_t(t_cut)
	var dia_cm: float = float(samp.radius) * 200.0
	var world_cut_pos: Vector3 = branch.to_global(samp.pos as Vector3)

	if branch.kind == TreeSpecies.BranchKind.TRUNK:
		if _audio_fx:
			_audio_fx.play_at("snip_jam", world_cut_pos, 0.05, -2.0)
		var trunk_msg := "Main Trunk is protected! Prune side branches, watersprouts & suckers."
		emit_signal("feedback_emitted", trunk_msg, Color(0.95, 0.30, 0.25))
		return {"cut": false, "jammed": true, "message": trunk_msg}

	if tool_id == "secateurs" and dia_cm > 2.4:
		if _audio_fx:
			_audio_fx.play_at("snip_jam", world_cut_pos, 0.06, -1.0)
		var msg := "Too thick (%.1f cm) for Secateurs! Switch to Loppers or Pruning Saw." % dia_cm
		emit_signal("feedback_emitted", msg, Color(0.98, 0.58, 0.20))
		return {"cut": false, "jammed": true, "message": msg}

	if tool_id == "loppers" and dia_cm > 5.0:
		if _audio_fx:
			_audio_fx.play_at("snip_jam", world_cut_pos, 0.06, -1.0)
		var msg := "Too thick (%.1f cm) for Loppers! Use the Pruning Saw." % dia_cm
		emit_signal("feedback_emitted", msg, Color(0.98, 0.58, 0.20))
		return {"cut": false, "jammed": true, "message": msg}

	if tool_id == "saw":
		branch.saw_progress += saw_delta / maxf(0.18, dia_cm * 0.14)
		branch.update_saw_kerf(t_cut, clampf(branch.saw_progress, 0.0, 1.0))
		_spawn_sawdust_burst(world_cut_pos, 5)
		if branch.saw_progress < 1.0:
			return {"cut": false, "sawing": true, "progress": branch.saw_progress}

	var qual := branch.evaluate_cut_quality(t_cut)
	var record := branch.split_at_t(t_cut)

	var debris_body := RigidBody3D.new()
	debris_body.mass = clampf(dia_cm * 0.28, 0.15, 2.8)
	debris_body.linear_damp = 0.28
	debris_body.angular_damp = 0.35
	debris_body.collision_layer = 8
	debris_body.collision_mask = 1
	_debris_holder.add_child(debris_body)
	debris_body.global_transform = Transform3D(branch.global_transform.basis, world_cut_pos)

	var sev_branch := PrunableBranch.new()
	sev_branch.is_severed_debris = true
	sev_branch.setup(9000 + _cuts_made, branch.kind, species_id,
		record.sev_points, record.sev_radii, branch.bark_material, branch.cut_material, branch.leaf_material, branch.bud_material)
	sev_branch.rebuild_geometry(true, false)
	debris_body.add_child(sev_branch)

	for item in record.moved_leaves:
		var mi := MeshInstance3D.new()
		mi.mesh = PrunableBranch._create_botanical_bough_mesh(item.scale)
		mi.material_override = branch.leaf_material
		mi.position = item.pos - record.cut_pos_local
		mi.basis = item.basis
		debris_body.add_child(mi)

	for bd in record.get("moved_buds", []):
		if PrunableBranch._cached_bud_mesh == null:
			PrunableBranch._cached_bud_mesh = PrunableBranch._create_bud_mesh()
		var bmi := MeshInstance3D.new()
		bmi.mesh = PrunableBranch._cached_bud_mesh
		if branch.bud_material:
			bmi.material_override = branch.bud_material
		bmi.position = (bd.pos as Vector3) - (record.cut_pos_local as Vector3)
		bmi.basis = (bd.basis as Basis).scaled(Vector3.ONE * float(bd.scale))
		debris_body.add_child(bmi)

	for item in record.moved_children:
		var cb: PrunableBranch = item.node
		cb.position -= record.cut_pos_local
		cb.is_severed_debris = true
		debris_body.add_child(cb)

	# Multi-segment physics capsules so severed branches land & rest realistically on the ground!
	var sev_pts: PackedVector3Array = record.sev_points
	var sev_rads: PackedFloat32Array = record.sev_radii
	for i in range(sev_pts.size() - 1):
		var p0 := sev_pts[i]
		var p1 := sev_pts[i + 1]
		var seg := p1 - p0
		var sl := seg.length()
		if sl < 0.01:
			continue
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = maxf(0.018, maxf(sev_rads[i], sev_rads[i + 1]) * 1.3)
		cap.height = sl + cap.radius * 1.4
		col.shape = cap
		var y_dir := seg.normalized()
		var x_dir := y_dir.cross(Vector3.FORWARD)
		if x_dir.length_squared() < 0.001:
			x_dir = y_dir.cross(Vector3.RIGHT)
		x_dir = x_dir.normalized()
		var z_dir := x_dir.cross(y_dir).normalized()
		col.transform = Transform3D(Basis(x_dir, y_dir, z_dir), (p0 + p1) * 0.5)
		debris_body.add_child(col)

	var away := (world_cut_pos - global_position)
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.RIGHT
	debris_body.apply_central_impulse(away * 0.25 + Vector3(0, -0.14, 0))
	debris_body.apply_torque_impulse(Vector3(randf_range(-0.14, 0.14), randf_range(-0.1, 0.1), randf_range(-0.14, 0.14)))

	_spawn_sawdust_burst(world_cut_pos, 18)
	if _audio_fx:
		if tool_id == "saw":
			_audio_fx.play_at("branch_crack", world_cut_pos)
		elif dia_cm > 2.0:
			_audio_fx.play_at("snip_thick", world_cut_pos)
		else:
			_audio_fx.play_at("snip_clean", world_cut_pos)
		if record.moved_leaves.size() > 0:
			_audio_fx.play_at("leaves_rustle", world_cut_pos, 0.1, -4.0)

	_cuts_made += 1
	_score = maxi(0, _score + int(qual.score))
	if qual.grade == "PERFECT":
		_perfect_cuts += 1
	elif int(qual.score) < 0:
		_mistakes += 1

	record["debris_body"] = debris_body
	record["score_delta"] = int(qual.score)
	record["grade"] = qual.grade
	_undo_stack.append(record)

	refresh_hints()
	emit_stats()
	emit_signal("feedback_emitted", qual.message, qual.color)
	return {"cut": true, "grade": qual.grade, "message": qual.message, "color": qual.color}


func undo_last_cut() -> bool:
	if _undo_stack.is_empty():
		return false
	var rec: Dictionary = _undo_stack.pop_back()
	var b: PrunableBranch = rec.branch
	var debris: Node = rec.debris_body
	if is_instance_valid(debris):
		debris.queue_free()
	for item in rec.moved_children:
		var cb: PrunableBranch = item.node
		if cb.get_parent():
			cb.get_parent().remove_child(cb)
		cb.position += rec.cut_pos_local
		cb.is_severed_debris = false
	if is_instance_valid(b):
		b.restore_from_split(rec)
	_cuts_made = maxi(0, _cuts_made - 1)
	_score = maxi(0, _score - int(rec.score_delta))
	if rec.grade == "PERFECT":
		_perfect_cuts = maxi(0, _perfect_cuts - 1)
	elif int(rec.score_delta) < 0:
		_mistakes = maxi(0, _mistakes - 1)

	refresh_hints()
	emit_stats()
	emit_signal("feedback_emitted", "Undid last cut.", Color(0.55, 0.85, 1.0))
	return true


func emit_stats() -> void:
	var counts := _trunk.count_remaining_targets() if is_instance_valid(_trunk) else {"targets": 0, "healthy": 0}
	var cleared := maxi(0, _initial_targets - counts.targets)
	var health_pct := int(round(clampf(float(cleared) / float(_initial_targets) * 100.0 - float(_mistakes) * 8.0, 0.0, 100.0)))
	emit_signal("tree_updated", {
		"species_title": TreeSpecies.SPECIES_CONFIG[species_id].title,
		"species_subtitle": TreeSpecies.SPECIES_CONFIG[species_id].subtitle,
		"targets_remaining": counts.targets,
		"targets_total": _initial_targets,
		"healthy_remaining": counts.healthy,
		"cuts_made": _cuts_made,
		"perfect_cuts": _perfect_cuts,
		"mistakes": _mistakes,
		"score": _score,
		"health_pct": health_pct,
	})


func _spawn_sawdust_burst(world_pos: Vector3, count: int) -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = count
	p.lifetime = 0.75
	p.direction = Vector3(0.0, 0.4, 0.0)
	p.spread = 115.0
	p.initial_velocity_min = 0.45
	p.initial_velocity_max = 1.45
	p.gravity = Vector3(0.0, -5.5, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.008, 0.005, 0.006)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.84, 0.70, 0.46)
	mat.roughness = 0.9
	mesh.material = mat
	p.mesh = mesh
	_particles_holder.add_child(p)
	p.global_position = world_pos
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)


func _make_bark_material(albedo_path: String, normal_path: String, rough_path: String, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(albedo_path)
	mat.albedo_color = tint
	mat.normal_enabled = true
	mat.normal_texture = load(normal_path)
	mat.normal_scale = 1.35
	mat.roughness_texture = load(rough_path)
	mat.roughness = 0.94
	return mat


func _make_cut_material(albedo_path: String, normal_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(albedo_path)
	mat.normal_enabled = true
	mat.normal_texture = load(normal_path)
	mat.roughness = 0.76
	return mat


func _make_leaf_material(albedo_path: String, normal_path: String, tint: Color, backlight: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE_SHADER
	mat.set_shader_parameter("albedo_tex", load(albedo_path))
	mat.set_shader_parameter("normal_tex", load(normal_path))
	mat.set_shader_parameter("tint_color", tint)
	mat.set_shader_parameter("backlight_color", backlight)
	mat.set_shader_parameter("alpha_scissor", 0.36)
	mat.set_shader_parameter("wind_strength", 0.020)
	return mat


func _make_bud_material(tint: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/bud_scale_albedo.png")
	mat.albedo_color = tint
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/bud_scale_normal.png")
	mat.roughness = rough
	return mat
