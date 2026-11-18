class_name GameHUD
extends CanvasLayer
## CS2-style HUD: HP/Armor, Money, Ammo, Timer/Score, Dynamic Crosshair,
## Sniper Scope, Dust II Radar Minimap, Killfeed, Callout, and Plant/Defuse bar.

var _root: Control
var _hp_label: Label
var _armor_label: Label
var _money_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _timer_label: Label
var _score_ct_label: Label
var _score_t_label: Label
var _alive_label: Label
var _callout_label: Label
var _buy_hint: Label
var _banner_box: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _killfeed_box: VBoxContainer
var _progress_bar: ProgressBar
var _progress_label: Label
var _flash_rect: ColorRect
var _scope_overlay: Control
var _crosshair: Control

# Radar
var _radar_panel: PanelContainer
var _radar_tex: TextureRect
var _player_dot: ColorRect
var _bomb_dot: ColorRect
var _bot_dots: Array[ColorRect] = []
var _overview_pos_x: float = -2476.0
var _overview_pos_y: float = 3239.0
var _overview_scale: float = 4.4

func _ready() -> void:
	layer = 5
	_load_overview()
	_build_ui()
	GameManager.killfeed_event.connect(_on_killfeed)
	GameManager.round_banner.connect(_on_round_banner)

func _load_overview() -> void:
	var path := "res://assets/data/dust2-overview.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		_overview_pos_x = float(data.get("pos_x", -2476.0))
		_overview_pos_y = float(data.get("pos_y", 3239.0))
		_overview_scale = float(data.get("scale", 4.4))

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Sniper Scope Overlay
	_scope_overlay = _ScopeOverlay.new()
	_scope_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope_overlay.visible = false
	_root.add_child(_scope_overlay)

	# Dynamic Crosshair
	_crosshair = _CrosshairOverlay.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	# Radar Minimap (Top-Left)
	_radar_panel = PanelContainer.new()
	_radar_panel.position = Vector2(18, 18)
	_radar_panel.custom_minimum_size = Vector2(210, 210)
	_root.add_child(_radar_panel)

	var radar_inner := Control.new()
	radar_inner.custom_minimum_size = Vector2(200, 200)
	radar_inner.clip_contents = true
	_radar_panel.add_child(radar_inner)

	_radar_tex = TextureRect.new()
	_radar_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_radar_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_radar_tex.stretch_mode = TextureRect.STRETCH_SCALE
	if ResourceLoader.exists("res://assets/models/maps/dust2-radar.png"):
		_radar_tex.texture = load("res://assets/models/maps/dust2-radar.png")
	radar_inner.add_child(_radar_tex)

	_player_dot = ColorRect.new()
	_player_dot.size = Vector2(8, 8)
	_player_dot.color = Color(0.2, 1.0, 0.35)
	radar_inner.add_child(_player_dot)

	_bomb_dot = ColorRect.new()
	_bomb_dot.size = Vector2(8, 8)
	_bomb_dot.color = Color(1.0, 0.25, 0.2)
	_bomb_dot.visible = false
	radar_inner.add_child(_bomb_dot)

	for _i in range(10):
		var d := ColorRect.new()
		d.size = Vector2(6, 6)
		d.visible = false
		radar_inner.add_child(d)
		_bot_dots.append(d)

	_callout_label = Label.new()
	_callout_label.position = Vector2(20, 234)
	_callout_label.add_theme_font_size_override("font_size", 16)
	_callout_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	_root.add_child(_callout_label)

	# Top Center Match Header (Score + Timer)
	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.position = Vector2(0, 14)
	top_bar.add_theme_constant_override("separation", 18)
	_root.add_child(top_bar)

	_score_ct_label = _make_badge(top_bar, "CT 0", Color(0.38, 0.65, 1.0), 22)
	_timer_label = _make_badge(top_bar, "01:55", Color(1.0, 1.0, 1.0), 24)
	_score_t_label = _make_badge(top_bar, "T 0", Color(0.96, 0.68, 0.26), 22)

	_alive_label = Label.new()
	_alive_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_alive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alive_label.position = Vector2(0, 52)
	_alive_label.add_theme_font_size_override("font_size", 14)
	_root.add_child(_alive_label)

	# Killfeed (Top-Right)
	_killfeed_box = VBoxContainer.new()
	_killfeed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_killfeed_box.offset_left = -380
	_killfeed_box.offset_right = -20
	_killfeed_box.offset_top = 18
	_killfeed_box.offset_bottom = 260
	_killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_killfeed_box)

	# Round Banner (Center-Top)
	_banner_box = VBoxContainer.new()
	_banner_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_box.offset_left = -260
	_banner_box.offset_right = 260
	_banner_box.offset_top = 130
	_banner_box.offset_bottom = 220
	_banner_box.visible = false
	_root.add_child(_banner_box)

	_banner_title = Label.new()
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 32)
	_banner_box.add_child(_banner_title)

	_banner_sub = Label.new()
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_font_size_override("font_size", 18)
	_banner_box.add_child(_banner_sub)

	# Money + Buy Hint (Left-Middle/Bottom)
	_money_label = Label.new()
	_money_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_money_label.offset_left = 24
	_money_label.offset_top = -140
	_money_label.add_theme_font_size_override("font_size", 28)
	_money_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.45))
	_root.add_child(_money_label)

	_buy_hint = Label.new()
	_buy_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_buy_hint.offset_left = 24
	_buy_hint.offset_top = -175
	_buy_hint.add_theme_font_size_override("font_size", 16)
	_buy_hint.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_buy_hint.text = "[B] Buy Menu   [F] Inspect"
	_root.add_child(_buy_hint)

	# Bottom-Left Health & Armor
	var hp_box := HBoxContainer.new()
	hp_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_box.offset_left = 24
	hp_box.offset_top = -78
	hp_box.offset_bottom = -20
	hp_box.add_theme_constant_override("separation", 24)
	_root.add_child(hp_box)

	_hp_label = _make_badge(hp_box, "HP 100", Color(1.0, 1.0, 1.0), 34)
	_armor_label = _make_badge(hp_box, "ARM 100", Color(0.65, 0.85, 1.0), 26)

	# Bottom-Right Weapon & Ammo
	var ammo_box := VBoxContainer.new()
	ammo_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_box.offset_left = -300
	ammo_box.offset_right = -24
	ammo_box.offset_top = -95
	ammo_box.offset_bottom = -20
	_root.add_child(ammo_box)

	_weapon_label = Label.new()
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_label.add_theme_font_size_override("font_size", 20)
	ammo_box.add_child(_weapon_label)

	_ammo_label = Label.new()
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_font_size_override("font_size", 34)
	ammo_box.add_child(_ammo_label)

	# Plant / Defuse Progress Bar
	_progress_bar = ProgressBar.new()
	_progress_bar.set_anchors_preset(Control.PRESET_CENTER)
	_progress_bar.offset_left = -150
	_progress_bar.offset_right = 150
	_progress_bar.offset_top = 75
	_progress_bar.offset_bottom = 98
	_progress_bar.max_value = 1.0
	_progress_bar.visible = false
	_root.add_child(_progress_bar)

	_progress_label = Label.new()
	_progress_label.set_anchors_preset(Control.PRESET_CENTER)
	_progress_label.offset_left = -150
	_progress_label.offset_right = 150
	_progress_label.offset_top = 48
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.visible = false
	_root.add_child(_progress_label)

	# Flashbang Overlay (on top)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash_rect)

func _make_badge(parent: Control, text_val: String, col: Color, fsize: int) -> Label:
	var lbl := Label.new()
	lbl.text = text_val
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", col)
	parent.add_child(lbl)
	return lbl

func _process(_delta: float) -> void:
	var p := GameManager.local_player
	if not is_instance_valid(p):
		return
	var snap := p.get_hud_snapshot()

	_hp_label.text = "+ %d" % int(snap["health"])
	_hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3) if int(snap["health"]) <= 25 else Color(1, 1, 1))
	_armor_label.text = "%s %d" % ["H+A" if snap["helmet"] else "ARM", int(snap["armor"])]
	_money_label.text = "$%d" % int(snap["money"])
	_weapon_label.text = str(snap["weapon_name"])
	if snap["has_ammo"]:
		_ammo_label.text = "%d / %d" % [int(snap["clip"]), int(snap["reserve"])]
	else:
		_ammo_label.text = "—"

	_callout_label.text = str(snap["callout"])
	_buy_hint.text = "[B] Buy Menu (In Buy Zone)   [F] Inspect   [E] Plant/Defuse" if snap["in_buy_zone"] else "[F] Inspect   [R] Reload   [E] Use"
	_flash_rect.color.a = float(snap["flash_alpha"])

	var scoped := int(snap["scope_level"]) > 0
	_scope_overlay.visible = scoped
	_crosshair.visible = not scoped and bool(snap["alive"])
	(_crosshair as _CrosshairOverlay).set_spread(float(snap["spread"]))

	# Match header
	_score_ct_label.text = "CT %d" % GameManager.score_ct
	_score_t_label.text = "T %d" % GameManager.score_t
	var t_rem := GameManager.bomb_timer if GameManager.bomb_planted else GameManager.phase_timer
	var mins := int(maxf(0.0, t_rem)) / 60
	var secs := int(maxf(0.0, t_rem)) % 60
	_timer_label.text = ("BOMB %02d:%02d" % [mins, secs]) if GameManager.bomb_planted else ("%02d:%02d" % [mins, secs])
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25) if GameManager.bomb_planted else Color(1, 1, 1))

	var counts := GameManager.get_alive_counts()
	_alive_label.text = "CT Alive: %d  |  T Alive: %d" % [counts["ct"], counts["t"]]

	# Plant / Defuse bar
	if snap["planting"]:
		_progress_bar.visible = true
		_progress_label.visible = true
		_progress_label.text = "Planting C4..."
		_progress_bar.value = float(snap["plant_progress"])
	elif snap["defusing"]:
		_progress_bar.visible = true
		_progress_label.visible = true
		_progress_label.text = "Defusing C4..."
		_progress_bar.value = float(snap["defuse_progress"])
	else:
		_progress_bar.visible = false
		_progress_label.visible = false

	_update_radar(p)

func _world_to_radar(world_pos: Vector3) -> Vector2:
	var sx := world_pos.x / 0.0254
	var sy := -world_pos.z / 0.0254
	var px := (sx - _overview_pos_x) / _overview_scale
	var py := (_overview_pos_y - sy) / _overview_scale
	return Vector2(px / 1024.0 * 200.0, py / 1024.0 * 200.0)

func _update_radar(p: PlayerController) -> void:
	var p_pos := _world_to_radar(p.global_position)
	_player_dot.position = p_pos - Vector2(4, 4)

	if GameManager.bomb_planted:
		_bomb_dot.visible = true
		_bomb_dot.position = _world_to_radar(GameManager.planted_bomb_pos) - Vector2(4, 4)
	else:
		_bomb_dot.visible = false

	for i in range(_bot_dots.size()):
		if i < GameManager.bots.size() and is_instance_valid(GameManager.bots[i]) and GameManager.bots[i].alive:
			var b := GameManager.bots[i]
			# Show teammates always; show enemies for testing convenience in red
			_bot_dots[i].visible = true
			_bot_dots[i].color = Color(0.35, 0.72, 1.0) if b.team == p.team else Color(1.0, 0.35, 0.25)
			_bot_dots[i].position = _world_to_radar(b.global_position) - Vector2(3, 3)
		else:
			_bot_dots[i].visible = false

func _on_killfeed(k_name: String, k_team: String, v_name: String, _v_team: String, weapon: String, hs: bool) -> void:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 15)
	var hs_tag := " [HS]" if hs else ""
	lbl.text = "%s  [%s%s]  %s" % [k_name, weapon, hs_tag, v_name]
	lbl.add_theme_color_override("font_color", Color(0.5, 0.78, 1.0) if k_team == "ct" else Color(1.0, 0.75, 0.35))
	_killfeed_box.add_child(lbl)
	if _killfeed_box.get_child_count() > 5:
		_killfeed_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_callback(func() -> void:
		if is_instance_valid(lbl):
			lbl.queue_free()
	)

func _on_round_banner(title: String, sub: String, winner: String) -> void:
	if title.is_empty():
		_banner_box.visible = false
		return
	_banner_box.visible = true
	_banner_title.text = title
	_banner_sub.text = sub
	var col := Color(1, 1, 1)
	if winner == "ct":
		col = Color(0.45, 0.72, 1.0)
	elif winner == "t":
		col = Color(1.0, 0.72, 0.3)
	_banner_title.add_theme_color_override("font_color", col)

class _CrosshairOverlay extends Control:
	var _spread: float = 0.01

	func set_spread(s: float) -> void:
		_spread = s
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var gap := clampf(5.0 + _spread * 260.0, 4.0, 42.0)
		var length := 8.0
		var thick := 2.0
		var col := Color(0.15, 1.0, 0.35, 0.92)
		draw_line(c + Vector2(-gap - length, 0), c + Vector2(-gap, 0), col, thick)
		draw_line(c + Vector2(gap, 0), c + Vector2(gap + length, 0), col, thick)
		draw_line(c + Vector2(0, -gap - length), c + Vector2(0, -gap), col, thick)
		draw_line(c + Vector2(0, gap), c + Vector2(0, gap + length), col, thick)

class _ScopeOverlay extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.44
		# Black borders around scope circle
		draw_rect(Rect2(0, 0, c.x - r, size.y), Color.BLACK)
		draw_rect(Rect2(c.x + r, 0, size.x - (c.x + r), size.y), Color.BLACK)
		draw_rect(Rect2(c.x - r, 0, r * 2.0, c.y - r), Color.BLACK)
		draw_rect(Rect2(c.x - r, c.y + r, r * 2.0, size.y - (c.y + r)), Color.BLACK)
		draw_arc(c, r, 0.0, TAU, 96, Color.BLACK, 18.0)
		draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0, 0.85), 2.0)
		draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0, 0, 0, 0.85), 2.0)
