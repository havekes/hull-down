extends Node
## Temporary SETUP-01 debug helper.
##
## Prints the project's tank/camera InputMap actions on start-up and logs each
## transition to "pressed" while the game is running. Run the project on macOS
## and watch the Output panel (or a headless run) to confirm the actions defined
## in `project.godot` are wired up.

const LOGGED_ACTIONS: PackedStringArray = [
	"tank_forward",
	"tank_backward",
	"tank_left",
	"tank_right",
	"tank_fire",
	"camera_zoom_in",
	"camera_zoom_out",
]

var _was_pressed: Dictionary = {}


func _ready() -> void:
	var descriptions: PackedStringArray = []
	for action: String in LOGGED_ACTIONS:
		if not InputMap.has_action(action):
			push_error("[InputDebug] Missing InputMap action: %s" % action)
			descriptions.append("%s=MISSING" % action)
			continue

		var event_texts: PackedStringArray = []
		for event: InputEvent in InputMap.action_get_events(action):
			event_texts.append(event.as_text())
		descriptions.append("%s [%s]" % [action, ", ".join(event_texts)])

	print("[InputDebug] InputMap ready: ", " | ".join(descriptions))


func _process(_delta: float) -> void:
	for action: String in LOGGED_ACTIONS:
		var is_pressed: bool = Input.is_action_pressed(action)
		if is_pressed and not _was_pressed.get(action, false):
			print("[InputDebug] Action pressed: ", action)
		_was_pressed[action] = is_pressed
