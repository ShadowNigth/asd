class_name TeamSelectMenu
extends CanvasLayer
## Team Selection overlay (CT SAS vs T Phoenix + Bot count on Dust II).

signal team_chosen(team: String, bots_per_team: int)

var _bots_spin: SpinBox

func _ready() -> void:
	layer = 15
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.07, 0.10, 0.86)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -180
	panel.offset_bottom = 180
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "COUNTER-STRIKE 2 — DUST II (GODOT 4)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Select your team (1 agent per side: SAS vs Phoenix)"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var bot_row := HBoxContainer.new()
	bot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_row.add_theme_constant_override("separation", 12)
	vbox.add_child(bot_row)

	var bot_lbl := Label.new()
	bot_lbl.text = "Players per Team (with Bots):"
	bot_row.add_child(bot_lbl)

	_bots_spin = SpinBox.new()
	_bots_spin.min_value = 1
	_bots_spin.max_value = 5
	_bots_spin.value = 5
	bot_row.add_child(_bots_spin)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var ct_btn := Button.new()
	ct_btn.text = "COUNTER-TERRORISTS\n(SAS)"
	ct_btn.custom_minimum_size = Vector2(240, 88)
	ct_btn.pressed.connect(func() -> void: _pick("ct"))
	btn_row.add_child(ct_btn)

	var t_btn := Button.new()
	t_btn.text = "TERRORISTS\n(Phoenix)"
	t_btn.custom_minimum_size = Vector2(240, 88)
	t_btn.pressed.connect(func() -> void: _pick("t"))
	btn_row.add_child(t_btn)

	var controls := Label.new()
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_font_size_override("font_size", 13)
	controls.text = "WASD Move | Shift Walk | Ctrl Crouch | F Inspect | R Reload | B Buy | E Plant/Defuse | Tab Scoreboard | Esc Menu"
	vbox.add_child(controls)

func _pick(team: String) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	team_chosen.emit(team, int(_bots_spin.value))
