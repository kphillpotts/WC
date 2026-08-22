extends AnimatedSprite2D
## Translates movement "intent" into the right animation + facing direction.
## Attach this directly to an AnimatedSprite2D. The owning body (player
## script, or later an NPC AI script) calls report_movement() every
## physics frame; this script figures out what to actually play.

enum LocoState { WALKING, RUNNING, STANDING }
#
# NOTE: Right now STANDING is used for both "just stopped" and "been
# stationary a while", since there's only one at-rest sprite sheet. If a
# separate tail-sway Idle sheet gets added later, this is where a
# Timer-driven "STANDING -> IDLE after a few seconds" escalation would
# slot back in — the report_movement()/_play_for_state() shape is already
# set up for it.

var loco_state: LocoState = LocoState.STANDING
var facing: String = "down"


func _ready() -> void:
	_play_for_state()


## Call this every physics frame from whatever is controlling this cat.
## `running` should only be true while there's also movement input.
func report_movement(input_vector: Vector2, running: bool = false) -> void:
	if input_vector != Vector2.ZERO:
		_update_facing(input_vector)
		_set_state(LocoState.RUNNING if running else LocoState.WALKING)
	else:
		_set_state(LocoState.STANDING)


func _update_facing(input_vector: Vector2) -> void:
	var new_facing := facing
	if abs(input_vector.x) > abs(input_vector.y):
		new_facing = "right" if input_vector.x > 0 else "left"
	else:
		new_facing = "down" if input_vector.y > 0 else "up"

	if new_facing != facing:
		facing = new_facing
		_play_for_state()


func _set_state(new_state: LocoState) -> void:
	if new_state == loco_state:
		return
	loco_state = new_state
	_play_for_state()


func _play_for_state() -> void:
	match loco_state:
		LocoState.WALKING:
			play("walk_%s" % facing)
		LocoState.RUNNING:
			play("run_%s" % facing)
		LocoState.STANDING:
			play("stand_%s" % facing)