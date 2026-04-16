extends Button

signal confirmed_pressed

var _mouse_activation_armed: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_event.pressed:
			if not has_focus():
				_mouse_activation_armed = false
				grab_focus()
				accept_event()
				return

			_mouse_activation_armed = true
			accept_event()
			return

		if _mouse_activation_armed:
			_mouse_activation_armed = false
			accept_event()
			confirmed_pressed.emit()


func _pressed() -> void:
	if _mouse_activation_armed:
		return

	# Keyboard/controller activation path still fires immediately.
	confirmed_pressed.emit()
