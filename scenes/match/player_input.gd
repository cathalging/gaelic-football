class_name PlayerInput
extends Node
## One human player's input source, routed to a single device.
##
## The match scene spawns one of these per MatchPlayerSlot and assigns it to the
## AIPlayer that seat is controlling. AIPlayer reads movement and actions from
## its PlayerInput instead of the global Input singleton — that is what lets two
## pads (and a keyboard) each drive their own player on one machine. The named
## input actions (move_*, pass, shoot, …) are unchanged: this layer just filters
## them to one device, so the input map and rebinding still work.
##
## Online later: a NetworkPlayerInput can extend / mirror this same surface
## (move_vector / pressed / just_pressed / aim) fed from replicated state, and no
## gameplay code has to change. See CLAUDE.md multiplayer rules.

## Joypad device this seat reads (ignored when is_keyboard). Set on spawn.
var device: int = 0
## True for the keyboard + mouse seat. Aims at the mouse cursor; a joypad seat
## aims along its player's facing (per the design doc).
var is_keyboard: bool = false
## 0 = home, 1 = away — the team this seat plays for.
var team: int = 0
## This seat's selection-marker colour, applied to whichever player it controls so
## seats can be told apart on screen (and matched to their HUD panel). Set on spawn.
var marker_color: Color = Color(1.0, 0.88, 0.1)
## Short on-screen label for this seat ("P1", "P2", …). Set on spawn.
var label: String = "P1"
## The AIPlayer this seat currently controls (set by the match scene).
var controlled: Node = null

# Per-seat player-switching cycle (driven by the match scene): the current
# shortlist of switch targets, the cursor into it, and the lapse timer.
var switch_cycle: Array = []
var switch_index := 0
var switch_timer := 0.0

const DEADZONE := 0.2

# Gameplay action names this layer tracks. ui_* nav is left to the global Input
# (menus), and aim is read live (mouse / stick), so neither is listed here.
const _ACTIONS: Array[String] = [
	"pass", "shoot", "sprint", "solo", "bounce", "tackle", "jockey",
	"switch_player", "pause",
]

# Held state, edge-updated from device-filtered events; previous-frame snapshot
# for per-physics-frame "just pressed" edge detection (see end_frame).
var _pressed: Dictionary = {}
var _prev_pressed: Dictionary = {}

# Right-stick flick latch (joypad seats) — see right_stick / flick gating.
var _rs_ready := true


func _ready() -> void:
	for a in _ACTIONS:
		_pressed[a] = false
		_prev_pressed[a] = false
	# Snapshot the held state for edge detection AFTER every other node has read
	# its input this physics frame. A high priority makes this _physics_process
	# run last, so just_pressed() reads true for the whole frame regardless of the
	# order match_scene and the AIPlayers happen to process in.
	process_priority = 1000


## Only handle events from this seat's own device. Keyboard/mouse events all
## belong to the keyboard seat; joypad events belong to the seat whose `device`
## matches. This is what keeps two pads from driving the same player.
func _owns_event(event: InputEvent) -> bool:
	if is_keyboard:
		return event is InputEventKey \
			or event is InputEventMouseButton \
			or event is InputEventMouseMotion
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device == device
	return false


func _input(event: InputEvent) -> void:
	if not _owns_event(event):
		return
	for a in _ACTIONS:
		if event.is_action_pressed(a):
			_pressed[a] = true
		elif event.is_action_released(a):
			_pressed[a] = false


## Snapshot the held state at the end of each physics frame (runs last — see the
## process_priority set in _ready) so just_pressed() reports a clean one-frame
## edge to every reader during the next frame.
func _physics_process(_delta: float) -> void:
	for a in _ACTIONS:
		_prev_pressed[a] = _pressed[a]


## True while the action is held on this seat's device.
func pressed(action: String) -> bool:
	return _pressed.get(action, false)


## True on the physics frame this seat's device first pressed the action.
func just_pressed(action: String) -> bool:
	return _pressed.get(action, false) and not _prev_pressed.get(action, false)


## Normalised movement for this seat (≤1 in length, zero inside the deadzone).
func move_vector() -> Vector2:
	if is_keyboard:
		var kx := _key_axis("move_right") - _key_axis("move_left")
		var ky := _key_axis("move_down") - _key_axis("move_up")
		return Vector2(kx, ky).limit_length(1.0)
	var v := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):  v.x -= 1.0
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT): v.x += 1.0
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):    v.y -= 1.0
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):  v.y += 1.0
	if v.length() < DEADZONE:
		return Vector2.ZERO
	return v.limit_length(1.0)


## 1.0 if any keyboard key bound to `action` is held, else 0.0. Reads the action
## map (so rebinding still applies) but only the key events — never a joypad
## axis — so the keyboard seat stays isolated from the pads.
func _key_axis(action: String) -> float:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var kc: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			if kc != 0 and Input.is_physical_key_pressed(kc):
				return 1.0
	return 0.0


## Right-stick vector for a joypad seat (zero for the keyboard seat — its switch
## uses the button only). Used by the match scene for the flick-to-switch.
func right_stick() -> Vector2:
	if is_keyboard:
		return Vector2.ZERO
	return Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))


## Edge-triggered right-stick flick: returns a unit direction once when the stick
## is pushed past `on`, then re-arms only after it falls back below `off`. Mirrors
## the old single-player flick, now per-seat. Returns ZERO when no flick fires.
func flick(on: float, off: float) -> Vector2:
	var rs := right_stick()
	var mag := rs.length()
	if mag < off:
		_rs_ready = true
		return Vector2.ZERO
	if mag >= on and _rs_ready:
		_rs_ready = false
		return rs.normalized()
	return Vector2.ZERO
