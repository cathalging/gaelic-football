extends Node
## CrowdAudio — placeholder crowd-noise event hub.
##
## Real audio assets aren't in yet, so this is a thin shim: match_scene calls
## react_score() / react_foul() at the right moments, and we play whatever stream
## has been assigned (none, for now). When real clips are added, drop them into the
## exported slots in the inspector and the events already fire in the right places.
##
## Until then each event is logged so you can see the crowd "reacting" while testing.

## Big roar when a goal goes in.
@export var cheer_goal: AudioStream = null
## Lighter cheer for a point.
@export var cheer_point: AudioStream = null
## Groan / jeer when a foul or card is shown.
@export var groan: AudioStream = null
## Looping background murmur (started on _ready if assigned).
@export var ambience: AudioStream = null

var _sfx: AudioStreamPlayer = null
var _ambient: AudioStreamPlayer = null


func _ready() -> void:
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "Master"
	add_child(_sfx)

	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "Master"
	_ambient.volume_db = -8.0
	add_child(_ambient)
	if ambience:
		_ambient.stream = ambience
		_ambient.play()


## A score went in. is_goal = true for a goal (3 pts), false for a point.
func react_score(is_goal: bool) -> void:
	if is_goal:
		_play(cheer_goal, "CROWD: goal roar")
	else:
		_play(cheer_point, "CROWD: point cheer")


## A foul / card — the crowd groans.
func react_foul() -> void:
	_play(groan, "CROWD: foul groan")


func _play(stream: AudioStream, placeholder_label: String) -> void:
	if stream:
		_sfx.stream = stream
		_sfx.play()
	else:
		# Placeholder until real audio lands — keep the event visible in the log.
		print("[crowd_audio] %s" % placeholder_label)
