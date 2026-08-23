extends AnimatedSprite2D
## Translates movement "intent" into the right animation + facing direction.
## Attach this directly to an AnimatedSprite2D. The owning body (player
## script, or later an NPC AI script) calls report_movement() every
## physics frame; this script figures out what to actually play.

enum LocoState { WALKING, RUNNING, STANDING, SITTING_DOWN, SITTING, LICKING, OBSERVING, STANDING_UP }
#
# NOTE: STANDING is used for both "just stopped" and "been stationary a
# while", since there's only one at-rest sprite sheet. Standing still long
# enough escalates to sitting (see auto_sit_delay), and sitting still long
# enough escalates again to a one-off grooming action. If a separate
# tail-sway Idle sheet gets added later it would slot in between standing
# and sitting, on the same _state_time clock.
#
# SITTING_DOWN / STANDING_UP are the two halves of one sprite sheet row:
# the sheet only stores standing -> sitting, so standing back up plays the
# same clip backwards. Both are non-looping, and animation_finished drives
# the handover to SITTING / STANDING.
#
# LICKING / OBSERVING are drawn in the same seated pose as the sitting
# idle, so they need no transition of their own — they just take over the
# sprite for a few seconds and hand it straight back to SITTING.

# Seated in any pose, including the transitions either side. The cat is not
# free to move in any of these.
const SEATED_STATES := [LocoState.SITTING_DOWN, LocoState.SITTING, LocoState.LICKING,
		LocoState.OBSERVING, LocoState.STANDING_UP]
# Settled on its bum: no transition in flight, so it can be interrupted freely.
const SETTLED_STATES := [LocoState.SITTING, LocoState.LICKING, LocoState.OBSERVING]
# One-shot flavour animations played out of the sitting idle.
const IDLE_ACTION_STATES := [LocoState.LICKING, LocoState.OBSERVING]

## Seconds of standing perfectly still before the cat sits down of its own
## accord. Set to 0 (or less) to disable the escalation entirely.
@export var auto_sit_delay: float = 10.0

@export_group("Idle actions")
## Range to wait, sitting still, before playing a grooming action. Re-rolled
## after every action so the cat doesn't feel metronomic. Set the max to 0
## (or less) to disable idle actions.
@export var idle_action_delay_min: float = 4.0
@export var idle_action_delay_max: float = 9.0
## Roughly how long an idle action should run. The clip repeats until this
## much time has passed, then finishes its current cycle before sitting
## again — so the cat is never cut off mid-lick.
@export var idle_action_duration: float = 2.5

var loco_state: LocoState = LocoState.STANDING
var facing: String = "down"

# How long we've been in the current state uninterrupted. Any state change
# resets it, so walking a single step — or standing back up — restarts
# whichever countdown applies.
var _state_time: float = 0.0
var _next_action_delay: float = 0.0


func _ready() -> void:
	animation_finished.connect(_on_animation_finished)
	_roll_next_action_delay()
	_play_for_state()


func _process(delta: float) -> void:
	_state_time += delta

	match loco_state:
		LocoState.STANDING:
			if auto_sit_delay > 0.0 and _state_time >= auto_sit_delay:
				sit()
		LocoState.SITTING:
			if idle_action_delay_max > 0.0 and _state_time >= _next_action_delay:
				_set_state(IDLE_ACTION_STATES[randi() % IDLE_ACTION_STATES.size()])


## Call this every physics frame from whatever is controlling this cat.
## `running` should only be true while there's also movement input.
## Ignored while sitting or mid-transition — those postures own the sprite
## until sit()/stand_up() releases them.
func report_movement(input_vector: Vector2, running: bool = false) -> void:
	if is_seated():
		return

	if input_vector != Vector2.ZERO:
		_update_facing(input_vector)
		_set_state(LocoState.RUNNING if running else LocoState.WALKING)
	else:
		_set_state(LocoState.STANDING)


## True from the first frame of sitting down until standing up has finished,
## i.e. whenever the cat isn't free to move.
func is_seated() -> bool:
	return loco_state in SEATED_STATES


## True once the cat is settled on its bum, whether it's idling, licking or
## observing. False while either transition is still playing.
func is_sitting() -> bool:
	return loco_state in SETTLED_STATES


## True while a sit-down/stand-up transition is still playing.
func is_transitioning() -> bool:
	return loco_state == LocoState.SITTING_DOWN or loco_state == LocoState.STANDING_UP


## Start sitting down. No-op unless the cat is currently on its feet.
func sit() -> void:
	if is_seated():
		return
	_set_state(LocoState.SITTING_DOWN)


## Start standing back up. Interrupts a grooming action if one is playing,
## but leaves a transition already in flight to finish.
func stand_up() -> void:
	if not is_sitting():
		return
	_set_state(LocoState.STANDING_UP)


## Sit if standing, stand if sitting. Ignored mid-transition.
func toggle_sit() -> void:
	if is_sitting():
		stand_up()
	elif not is_transitioning():
		sit()


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
	_state_time = 0.0
	if new_state == LocoState.SITTING:
		_roll_next_action_delay()
	_play_for_state()


func _roll_next_action_delay() -> void:
	_next_action_delay = randf_range(idle_action_delay_min, idle_action_delay_max)


func _play_for_state() -> void:
	match loco_state:
		LocoState.WALKING:
			play("walk_%s" % facing)
		LocoState.RUNNING:
			play("run_%s" % facing)
		LocoState.STANDING:
			play("stand_%s" % facing)
		LocoState.SITTING_DOWN:
			play("sit_transition_%s" % facing)
		LocoState.SITTING:
			play("sit_%s" % facing)
		LocoState.LICKING:
			_restart("lick_%s" % facing)
		LocoState.OBSERVING:
			_restart("observe_%s" % facing)
		LocoState.STANDING_UP:
			# Same clip as sitting down, run in reverse.
			play_backwards("sit_transition_%s" % facing)


## play() on a non-looping clip that has already run to its end won't rewind
## on its own, which matters when we repeat an idle action cycle.
func _restart(anim_name: String) -> void:
	set_frame_and_progress(0, 0.0)
	play(anim_name)


func _on_animation_finished() -> void:
	match loco_state:
		LocoState.SITTING_DOWN:
			_set_state(LocoState.SITTING)
		LocoState.STANDING_UP:
			_set_state(LocoState.STANDING)
		LocoState.LICKING, LocoState.OBSERVING:
			# Always finish a whole cycle; only stop once we've run long enough.
			if _state_time < idle_action_duration:
				_play_for_state()
			else:
				_set_state(LocoState.SITTING)
