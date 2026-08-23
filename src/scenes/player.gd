extends CharacterBody2D

@export var walk_speed: float = 100.0
@export var run_speed: float = 180.0
## When true, pushing a direction while sitting stands the cat back up
## instead of the input simply being ignored. Turn off if sitting should
## only ever be broken by the "sit" key.
@export var stand_up_on_move: bool = true

@onready var animator: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if Input.is_action_just_pressed("sit"):
		animator.toggle_sit()

	# Sitting (and the transitions either side of it) locks movement; the
	# animator stays in charge of the sprite until it hands control back.
	if animator.is_seated():
		if stand_up_on_move and input_vector != Vector2.ZERO:
			animator.stand_up()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var is_running := Input.is_action_pressed("run") and input_vector != Vector2.ZERO

	velocity = input_vector * (run_speed if is_running else walk_speed)

	move_and_slide()

	animator.report_movement(input_vector, is_running)
