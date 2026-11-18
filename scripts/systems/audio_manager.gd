extends Node
## AudioManager: 2D + 3D spatial audio playback for weapons, footsteps, bomb, and UI.
## Supports .ogg from cs2go and optional .wav overrides from ShadowNigth/archi.

const POOL_3D_SIZE := 32
const POOL_2D_SIZE := 16

var _players_3d: Array[AudioStreamPlayer3D] = []
var _idx_3d: int = 0
var _players_2d: Array[AudioStreamPlayer] = []
var _idx_2d: int = 0
var _cache: Dictionary = {}

func _ready() -> void:
	for i in range(POOL_3D_SIZE):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 65.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		add_child(p)
		_players_3d.append(p)

	for i in range(POOL_2D_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)

func _resolve_path(clip_name: String) -> String:
	var candidates := [
		"res://assets/audio/%s.ogg" % clip_name,
		"res://assets/audio/source/%s.ogg" % clip_name,
		"res://assets/audio/source/%s.wav" % clip_name,
		"res://assets/audio/archi/%s.wav" % clip_name,
		"res://assets/audio/%s.wav" % clip_name,
	]
	for c in candidates:
		if ResourceLoader.exists(c):
			return c
	return ""

func _get_stream(clip_name: String) -> AudioStream:
	if clip_name.is_empty():
		return null
	if _cache.has(clip_name):
		return _cache[clip_name]
	var path := _resolve_path(clip_name)
	if path.is_empty():
		_cache[clip_name] = null
		return null
	var stream: AudioStream = load(path)
	_cache[clip_name] = stream
	return stream

func play_2d(clip_name: String, volume_db: float = -3.0, pitch_scale: float = 1.0) -> void:
	var stream := _get_stream(clip_name)
	if stream == null:
		return
	var p := _players_2d[_idx_2d]
	_idx_2d = (_idx_2d + 1) % POOL_2D_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.play()

func play_3d(clip_name: String, world_pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var stream := _get_stream(clip_name)
	if stream == null:
		return
	var p := _players_3d[_idx_3d]
	_idx_3d = (_idx_3d + 1) % POOL_3D_SIZE
	p.global_position = world_pos
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.play()

func play_weapon_fire(weapon_id: int, world_pos: Vector3, is_local: bool, suppressed: bool = true) -> void:
	var kit := WeaponDB.get_audio_kit(weapon_id)
	var clip: String = str(kit.get("shot", "ak47-1"))
	if not suppressed and kit.has("unsuppressed"):
		clip = str(kit["unsuppressed"])
	var pitch := randf_range(0.97, 1.03)
	if is_local:
		play_2d(clip, -2.0, pitch)
	else:
		play_3d(clip, world_pos, 1.0, pitch)
		if kit.has("distant"):
			play_3d(str(kit["distant"]), world_pos, -4.0, pitch)

func play_weapon_cue(weapon_id: int, cue: String, world_pos: Vector3, is_local: bool) -> void:
	var kit := WeaponDB.get_audio_kit(weapon_id)
	if not kit.has(cue):
		return
	var clip := str(kit[cue])
	if is_local:
		play_2d(clip, -5.0)
	else:
		play_3d(clip, world_pos, -8.0)

func play_footstep(world_pos: Vector3, surface: String = "concrete", is_local: bool = false) -> void:
	var idx := randi_range(1, 4)
	var clip := "step-%s-%d" % [surface, idx]
	var vol := -11.0 if is_local else -6.0
	if is_local:
		play_2d(clip, vol, randf_range(0.95, 1.05))
	else:
		play_3d(clip, world_pos, vol, randf_range(0.95, 1.05))
