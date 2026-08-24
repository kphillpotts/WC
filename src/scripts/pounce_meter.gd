extends Control
## Golf-style power bar for the pounce, drawn at the bottom of the screen
## while the cat is winding up and hidden the rest of the time.
##
## The zone showing where targeted prey sits along the bar isn't here yet —
## it arrives with prey. Until then the bar is just a distance chooser, and
## _draw() is deliberately kept simple enough to slot that band in later.

## The cat whose charge this reflects.
@export var player_path: NodePath

@export_group("Layout")
## Kept in whole pixels: the viewport is 640x360 with integer scaling, so
## fractional sizes would shimmer.
@export var bar_size: Vector2i = Vector2i(96, 7)
## Gap between the bottom of the bar and the bottom of the screen.
@export var bottom_margin: int = 20

@export_group("Colours")
@export var border_color: Color = Color(0.87, 0.84, 0.76)
@export var background_color: Color = Color(0.10, 0.09, 0.12, 0.85)
@export var fill_low_color: Color = Color(0.55, 0.72, 0.45)
@export var fill_high_color: Color = Color(0.90, 0.44, 0.30)
@export var marker_color: Color = Color(1.0, 0.98, 0.92)

var _player: Node = null


func _ready() -> void:
	_player = get_node_or_null(player_path)
	if _player == null:
		push_warning("PounceMeter has no player assigned; the bar will never show.")
	visible = false
	_reposition()
	get_viewport().size_changed.connect(_reposition)


func _process(_delta: float) -> void:
	var charging: bool = _player != null and _player.animator.is_charging_pounce()
	if charging != visible:
		visible = charging
	if charging:
		queue_redraw()


func _reposition() -> void:
	var view := get_viewport_rect().size
	size = Vector2(bar_size)
	# Whole pixels, and centred on the same parity as the viewport.
	position = Vector2(
		floorf((view.x - float(bar_size.x)) * 0.5),
		floorf(view.y - float(bar_size.y) - float(bottom_margin)))


func _draw() -> void:
	if _player == null:
		return

	var w := float(bar_size.x)
	var h := float(bar_size.y)
	draw_rect(Rect2(0, 0, w, h), background_color)

	# Interior is inset by the 1px border on every side.
	var inner_w := w - 2.0
	var power: float = clampf(_player.pounce_power, 0.0, 1.0)
	var filled := floorf(inner_w * power)

	if filled > 0.0:
		draw_rect(Rect2(1, 1, filled, h - 2.0),
				fill_low_color.lerp(fill_high_color, power))

	# The marker head, so the exact release point is readable at a glance.
	draw_rect(Rect2(1.0 + clampf(filled - 1.0, 0.0, inner_w - 1.0), 1, 1, h - 2.0),
			marker_color)

	draw_rect(Rect2(0, 0, w, h), border_color, false, 1.0)
