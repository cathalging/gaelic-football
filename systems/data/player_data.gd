extends Resource
class_name PlayerData
## A single player's persistent attributes. Pure data, no behaviour.
##
## Modelled as a Resource: Godot serialises Resources for free, which is what
## makes save/load and (later) network sync straightforward. Keep gameplay
## logic out of here — systems read these values, they don't live here.

@export var display_name: String = ""
@export var age: int = 18
@export_enum("GK", "DEF", "MID", "FWD") var position: String = "MID"

# Core attributes (0–100). Expand as the gameplay/tactics layer grows.
@export var pace: int = 50
@export var passing: int = 50
@export var shooting: int = 50
@export var tackling: int = 50
@export var stamina: int = 50
