class_name AudioFX
extends Node3D

## Spatialized audio player pool for pruning shears, saw rasps, falling branches, and UI clicks.

const SFX_FILES := {
	"snip_clean": "res://assets/audio/snip_clean.wav",
	"snip_thick": "res://assets/audio/snip_thick.wav",
	"snip_jam": "res://assets/audio/snip_jam.wav",
	"saw_stroke": "res://assets/audio/saw_stroke.wav",
	"branch_crack": "res://assets/audio/branch_crack.wav",
	"leaves_rustle": "res://assets/audio/leaves_rustle.wav",
	"ui_click": "res://assets/audio/ui_click.wav",
}

var _streams: Dictionary = {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_idx: int = 0


func _ready() -> void:
	for key in SFX_FILES:
		if ResourceLoader.exists(SFX_FILES[key]):
			_streams[key] = load(SFX_FILES[key])
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 12.0
		p.unit_size = 1.5
		add_child(p)
		_players_3d.append(p)


func play_at(sfx_name: String, world_pos: Vector3, pitch_jitter: float = 0.08, db: float = 0.0) -> void:
	if not _streams.has(sfx_name):
		return
	var p := _players_3d[_next_idx]
	_next_idx = (_next_idx + 1) % _players_3d.size()
	p.stop()
	p.stream = _streams[sfx_name]
	p.global_position = world_pos
	p.volume_db = db
	p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()

