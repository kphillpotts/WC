extends Node2D
## Faint disc on the ground marking where a pounce released right now would
## land. The player moves this while charging; it needs no per-frame redraw
## because only its transform changes.
##
## Sits on its own z_index below the cat so it reads as being on the floor
## rather than painted over the sprite.

## Roughly the cat's footprint, so the disc reads as "the cat ends up here".
@export var radius: float = 7.0
## Subtle — a hint, not a targeting reticle — but readable over light ground.
@export var color: Color = Color(1.0, 1.0, 1.0, 0.25)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
