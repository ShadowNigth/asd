extends Node
## WeaponDB: Port of CS2GO/Source weapon stats, recoil tables, accuracy params,
## animation timings, and audio kit mappings.

const WEAPON_STATS_PATH := "res://assets/data/weapon-stats.json"
const RECOIL_PATH := "res://assets/data/recoil.json"
const ACCURACY_PATH := "res://assets/data/accuracy.json"
const WEAPON_ACTIONS_PATH := "res://assets/data/weapon-actions.json"

const VIEWMODEL_NAMES: Array[String] = [
	"ak-47",       # 0
	"m4a1_s",      # 1
	"usp-s",       # 2
	"awp",         # 3
	"bayonet",     # 4 (knife)
	"bayonet",     # 5 (butterfly fallback)
	"bayonet",     # 6 (karambit fallback)
	"glock",       # 7
	"deagle",      # 8
	"m4a4",        # 9
	"nova",        # 10
	"mp9",         # 11
	"hkp2000",     # 12
	"p250",        # 13
	"fiveseven",   # 14
	"tec9",        # 15
	"cz75a",       # 16
	"revolver",    # 17
	"elite",       # 18
	"famas",       # 19
	"galilar",     # 20
	"aug",         # 21
	"sg556",       # 22
	"ssg08",       # 23
	"scar20",      # 24
	"g3sg1",       # 25
	"mac10",       # 26
	"mp7",         # 27
	"mp5sd",       # 28
	"ump45",       # 29
	"p90",         # 30
	"bizon",       # 31
	"xm1014",      # 32
	"mag7",        # 33
	"sawedoff",    # 34
	"m249",        # 35
	"negev",       # 36
]

const AUDIO_KITS: Dictionary = {
	0: {"shot": "ak47-1", "distant": "ak47-1-distant", "reload": "ak47_clipout", "reloadIn": "ak47_clipin", "bolt": "ak47_boltpull", "boltForward": "ak47_boltpull", "draw": "ak47_draw"},
	1: {"shot": "m4a1-1-single", "unsuppressed": "m4a1-1", "reload": "m4a1_clipout", "reloadIn": "m4a1_clipin", "bolt": "m4a1_silencer_boltback", "boltForward": "m4a1_silencer_boltforward", "draw": "m4a1_draw"},
	2: {"shot": "usp1", "unsuppressed": "hkp2000-1", "reload": "usp_clipout", "reloadIn": "usp_clipin", "bolt": "usp_slideback", "boltForward": "usp_sliderelease", "draw": "usp_draw"},
	3: {"shot": "awp1", "scope": "zoom", "reload": "awp_clipout", "reloadIn": "awp_clipin", "bolt": "awp_boltback", "boltForward": "awp_boltforward", "draw": "awp_draw"},
	7: {"shot": "glock18-1", "reload": "glock_clipout", "reloadIn": "glock_clipin", "bolt": "glock_slideback", "boltForward": "glock_sliderelease", "draw": "glock_draw"},
	8: {"shot": "deagle-1", "reload": "de_clipout", "reloadIn": "de_clipin", "bolt": "de_slideback", "boltForward": "de_slideforward", "draw": "de_draw"},
	9: {"shot": "m4a1-1", "reload": "m4a1_clipout", "reloadIn": "m4a1_clipin", "bolt": "m4a1_boltback", "boltForward": "m4a1_boltforward", "draw": "m4a1_draw"},
	10: {"shot": "nova-1", "reload": "nova_insertshell", "reloadIn": "nova_insertshell", "bolt": "nova_pump", "boltForward": "nova_pump", "draw": "nova_draw"},
	11: {"shot": "mp9-1", "reload": "mp9_clipout", "reloadIn": "mp9_clipin", "bolt": "mp9_boltback", "boltForward": "mp9_boltforward", "draw": "mp9_draw"},
	12: {"shot": "hkp2000-1", "reload": "hkp2000_clipout", "reloadIn": "hkp2000_clipin", "bolt": "hkp2000_slideback", "boltForward": "hkp2000_sliderelease", "draw": "hkp2000_draw"},
	13: {"shot": "p250-1", "reload": "p250_clipout", "reloadIn": "p250_clipin", "bolt": "p250_slideback", "boltForward": "p250_sliderelease", "draw": "p250_draw"},
	14: {"shot": "fiveseven-1", "reload": "fiveseven_clipout", "reloadIn": "fiveseven_clipin", "bolt": "fiveseven_slideback", "boltForward": "fiveseven_sliderelease", "draw": "fiveseven_draw"},
	15: {"shot": "tec9-1", "reload": "tec9_clipout", "reloadIn": "tec9_clipin", "bolt": "tec9_boltpull", "boltForward": "tec9_boltrelease", "draw": "tec9_draw"},
	16: {"shot": "cz75a-1", "reload": "p250_clipout", "reloadIn": "cz75_clipin", "bolt": "p250_slideback", "boltForward": "p250_sliderelease", "draw": "p250_draw"},
	17: {"shot": "revolver-1_01", "reload": "revolver_clipout", "reloadIn": "revolver_clipin", "bolt": "revolver_sideback", "boltForward": "revolver_siderelease", "draw": "revolver_draw"},
	18: {"shot": "elite-1", "reload": "elite_clipout", "reloadIn": "elite_leftclipin", "bolt": "elite_sliderelease", "boltForward": "elite_sliderelease", "draw": "elite_draw"},
	19: {"shot": "famas-1", "reload": "famas_clipout", "reloadIn": "famas_clipin", "bolt": "famas_boltback", "boltForward": "famas_boltforward", "draw": "famas_draw"},
	20: {"shot": "galil-1", "reload": "galil_clipout", "reloadIn": "galil_clipin", "bolt": "galil_boltback", "boltForward": "galil_boltforward", "draw": "galil_draw"},
	21: {"shot": "aug-1", "scope": "aug_zoom", "reload": "aug_clipout", "reloadIn": "aug_clipin", "bolt": "aug_boltpull", "boltForward": "aug_boltrelease", "draw": "aug_draw"},
	22: {"shot": "sg556-1", "scope": "sg556_zoom", "reload": "sg556_clipout", "reloadIn": "sg556_clipin", "bolt": "sg556_boltback", "boltForward": "sg556_boltforward", "draw": "sg556_draw"},
	23: {"shot": "ssg08-1", "scope": "ssg08_zoom", "reload": "ssg08_clipout", "reloadIn": "ssg08_clipin", "bolt": "ssg08_boltback", "boltForward": "ssg08_boltforward", "draw": "ssg08_draw"},
	24: {"shot": "scar20_01", "scope": "scar20_zoom", "reload": "scar20_clipout", "reloadIn": "scar20_clipin", "bolt": "scar20_boltback", "boltForward": "scar20_boltforward", "draw": "scar20_draw"},
	25: {"shot": "g3sg1-1", "scope": "g3sg1_zoom", "reload": "g3sg1_clipout", "reloadIn": "g3sg1_clipin", "bolt": "g3sg1_slideback", "boltForward": "g3sg1_slideforward", "draw": "g3sg1_draw"},
	26: {"shot": "mac10-1", "reload": "mac10_clipout", "reloadIn": "mac10_clipin", "bolt": "mac10_boltback", "boltForward": "mac10_boltforward", "draw": "mac10_draw"},
	27: {"shot": "mp7-1", "reload": "mp7_clipout", "reloadIn": "mp7_clipin", "bolt": "mp7_slideback", "boltForward": "mp7_slideforward", "draw": "mp7_draw"},
	28: {"shot": "mp5_01", "reload": "mp5_clipout", "reloadIn": "mp5_clipin", "bolt": "mp5_slideback", "boltForward": "mp5_slideforward", "draw": "mp5_draw"},
	29: {"shot": "ump45-1", "reload": "ump45_clipout", "reloadIn": "ump45_clipin", "bolt": "ump45_boltback", "boltForward": "ump45_boltforward", "draw": "ump45_draw"},
	30: {"shot": "p90-1", "reload": "p90_clipout", "reloadIn": "p90_clipin", "bolt": "p90_boltback", "boltForward": "p90_boltforward", "draw": "p90_draw"},
	31: {"shot": "bizon-1", "reload": "bizon_clipout", "reloadIn": "bizon_clipin", "bolt": "bizon_boltback", "boltForward": "bizon_boltforward", "draw": "bizon_draw"},
	32: {"shot": "xm1014-1", "reload": "xm1014_insertshell", "reloadIn": "xm1014_insertshell", "bolt": "xm1014_pump", "boltForward": "xm1014_pump", "draw": "xm1014_draw"},
	33: {"shot": "mag7-1", "reload": "mag7_clipout", "reloadIn": "mag7_clipin", "bolt": "mag7_pump_back", "boltForward": "mag7_pump_forward", "draw": "mag7_draw"},
	34: {"shot": "sawedoff-1", "reload": "sawedoff_insertshell", "reloadIn": "sawedoff_insertshell", "bolt": "sawedoff_pump", "boltForward": "sawedoff_pump", "draw": "sawedoff_draw"},
	35: {"shot": "m249-1", "reload": "m249_boxout", "reloadIn": "m249_boxin", "bolt": "m249_pump", "boltForward": "m249_pump", "draw": "m249_draw"},
	36: {"shot": "negev-1", "reload": "negev_boxout", "reloadIn": "negev_boxin", "bolt": "negev_pump", "boltForward": "negev_pump", "draw": "negev_draw"},
}

var weapons: Array = []
var recoil_params: Array = []
var accuracy_params: Array = []
var accuracy_defaults: Dictionary = {}
var weapon_actions: Array = []
var recoil_tables: Array = [] # [weapon_id][mode 0|1][shot 0..63] -> Vector2(pitch_rad, yaw_rad)

func _ready() -> void:
	_load_all()

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)

func _load_all() -> void:
	var ws = _read_json(WEAPON_STATS_PATH)
	if ws is Dictionary and ws.has("weapons"):
		weapons = ws["weapons"]

	var rc = _read_json(RECOIL_PATH)
	if rc is Dictionary and rc.has("weapons"):
		recoil_params = rc["weapons"]

	var ac = _read_json(ACCURACY_PATH)
	if ac is Dictionary:
		accuracy_defaults = ac.get("defaults", {})
		accuracy_params = ac.get("weapons", [])

	var wa = _read_json(WEAPON_ACTIONS_PATH)
	if wa is Dictionary and wa.has("weapons"):
		weapon_actions = wa["weapons"]

	_build_recoil_tables()

static func is_knife(weapon_id: int) -> bool:
	return weapon_id == 4 or weapon_id == 5 or weapon_id == 6

static func is_pistol(weapon_id: int) -> bool:
	return weapon_id == 2 or weapon_id == 7 or weapon_id == 8 or (weapon_id >= 12 and weapon_id <= 18)

static func weapon_slot(weapon_id: int) -> int:
	if is_knife(weapon_id):
		return 3
	if is_pistol(weapon_id):
		return 2
	return 1

func get_weapon(weapon_id: int) -> Dictionary:
	if weapon_id >= 0 and weapon_id < weapons.size():
		return weapons[weapon_id]
	return {}

func get_recoil_param(weapon_id: int) -> Dictionary:
	var idx := 4 if is_knife(weapon_id) else weapon_id
	if idx >= 0 and idx < recoil_params.size():
		return recoil_params[idx]
	return {}

func get_accuracy_param(weapon_id: int) -> Dictionary:
	var idx := 4 if is_knife(weapon_id) else weapon_id
	if idx >= 0 and idx < accuracy_params.size():
		return accuracy_params[idx]
	return {}

func get_viewmodel_name(weapon_id: int) -> String:
	if weapon_id >= 0 and weapon_id < VIEWMODEL_NAMES.size():
		return VIEWMODEL_NAMES[weapon_id]
	return "ak-47"

func get_audio_kit(weapon_id: int) -> Dictionary:
	return AUDIO_KITS.get(weapon_id, {})

func get_action_info(weapon_id: int) -> Dictionary:
	if weapon_id >= 0 and weapon_id < weapon_actions.size():
		return weapon_actions[weapon_id]
	return {}

func get_buyable_weapons(team: String) -> Array:
	var out: Array = []
	for w in weapons:
		var wid: int = int(w.get("id", -1))
		if is_knife(wid):
			continue
		var wt: String = str(w.get("team", "both"))
		if wt == "both" or wt == team:
			out.append(w)
	return out

## Park-Miller PRNG with 32-entry shuffle matching Source Engine's uniform stream
class RecoilRandom:
	var _seed: int
	var _previous: int = 0
	var _shuffle: PackedInt32Array

	func _init(seed_val: int) -> void:
		_seed = -maxi(1, absi(seed_val))
		_shuffle = PackedInt32Array()
		_shuffle.resize(32)

	func _advance() -> void:
		var high := int(_seed / 127773)
		_seed = 16807 * (_seed - high * 127773) - 2836 * high
		if _seed < 0:
			_seed += 2147483647

	func next_val() -> float:
		if _seed <= 0 or _previous == 0:
			_seed = maxi(1, -_seed)
			for i in range(39, -1, -1):
				_advance()
				if i < 32:
					_shuffle[i] = _seed
			_previous = _shuffle[0]
		_advance()
		var index := int(_previous / 67108864)
		_previous = _shuffle[index]
		_shuffle[index] = _seed
		return minf(float(_previous) / 2147483647.0, 1.0 - 1.2e-7)

	func rand_range(min_v: float, max_v: float) -> float:
		return min_v + next_val() * (max_v - min_v)

func _build_recoil_tables() -> void:
	recoil_tables.clear()
	const SCALE := 2.0
	const TABLE_SIZE := 64
	const SMOOTHING := 0.55
	const SUPPRESSION := 0.75
	const SUPPRESSION_SHOTS := 4.0
	const DEG := PI / 180.0

	for i in range(weapons.size()):
		var rp := get_recoil_param(i)
		var modes_arr := []
		if rp.is_empty():
			for _m in range(2):
				var empty_shots := PackedVector2Array()
				empty_shots.resize(TABLE_SIZE)
				modes_arr.append(empty_shots)
			recoil_tables.append(modes_arr)
			continue

		var seed_val := int(rp.get("seed", 1))
		var full_auto := bool(rp.get("fullAuto", false))
		var angles: Array = rp.get("angle", [0.0, 0.0])
		var angle_vars: Array = rp.get("angleVariance", [0.0, 0.0])
		var mags: Array = rp.get("magnitude", [0.0, 0.0])
		var mag_vars: Array = rp.get("magnitudeVariance", [0.0, 0.0])

		for mode in range(2):
			var rng := RecoilRandom.new(seed_val)
			var angle := 0.0
			var magnitude := 0.0
			var shots := PackedVector2Array()
			shots.resize(TABLE_SIZE)
			for shot in range(TABLE_SIZE):
				var next_angle := float(angles[mode]) + rng.rand_range(-float(angle_vars[mode]), float(angle_vars[mode]))
				var next_mag := float(mags[mode]) + rng.rand_range(-float(mag_vars[mode]), float(mag_vars[mode]))
				if full_auto and shot > 0:
					angle = angle + SMOOTHING * (next_angle - angle)
					magnitude = magnitude + SMOOTHING * (next_mag - magnitude)
				else:
					angle = next_angle
					magnitude = next_mag
				var suppression := (SUPPRESSION + ((1.0 - SUPPRESSION) * float(shot)) / SUPPRESSION_SHOTS) if (full_auto and shot < int(SUPPRESSION_SHOTS)) else 1.0
				magnitude *= suppression
				var strength := magnitude * SCALE * DEG
				shots[shot] = Vector2(cos(angle * DEG) * strength, -sin(angle * DEG) * strength)
			modes_arr.append(shots)
		recoil_tables.append(modes_arr)

func get_recoil_impulse(weapon_id: int, mode: int, shot_index: int) -> Vector2:
	if weapon_id < 0 or weapon_id >= recoil_tables.size():
		return Vector2.ZERO
	var m := clampi(mode, 0, 1)
	var idx := clampi(shot_index, 0, 63)
	return recoil_tables[weapon_id][m][idx]
