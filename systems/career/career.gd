extends Resource
class_name Career
## Root save object — everything a single save slot contains.
##
## Because this (and everything it references) is a Resource tree, a whole
## career can be saved, loaded, and serialised for network transfer as one
## unit. CareerManager owns the live instance.

@export var save_name: String = ""
@export var current_day: int = 0

@export var clubs: Array[ClubData] = []
@export var fixtures: Array[FixtureData] = []

## The club/county the user controls in Manager Career.
@export var managed_club: ClubData
## The single player the user controls in Player Career.
@export var controlled_player: PlayerData
