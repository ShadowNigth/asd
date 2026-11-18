extends Node
## GameManager: CS2 Competitive/Casual round state machine, economy, C4 lifecycle,
## killfeed, and bot roster management on Dust II.

signal phase_changed(phase: String)
signal killfeed_event(killer_name: String, killer_team: String, victim_name: String, victim_team: String, weapon: String, headshot: bool)
signal round_banner(title: String, subtitle: String, winner_team: String)

enum Phase { TEAM_SELECT, FREEZE_TIME, LIVE, ROUND_END, MATCH_END }

const FREEZE_TIME_SEC := 4.0
const ROUND_TIME_SEC := 115.0
const BOMB_TIME_SEC := 40.0
const ROUND_END_SEC := 5.0
const MAX_ROUNDS := 24
const WIN_ROUNDS := 13

var phase: Phase = Phase.TEAM_SELECT
var phase_timer: float = 0.0
var round_number: int = 0
var score_ct: int = 0
var score_t: int = 0
var loss_streak_ct: int = 0
var loss_streak_t: int = 0

var bomb_planted: bool = false
var planted_bomb_pos: Vector3 = Vector3.ZERO
var planted_site: int = -1
var bomb_timer: float = 0.0
var _bomb_beep_accum: float = 0.0
var _bomb_node: Node3D = null

var dust2_map: Dust2Map = null
var local_player: PlayerController = null
var bots: Array[BotController] = []
var bot_count_per_team: int = 4

func _ready() -> void:
	pass

func start_match(player_team: String, bots_per_team: int = 4) -> void:
	bot_count_per_team = clampi(bots_per_team, 0, 5)
	round_number = 0
	score_ct = 0
	score_t = 0
	loss_streak_ct = 0
	loss_streak_t = 0

	if is_instance_valid(local_player):
		local_player.reset_full_loadout(player_team)

	_rebuild_bots(player_team)
	_start_next_round()

func _rebuild_bots(player_team: String) -> void:
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()

	if not is_instance_valid(dust2_map):
		return
	var parent := dust2_map.get_parent()
	if parent == null:
		return

	var ct_needed := bot_count_per_team - (1 if player_team == "ct" else 0)
	var t_needed := bot_count_per_team - (1 if player_team == "t" else 0)

	var ct_names := ["Bot SAS-1", "Bot SAS-2", "Bot SAS-3", "Bot SAS-4", "Bot SAS-5"]
	var t_names := ["Bot Phoenix-1", "Bot Phoenix-2", "Bot Phoenix-3", "Bot Phoenix-4", "Bot Phoenix-5"]

	for i in range(maxi(0, ct_needed)):
		var b := BotController.new()
		b.team = "ct"
		b.actor_name = ct_names[i % ct_names.size()]
		parent.add_child(b)
		bots.append(b)

	for i in range(maxi(0, t_needed)):
		var b := BotController.new()
		b.team = "t"
		b.actor_name = t_names[i % t_names.size()]
		parent.add_child(b)
		bots.append(b)

func _start_next_round() -> void:
	round_number += 1
	bomb_planted = false
	planted_site = -1
	bomb_timer = 0.0
	if is_instance_valid(_bomb_node):
		_bomb_node.queue_free()
		_bomb_node = null

	if not is_instance_valid(dust2_map) or not is_instance_valid(local_player):
		return

	var ct_idx := 0
	var t_idx := 0
	var p_team := local_player.team
	var p_spawn := dust2_map.get_spawn(p_team, 0)
	if p_team == "ct":
		ct_idx += 1
	else:
		t_idx += 1

	local_player.spawn_for_round(p_spawn["pos"], float(p_spawn["yaw"]), p_team, p_team == "t")

	for b in bots:
		if not is_instance_valid(b):
			continue
		var idx := ct_idx if b.team == "ct" else t_idx
		if b.team == "ct":
			ct_idx += 1
		else:
			t_idx += 1
		var sp := dust2_map.get_spawn(b.team, idx)
		b.spawn_for_round(sp["pos"], float(sp["yaw"]), b.team)

	phase = Phase.FREEZE_TIME
	phase_timer = FREEZE_TIME_SEC
	phase_changed.emit("FREEZE_TIME")
	round_banner.emit("ROUND %d" % round_number, "Buy Time — Press [B] to Buy", "")

func is_freeze_time() -> bool:
	return phase == Phase.FREEZE_TIME

func get_all_actors() -> Array:
	var out: Array = []
	if is_instance_valid(local_player):
		out.append(local_player)
	for b in bots:
		if is_instance_valid(b):
			out.append(b)
	return out

func get_alive_counts() -> Dictionary:
	var ct := 0
	var t := 0
	for a in get_all_actors():
		if a.get("alive"):
			if str(a.get("team")) == "ct":
				ct += 1
			else:
				t += 1
	return {"ct": ct, "t": t}

func _process(delta: float) -> void:
	if phase == Phase.TEAM_SELECT or phase == Phase.MATCH_END:
		return

	if phase == Phase.FREEZE_TIME:
		phase_timer -= delta
		if phase_timer <= 0.0:
			phase = Phase.LIVE
			phase_timer = ROUND_TIME_SEC
			phase_changed.emit("LIVE")
			AudioManager.play_2d("ready", -4.0)
			round_banner.emit("", "", "")
		return

	if phase == Phase.LIVE:
		if bomb_planted:
			bomb_timer -= delta
			var beep_interval := clampf(lerpf(0.15, 1.0, bomb_timer / BOMB_TIME_SEC), 0.14, 1.0)
			_bomb_beep_accum += delta
			if _bomb_beep_accum >= beep_interval:
				_bomb_beep_accum = 0.0
				AudioManager.play_3d("bomb-beep-fast" if bomb_timer < 10.0 else "bomb-beep", planted_bomb_pos, 1.0)
			if bomb_timer <= 0.0:
				_explode_bomb()
		else:
			phase_timer -= delta
			if phase_timer <= 0.0:
				_end_round("ct", "Time Expired — Counter-Terrorists Win")
		return

	if phase == Phase.ROUND_END:
		phase_timer -= delta
		if phase_timer <= 0.0:
			if score_ct >= WIN_ROUNDS or score_t >= WIN_ROUNDS or round_number >= MAX_ROUNDS:
				phase = Phase.MATCH_END
				phase_changed.emit("MATCH_END")
				var win_msg := "COUNTER-TERRORISTS WIN" if score_ct >= score_t else "TERRORISTS WIN"
				round_banner.emit("MATCH COMPLETE", win_msg, "ct" if score_ct >= score_t else "t")
			else:
				_start_next_round()

func plant_bomb(pos: Vector3, site: int, planter: Node) -> void:
	if bomb_planted or phase != Phase.LIVE:
		return
	bomb_planted = true
	planted_bomb_pos = pos
	planted_site = site
	bomb_timer = BOMB_TIME_SEC
	_bomb_beep_accum = 0.0
	AudioManager.play_2d("bomb-plant", -2.0)
	round_banner.emit("THE BOMB HAS BEEN PLANTED", "Bombsite %s" % ("A" if site == 0 else "B"), "t")

	if is_instance_valid(planter) and planter == local_player:
		local_player.money = mini(16000, local_player.money + 300)

	_bomb_node = Node3D.new()
	var c4_inst := ModelLoader.instantiate_model("res://assets/models/c4.glb")
	if c4_inst != null:
		_bomb_node.add_child(c4_inst)
	else:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.26, 0.09, 0.18)
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.27, 0.22)
		m.material_override = mat
		_bomb_node.add_child(m)
	dust2_map.add_child(_bomb_node)
	_bomb_node.global_position = pos + Vector3.UP * 0.05

func defuse_bomb(defuser: Node) -> void:
	if not bomb_planted or phase != Phase.LIVE:
		return
	bomb_planted = false
	AudioManager.play_2d("bomb-defuse", -1.0)
	if is_instance_valid(_bomb_node):
		_bomb_node.queue_free()
		_bomb_node = null
	if is_instance_valid(defuser) and defuser == local_player:
		local_player.money = mini(16000, local_player.money + 300)
	_end_round("ct", "Bomb Defused — Counter-Terrorists Win")

func _explode_bomb() -> void:
	bomb_planted = false
	AudioManager.play_2d("bomb-explode", 2.0)
	EffectsManager.spawn_explosion(planted_bomb_pos)
	for a in get_all_actors():
		if not is_instance_valid(a) or not a.get("alive"):
			continue
		var d := a.global_position.distance_to(planted_bomb_pos)
		if d < 42.0:
			var dmg := int(maxf(1.0, 400.0 * exp(-d / 14.0)))
			if a.has_method("apply_damage"):
				a.apply_damage(dmg, null, "C4 Explosive", false)
	if is_instance_valid(_bomb_node):
		_bomb_node.queue_free()
		_bomb_node = null
	_end_round("t", "Target Destroyed — Terrorists Win")

func on_actor_killed(victim: Node, attacker: Node, weapon_name: String, headshot: bool) -> void:
	var k_name := str(attacker.get("actor_name")) if is_instance_valid(attacker) else "World"
	var k_team := str(attacker.get("team")) if is_instance_valid(attacker) else ""
	var v_name := str(victim.get("actor_name"))
	var v_team := str(victim.get("team"))

	if is_instance_valid(attacker) and attacker != victim:
		attacker.set("kills", int(attacker.get("kills")) + 1)
		if attacker == local_player:
			local_player.money = mini(16000, local_player.money + 300)

	killfeed_event.emit(k_name, k_team, v_name, v_team, weapon_name, headshot)

	if phase != Phase.LIVE:
		return
	var counts := get_alive_counts()
	if counts["ct"] == 0 and counts["t"] > 0:
		_end_round("t", "Counter-Terrorists Eliminated — Terrorists Win")
	elif counts["t"] == 0 and not bomb_planted:
		_end_round("ct", "Terrorists Eliminated — Counter-Terrorists Win")

func _end_round(winner: String, reason: String) -> void:
	if phase != Phase.LIVE:
		return
	phase = Phase.ROUND_END
	phase_timer = ROUND_END_SEC
	phase_changed.emit("ROUND_END")

	if winner == "ct":
		score_ct += 1
		loss_streak_ct = 0
		loss_streak_t = mini(4, loss_streak_t + 1)
	else:
		score_t += 1
		loss_streak_t = 0
		loss_streak_ct = mini(4, loss_streak_ct + 1)

	# Economy rewards matching CS2
	if is_instance_valid(local_player):
		var p_won := (local_player.team == winner)
		var reward := 3250 if p_won else (1400 + (loss_streak_ct if local_player.team == "ct" else loss_streak_t) * 500)
		local_player.money = mini(16000, local_player.money + reward)

	round_banner.emit("CT WIN" if winner == "ct" else "T WIN", reason, winner)
	AudioManager.play_2d("music-win" if (is_instance_valid(local_player) and local_player.team == winner) else "music-lose", -5.0)
