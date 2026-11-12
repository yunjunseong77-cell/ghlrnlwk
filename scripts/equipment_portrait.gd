extends Control

const Appearance := preload("res://scripts/soldier_appearance.gd")
var equipment: Dictionary = {}
var facing := 0
var moving := false
var animation_time := 0.0

func _process(delta: float) -> void:
	if moving:
		animation_time += delta
	queue_redraw()

func rotate_preview(direction: int = 1) -> void:
	facing = posmod(facing + direction, 4)
	queue_redraw()

func _draw() -> void:
	var feet := Vector2(size.x / 2, size.y - 14)
	var zoom := minf((size.y - 22) / 75.0, (size.x - 30) / 43.0)
	var center := feet - Vector2(0, zoom * 36)
	draw_arc(center, minf(size.x * 0.46, zoom * 28), 0, TAU, 90, Color(0.59, 0.71, 0.55, 0.12), 1, true)
	draw_line(Vector2(10, center.y), Vector2(size.x - 10, center.y), Color(0.59, 0.71, 0.55, 0.10))
	draw_set_transform(feet, 0, Vector2(zoom, zoom * 0.42))
	draw_circle(Vector2.ZERO, 17, Color(0, 0, 0, 0.35))
	draw_set_transform(feet, 0, Vector2.ONE * zoom)
	Appearance.draw_character(self, equipment, facing, 1 + int(animation_time * 7) % 2 if moving else 0)
	draw_set_transform(Vector2.ZERO)
