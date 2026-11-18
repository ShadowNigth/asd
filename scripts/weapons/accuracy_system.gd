class_name AccuracySystem
extends RefCounted
## Faithful port of CS2GO/Source weapon inaccuracy & recovery.

const SOURCE_UNIT := 0.0254
const LN10 := 2.302585093

var penalty: float = 0.0
var baseline: float = 0.0
var mode: int = 0

func reset() -> void:
	penalty = 0.0
	baseline = 0.0
	mode = 0

func _recovery_time(weapon_id: int, shots: float, crouched: bool, grounded: bool) -> float:
	var p := WeaponDB.get_recoil_param(weapon_id)
	if p.is_empty():
		return 0.35
	if not grounded:
		return float(p.get("recoveryCrouch", 0.25)) * 4.0
	var start_t := float(p.get("recoveryTransitionStart", 2))
	var end_t := float(p.get("recoveryTransitionEnd", 5))
	var progress := clampf((floorf(shots) - start_t) / maxf(1.0, end_t - start_t), 0.0, 1.0)
	var s := float(p.get("recoveryCrouch" if crouched else "recoveryStand", 0.35))
	var f := float(p.get("recoveryCrouchFinal" if crouched else "recoveryStandFinal", s))
	if f < 0.0:
		f = s
	return s + (f - s) * progress

func compute_baseline(weapon_id: int, fire_mode: int, speed_mps: float, crouch_amount: float, grounded: bool, reloading: bool = false) -> float:
	var p := WeaponDB.get_accuracy_param(weapon_id)
	if p.is_empty():
		return 0.01
	var m := clampi(fire_mode, 0, 1)
	var c := clampf(crouch_amount, 0.0, 1.0)
	var stand_v := float(p.get("stand", [0.01, 0.01])[m])
	var crouch_v := float(p.get("crouch", [0.008, 0.008])[m])
	var jump_v := float(p.get("jump", [0.1, 0.1])[m])
	var move_v := float(p.get("move", [0.1, 0.1])[m])
	var max_spd := float(p.get("maxSpeed", [215.0, 215.0])[m]) * SOURCE_UNIT

	var air_scale := float(WeaponDB.accuracy_defaults.get("weapon_air_spread_scale", 1.0))
	var stance := (stand_v + jump_v * air_scale) if not grounded else (stand_v + (crouch_v - stand_v) * c)

	# Movement inaccuracy kicks in above ~34% of weapon maxSpeed (CS2/CSGO walk threshold)
	var walk_thresh := max_spd * 0.34
	var move_ratio := 0.0
	if max_spd > walk_thresh and speed_mps > walk_thresh:
		move_ratio = clampf((speed_mps - walk_thresh) / (max_spd - walk_thresh), 0.0, 1.0)
	var move_add := move_v * pow(move_ratio, 1.25)

	var rel_add := float(p.get("reload", 0.0)) if reloading else 0.0
	return stance + move_add + rel_add

func advance(dt: float, weapon_id: int, shots: float, fire_mode: int, speed_mps: float, crouch_amount: float, grounded: bool, reloading: bool = false) -> void:
	if dt <= 0.0:
		return
	var new_base := compute_baseline(weapon_id, fire_mode, speed_mps, crouch_amount, grounded, reloading)
	var prev_total := baseline + penalty
	var rec := _recovery_time(weapon_id, shots, crouch_amount > 0.5, grounded)
	var factor := exp((-LN10 * dt) / rec) if rec > 0.0 else 0.0
	var total := maxf(new_base, new_base + (prev_total - new_base) * factor)
	baseline = new_base
	penalty = maxf(0.0, total - new_base)
	if penalty < 1e-8:
		penalty = 0.0
	mode = fire_mode

func apply_fire(weapon_id: int, fire_mode: int) -> void:
	var p := WeaponDB.get_accuracy_param(weapon_id)
	if p.is_empty():
		return
	var m := clampi(fire_mode, 0, 1)
	var fire_inc := float(p.get("fire", [0.008, 0.008])[m])
	penalty = maxf(0.0, penalty + fire_inc)
	mode = fire_mode

func apply_landing(weapon_id: int, fire_mode: int, downward_speed_mps: float) -> void:
	var p := WeaponDB.get_accuracy_param(weapon_id)
	if p.is_empty():
		return
	var m := clampi(fire_mode, 0, 1)
	var land_coeff := float(p.get("land", [0.0002, 0.0002])[m])
	var speed_su := absf(downward_speed_mps) / SOURCE_UNIT
	penalty += land_coeff * speed_su

func get_total_inaccuracy(weapon_id: int, fire_mode: int) -> float:
	var p := WeaponDB.get_accuracy_param(weapon_id)
	var spread := float(p.get("spread", [0.0006, 0.0006])[clampi(fire_mode, 0, 1)]) if not p.is_empty() else 0.0006
	return spread + baseline + penalty
