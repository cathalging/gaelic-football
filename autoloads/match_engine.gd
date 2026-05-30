extends Node
## MatchEngine — produces match results, either by simulation or by live play.
##
## Strictly separates *simulation* (deterministic, headless, fast) from
## *presentation* (the playable 2D match scene). Simulated and played matches
## must return the same result shape, so leagues, stats and multiplayer treat
## them identically.
##
## IMPORTANT: never put rendering or input code here. The interactive match
## lives in its own scene (scenes/match/) which reports its result back through
## the match_finished signal.

signal match_finished(result: Dictionary)


## Quickly resolve a fixture without playing it. Deterministic given a seed so
## multiplayer peers can independently compute the same outcome.
## Returns a result Dictionary (see _empty_result for the shape).
func simulate(_home: ClubData, _away: ClubData, _seed: int = 0) -> Dictionary:
	# TODO: model possession, scoring chances and player ratings.
	push_warning("MatchEngine.simulate not implemented yet (scaffold).")
	return _empty_result()


## Hand off to the interactive match scene. The result is delivered later via
## the match_finished signal when play ends.
func play(_home: ClubData, _away: ClubData) -> void:
	# TODO: load scenes/match/match.tscn, feed it the teams, await its result.
	push_warning("MatchEngine.play not implemented yet (scaffold).")


## The canonical result shape. Gaelic football scoring is goals (worth 3) and
## points (worth 1), reported separately so the UI can show "1-12" style lines.
func _empty_result() -> Dictionary:
	return {
		"home_score": {"goals": 0, "points": 0},
		"away_score": {"goals": 0, "points": 0},
		"events": [],  # timeline of scores, cards, substitutions, etc.
	}
