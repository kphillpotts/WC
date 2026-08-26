extends AnimatedSprite2D
## Translates a chick's movement "intent" into the right animation + facing
## direction. Built the same way as cat_animator.gd — the owning body calls
## report_movement() every physics frame and this decides what actually
## plays — but a chick has far less to say for itself: it potters, pecks,
## bolts, or ends up as dinner.
##
# Two things aren't drawn and get faked, the same way the cat's jump and
# crawl are:
#
# There is no walk cycle in the sheet, so STROLLING is the run clip played
# back slowed down. At 16px and a potter's pace that reads fine — the legs
# just need to not be going like the clappers.
#
# There is no carcass either, so DEAD flips a standing frame upside down
# and drops it to the floor. Legs-up is about the most readable "this bird
# is finished" you can manage in a 16px sprite, and it costs no art.
#
# The idle clip (head bobbing, looking about) is what a chick does when it
# has stopped of its own accord. STANDING is the single static frame, kept
# separate because the alert freeze wants a hard stop, not a bob — the
# stillness is the tell that the cat has been spotted.

enum State { STANDING, IDLE, STROLLING, PECKING, RUNNING, DEAD }

## Playback rate for the run clip while strolling, since there's no walk
## cycle to play instead.
@export var stroll_speed_scale: float = 0.45
## Pixels the carcass drops once flipped, so it lies on the ground rather
## than standing on its head where the live chick's feet were.
@export var dead_drop_pixels: float = 5.0

var state: State = State.IDLE
var facing: String = "down"

# The authored art alignment, which the death drop sits on top of.
var _base_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_base_offset = offset
	_play_for_state()


## Call this every physics frame from whatever is driving this chick.
## `running` picks the panicked sprint over the potter. Ignored once dead —
## nothing hands the sprite back after that.
func report_movement(input_vector: Vector2, running: bool = false) -> void:
	if state == State.DEAD:
		return

	if input_vector != Vector2.ZERO:
		_update_facing(input_vector)
		_set_state(State.RUNNING if running else State.STROLLING)
	else:
		_set_state(State.IDLE)


## Turn on the spot without moving. Used for the alert freeze, so the chick
## squares up to whatever just spooked it.
func face(direction: Vector2) -> void:
	if state == State.DEAD or direction == Vector2.ZERO:
		return
	_update_facing(direction)


## Hard stop on a single frame. Reads as "it has seen something".
func freeze() -> void:
	if state == State.DEAD:
		return
	_set_state(State.STANDING)


## Head down, pecking at the ground.
func peck() -> void:
	if state == State.DEAD:
		return
	_set_state(State.PECKING)


## Stopped, but relaxed about it — bobbing and looking around.
func idle() -> void:
	if state == State.DEAD:
		return
	_set_state(State.IDLE)


## Terminal. Nothing else moves this sprite again.
func die() -> void:
	_set_state(State.DEAD)


func is_dead() -> bool:
	return state == State.DEAD


func _update_facing(input_vector: Vector2) -> void:
	var new_facing := facing
	if abs(input_vector.x) > abs(input_vector.y):
		new_facing = "right" if input_vector.x > 0 else "left"
	else:
		new_facing = "down" if input_vector.y > 0 else "up"

	if new_facing != facing:
		facing = new_facing
		_play_for_state()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	_play_for_state()


func _play_for_state() -> void:
	# Only the stroll borrows a clip at the wrong rate, so every other state
	# hands the playback speed back on the way in.
	speed_scale = stroll_speed_scale if state == State.STROLLING else 1.0

	match state:
		State.STANDING:
			play("stand_%s" % facing)
		State.IDLE:
			play("idle_%s" % facing)
		State.STROLLING, State.RUNNING:
			play("run_%s" % facing)
		State.PECKING:
			play("peck_%s" % facing)
		State.DEAD:
			# Upside down on the spot it fell, legs in the air.
			animation = "stand_%s" % facing
			stop()
			flip_v = true
			offset = _base_offset + Vector2(0, dead_drop_pixels)
