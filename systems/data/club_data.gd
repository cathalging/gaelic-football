extends Resource
class_name ClubData
## A club or county team and its squad. Pure data, no behaviour.

@export var club_name: String = ""
## County teams are assembled from club players; flagged here so the call-up
## logic in Player Career can treat them differently.
@export var is_county: bool = false
@export var squad: Array[PlayerData] = []
