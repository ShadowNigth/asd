extends Node3D
## Main Match Scene Root: wires Dust2Map, PlayerController, HUD, BuyMenu,
## TeamSelectMenu, ScoreboardUI, and PauseMenu.

var _map: Dust2Map
var _player: PlayerController
var _hud: GameHUD
var _buy_menu: BuyMenu
var _team_menu: TeamSelectMenu
var _scoreboard: ScoreboardUI
var _pause_menu: PauseMenu

func _ready() -> void:
	EffectsManager.set_world_root(self)

	_map = Dust2Map.new()
	add_child(_map)
	GameManager.dust2_map = _map

	_player = PlayerController.new()
	add_child(_player)
	GameManager.local_player = _player

	_hud = GameHUD.new()
	add_child(_hud)

	_buy_menu = BuyMenu.new()
	add_child(_buy_menu)

	_scoreboard = ScoreboardUI.new()
	add_child(_scoreboard)

	_pause_menu = PauseMenu.new()
	_pause_menu.open_team_select.connect(_show_team_select)
	add_child(_pause_menu)

	_team_menu = TeamSelectMenu.new()
	_team_menu.team_chosen.connect(_on_team_chosen)
	add_child(_team_menu)

func _show_team_select() -> void:
	_buy_menu.visible = false
	_pause_menu.visible = false
	_team_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_team_chosen(team: String, bots_per_team: int) -> void:
	GameManager.start_match(team, bots_per_team)

func _unhandled_input(event: InputEvent) -> void:
	if _team_menu.visible:
		return
	if event.is_action_pressed("pause"):
		if _buy_menu.visible:
			_buy_menu.toggle()
		else:
			_pause_menu.toggle()
	elif event.is_action_pressed("buy_menu") and not _pause_menu.visible:
		_buy_menu.toggle()
	elif event.is_action_pressed("team_menu"):
		_show_team_select()

func _process(_delta: float) -> void:
	if _team_menu.visible or _pause_menu.visible:
		_scoreboard.visible = false
		return
	var show_tab := Input.is_action_pressed("scoreboard")
	if show_tab and not _scoreboard.visible:
		_scoreboard.refresh()
	_scoreboard.visible = show_tab
