class_name HUD
extends CanvasLayer
## Match HUD — score, clock, power bar. Step dots are drawn by player nodes.

@onready var _home_label:  Label       = %HomeLabel
@onready var _away_label:  Label       = %AwayLabel
@onready var _power_bar:   ProgressBar = %PowerBar
@onready var _event_label: Label       = %EventLabel

var _clock_label:  Label = null
var _status_label: Label = null

# Possession indicator (top-left) — built in code.
var _poss_label: Label = null
var _possession := -2     # cached so we only restyle on change (-1 loose, 0/1 team)
const C_POSS_HOME := Color(0.40, 0.62, 1.0)
const C_POSS_AWAY := Color(1.0, 0.42, 0.42)
const C_POSS_NONE := Color(0.8, 0.8, 0.8)

# Per-seat player panels (bottom-left, stacked) — colour-coded label + stamina
# bar per human seat, so players can be told apart. Built by setup_player_hud.
const PHUD_W     := 168.0
const PHUD_BAR_H := 14.0
var _player_panels: Array = []   # [{root: Control, fill: ColorRect}]

# Minimap (bottom-right).
const MINIMAP_W := 240.0
const MINIMAP_H := 150.0
var _minimap: Minimap = null

# Card flash (yellow/red) shown when a foul is called.
var _card_rect: ColorRect = null
var _card_tween: Tween = null

# Full-time scoreboard popup.
var _scoreboard: Control = null

# Tackle timing meter — built in code (see _setup_tackle_meter).
const TACKLE_BAR_W := 320.0
const TACKLE_BAR_H := 26.0
var _tackle_root:    Control   = null
var _tackle_good:    ColorRect = null
var _tackle_perfect: ColorRect = null
var _tackle_cursor:  ColorRect = null


func _ready() -> void:
	_power_bar.visible   = false
	_event_label.visible = false
	_setup_power_marker()
	update_score(0, 0, 0, 0)
	_setup_clock_label()
	_setup_status_label()
	_setup_tackle_meter()
	_setup_possession()
	_setup_card()


func _setup_clock_label() -> void:
	_clock_label = Label.new()
	_clock_label.layout_mode             = 1   # LAYOUT_MODE_ANCHORS
	_clock_label.anchor_left             = 0.5
	_clock_label.anchor_right            = 0.5
	_clock_label.anchor_top              = 0.0
	_clock_label.anchor_bottom           = 0.0
	_clock_label.offset_left             = -110.0
	_clock_label.offset_right            =  110.0
	_clock_label.offset_top             =   54.0
	_clock_label.offset_bottom           =   80.0
	_clock_label.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 20)
	_clock_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_clock_label.text = "H1  00:00"
	$UIRoot.add_child(_clock_label)


func _setup_status_label() -> void:
	_status_label = Label.new()
	_status_label.layout_mode          = 1   # LAYOUT_MODE_ANCHORS
	_status_label.anchor_left          = 0.5
	_status_label.anchor_right         = 0.5
	_status_label.anchor_top           = 0.0
	_status_label.anchor_bottom        = 0.0
	_status_label.offset_left          = -220.0
	_status_label.offset_right         =  220.0
	_status_label.offset_top           =  92.0
	_status_label.offset_bottom        =  128.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 26)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
	_status_label.visible = false
	$UIRoot.add_child(_status_label)


## Tackle timing meter: a track with a wide "good" zone and a narrow "perfect"
## zone in the centre, plus a sweeping cursor. Built from ColorRects so it needs
## no extra script. Centred low on screen, just above the power bar slot.
func _setup_tackle_meter() -> void:
	_tackle_root = Control.new()
	_tackle_root.layout_mode   = 1   # LAYOUT_MODE_ANCHORS
	_tackle_root.anchor_left   = 0.5
	_tackle_root.anchor_right  = 0.5
	_tackle_root.anchor_top    = 1.0
	_tackle_root.anchor_bottom = 1.0
	_tackle_root.offset_left   = -TACKLE_BAR_W * 0.5
	_tackle_root.offset_right  =  TACKLE_BAR_W * 0.5
	_tackle_root.offset_top    = -110.0
	_tackle_root.offset_bottom = -110.0 + TACKLE_BAR_H
	_tackle_root.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_tackle_root.visible       = false

	var track := ColorRect.new()
	track.color = Color(0.05, 0.05, 0.07, 0.85)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tackle_root.add_child(track)

	_tackle_good = ColorRect.new()
	_tackle_good.color = Color(0.95, 0.78, 0.20, 0.90)
	_tackle_root.add_child(_tackle_good)

	_tackle_perfect = ColorRect.new()
	_tackle_perfect.color = Color(0.30, 0.95, 0.45, 0.95)
	_tackle_root.add_child(_tackle_perfect)

	_tackle_cursor = ColorRect.new()
	_tackle_cursor.color = Color(1.0, 1.0, 1.0, 1.0)
	_tackle_root.add_child(_tackle_cursor)

	$UIRoot.add_child(_tackle_root)


## Show/update the tackle meter. cursor, good_hw and perfect_hw are 0..1 fractions
## (half-widths measured out from the centre at 0.5).
func show_tackle_meter(cursor: float, good_hw: float, perfect_hw: float) -> void:
	_tackle_root.visible = true
	var w := TACKLE_BAR_W
	_tackle_good.position    = Vector2((0.5 - good_hw) * w, 0.0)
	_tackle_good.size        = Vector2(good_hw * 2.0 * w, TACKLE_BAR_H)
	_tackle_perfect.position = Vector2((0.5 - perfect_hw) * w, 0.0)
	_tackle_perfect.size     = Vector2(perfect_hw * 2.0 * w, TACKLE_BAR_H)
	_tackle_cursor.size      = Vector2(4.0, TACKLE_BAR_H)
	_tackle_cursor.position  = Vector2(clampf(cursor, 0.0, 1.0) * w - 2.0, 0.0)


func hide_tackle_meter() -> void:
	if _tackle_root:
		_tackle_root.visible = false


## Persistent banner for set pieces (free, 45, penalty, kickout, sideline).
## Unlike show_event it does not auto-hide — call clear_status() to remove it.
func set_status(text: String) -> void:
	if _status_label:
		_status_label.text    = text
		_status_label.visible = true


func clear_status() -> void:
	if _status_label:
		_status_label.visible = false


## Display score in GAA notation: goals-points (e.g. "1-08").
func update_score(home_g: int, home_p: int, away_g: int, away_p: int) -> void:
	_home_label.text = "%d-%02d" % [home_g, home_p]
	_away_label.text = "%d-%02d" % [away_g, away_p]


## Update the match clock label.  text format: "H1  28:47"
func set_clock(text: String) -> void:
	if _clock_label:
		_clock_label.text = text


## Mark the shot sweet spot on the power bar: release at or just before this line
## for the most accurate shot; holding past it (overcharging) sprays it. Kept in
## sync with the shot model via AIPlayer.OVERCHARGE_KNEE so there's one source.
func _setup_power_marker() -> void:
	var marker := ColorRect.new()
	marker.color         = Color(0.20, 0.95, 0.45, 0.95)
	marker.layout_mode   = 1   # LAYOUT_MODE_ANCHORS
	marker.anchor_left   = AIPlayer.OVERCHARGE_KNEE
	marker.anchor_right  = AIPlayer.OVERCHARGE_KNEE
	marker.anchor_top    = 0.0
	marker.anchor_bottom = 1.0
	marker.offset_left   = -2.0
	marker.offset_right  =  2.0
	marker.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_power_bar.add_child(marker)


## Show the power bar filled 0..1. Called every frame while a button is held.
func set_power(value: float) -> void:
	_power_bar.visible = true
	_power_bar.value   = clampf(value, 0.0, 1.0) * 100.0


func hide_power() -> void:
	_power_bar.visible = false


## Flash a short event message (score, foul, wide, etc.) then auto-hide.
func show_event(text: String, duration: float = 2.0) -> void:
	_event_label.text    = text
	_event_label.visible = true
	await get_tree().create_timer(duration).timeout
	_event_label.visible = false


# ── Possession indicator ─────────────────────────────────────────────────────--

func _setup_possession() -> void:
	_poss_label = Label.new()
	_poss_label.layout_mode    = 1   # LAYOUT_MODE_ANCHORS
	_poss_label.offset_left    = 18.0
	_poss_label.offset_top     = 16.0
	_poss_label.offset_right   = 220.0
	_poss_label.offset_bottom  = 44.0
	_poss_label.add_theme_font_size_override("font_size", 18)
	_poss_label.text = "POSS  —"
	$UIRoot.add_child(_poss_label)
	set_possession(-1)


## Show which team has the ball: 0 = home, 1 = away, -1 = loose.
func set_possession(team: int) -> void:
	if team == _possession or _poss_label == null:
		return
	_possession = team
	match team:
		0:
			_poss_label.text = "POSS  HOME"
			_poss_label.add_theme_color_override("font_color", C_POSS_HOME)
		1:
			_poss_label.text = "POSS  AWAY"
			_poss_label.add_theme_color_override("font_color", C_POSS_AWAY)
		_:
			_poss_label.text = "POSS  —"
			_poss_label.add_theme_color_override("font_color", C_POSS_NONE)


# ── Per-seat player panels (stamina + colour) ─────────────────────────────────--

## Build one bottom-left panel per human seat: a colour-coded label (matching the
## player's on-pitch selection marker) over a stamina bar. `slots` is the match
## scene's Array[PlayerInput]; each must expose label, team and marker_color.
func setup_player_hud(slots: Array) -> void:
	for p in _player_panels:
		if is_instance_valid(p["root"]):
			p["root"].queue_free()
	_player_panels.clear()
	for i in slots.size():
		var slot = slots[i]
		var root := Control.new()
		root.layout_mode   = 1
		root.anchor_top    = 1.0
		root.anchor_bottom = 1.0
		root.offset_left   = 18.0
		root.offset_right  = 18.0 + PHUD_W
		var y := -40.0 - i * 44.0
		root.offset_top    = y
		root.offset_bottom = y + 34.0
		root.mouse_filter  = Control.MOUSE_FILTER_IGNORE

		var label := Label.new()
		label.text = "%s  %s" % [slot.label, "HOME" if slot.team == 0 else "AWAY"]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", slot.marker_color)
		label.position = Vector2(0.0, -2.0)
		root.add_child(label)

		var track := ColorRect.new()
		track.color    = Color(0.05, 0.05, 0.07, 0.85)
		track.position = Vector2(0.0, 16.0)
		track.size     = Vector2(PHUD_W, PHUD_BAR_H)
		root.add_child(track)

		var fill := ColorRect.new()
		fill.position = Vector2(2.0, 18.0)
		fill.size     = Vector2(PHUD_W - 4.0, PHUD_BAR_H - 4.0)
		fill.color    = Color(0.30, 0.85, 0.40)
		root.add_child(fill)

		$UIRoot.add_child(root)
		_player_panels.append({"root": root, "fill": fill})


## Set a seat's stamina (0..1). Bar shrinks and shifts green→amber→red.
func set_player_stamina(index: int, value: float) -> void:
	if index < 0 or index >= _player_panels.size():
		return
	var fill: ColorRect = _player_panels[index]["fill"]
	var v := clampf(value, 0.0, 1.0)
	fill.size.x = (PHUD_W - 4.0) * v
	if v > 0.5:
		fill.color = Color(0.30, 0.85, 0.40)        # green
	elif v > 0.2:
		fill.color = Color(0.95, 0.78, 0.20)        # amber
	else:
		fill.color = Color(0.90, 0.30, 0.25)        # red


# ── Minimap ──────────────────────────────────────────────────────────────────--

## Create the corner minimap and wire it to the live match sources.
func setup_minimap(team_a: Array, team_b: Array, ball: Node2D, half_length: float, half_width: float) -> void:
	_minimap = Minimap.new()
	_minimap.layout_mode   = 1
	_minimap.anchor_left   = 1.0
	_minimap.anchor_right  = 1.0
	_minimap.anchor_top    = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left   = -MINIMAP_W - 18.0
	_minimap.offset_right  = -18.0
	_minimap.offset_top    = -MINIMAP_H - 18.0
	_minimap.offset_bottom = -18.0
	_minimap.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_minimap.configure(team_a, team_b, ball, half_length, half_width)
	$UIRoot.add_child(_minimap)


# ── Cards ────────────────────────────────────────────────────────────────────--

func _setup_card() -> void:
	_card_rect = ColorRect.new()
	_card_rect.layout_mode   = 1
	_card_rect.anchor_left   = 0.5
	_card_rect.anchor_right  = 0.5
	_card_rect.anchor_top    = 0.5
	_card_rect.anchor_bottom = 0.5
	_card_rect.offset_left   = -38.0
	_card_rect.offset_right  =  38.0
	_card_rect.offset_top    = -54.0
	_card_rect.offset_bottom =  54.0
	_card_rect.pivot_offset  = Vector2(38.0, 54.0)
	_card_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_card_rect.visible       = false
	$UIRoot.add_child(_card_rect)


## Flash a yellow (is_red = false) or red card with a quick pop-and-settle tween.
func show_card(is_red: bool) -> void:
	if _card_rect == null:
		return
	_card_rect.color   = Color(0.85, 0.15, 0.15) if is_red else Color(0.95, 0.82, 0.18)
	_card_rect.visible = true
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	# Pop in (overshoot scale + spin), hold, then drop away.
	_card_rect.scale    = Vector2(0.1, 0.1)
	_card_rect.rotation = -0.6
	_card_tween = create_tween()
	_card_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(_card_rect, "scale", Vector2(1.0, 1.0), 0.25)
	_card_tween.parallel().tween_property(_card_rect, "rotation", 0.0, 0.25)
	_card_tween.tween_interval(1.1)
	_card_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_card_tween.tween_property(_card_rect, "scale", Vector2(0.1, 0.1), 0.2)
	_card_tween.tween_callback(func() -> void: _card_rect.visible = false)


# ── Full-time scoreboard ───────────────────────────────────────────────────────

## Show a centred full-time panel: final score plus a top-scorers list.
## scorers is an Array of { team, jersey, goals, points } (see match_scene._top_scorers).
func show_scoreboard(home_g: int, home_p: int, away_g: int, away_p: int, scorers: Array) -> void:
	if _scoreboard and is_instance_valid(_scoreboard):
		_scoreboard.queue_free()

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.anchor_right  = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.layout_mode   = 1
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -260.0
	panel.offset_right  =  260.0
	panel.offset_top    = -200.0
	panel.offset_bottom =  200.0
	dim.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "FULL TIME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	var score := Label.new()
	score.text = "HOME  %d-%02d    —    %d-%02d  AWAY" % [home_g, home_p, away_g, away_p]
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 26)
	vbox.add_child(score)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var heading := Label.new()
	heading.text = "TOP SCORERS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
	vbox.add_child(heading)

	if scorers.is_empty():
		var none := Label.new()
		none.text = "No scores"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(none)
	else:
		for s in scorers:
			var side: String = "HOME" if s["team"] == 0 else "AWAY"
			var row := Label.new()
			row.text = "%s  #%d    %d-%02d" % [side, s["jersey"], s["goals"], s["points"]]
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_theme_font_size_override("font_size", 18)
			row.add_theme_color_override("font_color", C_POSS_HOME if s["team"] == 0 else C_POSS_AWAY)
			vbox.add_child(row)

	$UIRoot.add_child(dim)
	_scoreboard = dim
