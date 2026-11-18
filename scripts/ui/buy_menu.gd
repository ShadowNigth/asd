class_name BuyMenu
extends CanvasLayer
## CS2-style Buy Menu (B key) with all 34 weapons + Armor/Helmet/Kit/Grenades.

var _panel: PanelContainer
var _money_lbl: Label
var _grid: GridContainer

func _ready() -> void:
	layer = 10
	_build_ui()
	visible = false

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.05, 0.08, 0.72)
	add_child(bg)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -520
	_panel.offset_right = 520
	_panel.offset_top = -320
	_panel.offset_bottom = 320
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)
	var title := Label.new()
	title.text = "BUY MENU — DUST II"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)

	_money_lbl = Label.new()
	_money_lbl.add_theme_font_size_override("font_size", 24)
	_money_lbl.add_theme_color_override("font_color", Color(0.55, 0.92, 0.45))
	hdr.add_child(_money_lbl)

	var close_btn := Button.new()
	close_btn.text = "Close [B]"
	close_btn.pressed.connect(toggle)
	hdr.add_child(close_btn)

	# Gear & Grenades row
	var gear_bar := HBoxContainer.new()
	gear_bar.add_theme_constant_override("separation", 8)
	vbox.add_child(gear_bar)

	_add_gear_btn(gear_bar, "Kevlar ($650)", 650, func(p: PlayerController) -> bool:
		if p.armor >= 100: return false
		p.armor = 100
		return true
	)
	_add_gear_btn(gear_bar, "Kevlar+Helmet ($1000)", 1000, func(p: PlayerController) -> bool:
		if p.armor >= 100 and p.has_helmet: return false
		p.armor = 100
		p.has_helmet = true
		return true
	)
	_add_gear_btn(gear_bar, "Defuse Kit ($400)", 400, func(p: PlayerController) -> bool:
		if p.team != "ct" or p.has_defuse_kit: return false
		p.has_defuse_kit = true
		return true
	)
	_add_gear_btn(gear_bar, "HE ($300)", 300, func(p: PlayerController) -> bool: return p.give_grenade("he"))
	_add_gear_btn(gear_bar, "Flash ($200)", 200, func(p: PlayerController) -> bool: return p.give_grenade("flash"))
	_add_gear_btn(gear_bar, "Smoke ($300)", 300, func(p: PlayerController) -> bool: return p.give_grenade("smoke"))
	_add_gear_btn(gear_bar, "Molotov/Inc ($400)", 400, func(p: PlayerController) -> bool: return p.give_grenade("molotov"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

func _add_gear_btn(parent: Control, label: String, price: int, action: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(func() -> void:
		var p := GameManager.local_player
		if not is_instance_valid(p) or not p._in_buy_zone or p.money < price:
			return
		if action.call(p):
			p.money -= price
			AudioManager.play_2d("buy", -3.0)
			refresh()
	)
	parent.add_child(btn)

func refresh() -> void:
	var p := GameManager.local_player
	if not is_instance_valid(p):
		return
	_money_lbl.text = "$%d" % p.money
	for c in _grid.get_children():
		c.queue_free()

	for w in WeaponDB.get_buyable_weapons(p.team):
		var wid := int(w.get("id", -1))
		var price := int(w.get("price", 0))
		var wname := str(w.get("name", "Weapon"))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(235, 48)
		btn.text = "%s\n$%d" % [wname, price]
		btn.disabled = (p.money < price) or (not p._in_buy_zone)
		btn.pressed.connect(func() -> void:
			if p.money >= price and p._in_buy_zone:
				p.money -= price
				p.give_weapon(wid)
				AudioManager.play_2d("buy", -3.0)
				refresh()
		)
		_grid.add_child(btn)

func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
