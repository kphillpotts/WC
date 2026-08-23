extends CharacterBody2D

@export var walk_speed: float = 100.0
@export var run_speed: float = 180.0

@onready var animator: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var is_running := Input.is_action_pressed("run") and input_vector != Vector2.ZERO

	velocity = input_vector * (run_speed if is_running else walk_speed)

	move_and_slide()

	animator.report_movement(input_vector, is_running)