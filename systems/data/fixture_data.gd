extends Resource
class_name FixtureData
## A scheduled match between two teams on a given calendar day.

@export var home: ClubData
@export var away: ClubData
@export var day: int = 0              ## calendar day index within the career
@export var competition: String = "" ## e.g. "Club Championship", "All-Ireland"
@export var played: bool = false
@export var result: Dictionary = {}  ## mirrors MatchEngine's result shape
