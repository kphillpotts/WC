extends CharacterBody2D

## Bit of the "Obstacles" physics layer, per project.godot's layer_names.
const OBSTACLE_LAYER := 2

@export var walk_speed: float = 100.0
@export var run_speed: float = 180.0
## Speed held for the whole leap. Distance covered is this multiplied by the
## animator's jump_duration, which owns the timing and the arc height.
@export var jump_speed: float = 210.0
## When true, pushing a direction while sitting stands the cat back up
## instead of the input simply being ignored. Turn off if sitting should
## only ever be broken by the "sit" key.
@export var stand_up_on_move: bool = true

@onready var animator: AnimatedSprite2D = $AnimatedSprite2D

# Locked in at launch: a leap is committed, so steering is ignored until the
# cat lands.
var _leap_velocity: Vector2 = Vector2.ZERO
# True while the cat is sailing over the Obstacles layer with it masked out.
var _obstacles_ignored: bool = false

## Facing directions, as the animator names them, to a unit vector.
const FACING_VECTORS := {
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"up": Vector2.UP,
	"right": Vector2.RIGHT,
}


func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if animator.is_jumping():
		_process_leap()
		return

	if _obstacles_ignored:
		# Landed inside something solid. Stay permeable until the cat has
		# walked clear rather than trapping it in the tile it came down on.
		_try_restore_obstacle_collision()

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


## Commit to a leap. Direction comes from the current input if there is any,
## otherwise from whichever way the cat is already facing.
func _start_leap(input_vector: Vector2) -> bool:
	if not animator.jump():
		return false

	var direction := input_vector.normalized()
	if direction == Vector2.ZERO:
		direction = FACING_VECTORS.get(animator.facing, Vector2.DOWN)
	_leap_velocity = direction * jump_speed

	# Airborne, so obstacles pass underneath.
	set_collision_mask_value(OBSTACLE_LAYER, false)
	_obstacles_ignored = true

	_process_leap()
	return true


func _process_leap() -> void:
	velocity = _leap_velocity
	move_and_slide()
	if not animator.is_jumping():
		_try_restore_obstacle_collision()


## Make obstacles solid again, but only once the cat isn't standing in one.
func _try_restore_obstacle_collision() -> void:
	set_collision_mask_value(OBSTACLE_LAYER, true)
	if test_move(global_transform, Vector2.ZERO, null, 0.08, true):
		set_collision_mask_value(OBSTACLE_LAYER, false)
		return
	_obstacles_ignored = false
