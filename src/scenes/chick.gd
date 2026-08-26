extends CharacterBody2D
## A chick: potters about, notices the cat, and bolts. Free-roaming — it has
## no home point and settles wherever a scare happens to leave it.
##
# Spotting the cat is a plain distance check, scaled by how conspicuous the
# cat is currently being (Player.get_stealth_factor). That indirection is
# the whole point of the stance system as far as prey are concerned: a
# crawling cat gets close enough to pounce before it's noticed, a strolling
# one doesn't quite, and a running one is spotted from most of a screen
# away. The chick never inspects the cat's stances itself, so crouching and
# pouncing stay the cat's business.
#
# Fleeing is deliberately dumber than pathfinding: run away from the cat,
# let move_and_slide skate along whatever it hits, and swerve if that
# leaves it wedged. A cornered chick genuinely being cornered is a better
# moment than a chick that navigates its way out.

enum State { STROLL, PAUSE, PECK, ALERT, FLEE, SETTLE, DEAD }

@export_group("Wander")
## Potter pace. Slow enough to be worth stalking rather than chasing.
@export var stroll_speed: float = 22.0
@export var stroll_time_min: float = 0.6
@export var stroll_time_max: float = 1.8
@export var rest_time_min: float = 0.8
@export var rest_time_max: float = 2.5
## Odds that a rest is spent pecking at the ground rather than looking about.
@export_range(0.0, 1.0) var peck_chance: float = 0.45

@export_group("Fleeing")
## Faster than the cat's walk, slower than its run — so a bolting chick
## escapes a stroll but can be run down, at the cost of making a racket.
@export var flee_speed: float = 130.0
## Range the cat is noticed at while behaving normally. Scaled by the cat's
## stealth factor, so this is the walking-up case.
@export var detect_radius: float = 56.0
## How far the cat has to get before the chick stops running. Comfortably
## wider than detect_radius, so it can't flicker between the two.
@export var calm_distance: float = 120.0
## Beat spent frozen on the spot before running. This is the player's "you
## have been seen" tell, and the last window to pounce anyway.
@export var alert_time: float = 0.25
## Shortest dash the chick will commit to, however quickly the cat backs off.
@export var min_flee_time: float = 1.2
## Recovery spent standing still before going back to pottering.
@export var settle_time: float = 1.5

@export_group("Obstacles")
## How long the chick has to fail to make progress before it accepts it's
## walked into something and picks a new way to go.
@export var wedge_time: float = 0.2

@onready var animator: AnimatedSprite2D = $AnimatedSprite2D

var state: State = State.PAUSE

# Time in the current state, and how long it should last. Only the timed
# wander states use the duration; ALERT/FLEE/SETTLE have their own limits.
var _state_time: float = 0.0
var _state_duration: float = 0.0
# Unit vector the chick is currently trying to travel along.
var _heading: Vector2 = Vector2.ZERO
# Running total of time spent not getting anywhere, for the wedge check.
var _wedged_time: float = 0.0
# Extra rotation on the flee heading, applied when running straight away
# from the cat means running straight into a wall. Decays back to zero once
# the chick is clear, so it straightens up rather than circling.
var _flee_swerve: float = 0.0
# Which way it swerves out of the next corner; alternates so a chick can't
# get stuck rocking against the same wall.
var _swerve_direction: float = 1.0

var _player: Node2D = null


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null or not _player.has_method("get_stealth_factor"):
		push_warning("Chick found no cat in the \"player\" group; it will never spook.")
		_player = null
	# Stagger the flock, so a row of chicks doesn't peck in lockstep.
	_enter_rest()
	_state_time = randf() * _state_duration


func _physics_process(delta: float) -> void:
	_state_time += delta

	match state:
		State.STROLL:
			_process_stroll(delta)
		State.PAUSE, State.PECK:
			_process_rest()
		State.ALERT:
			_process_alert()
		State.FLEE:
			_process_flee(delta)
		State.SETTLE:
			_process_settle()


## Killed by a cat coming down on top of it. Terminal: it stops being prey
## and becomes an item lying on the ground, which is all the inventory it
## needs until there's an inventory.
func catch() -> void:
	if state == State.DEAD:
		return
	_set_state(State.DEAD)
	remove_from_group("prey")
	add_to_group("item")
	velocity = Vector2.ZERO
	animator.die()
	set_physics_process(false)


func is_dead() -> bool:
	return state == State.DEAD


# --- Wandering ---------------------------------------------------------------

func _process_stroll(delta: float) -> void:
	if _spotted_cat():
		_enter_alert()
		return

	velocity = _heading * stroll_speed
	move_and_slide()
	animator.report_movement(_heading, false)

	if _is_wedged(delta, stroll_speed):
		# Walked into something. Try somewhere else rather than grinding.
		_pick_wander_heading()
		return

	if _state_time >= _state_duration:
		_enter_rest()


func _process_rest() -> void:
	if _spotted_cat():
		_enter_alert()
		return

	velocity = Vector2.ZERO
	move_and_slide()

	if _state_time >= _state_duration:
		_enter_stroll()


## Stop for a bit, either head down in the dirt or looking around.
func _enter_rest() -> void:
	var pecking := randf() < peck_chance
	_set_state(State.PECK if pecking else State.PAUSE)
	_state_duration = randf_range(rest_time_min, rest_time_max)
	velocity = Vector2.ZERO
	if pecking:
		animator.peck()
	else:
		animator.idle()


## Set off in a fresh random direction for a bit.
func _enter_stroll() -> void:
	_set_state(State.STROLL)
	_state_duration = randf_range(stroll_time_min, stroll_time_max)
	_pick_wander_heading()


func _pick_wander_heading() -> void:
	_heading = Vector2.RIGHT.rotated(randf() * TAU)


# --- Spooked -----------------------------------------------------------------

## The beat between being seen and running: frozen, squared up to the cat.
func _enter_alert() -> void:
	_set_state(State.ALERT)
	velocity = Vector2.ZERO
	if _player != null:
		animator.face(_player.global_position - global_position)
	animator.freeze()


func _process_alert() -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	if _state_time >= alert_time:
		_set_state(State.FLEE)
		_flee_swerve = 0.0
		_heading = _away_from_cat()


func _process_flee(delta: float) -> void:
	_advance_flee_heading(delta)

	velocity = _heading * flee_speed
	move_and_slide()
	animator.report_movement(_heading, true)

	if _is_wedged(delta, flee_speed):
		# Pressed into something with a cat behind it. Break along the wall
		# instead of shoving at it, and pick the other way next time.
		_flee_swerve = PI * 0.5 * _swerve_direction
		_swerve_direction = -_swerve_direction

	if _state_time >= min_flee_time and not _cat_within(calm_distance):
		_set_state(State.SETTLE)
		velocity = Vector2.ZERO
		animator.idle()


## Aim away from the cat, plus whatever swerve the last corner called for.
## The swerve bleeds off so the chick straightens out once it's clear.
func _advance_flee_heading(delta: float) -> void:
	_flee_swerve = move_toward(_flee_swerve, 0.0, delta * 2.0)
	_heading = _away_from_cat().rotated(_flee_swerve)


func _away_from_cat() -> Vector2:
	if _player == null:
		return _heading if _heading != Vector2.ZERO else Vector2.DOWN
	var away := global_position - _player.global_position
	if away == Vector2.ZERO:
		# Standing exactly on it. Any direction beats dividing by zero.
		return Vector2.RIGHT.rotated(randf() * TAU)
	return away.normalized()


func _process_settle() -> void:
	velocity = Vector2.ZERO
	move_and_slide()

	if _spotted_cat():
		_enter_alert()
		return

	if _state_time >= settle_time:
		_enter_rest()


# --- Senses ------------------------------------------------------------------

## True when the cat is near enough — for how loudly it is currently moving
## — for the chick to notice it.
func _spotted_cat() -> bool:
	if _player == null:
		return false
	return _cat_within(detect_radius * _player.get_stealth_factor())


func _cat_within(distance: float) -> bool:
	if _player == null:
		return false
	return global_position.distance_squared_to(_player.global_position) <= distance * distance


# --- Helpers -----------------------------------------------------------------

## True once the body has spent long enough failing to make progress that we
## can assume it's jammed against something rather than just clipping a
## corner. Resets itself when it fires, so callers get one nudge per jam.
func _is_wedged(delta: float, intended_speed: float) -> bool:
	# Compared against the speed we asked for, not `velocity`, which
	# move_and_slide has already rewritten to the post-collision result.
	if intended_speed > 1.0 and get_real_velocity().length() < intended_speed * 0.4:
		_wedged_time += delta
	else:
		_wedged_time = 0.0

	if _wedged_time >= wedge_time:
		_wedged_time = 0.0
		return true
	return false


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_wedged_time = 0.0
