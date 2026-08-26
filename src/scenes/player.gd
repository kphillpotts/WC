extends CharacterBody2D

## Bit of the "Obstacles" physics layer, per project.godot's layer_names.
const OBSTACLE_LAYER := 2

## Facing directions, as the animator names them, to a unit vector.
const FACING_VECTORS := {
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"up": Vector2.UP,
	"right": Vector2.RIGHT,
}

@export var walk_speed: float = 100.0
@export var run_speed: float = 180.0
## Stalking pace. Slow enough that closing on prey is a real commitment.
@export var crawl_speed: float = 45.0
## Speed held for the whole leap. Distance covered is this multiplied by the
## animator's jump_duration, which owns the timing and the arc height.
@export var jump_speed: float = 210.0
## When true, pushing a direction while sitting stands the cat back up
## instead of the input simply being ignored. Turn off if sitting should
## only ever be broken by the "sit" key.
@export var stand_up_on_move: bool = true

@export_group("Pounce")
## Seconds for the power marker to sweep the bar once. It ping-pongs, so a
## full round trip is twice this.
@export var pounce_sweep_time: float = 1.0
## Distance range the bar maps onto, in pixels. Tiles are 32px, so the
## default spans one to four tiles.
@export var pounce_min_distance: float = 32.0
@export var pounce_max_distance: float = 128.0
## Hang time and arc of a full-power pounce. Shorter pounces scale down from
## these — duration by the square root of distance so a small hop is quick
## and flat rather than floating for the same time as a long one.
@export var pounce_max_duration: float = 0.5
@export var pounce_max_height: float = 16.0

@export_group("Hunting")
## How close the cat has to come down to a chick for the landing to count as
## catching it.
@export var catch_radius: float = 10.0
## Multipliers on prey detection range for each stance, read by prey through
## get_stealth_factor(). The gap between crawling and walking is what makes
## the crouch a hunting stance rather than just a slow one: crawling gets the
## cat inside pounce range unnoticed, strolling up does not.
@export var stealth_crouched: float = 0.35
@export var stealth_crawling: float = 0.5
@export var stealth_still: float = 0.7
@export var stealth_walking: float = 1.0
## Also covers being airborne — a cat mid-leap is about as subtle as it gets.
@export var stealth_running: float = 1.4

@onready var animator: AnimatedSprite2D = $AnimatedSprite2D
@onready var pounce_target: Node2D = $PounceTarget

## 0..1 position of the power marker. Read by the HUD meter while charging.
var pounce_power: float = 0.0

# Locked in at launch: a leap is committed, so steering is ignored until the
# cat lands.
var _leap_velocity: Vector2 = Vector2.ZERO
# True while the cat is sailing over the Obstacles layer with it masked out.
# Only ever set by the plain leap — a pounce stays grounded and solid.
var _obstacles_ignored: bool = false
# Direction the marker is currently sweeping.
var _power_direction: float = 1.0
# True on any frame spent in the air, so the frame after a leap ends can tell
# it was a landing and check what the cat came down on.
var _airborne_last_frame: bool = false


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if animator.is_jumping():
		_process_leap()
		return

	if _airborne_last_frame:
		# Just came down. Anything small under the paws is dinner.
		_airborne_last_frame = false
		_catch_prey_underfoot()

	if _obstacles_ignored:
		# Landed inside something solid. Stay permeable until the cat has
		# walked clear rather than trapping it in the tile it came down on.
		_try_restore_obstacle_collision()

	if animator.is_charging_pounce():
		_process_charge(delta, input_vector)
		return

	if animator.is_crouch_transitioning():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed("crouch"):
		animator.toggle_crouch()

	if animator.is_crouched():
		_process_crouched(input_vector)
		return

	if Input.is_action_just_pressed("sit"):
		animator.toggle_sit()

	# Sitting (and the transitions either side of it) locks movement; the
	# animator stays in charge of the sprite until it hands control back.
	if animator.is_seated():
		var wants_out := input_vector != Vector2.ZERO and stand_up_on_move
		if wants_out or Input.is_action_just_pressed("jump"):
			animator.stand_up()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed("jump") and _start_leap(input_vector):
		return

	var is_running := Input.is_action_pressed("run") and input_vector != Vector2.ZERO

	velocity = input_vector * (run_speed if is_running else walk_speed)

	move_and_slide()

	animator.report_movement(input_vector, is_running)


# --- Crouch stance -----------------------------------------------------------

func _process_crouched(input_vector: Vector2) -> void:
	# Jump means pounce from down here; that's the whole point of the stance.
	if Input.is_action_just_pressed("jump") and animator.begin_pounce_charge():
		pounce_power = 0.0
		_power_direction = 1.0
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Sitting from a stalk stands the cat up first; the animator queues it.
	if Input.is_action_just_pressed("sit"):
		animator.toggle_sit()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	velocity = input_vector * crawl_speed
	move_and_slide()
	animator.report_movement(input_vector, false)


func _process_charge(delta: float, input_vector: Vector2) -> void:
	if Input.is_action_just_pressed("cancel_pounce"):
		animator.cancel_pounce_charge()
		pounce_power = 0.0
		pounce_target.visible = false
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Ping-pong the marker between the ends of the bar.
	pounce_power += _power_direction * delta / maxf(pounce_sweep_time, 0.001)
	if pounce_power >= 1.0:
		pounce_power = 1.0
		_power_direction = -1.0
	elif pounce_power <= 0.0:
		pounce_power = 0.0
		_power_direction = 1.0

	# Rooted, but still free to line up the target.
	animator.aim(input_vector)
	velocity = Vector2.ZERO
	move_and_slide()

	# Show where the cat would come down if released right now.
	pounce_target.position = _pounce_direction(input_vector) * _pounce_distance()
	pounce_target.visible = true

	if Input.is_action_just_released("jump"):
		_release_pounce(input_vector)


## Distance the pounce would cover at the marker's current position.
func _pounce_distance() -> float:
	return lerpf(pounce_min_distance, pounce_max_distance, pounce_power)


## Where a pounce would head: current input if any, else the way it faces.
func _pounce_direction(input_vector: Vector2) -> Vector2:
	var direction := input_vector.normalized()
	if direction == Vector2.ZERO:
		direction = FACING_VECTORS.get(animator.facing, Vector2.DOWN)
	return direction


## Fire the pounce at whatever power the marker was sitting on.
func _release_pounce(input_vector: Vector2) -> void:
	pounce_target.visible = false

	var distance := _pounce_distance()
	var reach := distance / maxf(pounce_max_distance, 0.001)
	# Projectile-ish: hang time grows with the square root of distance, height
	# in proportion to it, so short pounces stay quick and flat.
	var duration := pounce_max_duration * sqrt(reach)
	var height := pounce_max_height * reach

	if not animator.jump(duration, height):
		return

	_leap_velocity = _pounce_direction(input_vector) * (distance / duration)
	# Deliberately no collision mask change: a pounce hugs the ground and is
	# stopped by obstacles, unlike the leap.
	_process_leap()


# --- Leaping -----------------------------------------------------------------

## Commit to a leap. Direction comes from the current input if there is any,
## otherwise from whichever way the cat is already facing.
func _start_leap(input_vector: Vector2) -> bool:
	if not animator.jump():
		return false

	_leap_velocity = _pounce_direction(input_vector) * jump_speed

	# Airborne, so obstacles pass underneath.
	set_collision_mask_value(OBSTACLE_LAYER, false)
	_obstacles_ignored = true

	_process_leap()
	return true


func _process_leap() -> void:
	_airborne_last_frame = true
	velocity = _leap_velocity
	move_and_slide()
	if not animator.is_jumping() and _obstacles_ignored:
		_try_restore_obstacle_collision()


# --- Hunting -----------------------------------------------------------------

## Kill anything in the "prey" group the cat has just landed on top of.
## Distance against the landing point rather than a hitbox: it needs no extra
## frame for an Area2D to register overlaps, which matters when the whole
## check happens on the single frame the leap ends.
func _catch_prey_underfoot() -> void:
	var reach := catch_radius * catch_radius
	for prey: Node2D in get_tree().get_nodes_in_group("prey"):
		if global_position.distance_squared_to(prey.global_position) <= reach:
			prey.catch()


## How conspicuous the cat is right now, as a multiplier on prey detection
## radius. Prey read this instead of inspecting the cat's stances, so what
## counts as sneaking stays in one place here rather than spread across every
## animal that might care.
func get_stealth_factor() -> float:
	if animator.is_jumping():
		return stealth_running

	var moving := velocity.length() > 1.0

	if animator.is_crouched() or animator.is_crouch_transitioning():
		return stealth_crawling if moving else stealth_crouched

	if not moving:
		return stealth_still

	return stealth_running if velocity.length() > walk_speed + 1.0 else stealth_walking


# --- Leaping (continued) -----------------------------------------------------

## Make obstacles solid again, but only once the cat isn't standing in one.
func _try_restore_obstacle_collision() -> void:
	set_collision_mask_value(OBSTACLE_LAYER, true)
	if test_move(global_transform, Vector2.ZERO, null, 0.08, true):
		set_collision_mask_value(OBSTACLE_LAYER, false)
		return
	_obstacles_ignored = false
