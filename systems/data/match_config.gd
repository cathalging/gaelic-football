extends Resource
class_name MatchConfig
## How a single match is set up: single- or multiplayer, and the seat of every
## human player (see MatchPlayerSlot). Built by the match-setup lobby, owned by
## GameManager, and passed into the match scene, which spawns one PlayerInput
## per slot. Pure, JSON-serialisable data so the same object can later be sent
## to peers for a networked match (see CLAUDE.md multiplayer rules).

## Single = one local human (keyboard, home). Multi = whatever the lobby built.
enum Mode { SINGLE, MULTI }

@export var mode: Mode = Mode.SINGLE

## Human seats for this match (0 = an all-AI exhibition; 1 = the classic solo
## game). Order is the seat order — slot 0 is the "primary" seat the shared HUD
## power bar / stamina readout follows.
@export var slots: Array[MatchPlayerSlot] = []


## A plain single-player setup: one keyboard human on the home team. Used by the
## Quick Play "Single Player" shortcut and as a safe default if the match scene
## is ever opened without a config wired (isolated testing).
static func single_player() -> MatchConfig:
	var cfg := MatchConfig.new()
	cfg.mode = Mode.SINGLE
	var slot := MatchPlayerSlot.new()
	slot.is_keyboard = true
	slot.team = 0
	cfg.slots = [slot]
	return cfg


## Human seats on a given team, in seat order.
func slots_for_team(team: int) -> Array[MatchPlayerSlot]:
	var out: Array[MatchPlayerSlot] = []
	for s in slots:
		if s.team == team:
			out.append(s)
	return out
