class_name TreeSpecies
extends RefCounted

## Defines botanical species parameters and pruning rules for realistic procedural trees.

enum BranchKind {
	TRUNK,
	SCAFFOLD,     # Primary structural branch - KEEP
	LATERAL,      # Healthy fruit/canopy lateral - KEEP unless overcrowded
	DEADWOOD,     # Dead brittle twig/limb - PRUNE
	DISEASED,     # Blighted / cankered branch - PRUNE
	CROSSING,     # Inward / rubbing branch - PRUNE
	WATERSPROUT,  # Vigorous upright shoot - PRUNE
	SUCKER        # Basal rootstock shoot - PRUNE
}

const SPECIES_CONFIG := {
	"apple": {
		"title": "Honeycrisp Apple (Orchard)",
		"subtitle": "Open-Center Training: Remove deadwood, crossing limbs & upright watersprouts.",
		"bark_albedo": "res://assets/textures/bark_apple_albedo.png",
		"bark_normal": "res://assets/textures/bark_apple_normal.png",
		"bark_roughness": "res://assets/textures/bark_apple_roughness.png",
		"leaf_albedo": "res://assets/textures/leaf_apple_albedo.png",
		"leaf_normal": "res://assets/textures/leaf_apple_normal.png",
		"backlight": Color(0.35, 0.52, 0.14, 1.0),
		"trunk_height": 0.74,
		"trunk_radius": 0.062,
		"scaffold_count": 4,
		"branch_spread": 0.72,
		"leaf_scale": 0.25,
		"leaf_tint": Color(0.96, 1.0, 0.92, 1.0),
	},
	"maple": {
		"title": "Japanese Maple (Acer palmatum)",
		"subtitle": "Aesthetic Layering: Thin crowded shoots, remove deadwood & balance tiers.",
		"bark_albedo": "res://assets/textures/bark_maple_albedo.png",
		"bark_normal": "res://assets/textures/bark_maple_normal.png",
		"bark_roughness": "res://assets/textures/bark_maple_roughness.png",
		"leaf_albedo": "res://assets/textures/leaf_maple_albedo.png",
		"leaf_normal": "res://assets/textures/leaf_maple_normal.png",
		"backlight": Color(0.58, 0.16, 0.10, 1.0),
		"trunk_height": 0.68,
		"trunk_radius": 0.052,
		"scaffold_count": 5,
		"branch_spread": 0.82,
		"leaf_scale": 0.24,
		"leaf_tint": Color(1.0, 0.94, 0.92, 1.0),
	},
	"olive": {
		"title": "Garden Olive (Rejuvenation)",
		"subtitle": "Crown Renewal: Clear basal suckers, diseased grey shoots & dense interior.",
		"bark_albedo": "res://assets/textures/bark_olive_albedo.png",
		"bark_normal": "res://assets/textures/bark_olive_normal.png",
		"bark_roughness": "res://assets/textures/bark_olive_roughness.png",
		"leaf_albedo": "res://assets/textures/leaf_olive_albedo.png",
		"leaf_normal": "res://assets/textures/leaf_olive_normal.png",
		"backlight": Color(0.28, 0.42, 0.24, 1.0),
		"trunk_height": 0.64,
		"trunk_radius": 0.068,
		"scaffold_count": 4,
		"branch_spread": 0.75,
		"leaf_scale": 0.23,
		"leaf_tint": Color(0.95, 0.99, 0.94, 1.0),
	}
}


static func should_prune(kind: BranchKind) -> bool:
	return kind in [
		BranchKind.DEADWOOD,
		BranchKind.DISEASED,
		BranchKind.CROSSING,
		BranchKind.WATERSPROUT,
		BranchKind.SUCKER,
	]


static func kind_label(kind: BranchKind) -> String:
	match kind:
		BranchKind.TRUNK: return "Main Trunk (Preserve)"
		BranchKind.SCAFFOLD: return "Primary Scaffold (Preserve)"
		BranchKind.LATERAL: return "Healthy Lateral (Preserve)"
		BranchKind.DEADWOOD: return "Deadwood (Prune at Collar)"
		BranchKind.DISEASED: return "Diseased Limb (Prune Clean)"
		BranchKind.CROSSING: return "Crossing / Inward (Prune)"
		BranchKind.WATERSPROUT: return "Upright Watersprout (Prune)"
		BranchKind.SUCKER: return "Basal Sucker (Remove Flush)"
	return "Branch"


static func kind_hint_color(kind: BranchKind) -> Color:
	match kind:
		BranchKind.DEADWOOD: return Color(0.95, 0.48, 0.16)
		BranchKind.DISEASED: return Color(0.92, 0.20, 0.22)
		BranchKind.CROSSING: return Color(0.95, 0.76, 0.18)
		BranchKind.WATERSPROUT: return Color(0.92, 0.62, 0.22)
		BranchKind.SUCKER: return Color(0.96, 0.30, 0.42)
		_: return Color(0.28, 0.85, 0.45)
