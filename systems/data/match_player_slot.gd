extends Resource
class_name MatchPlayerSlot
## One human player's seat at a match: which input device drives it and which
## team it plays for. Pure data — the match scene turns each slot into a live
## PlayerInput on spawn. Kept as typed fields (not a loose Dictionary) so it
## serialises cleanly and a future network lobby can replicate it as-is.

## Joypad device id this slot reads (ignored when is_keyboard is true). Godot
## numbers connected pads 0,1,2,… — captured when the player joins the lobby.
@export var device_id: int = 0

## True if this slot is the keyboard + mouse player. Only one keyboard slot is
## allowed per machine (there is one mouse). Distinguishes a keyboard slot from
## joypad device 0, which can share the same numeric id.
@export var is_keyboard: bool = false

## 0 = home (blue, attacks +x).  1 = away (red, attacks −x).
@export var team: int = 0
