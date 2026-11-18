class_name RecoilSystem
extends RefCounted
## Faithful port of CS2GO/Source recoil & aim-punch spring decay.

const RECOIL_VIEW_SCALE := 0.45
const ANGLE_DECAY := 8.0
const VELOCITY_DECAY := 4.5
const ANGLE_LINEAR_DECAY := 18.0
const INDEX_DECAY := 2.302585093 * 2.0 # ln(10) * 2
const DEG := PI / 180.0

var pitch: float = 0.0
var yaw: float = 0.0
var pitch_velocity: float = 0.0
var yaw_velocity: float = 0.0

var shot_index: float = 0.0
var time_since_shot: float = 1e9
var mode: int = 0

func reset() -> void:
	pitch = 0.0
	yaw = 0.0
	pitch_velocity = 0.0
	yaw_velocity = 0.0
	shot_index = 0.0
	time_since_shot = 1e9

func reset_weapon_index() -> void:
	shot_index = 0.0
	time_since_shot = 1e9

func apply_shot(weapon_id: int, fire_mode: int) -> void:
	var idx := mini(int(floor(shot_index)), 63)
	var impulse := WeaponDB.get_recoil_impulse(weapon_id, fire_mode, idx)
	pitch_velocity += impulse.x
	yaw_velocity += impulse.y
	shot_index = minf(shot_index + 1.0, 64.0)
	time_since_shot = 0.0
	mode = fire_mode

func step(dt: float, weapon_id: int, crouched: bool) -> void:
	if dt <= 0.0:
		return
	time_since_shot += dt

	# Decay aim punch (spring-like linear + exponential decay)
	pitch += pitch_velocity * dt
	yaw += yaw_velocity * dt

	var vel_decay := exp(-VELOCITY_DECAY * dt)
	pitch_velocity *= vel_decay
	yaw_velocity *= vel_decay

	var ang_decay := exp(-ANGLE_DECAY * dt)
	pitch *= ang_decay
	yaw *= ang_decay

	var mag := sqrt(pitch * pitch + yaw * yaw)
	if mag > 1e-6:
		var lin := ANGLE_LINEAR_DECAY * DEG * dt
		if mag <= lin:
			pitch = 0.0
			yaw = 0.0
		else:
			var scale := (mag - lin) / mag
			pitch *= scale
			yaw *= scale
	else:
		pitch = 0.0
		yaw = 0.0

	# Decay recoil index once firing stops past cycleTime
	var rp := WeaponDB.get_recoil_param(weapon_id)
	var cycle_arr: Array = rp.get("cycleTime", [0.1, 0.1])
	var cycle := float(cycle_arr[clampi(mode, 0, 1)])
	if time_since_shot > cycle and shot_index > 0.0:
		var rec_stand := float(rp.get("recoveryStand", 0.35))
		var rec_crouch := float(rp.get("recoveryCrouch", 0.25))
		var rec := maxf(0.05, rec_crouch if crouched else rec_stand)
		shot_index = maxf(0.0, shot_index * exp(-INDEX_DECAY * dt / maxf(0.2, rec)) - 2.0 * dt)

func get_view_pitch() -> float:
	return pitch * RECOIL_VIEW_SCALE

func get_view_yaw() -> float:
	return yaw * RECOIL_VIEW_SCALE

func get_ballistic_pitch() -> float:
	return pitch

func get_ballistic_yaw() -> float:
	return yaw
