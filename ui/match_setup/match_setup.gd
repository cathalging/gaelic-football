extends Control
## Match setup — first choose Single Player or Multiplayer, then (multiplayer
## only) seat each device on a team before a Quick Play match.
##
## Stage MODE: the device that picks Single Player becomes the lone human (on
## Home), so a controller player plays solo on their pad and a keyboard player on
## the keyboard. Multiplayer drops into the press-to-join team lobby.
##
## Stage TEAMS (multiplayer): each device joins on its own — a controller presses
## A, the keyboard presses Space — then moves between Home and Away with the
## D-pad / A·D keys. Start (controller) / Enter (keyboard) launches.
##
## Per-device detection mirrors PlayerInput: keyboard events are the keyboard
## seat; joypad events carry the device id, which becomes the seat's device. The
## screen owns no persistent state — it builds a MatchConfig and hands it to
## GameManager.start_match().

enum Stage { MODE, TEAMS }
var _stage := Stage.MODE

# Joined seats, in join order (slot 0 = the primary seat).
var _seats: Array[MatchPlayerSlot] = []

@onready var _title: Label = %Title
@onready var _mode_panel: VBoxContainer = %ModePanel
@onready var _teams_panel: VBoxContainer = %TeamsPanel
@onready var _home_list: VBoxContainer = %HomeList
@onready var _away_list: VBoxContainer = %AwayList
@onready var _hint: Label = %Hint


func _ready() -> void:
	_show_mode_stage()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_handle_pad_button(event.device, event.button_index)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.physical_keycode if event.physical_keycode != 0 else event.keycode)


# ── Stage: choose mode ──────────────────────────────────────────────────────--

func _show_mode_stage() -> void:
	_stage = Stage.MODE
	_seats.clear()
	_title.text = "QUICK PLAY"
	_mode_panel.visible = true
	_teams_panel.visible = false
	_hint.text = "B / Esc — back to menu"


## Begin a single-player match driven by `slot`, on the home team, vs AI.
func _start_single(slot: MatchPlayerSlot) -> void:
	slot.team = 0
	var cfg := MatchConfig.new()
	cfg.mode = MatchConfig.Mode.SINGLE
	cfg.slots = [slot]
	GameManager.start_match(cfg)


# ── Stage: team selection (multiplayer) ─────────────────────────────────────--

func _show_teams_stage() -> void:
	_stage = Stage.TEAMS
	_title.text = "MULTIPLAYER"
	_mode_panel.visible = false
	_teams_panel.visible = true
	_refresh_teams()


# ── Controller input ────────────────────────────────────────────────────────--

func _handle_pad_button(device: int, button: int) -> void:
	if _stage == Stage.MODE:
		match button:
			JOY_BUTTON_A:
				_start_single(_make_slot(false, device))
			JOY_BUTTON_X:
				_show_teams_stage()
			JOY_BUTTON_B:
				GameManager.return_to_main_menu()
		return
	# Stage TEAMS
	match button:
		JOY_BUTTON_A:
			if _find_seat(false, device) == -1:
				_seats.append(_make_slot(false, device))   # join on Home
		JOY_BUTTON_B:
			var idx := _find_seat(false, device)
			if idx != -1:
				_remove_seat(idx)
			else:
				_show_mode_stage()
		JOY_BUTTON_DPAD_LEFT:
			_set_team(_find_seat(false, device), 0)
		JOY_BUTTON_DPAD_RIGHT:
			_set_team(_find_seat(false, device), 1)
		JOY_BUTTON_START:
			_start_multi()
	_refresh_teams()


# ── Keyboard input ──────────────────────────────────────────────────────────--

func _handle_key(keycode: int) -> void:
	if _stage == Stage.MODE:
		match keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_start_single(_make_slot(true, 0))
			KEY_M:
				_show_teams_stage()
			KEY_ESCAPE:
				GameManager.return_to_main_menu()
		return
	# Stage TEAMS
	match keycode:
		KEY_SPACE:
			if _find_seat(true, 0) == -1:
				_seats.append(_make_slot(true, 0))
		KEY_ESCAPE:
			var idx := _find_seat(true, 0)
			if idx != -1:
				_remove_seat(idx)
			else:
				_show_mode_stage()
		KEY_A, KEY_LEFT:
			_set_team(_find_seat(true, 0), 0)
		KEY_D, KEY_RIGHT:
			_set_team(_find_seat(true, 0), 1)
		KEY_ENTER, KEY_KP_ENTER:
			_start_multi()
	_refresh_teams()


# ── Seat management ─────────────────────────────────────────────────────────--

func _make_slot(is_keyboard: bool, device: int, team: int = 0) -> MatchPlayerSlot:
	var slot := MatchPlayerSlot.new()
	slot.is_keyboard = is_keyboard
	slot.device_id = device
	slot.team = team
	return slot


## Index of the seat for a device (or the keyboard), or -1 if not joined.
func _find_seat(is_keyboard: bool, device: int) -> int:
	for i in _seats.size():
		var s := _seats[i]
		if s.is_keyboard == is_keyboard and (is_keyboard or s.device_id == device):
			return i
	return -1


func _remove_seat(index: int) -> void:
	if index >= 0 and index < _seats.size():
		_seats.remove_at(index)


func _set_team(index: int, team: int) -> void:
	if index >= 0 and index < _seats.size():
		_seats[index].team = team


func _start_multi() -> void:
	if _seats.is_empty():
		return   # need at least one human to start
	var cfg := MatchConfig.new()
	cfg.mode = MatchConfig.Mode.SINGLE if _seats.size() == 1 else MatchConfig.Mode.MULTI
	cfg.slots = _seats.duplicate()
	GameManager.start_match(cfg)


# ── Display ─────────────────────────────────────────────────────────────────--

func _refresh_teams() -> void:
	for child in _home_list.get_children():
		child.queue_free()
	for child in _away_list.get_children():
		child.queue_free()
	for s in _seats:
		var label := Label.new()
		label.text = _seat_label(s)
		(_home_list if s.team == 0 else _away_list).add_child(label)
	_hint.text = "Controller: A join · D-pad ◄ ► team · Start play · B leave\n" \
		+ "Keyboard: Space join · A/D team · Enter play · Esc leave"


func _seat_label(slot: MatchPlayerSlot) -> String:
	return "Keyboard + Mouse" if slot.is_keyboard else "Controller %d" % (slot.device_id + 1)
