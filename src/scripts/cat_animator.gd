extends AnimatedSprite2D
## Translates movement "intent" into the right animation + facing direction.
## Attach this directly to an AnimatedSprite2D. The owning body (player
## script, or later an NPC AI script) calls report_movement() every
## physics frame; this script figures out what to actually play.

enum LocoState {
	WALKING, RUNNING, STANDING, JUMPING,
	CROUCH_DOWN, CROUCHING, CRAWLING, POUNCE_CHARGE, CROUCH_UP,
	SITTING_DOWN, SITTING, LICKING, OBSERVING, STANDING_UP,
}
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
#
# JUMPING has no sprite sheet of its own. It borrows two poses from the run
# cycle — the gathered frame for the crouch and launch, the fully extended
# frame for the airborne stretch — and sells the leap with a parabola on
# the sprite's offset instead. The frame is picked from elapsed progress
# rather than played back, so the clip can never drift out of sync with
# jump_duration however that gets tuned.
#
# The crouch stance is the hunting half of the game: slow, quiet, and the
# only stance a pounce can be launched from. It borrows the middle frame of
# the standing -> laying transition, which is already a lowered, legs-bent
# stalk pose, so it needs no new art either. CROUCH_DOWN / CROUCH_UP are
# that transition forwards and backwards, the same trick sitting uses.
# There is no crawl cycle in any sheet, so CRAWLING holds the stalk pose and
# bobs the sprite a pixel instead — at 32px that reads as a slink.

# Seated in any pose, including the transitions either side. The cat is not
# free to move in any of these.
const SEATED_STATES := [LocoState.SITTING_DOWN, LocoState.SITTING, LocoState.LICKING,
		LocoState.OBSERVING, LocoState.STANDING_UP]
# Settled on its bum: no transition in flight, so it can be interrupted freely.
const SETTLED_STATES := [LocoState.SITTING, LocoState.LICKING, LocoState.OBSERVING]
# One-shot flavour animations played out of the sitting idle.
const IDLE_ACTION_STATES := [LocoState.LICKING, LocoState.OBSERVING]
# Settled in the stalk: free to crawl, turn, or wind up a pounce.
const CROUCHED_STATES := [LocoState.CROUCHING, LocoState.CRAWLING, LocoState.POUNCE_CHARGE]
# Dropping into or rising out of the stalk; movement is locked meanwhile.
const CROUCH_TRANSITION_STATES := [LocoState.CROUCH_DOWN, LocoState.CROUCH_UP]

@export_group("Crouch")
## Pixels the sprite bobs while crawling, and how many bobs per second. There
## is no crawl cycle in the art, so this is what sells the slink.
@export var crawl_bob_pixels: float = 1.0
@export var crawl_bob_rate: float = 4.0
## Sideways wiggle of the wind-up before a pounce, in pixels and per second.
@export var charge_wiggle_pixels: float = 1.0
@export var charge_wiggle_rate: float = 12.0

@export_group("Jump")
## How long a leap takes from launch to landing.
@export var jump_duration: float = 0.45
## Peak height of the arc, in pixels. Applied to the sprite's offset, not its
## position, so lifting the cat can't disturb Y-sorting and make it draw
## behind the very thing it's leaping over.
@export var jump_height: float = 14.0
## Fractions of the leap spent crouched at launch and again on landing; the
## stretched airborne pose fills everything between them.
@export_range(0.0, 0.5) var jump_crouch_fraction: float = 0.15

@export_group("")
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
# The authored art alignment, which the arc, bob and wiggle sit on top of.
var _base_offset: Vector2 = Vector2.ZERO
# Timing and arc for the leap currently in the air. A pounce overrides these
# per jump so its distance, hang time and height stay in proportion.
var _active_jump_duration: float = 0.0
var _active_jump_height: float = 0.0
# Whether the current leap should come down into the stalk or onto its feet.
var _jump_returns_to_crouch: bool = false
# Set when the sit key is pressed from the stalk: the cat has to stand up
# before it can sit, so the sit waits for the crouch to finish unwinding.
var _sit_after_crouch_up: bool = false


func _ready() -> void:
	_base_offset = offset
	animation_finished.connect(_on_animation_finished)
	_roll_next_action_delay()
	_play_for_state()


func _process(delta: float) -> void:
	_state_time += delta

	match loco_state:
		LocoState.JUMPING:
			_advance_jump()
		LocoState.CRAWLING:
			offset.y = _base_offset.y - _square_wave(crawl_bob_rate) * crawl_bob_pixels
		LocoState.POUNCE_CHARGE:
			offset.x = _base_offset.x + (_square_wave(charge_wiggle_rate) * 2.0 - 1.0) \
					* charge_wiggle_pixels
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
	if is_seated() or is_jumping() or is_crouch_transitioning() \
			or loco_state == LocoState.POUNCE_CHARGE:
		return

	if is_crouched():
		# Crawling is 8-way like walking, just slower and lower.
		if input_vector != Vector2.ZERO:
			_update_facing(input_vector)
			_set_state(LocoState.CRAWLING)
		else:
			_set_state(LocoState.CROUCHING)
		return

	if input_vector != Vector2.ZERO:
		_update_facing(input_vector)
		_set_state(LocoState.RUNNING if running else LocoState.WALKING)
	else:
		_set_state(LocoState.STANDING)


## Turn on the spot without moving. Used while winding up a pounce, so the
## cat can line up its target the way a real one shuffles into position.
func aim(input_vector: Vector2) -> void:
	if input_vector != Vector2.ZERO:
		_update_facing(input_vector)


## True from the first frame of sitting down until standing up has finished,
## i.e. whenever the cat isn't free to move.
func is_seated() -> bool:
	return loco_state in SEATED_STATES


## True once the cat is settled on its bum, whether it's idling, licking or
## observing. False while either transition is still playing.
func is_sitting() -> bool:
	return loco_state in SETTLED_STATES


## True from launch until the cat has landed.
func is_jumping() -> bool:
	return loco_state == LocoState.JUMPING


## True once settled in the stalk — crouched still, crawling, or winding up.
func is_crouched() -> bool:
	return loco_state in CROUCHED_STATES


## True while dropping into or rising out of the stalk.
func is_crouch_transitioning() -> bool:
	return loco_state in CROUCH_TRANSITION_STATES


## True while a pounce is being wound up.
func is_charging_pounce() -> bool:
	return loco_state == LocoState.POUNCE_CHARGE


## Drop into the stalk. No-op if seated, airborne, or already crouched.
func crouch() -> void:
	if is_seated() or is_jumping() or is_crouched() or is_crouch_transitioning():
		return
	_sit_after_crouch_up = false
	_set_state(LocoState.CROUCH_DOWN)


## Rise back onto its feet out of the stalk.
func uncrouch() -> void:
	if not is_crouched():
		return
	_set_state(LocoState.CROUCH_UP)


## Ctrl toggles the stance either way.
func toggle_crouch() -> void:
	if is_crouched():
		uncrouch()
	else:
		crouch()


## Begin winding up a pounce. Only possible from the stalk — this is what
## makes crouching the hunting stance rather than just a slow walk.
func begin_pounce_charge() -> bool:
	if not is_crouched() or loco_state == LocoState.POUNCE_CHARGE:
		return false
	_set_state(LocoState.POUNCE_CHARGE)
	return true


## Abandon a wind-up and settle back into the stalk, no pounce fired.
func cancel_pounce_charge() -> void:
	if loco_state == LocoState.POUNCE_CHARGE:
		_set_state(LocoState.CROUCHING)


## Launch into a leap in the direction the cat is already facing. `duration`
## and `height` override the exported defaults for this one jump, which is
## how a pounce keeps its hang time and arc in proportion to its distance.
## Returns false if it isn't in a position to jump — seated, or already
## airborne — so the caller knows not to commit any leap velocity.
func jump(duration: float = -1.0, height: float = -1.0) -> bool:
	if is_seated() or is_jumping() or is_crouch_transitioning():
		return false
	_active_jump_duration = duration if duration > 0.0 else jump_duration
	_active_jump_height = height if height >= 0.0 else jump_height
	# A pounce comes down still hunting; a plain leap lands on its feet.
	_jump_returns_to_crouch = is_crouched()
	_set_state(LocoState.JUMPING)
	return true


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
	elif is_crouched():
		# Can't sit straight from a stalk — rise first, then sit.
		_sit_after_crouch_up = true
		uncrouch()
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
	# The arc, the crawl bob and the charge wiggle all borrow the sprite
	# offset, so hand it back whole on every state change.
	offset = _base_offset
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
		LocoState.CROUCH_DOWN:
			play("crouch_transition_%s" % facing)
		LocoState.CROUCHING, LocoState.CRAWLING, LocoState.POUNCE_CHARGE:
			play("crouch_%s" % facing)
		LocoState.CROUCH_UP:
			play_backwards("crouch_transition_%s" % facing)
		LocoState.JUMPING:
			# Frames are driven by _advance_jump(), not played back.
			animation = "jump_%s" % facing
			stop()
			_advance_jump()
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


## Pose and lift the cat according to how far through the leap it is.
func _advance_jump() -> void:
	var p := clampf(_state_time / maxf(_active_jump_duration, 0.001), 0.0, 1.0)
	# Parabola peaking at the leap's height halfway through.
	offset.y = _base_offset.y - _active_jump_height * 4.0 * p * (1.0 - p)
	if p < jump_crouch_fraction:
		frame = 0
	elif p < 1.0 - jump_crouch_fraction:
		frame = 1
	else:
		frame = 2
	if p >= 1.0:
		_set_state(LocoState.CROUCHING if _jump_returns_to_crouch else LocoState.STANDING)


## 1.0 for the first half of each cycle, 0.0 for the second.
func _square_wave(rate: float) -> float:
	return 1.0 if fmod(_state_time * rate, 1.0) < 0.5 else 0.0


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
		LocoState.CROUCH_DOWN:
			_set_state(LocoState.CROUCHING)
		LocoState.CROUCH_UP:
			if _sit_after_crouch_up:
				_sit_after_crouch_up = false
				_set_state(LocoState.SITTING_DOWN)
			else:
				_set_state(LocoState.STANDING)
		LocoState.LICKING, LocoState.OBSERVING:
			# Always finish a whole cycle; only stop once we've run long enough.
			if _state_time < idle_action_duration:
				_play_for_state()
			else:
				_set_state(LocoState.SITTING)
