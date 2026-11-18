class_name ScoreboardUI
extends CanvasLayer
## Tab Scoreboard showing CT vs T players, kills, deaths, and money.

var _list: VBoxContainer

func _ready() -> void:
	layer = 12
	_build_ui()
	visible = false

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -240
	panel.offset_bottom = 240
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "SCOREBOARD — DE_DUST2"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 22)
	vbox.add_child(hdr)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_list)

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()

	var ct_hdr := Label.new()
	ct_hdr.text = "COUNTER-TERRORISTS (%d)" % GameManager.score_ct
	ct_hdr.add_theme_color_override("font_color", Color(0.45, 0.72, 1.0))
	_list.add_child(ct_hdr)

	for a in GameManager.get_all_actors():
		if str(a.get("team")) == "ct":
			_add_row(a)

	var t_hdr := Label.new()
	t_hdr.text = "TERRORISTS (%d)" % GameManager.score_t
	t_hdr.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
	_list.add_child(t_hdr)

	for a in GameManager.get_all_actors():
		if str(a.get("team")) == "t":
			_add_row(a)

func _add_row(actor: Node) -> void:
	var row := Label.new()
	var alive_str := "ALIVE" if actor.get("alive") else "DEAD"
	row.text = "  %-20s  |  K: %-3d  D: %-3d  |  $%-5d  |  %s" % [
		str(actor.get("actor_name")),
		int(actor.get("kills")),
		int(actor.get("deaths")),
		int(actor.get("money")),
		alive_str,
	]
	_list.add_child(row)
