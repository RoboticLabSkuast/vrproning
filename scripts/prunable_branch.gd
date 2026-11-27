class_name PrunableBranch
extends Node3D

## Procedural tapered botanical branch with root/collar flare, multi-segment spline bark PBR,
## domed 3D foliage boughs, angled arborist cut caps, saw-kerf progress notch, and exact subtree splitting.

const RADIAL_SEGS := 12

var branch_id: int = 0
var kind: TreeSpecies.BranchKind = TreeSpecies.BranchKind.LATERAL
var species_id: String = "apple"
var points: PackedVector3Array = PackedVector3Array()
var radii: PackedFloat32Array = PackedFloat32Array()
var is_cut: bool = false
var is_severed_debris: bool = false
var saw_progress: float = 0.0
var cut_angle_tilt: Vector3 = Vector3.ZERO

var bark_material: StandardMaterial3D
var cut_material: StandardMaterial3D
var leaf_material: ShaderMaterial
var bud_material: StandardMaterial3D

# Children attached along this branch: { "node": PrunableBranch, "t": float }
var attached_children: Array[Dictionary] = []
var leaf_clusters: Array[Dictionary] = [] # { "node": MeshInstance3D, "t": float, "pos": Vector3, "basis": Basis, "scale": float }
var buds: Array[Dictionary] = [] # { "node": MeshInstance3D, "t": float, "pos": Vector3, "basis": Basis, "scale": float, "outward": bool }

static var _cached_bud_mesh: ArrayMesh = null
static var _cached_bough_mesh: ArrayMesh = null

var _mesh_instance: MeshInstance3D
var _static_body: StaticBody3D
var _hint_beacon: MeshInstance3D
var _saw_kerf_ring: MeshInstance3D


func setup(p_id: int, p_kind: TreeSpecies.BranchKind, p_species: String,
		p_points: PackedVector3Array, p_radii: PackedFloat32Array,
		p_bark_mat: StandardMaterial3D, p_cut_mat: StandardMaterial3D,
		p_leaf_mat: ShaderMaterial, p_bud_mat: StandardMaterial3D = null) -> void:
	branch_id = p_id
	kind = p_kind
	species_id = p_species
	points = p_points.duplicate()
	radii = p_radii.duplicate()
	bark_material = p_bark_mat
	cut_material = p_cut_mat
	leaf_material = p_leaf_mat
	bud_material = p_bud_mat

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "BarkMesh"
	add_child(_mesh_instance)

	_static_body = StaticBody3D.new()
	_static_body.name = "BranchCollider"
	_static_body.collision_layer = 2
	_static_body.collision_mask = 0
	_static_body.set_meta("branch_node", self)
	add_child(_static_body)

	rebuild_geometry(false, true)


static func _get_shared_bough_mesh() -> ArrayMesh:
	if _cached_bough_mesh == null:
		_cached_bough_mesh = _create_botanical_bough_mesh(1.0)
	return _cached_bough_mesh


func add_foliage_cluster(t_attach: float, local_pos: Vector3, local_basis: Basis, card_scale: float,
		leaf_rank: float = 0.5, visible_now: bool = true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _get_shared_bough_mesh()
	mi.material_override = leaf_material
	mi.position = local_pos
	mi.basis = local_basis.scaled(Vector3.ONE * card_scale)
	# Alpha-scissor foliage cards disable mobile Early-Z if drawn in directional shadow maps
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = visible_now
	add_child(mi)
	leaf_clusters.append({
		"node": mi,
		"t": t_attach,
		"pos": local_pos,
		"basis": local_basis,
		"scale": card_scale,
		"rank": leaf_rank,
	})


func set_leaf_fraction_visible(amount: float) -> void:
	for item in leaf_clusters:
		var mi: MeshInstance3D = item.node
		if is_instance_valid(mi):
			if amount <= 0.001:
				mi.visible = false
			elif amount >= 0.999:
				mi.visible = true
			else:
				mi.visible = float(item.get("rank", 0.5)) <= amount


func add_bud(t_attach: float, local_pos: Vector3, local_basis: Basis, bud_scale: float, is_outward: bool) -> void:
	if _cached_bud_mesh == null:
		_cached_bud_mesh = _create_bud_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _cached_bud_mesh
	if bud_material:
		mi.material_override = bud_material
	mi.position = local_pos
	mi.basis = local_basis.scaled(Vector3.ONE * bud_scale)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	buds.append({
		"node": mi,
		"t": t_attach,
		"pos": local_pos,
		"basis": local_basis,
		"scale": bud_scale,
		"outward": is_outward,
	})


func add_attached_branch(t_attach: float, child_branch: PrunableBranch) -> void:
	add_child(child_branch)
	attached_children.append({
		"node": child_branch,
		"t": t_attach,
	})


func get_total_length() -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return maxf(total, 0.01)


func sample_at_t(t: float) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	if points.size() < 2:
		return {"pos": Vector3.ZERO, "dir": Vector3.UP, "radius": 0.01}
	var f_idx := t * float(points.size() - 1)
	var i0 := mini(int(floor(f_idx)), points.size() - 2)
	var frac := f_idx - float(i0)
	var pos := points[i0].lerp(points[i0 + 1], frac)
	var dir := (points[i0 + 1] - points[i0]).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector3.UP
	var rad := lerpf(radii[i0], radii[i0 + 1], frac)
	return {"pos": pos, "dir": dir, "radius": rad}


func closest_t_to_world(world_pos: Vector3) -> Dictionary:
	var local_p := to_local(world_pos)
	var best_dist := 1e9
	var best_t := 0.5
	var best_local := Vector3.ZERO
	var n := points.size()
	if n < 2:
		return {"dist": 1e9, "t": 0.0, "world_pos": global_position, "world_dir": Vector3.UP, "radius": 0.01}

	for i in range(n - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var ab_len2 := ab.length_squared()
		var seg_t := 0.0
		if ab_len2 > 1e-8:
			seg_t = clampf((local_p - a).dot(ab) / ab_len2, 0.0, 1.0)
		var closest := a + ab * seg_t
		var rad := lerpf(radii[i], radii[i + 1], seg_t)
		var surface_dist := maxf(0.0, local_p.distance_to(closest) - rad)
		if surface_dist < best_dist:
			best_dist = surface_dist
			best_t = (float(i) + seg_t) / float(n - 1)
			best_local = closest

	var samp := sample_at_t(best_t)
	return {
		"dist": best_dist,
		"t": best_t,
		"world_pos": to_global(best_local),
		"world_dir": (global_transform.basis * (samp.dir as Vector3)).normalized(),
		"radius": float(samp.radius),
	}


func closest_to_ray_world(ray_orig: Vector3, ray_dir: Vector3) -> Dictionary:
	var best_ray_dist := 1e9
	var best_t := 0.5
	var best_local := Vector3.ZERO
	var n := points.size()
	if n < 2:
		return {"ray_dist": 1e9}

	var lo := to_local(ray_orig)
	var ld := (global_transform.basis.inverse() * ray_dir).normalized()

	for i in range(n - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var ab_len2 := ab.length_squared()
		if ab_len2 < 1e-8:
			continue
		# Closest approach between ray (lo + s * ld) and segment (a + u * ab)
		var w0 := lo - a
		var a_dot := ld.dot(ld)
		var b_dot := ld.dot(ab)
		var c_dot := ab_len2
		var d_dot := ld.dot(w0)
		var e_dot := ab.dot(w0)
		var denom := a_dot * c_dot - b_dot * b_dot
		var s := 0.0
		var u := 0.0
		if denom > 1e-6:
			s = clampf((b_dot * e_dot - c_dot * d_dot) / denom, 0.05, 5.0)
			u = clampf((a_dot * e_dot - b_dot * d_dot) / denom, 0.0, 1.0)
		else:
			u = 0.5
			s = maxf(0.05, ((a + ab * u) - lo).dot(ld))
		# Re-project s onto segment point for exact perpendicular distance
		var seg_pt := a + ab * u
		s = maxf(0.05, (seg_pt - lo).dot(ld))
		var ray_pt := lo + ld * s
		var rad := lerpf(radii[i], radii[i + 1], u)
		var d_surf := maxf(0.0, ray_pt.distance_to(seg_pt) - rad)
		if d_surf < best_ray_dist:
			best_ray_dist = d_surf
			best_t = (float(i) + u) / float(n - 1)
			best_local = seg_pt

	var samp := sample_at_t(best_t)
	return {
		"ray_dist": best_ray_dist,
		"dist": best_ray_dist,
		"t": best_t,
		"world_pos": to_global(best_local),
		"world_dir": (global_transform.basis * (samp.dir as Vector3)).normalized(),
		"radius": float(samp.radius),
	}


func evaluate_cut_quality(t_cut: float) -> Dictionary:
	if kind == TreeSpecies.BranchKind.TRUNK:
		return {"grade": "DANGER", "message": "Main Trunk! Do not top the central leader.", "color": Color(0.95, 0.18, 0.18), "score": -25}
	if kind == TreeSpecies.BranchKind.SCAFFOLD:
		return {"grade": "WARN", "message": "Primary Scaffold — Preserve structural framework!", "color": Color(0.95, 0.25, 0.20), "score": -15}
	if kind == TreeSpecies.BranchKind.LATERAL:
		var len_lat := get_total_length()
		var best_bud: Dictionary = {}
		var best_dist_above := 1e9
		for bd in buds:
			var bt: float = float(bd.t)
			if bt <= t_cut:
				var d_above := (t_cut - bt) * len_lat
				if d_above < best_dist_above:
					best_dist_above = d_above
					best_bud = bd
		if not best_bud.is_empty() and best_dist_above <= 0.042:
			if bool(best_bud.outward):
				return {"grade": "GOOD BUD CUT", "message": "Good Heading Cut just above an outward-facing bud!", "color": Color(0.26, 0.90, 0.54), "score": 8}
			else:
				return {"grade": "INWARD BUD", "message": "Cut above inward bud — outward-facing bud is better", "color": Color(0.95, 0.72, 0.22), "score": 0}
		return {"grade": "WARN", "message": "Healthy Lateral — Prune ~1 cm above an outward bud if thinning.", "color": Color(0.95, 0.65, 0.18), "score": -4}

	var len_m := get_total_length()
	var dist_from_base := t_cut * len_m
	var base_rad := radii[0] if radii.size() > 0 else 0.015
	var ideal_min := clampf(base_rad * 0.75, 0.008, 0.032)
	var ideal_max := clampf(maxf(base_rad * 4.2, len_m * 0.24), 0.048, 0.13)

	if dist_from_base < ideal_min * 0.55:
		return {"grade": "FLUSH", "message": "Slightly too flush — shift 1 cm outward to protect collar", "color": Color(0.96, 0.55, 0.15), "score": 6}
	elif dist_from_base <= ideal_max:
		return {"grade": "PERFECT", "message": "Clean Collar Cut! (" + TreeSpecies.kind_label(kind) + ")", "color": Color(0.18, 0.95, 0.42), "score": 15}
	else:
		return {"grade": "STUB", "message": "Stub left — cut closer to the branch collar", "color": Color(0.95, 0.80, 0.20), "score": 8}


func set_hint_beacon(show_hint: bool, tint: Color) -> void:
	# Keep realistic PBR bark completely unwashed; place a subtle glowing collar ring marker instead!
	if not show_hint or is_cut or is_severed_debris or points.size() < 2:
		if is_instance_valid(_hint_beacon):
			_hint_beacon.visible = false
		return
	if not is_instance_valid(_hint_beacon):
		var torus := TorusMesh.new()
		torus.inner_radius = 0.013
		torus.outer_radius = 0.017
		torus.rings = 16
		torus.ring_segments = 8
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hint_beacon = MeshInstance3D.new()
		_hint_beacon.mesh = torus
		_hint_beacon.material_override = mat
		add_child(_hint_beacon)

	var ideal_t := clampf(0.11, 0.06, 0.20)
	var s := sample_at_t(ideal_t)
	var up := (s.dir as Vector3).normalized()
	var x_ax := up.cross(Vector3.FORWARD)
	if x_ax.length_squared() < 0.001:
		x_ax = up.cross(Vector3.RIGHT)
	x_ax = x_ax.normalized()
	var z_ax := x_ax.cross(up).normalized()
	_hint_beacon.transform = Transform3D(Basis(x_ax, up, z_ax), s.pos as Vector3)
	var sc := clampf(float(s.radius) / 0.011, 0.75, 2.4)
	_hint_beacon.scale = Vector3(sc, 1.0, sc)
	var bmat := _hint_beacon.material_override as StandardMaterial3D
	bmat.albedo_color = Color(tint.r, tint.g, tint.b, 0.68)
	_hint_beacon.visible = true


func update_saw_kerf(t_cut: float, progress: float) -> void:
	if progress <= 0.01 or is_severed_debris:
		if is_instance_valid(_saw_kerf_ring):
			_saw_kerf_ring.visible = false
		return
	if not is_instance_valid(_saw_kerf_ring):
		var cyl := CylinderMesh.new()
		cyl.height = 0.005
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.10, 0.06, 1.0)
		mat.roughness = 0.95
		_saw_kerf_ring = MeshInstance3D.new()
		_saw_kerf_ring.mesh = cyl
		_saw_kerf_ring.material_override = mat
		add_child(_saw_kerf_ring)

	var s := sample_at_t(t_cut)
	var up := (s.dir as Vector3).normalized()
	var x_ax := up.cross(Vector3.FORWARD)
	if x_ax.length_squared() < 0.001:
		x_ax = up.cross(Vector3.RIGHT)
	x_ax = x_ax.normalized()
	var z_ax := x_ax.cross(up).normalized()
	var r := float(s.radius) * 1.04
	_saw_kerf_ring.transform = Transform3D(Basis(x_ax, up, z_ax), s.pos as Vector3)
	_saw_kerf_ring.scale = Vector3(r, 1.0 + progress * 1.6, r)
	_saw_kerf_ring.visible = true


func rebuild_geometry(cap_start: bool = false, cap_end: bool = true) -> void:
	if points.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n := points.size()
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	var tangents: Array[Vector3] = []
	var v_coords: PackedFloat32Array = PackedFloat32Array()

	var prev_right := Vector3.RIGHT
	var accum_len := 0.0

	for i in range(n):
		var p := points[i]
		if i > 0:
			accum_len += p.distance_to(points[i - 1])
		v_coords.append(accum_len * 3.8)

		var tang: Vector3
		if i == 0:
			tang = (points[1] - p).normalized()
		elif i == n - 1:
			tang = (p - points[n - 2]).normalized()
		else:
			tang = (points[i + 1] - points[i - 1]).normalized()
		if tang.length_squared() < 0.001:
			tang = Vector3.UP
		tangents.append(tang)

		var right := prev_right - tang * prev_right.dot(tang)
		if right.length_squared() < 0.001:
			var alt := Vector3.FORWARD if absf(tang.dot(Vector3.UP)) > 0.9 else Vector3.UP
			right = alt.cross(tang)
		right = right.normalized()
		prev_right = right
		var up := tang.cross(right).normalized()

		# Root buttress flare on trunk base or branch collar bulge at parent junction
		var r := radii[i]
		if kind == TreeSpecies.BranchKind.TRUNK and i == 0:
			r *= 1.32
		elif kind == TreeSpecies.BranchKind.TRUNK and i == 1:
			r *= 1.12
		elif i == 0 and not cap_start:
			r *= 1.30
		elif i == 1 and not cap_start and n >= 4:
			r *= 1.09

		# Natural arborist beveled cut plane on severed ends
		var cut_slant_dir := (right * 0.34 + Vector3.UP * 0.16).normalized()

		var ring := PackedVector3Array()
		var norms := PackedVector3Array()
		for s in range(RADIAL_SEGS + 1):
			var ang := float(s) / float(RADIAL_SEGS) * TAU
			var lobe := 1.0
			if kind == TreeSpecies.BranchKind.TRUNK and i <= 1:
				# 5-lobed organic root flare flutes at trunk base
				lobe += 0.16 * pow(0.5 + 0.5 * cos(ang * 5.0 + float(branch_id)), 1.6) * (1.0 - float(i) * 0.55)
			else:
				lobe += 0.055 * sin(ang * 3.0 + float(branch_id) + float(i) * 0.85)
			var dir_r := (right * cos(ang) + up * sin(ang)).normalized()
			var pt_ring := p + dir_r * (r * lobe)
			if i == n - 1 and is_cut and cap_end:
				# Slight realistic ~20-deg angled cut face to shed water like real pruning!
				pt_ring += tang * (dir_r.dot(cut_slant_dir) * r * 0.36)
			ring.append(pt_ring)
			norms.append(dir_r)
		rings.append(ring)
		ring_normals.append(norms)

	for i in range(n - 1):
		for s in range(RADIAL_SEGS):
			var u0 := float(s) / float(RADIAL_SEGS)
			var u1 := float(s + 1) / float(RADIAL_SEGS)
			var v0 := v_coords[i]
			var v1 := v_coords[i + 1]

			var a := rings[i][s]
			var b := rings[i][s + 1]
			var c := rings[i + 1][s + 1]
			var d := rings[i + 1][s]

			var na := ring_normals[i][s]
			var nb := ring_normals[i][s + 1]
			var nc := ring_normals[i + 1][s + 1]
			var nd := ring_normals[i + 1][s]

			st.set_normal(na); st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
			st.set_normal(nb); st.set_uv(Vector2(u1, v0)); st.add_vertex(b)
			st.set_normal(nc); st.set_uv(Vector2(u1, v1)); st.add_vertex(c)

			st.set_normal(na); st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
			st.set_normal(nc); st.set_uv(Vector2(u1, v1)); st.add_vertex(c)
			st.set_normal(nd); st.set_uv(Vector2(u0, v1)); st.add_vertex(d)

	st.generate_tangents()
	_mesh_instance.mesh = st.commit()
	_mesh_instance.material_override = null
	_mesh_instance.set_surface_override_material(0, bark_material)
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_severed_debris else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	if cap_start or (cap_end and is_cut):
		var cap_st := SurfaceTool.new()
		cap_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if cap_end and is_cut:
			_add_cap_disk(cap_st, points[n - 1], rings[n - 1], tangents[n - 1], false)
		if cap_start:
			_add_cap_disk(cap_st, points[0], rings[0], -tangents[0], true)
		cap_st.generate_tangents()
		var mesh_with_cap := _mesh_instance.mesh as ArrayMesh
		cap_st.commit(mesh_with_cap)
		if mesh_with_cap.get_surface_count() > 1:
			_mesh_instance.set_surface_override_material(1, cut_material)

	# Rebuild collision capsules
	for c in _static_body.get_children():
		c.queue_free()
	if not is_severed_debris:
		for i in range(n - 1):
			var p0 := points[i]
			var p1 := points[i + 1]
			var seg := p1 - p0
			var seg_len := seg.length()
			if seg_len < 0.005:
				continue
			var col := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = maxf(0.011, maxf(radii[i], radii[i + 1]) * 1.15)
			cap.height = seg_len + cap.radius * 1.4
			col.shape = cap
			var mid := (p0 + p1) * 0.5
			var y_dir := seg.normalized()
			var x_dir := y_dir.cross(Vector3.FORWARD)
			if x_dir.length_squared() < 0.001:
				x_dir = y_dir.cross(Vector3.RIGHT)
			x_dir = x_dir.normalized()
			var z_dir := x_dir.cross(y_dir).normalized()
			col.transform = Transform3D(Basis(x_dir, y_dir, z_dir), mid)
			_static_body.add_child(col)


func _add_cap_disk(st: SurfaceTool, center: Vector3, ring: PackedVector3Array, normal: Vector3, flip: bool) -> void:
	var n_dir := normal.normalized()
	for s in range(RADIAL_SEGS):
		var a0 := float(s) / float(RADIAL_SEGS) * TAU
		var a1 := float(s + 1) / float(RADIAL_SEGS) * TAU
		var uv_c := Vector2(0.5, 0.5)
		var uv0 := Vector2(0.5 + 0.48 * cos(a0), 0.5 + 0.48 * sin(a0))
		var uv1 := Vector2(0.5 + 0.48 * cos(a1), 0.5 + 0.48 * sin(a1))
		if flip:
			st.set_normal(n_dir); st.set_uv(uv_c); st.add_vertex(center)
			st.set_normal(n_dir); st.set_uv(uv1); st.add_vertex(ring[s + 1])
			st.set_normal(n_dir); st.set_uv(uv0); st.add_vertex(ring[s])
		else:
			st.set_normal(n_dir); st.set_uv(uv_c); st.add_vertex(center)
			st.set_normal(n_dir); st.set_uv(uv0); st.add_vertex(ring[s])
			st.set_normal(n_dir); st.set_uv(uv1); st.add_vertex(ring[s + 1])


func split_at_t(t_cut: float) -> Dictionary:
	t_cut = clampf(t_cut, 0.05, 0.90)
	var orig_points := points.duplicate()
	var orig_radii := radii.duplicate()
	var was_cut := is_cut

	var n := points.size()
	var f_idx := t_cut * float(n - 1)
	var i0 := mini(int(floor(f_idx)), n - 2)
	var frac := f_idx - float(i0)
	var cut_pos := points[i0].lerp(points[i0 + 1], frac)
	var cut_rad := lerpf(radii[i0], radii[i0 + 1], frac)

	# Ensure proximal stub always has >= 2 distinct points
	var kept_pts := PackedVector3Array()
	var kept_rads := PackedFloat32Array()
	for i in range(i0 + 1):
		kept_pts.append(points[i])
		kept_rads.append(radii[i])
	if kept_pts[kept_pts.size() - 1].distance_to(cut_pos) > 0.002:
		kept_pts.append(cut_pos)
		kept_rads.append(cut_rad)
	elif kept_pts.size() == 1:
		var push_dir := (points[1] - points[0]).normalized()
		cut_pos = points[0] + push_dir * 0.012
		kept_pts.append(cut_pos)
		kept_rads.append(cut_rad)

	var sev_pts := PackedVector3Array()
	var sev_rads := PackedFloat32Array()
	sev_pts.append(Vector3.ZERO)
	sev_rads.append(cut_rad)
	for i in range(i0 + 1, n):
		if points[i].distance_to(cut_pos) > 0.002 or i == n - 1:
			sev_pts.append(points[i] - cut_pos)
			sev_rads.append(radii[i])
	if sev_pts.size() < 2:
		sev_pts.append((points[n - 1] - points[0]).normalized() * 0.02)
		sev_rads.append(cut_rad * 0.85)

	points = kept_pts
	radii = kept_rads
	is_cut = true
	saw_progress = 0.0
	if is_instance_valid(_saw_kerf_ring):
		_saw_kerf_ring.visible = false
	rebuild_geometry(false, true)

	# Partition attached foliage and child branches AND rescale remaining t values!
	var moved_leaves: Array[Dictionary] = []
	var remaining_leaves: Array[Dictionary] = []
	for item in leaf_clusters:
		var orig_t: float = float(item.t)
		if orig_t > t_cut:
			item["was_visible"] = item.node.visible
			item.node.visible = false
			moved_leaves.append(item)
		else:
			item["prev_t"] = orig_t
			item["t"] = clampf(orig_t / t_cut, 0.0, 1.0)
			remaining_leaves.append(item)
	leaf_clusters = remaining_leaves

	var moved_buds: Array[Dictionary] = []
	var remaining_buds: Array[Dictionary] = []
	for bd in buds:
		var orig_bt: float = float(bd.t)
		if orig_bt > t_cut:
			bd.node.visible = false
			moved_buds.append(bd)
		else:
			bd["prev_t"] = orig_bt
			bd["t"] = clampf(orig_bt / t_cut, 0.0, 1.0)
			remaining_buds.append(bd)
	buds = remaining_buds

	var moved_children: Array[Dictionary] = []
	var remaining_children: Array[Dictionary] = []
	for item in attached_children:
		var orig_t: float = float(item.t)
		if orig_t > t_cut:
			var cb: PrunableBranch = item.node
			remove_child(cb)
			moved_children.append(item)
		else:
			item["prev_t"] = orig_t
			item["t"] = clampf(orig_t / t_cut, 0.0, 1.0)
			remaining_children.append(item)
	attached_children = remaining_children

	return {
		"branch": self,
		"t_cut": t_cut,
		"cut_pos_local": cut_pos,
		"cut_rad": cut_rad,
		"orig_points": orig_points,
		"orig_radii": orig_radii,
		"was_cut": was_cut,
		"sev_points": sev_pts,
		"sev_radii": sev_rads,
		"moved_leaves": moved_leaves,
		"moved_buds": moved_buds,
		"moved_children": moved_children,
		"rescaled_leaves": remaining_leaves.duplicate(),
		"rescaled_buds": remaining_buds.duplicate(),
		"rescaled_children": remaining_children.duplicate(),
	}


func restore_from_split(record: Dictionary) -> void:
	points = record.orig_points.duplicate()
	radii = record.orig_radii.duplicate()
	is_cut = record.was_cut
	saw_progress = 0.0
	if is_instance_valid(_saw_kerf_ring):
		_saw_kerf_ring.visible = false
	rebuild_geometry(false, true)

	for item in record.get("rescaled_leaves", []):
		if item.has("prev_t"):
			item["t"] = item["prev_t"]
	for bd in record.get("rescaled_buds", []):
		if bd.has("prev_t"):
			bd["t"] = bd["prev_t"]
	for item in record.get("rescaled_children", []):
		if item.has("prev_t"):
			item["t"] = item["prev_t"]

	for item in record.moved_leaves:
		item.node.visible = true
		leaf_clusters.append(item)
	for bd in record.get("moved_buds", []):
		bd.node.visible = true
		buds.append(bd)
	for item in record.moved_children:
		var cb: PrunableBranch = item.node
		add_child(cb)
		attached_children.append(item)


func count_remaining_targets() -> Dictionary:
	var targets := 0
	var healthy := 0
	if not is_cut and kind != TreeSpecies.BranchKind.TRUNK:
		if TreeSpecies.should_prune(kind):
			targets += 1
		else:
			healthy += 1
	for item in attached_children:
		var c: PrunableBranch = item.node
		var sub := c.count_remaining_targets()
		targets += sub.targets
		healthy += sub.healthy
	return {"targets": targets, "healthy": healthy}


static func _create_botanical_bough_mesh(sz: float) -> ArrayMesh:
	## Creates a lush 5-card arched 3D foliage bough with vertex AO (darker core, bright sunlit outer tips).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := sz * 0.52
	var planes := [
		{"yaw": 0.0, "pitch": 18.0, "roll": 4.0, "ao_tip": 1.04},
		{"yaw": 72.0, "pitch": 26.0, "roll": -6.0, "ao_tip": 1.00},
		{"yaw": 144.0, "pitch": 22.0, "roll": 5.0, "ao_tip": 0.98},
		{"yaw": 216.0, "pitch": 30.0, "roll": -4.0, "ao_tip": 0.95},
		{"yaw": 288.0, "pitch": 16.0, "roll": 6.0, "ao_tip": 1.02},
	]
	for p in planes:
		var rot := Basis(Vector3.UP, deg_to_rad(p.yaw)) * Basis(Vector3.RIGHT, deg_to_rad(p.pitch)) * Basis(Vector3.FORWARD, deg_to_rad(p.roll))
		var arch := sz * 0.14
		var p0 := rot * Vector3(-half, 0.0, 0.0)
		var p1 := rot * Vector3(half, 0.0, 0.0)
		var pm_l := rot * Vector3(-half * 1.04, sz * 0.52, arch)
		var pm_r := rot * Vector3(half * 1.04, sz * 0.52, arch)
		var p2 := rot * Vector3(half * 0.95, sz, -arch * 0.35)
		var p3 := rot * Vector3(-half * 0.95, sz, -arch * 0.35)
		var n_base := (rot * Vector3(0.0, 0.30, 1.0)).normalized()
		var n_tip := (rot * Vector3(0.0, 0.65, 0.75)).normalized()
		# Lower half (closer to twig stem, deeper AO)
		_emit_quad_ao(st, p0, p1, pm_r, pm_l, n_base, 0.68, 0.88, 1.0, 0.5)
		# Upper half (sunlit curved outer tip)
		_emit_quad_ao(st, pm_l, pm_r, p2, p3, n_tip, 0.88, p.ao_tip, 0.5, 0.0)

	st.generate_tangents()
	return st.commit()


static func _emit_quad_ao(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		n: Vector3, ao_bot: float, ao_top: float, v_bot: float, v_top: float) -> void:
	var c_bot := Color(ao_bot, ao_bot, ao_bot, 1.0)
	var c_top := Color(ao_top, ao_top, ao_top, 1.0)

	st.set_color(c_bot); st.set_normal(n); st.set_uv(Vector2(0.0, v_bot)); st.add_vertex(p0)
	st.set_color(c_bot); st.set_normal(n); st.set_uv(Vector2(1.0, v_bot)); st.add_vertex(p1)
	st.set_color(c_top); st.set_normal(n); st.set_uv(Vector2(1.0, v_top)); st.add_vertex(p2)

	st.set_color(c_bot); st.set_normal(n); st.set_uv(Vector2(0.0, v_bot)); st.add_vertex(p0)
	st.set_color(c_top); st.set_normal(n); st.set_uv(Vector2(1.0, v_top)); st.add_vertex(p2)
	st.set_color(c_top); st.set_normal(n); st.set_uv(Vector2(0.0, v_top)); st.add_vertex(p3)


static func _create_bud_mesh() -> ArrayMesh:
	## Sculpted unit teardrop botanical bud (+Y axis = bud tip, base at 0) with woody collar & pointed apex.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof: Array[Vector2] = [
		Vector2(0.18, 0.00),
		Vector2(0.30, 0.18),
		Vector2(0.38, 0.42),
		Vector2(0.32, 0.68),
		Vector2(0.17, 0.88),
		Vector2(0.00, 1.00),
	]
	var segs := 8
	for r_idx in range(prof.size() - 1):
		var r0: float = prof[r_idx].x
		var y0: float = prof[r_idx].y
		var r1: float = prof[r_idx + 1].x
		var y1: float = prof[r_idx + 1].y
		var v0: float = 1.0 - y0
		var v1: float = 1.0 - y1
		for s in range(segs):
			var a0 := float(s) / float(segs) * TAU
			var a1 := float(s + 1) / float(segs) * TAU
			var u0 := float(s) / float(segs)
			var u1 := float(s + 1) / float(segs)
			var p00 := Vector3(r0 * cos(a0), y0, r0 * sin(a0))
			var p01 := Vector3(r0 * cos(a1), y0, r0 * sin(a1))
			var p11 := Vector3(r1 * cos(a1), y1, r1 * sin(a1))
			var p10 := Vector3(r1 * cos(a0), y1, r1 * sin(a0))
			var n0 := Vector3(cos(a0), 0.35, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), 0.35, sin(a1)).normalized()
			if r1 > 0.001:
				st.set_normal(n0); st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
				st.set_normal(n1); st.set_uv(Vector2(u1, v0)); st.add_vertex(p01)
				st.set_normal(n1); st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)

				st.set_normal(n0); st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
				st.set_normal(n1); st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
				st.set_normal(n0); st.set_uv(Vector2(u0, v1)); st.add_vertex(p10)
			else:
				st.set_normal(n0); st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
				st.set_normal(n1); st.set_uv(Vector2(u1, v0)); st.add_vertex(p01)
				st.set_normal(Vector3.UP); st.set_uv(Vector2((u0 + u1) * 0.5, 0.0)); st.add_vertex(p10)
	st.generate_tangents()
	return st.commit()
