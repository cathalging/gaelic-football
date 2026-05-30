extends Node
## GameManager — top-level application state machine and scene router.
##
## Owns the high-level game state (which mode we are in) and is the single
## entry point for switching between menus, careers, and matches. Keep this
## thin: it routes and holds global state, but delegates all domain logic to
## CareerManager (career data) and MatchEngine (match results).
##
## Registered as an autoload singleton, so reachable anywhere as `GameManager`.

signal state_changed(new_state: State)

enum State {
	BOOT,
	MAIN_MENU,
	MANAGER_CAREER,
	PLAYER_CAREER,
	MATCH,
	SETTINGS,
}

## Which career the user chose on the main menu. CareerManager uses this to
## decide which slice of the save the UI exposes; the underlying data is shared.
enum CareerMode {
	NONE,
	MANAGER,
	PLAYER,
}

const SCENE_MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
const SCENE_SETTINGS  := "res://ui/settings/settings.tscn"
const SCENE_MATCH     := "res://scenes/match/MatchScene.tscn"
# const SCENE_MANAGER_HUB := "res://scenes/manager/manager_hub.tscn"

var current_state: State = State.BOOT
var career_mode: CareerMode = CareerMode.NONE


func _ready() -> void:
	# Autoloads initialise before the main scene. The main scene IS the menu,
	# so we just record state here; routing happens via the methods below.
	current_state = State.MAIN_MENU


func start_manager_career() -> void:
	career_mode = CareerMode.MANAGER
	# TODO: CareerManager.new_career() then route to the manager hub scene.
	push_warning("Manager Career not implemented yet (scaffold).")
	_set_state(State.MANAGER_CAREER)


func start_player_career() -> void:
	career_mode = CareerMode.PLAYER
	# TODO: CareerManager.new_career() then route to the player career scene.
	push_warning("Player Career not implemented yet (scaffold).")
	_set_state(State.PLAYER_CAREER)


## Jump straight into a match with no career context. Development shortcut only.
func start_quick_play() -> void:
	career_mode = CareerMode.NONE
	_set_state(State.MATCH)
	change_scene(SCENE_MATCH)


func open_settings() -> void:
	_set_state(State.SETTINGS)
	change_scene(SCENE_SETTINGS)


func return_to_main_menu() -> void:
	career_mode = CareerMode.NONE
	_set_state(State.MAIN_MENU)
	change_scene(SCENE_MAIN_MENU)


## Centralised scene swap so transitions, loading screens and (later)
## multiplayer sync all flow through one place rather than scattered
## change_scene_to_file() calls.
func change_scene(scene_path: String) -> void:
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("GameManager: failed to change scene to %s (error %d)" % [scene_path, err])


func _set_state(new_state: State) -> void:
	if new_state == current_state:
		return
	current_state = new_state
	state_changed.emit(new_state)
