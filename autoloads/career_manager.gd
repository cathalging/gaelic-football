extends Node
## CareerManager — owns the active career save and all career-mode systems.
##
## A "career" is the full persistent state of a save: clubs, players, fixtures,
## league tables, transfers and the in-game calendar. This manager is
## mode-agnostic — the same Career data backs both Manager and Player careers;
## GameManager.career_mode decides which slice the UI exposes.
##
## Designed to be serialisable end-to-end (see systems/career/career.gd) so the
## same state can later be synced across a network session.
## See CLAUDE.md → "Designing for multiplayer".

signal career_started
signal day_advanced(day: int)
signal fixture_ready(fixture: FixtureData)

## The loaded save. null when at the main menu / no career active.
var active_career: Career = null


func new_career(_config: Dictionary = {}) -> void:
	# TODO: build a fresh Career (generate clubs, squads and a fixture list)
	# from _config (chosen team, difficulty, etc.).
	push_warning("CareerManager.new_career not implemented yet (scaffold).")
	career_started.emit()


func load_career(_path: String) -> bool:
	# TODO: deserialise a save slot into active_career.
	push_warning("CareerManager.load_career not implemented yet (scaffold).")
	return false


func save_career(_path: String) -> bool:
	# TODO: persist active_career to disk (ResourceSaver on the Career resource).
	push_warning("CareerManager.save_career not implemented yet (scaffold).")
	return false


## Advance the calendar by one day: resolve any fixtures scheduled for today
## (via MatchEngine), then fire signals the UI listens to.
func advance_day() -> void:
	# TODO: tick active_career.current_day, resolve fixtures, emit day_advanced.
	push_warning("CareerManager.advance_day not implemented yet (scaffold).")
