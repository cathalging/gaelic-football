extends Control
## Main menu — routes to the two career modes and settings.
##
## Buttons are focus-navigable, so the menu works on controller out of the box
## (D-pad / left stick move focus, A button = ui_accept). The first button
## grabs focus on load so there is always a controller cursor.

func _ready() -> void:
	%ManagerCareerButton.grab_focus()


func _on_manager_career_pressed() -> void:
	GameManager.start_manager_career()


func _on_player_career_pressed() -> void:
	GameManager.start_player_career()


func _on_quick_play_pressed() -> void:
	GameManager.start_quick_play()


func _on_tutorial_pressed() -> void:
	GameManager.open_tutorial()


func _on_settings_pressed() -> void:
	GameManager.open_settings()


func _on_quit_pressed() -> void:
	get_tree().quit()
