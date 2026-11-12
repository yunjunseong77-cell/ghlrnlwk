extends Control

# Title impacts use native canvas drawing so their edges remain sharp at any resolution.
var marks: Array[Dictionary] = []
var fragments: Array[Dictionary] = []
const SHOT := preload("res://assets/audio/title_shot.ogg")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func reset() -> void:
	marks.clear()
	fragments.clear()
	queue_redraw()
	set_process(false)


func strike(point: Vector2, shot: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 973 + shot * 131
	var edge := PackedVector2Array()
	for i in range(17):
		var angle := TAU * float(i) / 16.0
		var radius := rng.randf_range(7.5, 10.5)
		edge.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.72))
	edge.append(edge[0])
	var cracks: Array[PackedVector2Array] = []
	for i in range(5):
		var angle := rng.randf_range(0.0, TAU)
		var direction := Vector2(cos(angle), sin(angle))
		cracks.append(PackedVector2Array([
			point + direction * 9.0,
			point + direction.rotated(0.09) * rng.randf_range(15.0, 21.0),
			point + direction.rotated(-0.04) * rng.randf_range(23.0, 31.0)
		]))
	marks.append({"point": point, "age": 0.0, "edge": edge, "cracks": cracks})
	for i in range(16):
		var angle := rng.randf_range(-PI, 0.4)
		var speed := rng.randf_range(90.0, 330.0)
		fragments.append({
			"point": point,
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"age": 0.0,
			"life": rng.randf_range(0.14, 0.38),
			"warm": i < 4
		})
	var sound := AudioStreamPlayer.new()
	sound.stream = SHOT
	sound.pitch_scale = [0.98, 1.0, 1.02][shot % 3]
	sound.volume_db = -8.0
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var moving := false
	for mark in marks:
		mark.age = float(mark.age) + delta
		if float(mark.age) < 1.2:
			moving = true
	for fragment in fragments:
		fragment.age = float(fragment.age) + delta
		fragment.velocity += Vector2(0.0, 440.0) * delta
		fragment.point += fragment.velocity * delta
	fragments = fragments.filter(func(fragment: Dictionary) -> bool:
		return float(fragment.age) < float(fragment.life)
	)
	queue_redraw()
	if not moving and fragments.is_empty():
		set_process(false)


func _draw() -> void:
	for mark in marks:
		var point: Vector2 = mark.point
		var age: float = mark.age
		# Hairline cracks and an irregular gunmetal rim remain after the flash.
		for crack in mark.cracks:
			draw_polyline(crack, Color(0.02, 0.025, 0.02, 0.72), 1.8, true)
			draw_polyline(crack, Color(0.67, 0.65, 0.58, 0.30), 0.6, true)
		draw_circle(point + Vector2(1, 2), 12.5, Color(0.0, 0.0, 0.0, 0.30))
		var edge: PackedVector2Array = mark.edge
		var translated := PackedVector2Array()
		for vertex in edge:
			translated.append(point + vertex)
		draw_colored_polygon(translated, Color("#6d7065"))
		draw_polyline(translated, Color(0.77, 0.75, 0.65, 0.64), 1.1, true)
		draw_set_transform(point, 0.12, Vector2(1.0, 0.72))
		draw_circle(Vector2.ZERO, 6.2, Color("#060b09"))
		draw_arc(Vector2.ZERO, 7.2, 0.15, 2.7, 14, Color(0.88, 0.85, 0.73, 0.65), 1.1, true)
		draw_set_transform(Vector2.ZERO)
		if age < 0.075:
			var strength := 1.0 - age / 0.075
			var tracer := point + Vector2(210.0, -95.0) * strength
			draw_line(tracer, point, Color(1.0, 0.91, 0.65, strength * 0.7), 1.5, true)
			draw_circle(point, 3.5 + 8.0 * strength, Color(1.0, 0.84, 0.50, strength * 0.8))
		if age < 0.18:
			var strength := 1.0 - age / 0.18
			draw_arc(point, 12.0 + age * 180.0, 0.0, TAU, 32, Color(0.86, 0.82, 0.69, strength * 0.13), 1.0, true)
		if age < 1.2:
			var smoke_alpha := sin(clampf(age / 1.2, 0.0, 1.0) * PI) * 0.018
			for i in range(5):
				var center := point + Vector2(float(i) * 2.0 + age * 9.0, -age * 30.0 - i * 3.0)
				draw_circle(center, 13.0 + age * 21.0 + i * 2.0, Color(0.69, 0.71, 0.64, smoke_alpha))
	for fragment in fragments:
		var alpha := 1.0 - float(fragment.age) / float(fragment.life)
		var point: Vector2 = fragment.point
		var velocity: Vector2 = fragment.velocity
		var color := Color(0.96, 0.77, 0.44, alpha) if fragment.warm else Color(0.70, 0.73, 0.65, alpha * 0.7)
		draw_line(point, point - velocity.normalized() * (3.0 + alpha * 7.0), color, 1.0, true)



