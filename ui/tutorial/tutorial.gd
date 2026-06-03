extends Control
## Tutorial / "How to Play" screen — a read-only reference reached from the main
## menu. Two tabs: a Controls grid (keyboard + controller for every named input
## action) and a Mechanics rundown explaining the systems behind those controls
## (tackling, shooting, carrying, etc.).
##
## The content is built as BBCode in _ready() rather than baked into the .tscn so
## the strings stay readable and edit-friendly here, next to the source of truth
## (the input map and match-feel notes in CLAUDE.md). This screen owns no state;
## it backs out to the menu on the "pause"/"ui_cancel" action or the Back button.

## One control row: action name, keyboard binding, controller binding, and notes.
const CONTROLS := [
	["Move", "WASD", "Left stick / D-pad", "Run your player around the pitch."],
	["Pass", "Left click", "A button", "Tap for a hand pass. Double-tap and hold for a kick pass — the longer you hold, the more power."],
	["Shoot", "Right click", "B button", "Hold for a point attempt. Double-tap and hold the second press for a goal attempt — power comes from the hold."],
	["Sprint", "Shift", "Right trigger", "A dash burst, then a per-player cooldown. The ring around your player shows when it is ready."],
	["Solo", "C", "X button", "Toe-tap the ball to yourself. Resets your carry-step counter — unlimited uses."],
	["Bounce", "V", "Y button", "Bounce the ball. Also resets the carry-step counter, but only once per possession."],
	["Tackle", "F", "Right bumper", "Shadow the carrier closely until the ring fills solid, then press to start a timing-contest tackle."],
	["Jockey", "E (hold)", "Left trigger (hold)", "Defender only. Shadow the carrier at contain speed, staying square to set up a tackle."],
	["Switch player", "Q", "Button 9", "On defence, take control of the player nearest the ball."],
	["Pause", "Esc", "Start", "Pause the match / back out of menus."],
	["Aim", "Mouse position", "Player's facing", "No button — passes and shots go where you aim. Mouse aims at the cursor; gamepad aims where the player faces."],
]

## Each entry is a [heading, body] pair rendered as one block in the Mechanics tab.
const MECHANICS := [
	[
		"Carrying the ball",
		"You can only take a few steps while holding the ball before you must release it. The carry-step counter fills as you run; [b]solo[/b] (toe-tap) or [b]bounce[/b] resets it so you can keep going. Solo is unlimited, but you only get one bounce per possession — so chain solos to travel and save the bounce. Run out of steps without releasing and you cough up the ball.",
	],
	[
		"Passing",
		"A quick [b]tap[/b] of pass plays a short hand pass to a teammate in the direction you are aiming. For distance, [b]double-tap and hold[/b] to wind up a kick pass — the power bar fills while you hold, and the ball travels further the longer you charge. Passes can never score: the ball stops being a shot the moment it leaves your hands.",
	],
	[
		"Shooting & the sweet spot",
		"[b]Hold shoot[/b] for a point attempt; [b]double-tap and hold[/b] the second press for a goal attempt. A power bar fills fast and has a [color=#7CFC00]green sweet-spot marker[/color]. Releasing near the sweet spot gives the cleanest strike. [b]Overcharging[/b] — holding all the way to the top — sprays the shot off target, so let go a touch early for accuracy.",
	],
	[
		"Points vs goals",
		"What you score is decided by the ball's actual arc as it crosses the goal line, not by which attempt you pressed. Over the crossbar = a [b]point[/b]; under the bar (into the net) = a [b]goal[/b]. The ball gains a ring when it is above crossbar height, and the crossbar is drawn in a warm colour, so you can read the height as it flies. There is a little leeway just outside the posts.",
	],
	[
		"Tackling",
		"You cannot tackle from anywhere. First [b]shadow the carrier[/b] within a close radius for a moment — the ring around your defender fills as you close the gap and goes solid when a tackle can land. Pressing [b]tackle[/b] then starts a timing-contest: win it and you strip the ball. [b]Jockey[/b] (hold) helps you contain and stay square while you close in.",
	],
	[
		"Charging down a shot",
		"Tackling and blocking are separate. Even when the tackle ring is not solid, getting square in front of a shooter lets you [b]charge down[/b] the shot head-on — a front-on block that does not need the close-shadow engagement a tackle does.",
	],
	[
		"Sprint & switching on defence",
		"[b]Sprint[/b] is a dash burst on a per-player cooldown that recovers in the background — when you switch to a player their dash is topped up and ready. On defence, [b]switch player[/b] hands you whoever is nearest the ball, so you can chase down the play without micromanaging the whole team.",
	],
	[
		"Set pieces & kickouts",
		"When you take a free, sideline or kickout, there is no countdown — the set piece arms immediately, so aim and go. When the AI takes one, it waits a beat before kicking to give you time to react and set up.",
	],
]


func _ready() -> void:
	%ControlsText.text = _build_controls_bbcode()
	%MechanicsText.text = _build_mechanics_bbcode()
	%BackButton.grab_focus()


func _on_back_pressed() -> void:
	GameManager.return_to_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		GameManager.return_to_main_menu()


## Render the controls as a four-column BBCode table (action / key / pad / notes).
func _build_controls_bbcode() -> String:
	var out := "[table=4]"
	out += _control_row("[b]Action[/b]", "[b]Keyboard[/b]", "[b]Controller[/b]", "[b]What it does[/b]")
	for row in CONTROLS:
		out += _control_row("[b]%s[/b]" % row[0], row[1], row[2], row[3])
	out += "[/table]"
	return out


func _control_row(action: String, key: String, pad: String, notes: String) -> String:
	return "[cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [action, key, pad, notes]


## Render the mechanics as headed paragraphs separated by blank lines.
func _build_mechanics_bbcode() -> String:
	var blocks := PackedStringArray()
	for entry in MECHANICS:
		blocks.append("[font_size=20][b]%s[/b][/font_size]\n%s" % [entry[0], entry[1]])
	return "\n\n".join(blocks)
