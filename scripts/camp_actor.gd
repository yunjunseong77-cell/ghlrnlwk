extends CharacterBody2D

const SHEET := preload("res://assets/art/world/recruit_walk.png")
const Appearance := preload("res://scripts/soldier_appearance.gd")
var equipment: Dictionary = {}
var facing := 0
var moving := false
var selected := false
var animation_time := 0.0
var tint := Color.WHITE

func _ready() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	add_child(shape)
	collision_layer = 2
	collision_mask = 1

func step(direction: Vector2, speed: float, delta: float) -> void:
	velocity = direction.limit_length() * speed
	move_and_slide()
	moving = get_real_velocity().length() > 8.0
	if direction.length_squared() > 0.01:
		if absf(direction.x) > absf(direction.y):
			facing = 2 if direction.x > 0 else 1
		else:
			facing = 0 if direction.y > 0 else 3
	animation_time += delta * (1.35 if speed > 230 else 1.0)
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2(1, -1), 17, Color(0.04, 0.07, 0.045, 0.30))
	if selected:
		draw_arc(Vector2.ZERO, 24, 0, TAU, 48, Color("#a0e5d1"), 2.5, true)
	draw_set_transform(Vector2.ZERO)
	var row := 0
	if moving:
		row = 1 + int(animation_time * 7.0) % 2
	Appearance.draw_character(self, equipment, facing, row, tint)
