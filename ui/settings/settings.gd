extends Control
## Settings placeholder. Real options (audio, display, control remapping) land
## here. Demonstrates reading a named input action ("pause") to back out, which
## works on both Esc and the Start button.

func _ready() -> void:
	%BackButton.grab_focus()


func _on_back_pressed() -> void:
	GameManager.return_to_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		GameManager.return_to_main_menu()
