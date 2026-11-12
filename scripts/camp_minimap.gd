extends Control

signal destination_requested(point: Vector2)
const MAP := preload("res://assets/art/world/recruit_camp.png")
var world_size := Vector2(2400, 1600)
var player_position := Vector2.ZERO
var objective := Vector2.ZERO
var markers: Array[Vector2] = []
var labels: Dictionary = {}

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		destination_requested.emit(event.position / size * world_size)
		accept_event()

func _draw() -> void:
	draw_texture_rect(MAP, Rect2(Vector2.ZERO, size), false, Color(0.68, 0.77, 0.69))
	for point in markers:
		draw_circle(point / world_size * size, 2.4, Color("#fff1ce"))
	var target := objective / world_size * size
	draw_arc(target, 6, 0, TAU, 24, Color("#eac17e"), 1.5, true)
	var dot := player_position / world_size * size
	draw_circle(dot, 5, Color("#112b25"))
	draw_circle(dot, 3, Color("#baf5db"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#738b77"), false, 1)
	if size.x > 400:
		var font := get_theme_default_font()
		for label in labels:
			var anchor: Vector2 = labels[label] / world_size * size
			var extent := font.get_string_size(str(label), HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			var position := anchor + Vector2(-extent.x / 2, -13)
			draw_rect(Rect2(position + Vector2(-4, -14), extent + Vector2(8, 4)), Color(0.03, 0.07, 0.05, 0.88))
			draw_string(font, position, str(label), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#fff1ce"))
