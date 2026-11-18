class_name PauseMenu
extends CanvasLayer
## Esc Pause Menu: Mouse sensitivity, practice sandbox weapons, team switch, resume.

signal open_team_select()

var _sens_slider: HSlider

func _ready() -> void:
	layer = 14
	_build_ui()
	visible = false

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06, 0.76)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -180
	panel.offset_bottom = 180
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSE MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var sens_lbl := Label.new()
	sens_lbl.text = "Mouse Sensitivity"
	vbox.add_child(sens_lbl)

	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.0005
	_sens_slider.max_value = 0.006
	_sens_slider.step = 0.0001
	_sens_slider.value = 0.0022
	_sens_slider.value_changed.connect(func(v: float) -> void:
		if is_instance_valid(GameManager.local_player):
			GameManager.local_player.mouse_sensitivity = v
	)
	vbox.add_child(_sens_slider)

	var resume_btn := Button.new()
	resume_btn.text = "Resume Match"
	resume_btn.pressed.connect(toggle)
	vbox.add_child(resume_btn)

	var give_money := Button.new()
	give_money.text = "Practice: Give $16,000"
	give_money.pressed.connect(func() -> void:
		if is_instance_valid(GameManager.local_player):
			GameManager.local_player.money = 16000
	)
	vbox.add_child(give_money)

	var team_btn := Button.new()
	team_btn.text = "Change Team / Restart"
	team_btn.pressed.connect(func() -> void:
		visible = false
		open_team_select.emit()
	)
	vbox.add_child(team_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit_btn)

func toggle() -> void:
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
