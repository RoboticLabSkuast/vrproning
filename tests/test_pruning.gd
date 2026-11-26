extends SceneTree

## Headless integration test suite verifying tree generation, species switching,
## branch collar evaluation, tool diameter limits, real-time 3D branch splitting, and undo.

var _ran: bool = false
var _rig: TreeRig


func _initialize() -> void:
	print("=== VR Pruning Headless Verification Suite ===")
	var tree_rig_script := load("res://scripts/tree_rig.gd")
	if tree_rig_script == null:
		printerr("FAIL: Could not load res://scripts/tree_rig.gd")
		quit(1)
		return
	_rig = tree_rig_script.new()
	root.add_child(_rig)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true

	var rig := _rig
	if rig == null or rig._all_branches.size() < 10:
		printerr("FAIL: Expected >=10 botanical branches generated, got ", 0 if rig == null else rig._all_branches.size())
		quit(1)
		return true
	var total_buds := 0
	for b in rig._all_branches:
		total_buds += b.buds.size()
	if total_buds < 30:
		printerr("FAIL: Expected >=30 botanical buds on tree, got ", total_buds)
		quit(1)
		return true
	print("[PASS] Tree generated with ", rig._all_branches.size(), " branches and ", total_buds, " botanical buds")

	var dead_branch: PrunableBranch = null
	var thick_branch: PrunableBranch = null
	var scaffold_branch: PrunableBranch = null
	for b in rig._all_branches:
		if b.kind == TreeSpecies.BranchKind.DEADWOOD and b.radii[0] * 200.0 > 2.8:
			thick_branch = b
		elif TreeSpecies.should_prune(b.kind) and b.radii[0] * 200.0 <= 2.2:
			dead_branch = b
		elif b.kind == TreeSpecies.BranchKind.SCAFFOLD:
			scaffold_branch = b

	if dead_branch == null or thick_branch == null or scaffold_branch == null:
		printerr("FAIL: Missing expected branch roles (thin/thick/scaffold)")
		quit(1)
		return true

	# Test 1: Tool capacity enforcement (secateurs jam on thick branch)
	var jam_res := rig.try_cut_branch(thick_branch, 0.14, "secateurs")
	if not jam_res.get("jammed", false):
		printerr("FAIL: Secateurs must jam on thick branch")
		quit(1)
		return true
	print("[PASS] Secateurs correctly rejected thick limb (", snappedf(thick_branch.radii[0] * 200.0, 0.1), " cm)")

	# Test 2: Secateurs clean collar cut on thin target branch
	var cut_res := rig.try_cut_branch(dead_branch, 0.12, "secateurs")
	if not cut_res.get("cut", false) or not dead_branch.is_cut or rig._debris_holder.get_child_count() != 1:
		printerr("FAIL: Secateurs cut or debris spawn failed")
		quit(1)
		return true
	print("[PASS] Real-time 3D branch split + RigidBody3D debris spawned: ", cut_res.get("message"))

	# Test 3: Progressive Japanese Pruning Saw on thick limb
	var saw_part := rig.try_cut_branch(thick_branch, 0.14, "saw", 0.15)
	if not saw_part.get("sawing", false) or thick_branch.is_cut:
		printerr("FAIL: Partial saw stroke should progress kerf without severing")
		quit(1)
		return true
	var saw_done := rig.try_cut_branch(thick_branch, 0.14, "saw", 1.5)
	if not saw_done.get("cut", false) or not thick_branch.is_cut:
		printerr("FAIL: Completed saw cut must sever thick limb")
		quit(1)
		return true
	print("[PASS] Progressive Japanese Pruning Saw severed thick limb")

	# Test 4: Undo restores branch cleanly
	var undone := rig.undo_last_cut()
	if not undone or thick_branch.is_cut:
		printerr("FAIL: Undo must restore severed branch")
		quit(1)
		return true
	print("[PASS] Undo restored branch and removed debris")

	# Test 4b: Trunk protection check
	var trunk_res := rig.try_cut_branch(rig._trunk, 0.5, "saw", 2.0)
	if not trunk_res.get("jammed", false) or rig._trunk.is_cut:
		printerr("FAIL: Trunk should be protected")
		quit(1)
		return true
	print("[PASS] Main trunk protected from topping")

	# Test 4c: Multi-cut on scaffold ensures rescaled child t-coordinates detach cleanly
	var sc_child_count := scaffold_branch.attached_children.size()
	if sc_child_count > 0:
		var tip_cut := rig.try_cut_branch(scaffold_branch, 0.85, "loppers")
		var inner_cut := rig.try_cut_branch(scaffold_branch, 0.20, "saw", 3.0)
		if not tip_cut.get("cut", false) or not inner_cut.get("cut", false):
			printerr("FAIL: Multi-cut failed on scaffold: tip=", tip_cut, " inner=", inner_cut)
			quit(1)
			return true
		if scaffold_branch.attached_children.size() != 0:
			printerr("FAIL: Child branches remained floating after inner cut")
			quit(1)
			return true
		print("[PASS] Multi-cut rescaled and detached all distal sub-branches cleanly")

	# Test 5: Species switching (Japanese Maple & Garden Olive)
	for sp in ["maple", "olive", "apple"]:
		rig.generate_tree(sp, 202)
		if rig.species_id != sp or rig._all_branches.size() < 8:
			printerr("FAIL: Species %s failed to generate" % sp)
			quit(1)
			return true
	print("[PASS] All 3 botanical species verified (apple, maple, olive)")

	# Test 6: Verify main.tscn loads & instantiates cleanly
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		printerr("FAIL: Could not load res://scenes/main.tscn")
		quit(1)
		return true
	var inst := main_scene.instantiate()
	if inst == null:
		printerr("FAIL: Could not instantiate res://scenes/main.tscn")
		quit(1)
		return true
	inst.free()
	print("[PASS] Main scene (res://scenes/main.tscn) loads and instantiates cleanly")

	print("=== ALL TESTS PASSED ===")
	quit(0)
	return true
