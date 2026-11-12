extends Node2D

signal fold_completed(piece: Node2D, precision: float)

var id := ""
var display_name := ""
var fabric: Texture2D
var dimensions := Vector2.ZERO
var folds: Array[String] = []
var fold_scores: Array[float] = []
var selected := false
var placed := false
var folding := false
var fold_progress := 0.0
var fold_perpendicular_error := 0.0
var settle_tween: Tween
var thickness := 0.0
var surface_uv := Rect2(0, 0, 1, 1)
var fold_assist := 0.0

func configure(piece_id: String, label: String, texture: Texture2D, extent: Vector2, sequence: Array[String]) -> void:
	id = piece_id
	display_name = label
	fabric = texture
	dimensions = extent
	folds = sequence

func complete() -> bool:
	return fold_scores.size() == folds.size()

func contains_point(point: Vector2) -> bool:
	return Rect2(-dimensions / 2.0, dimensions).has_point(to_local(point))

func axis() -> String:
	return folds[fold_scores.size()] if not complete() else ""

func handle_local() -> Vector2:
	if axis() == "vertical":
		return Vector2(dimensions.x / 2.0 - 9.0, dimensions.y * 0.32)
	return Vector2(dimensions.x * 0.32, dimensions.y / 2.0 - 9.0)

func fold_end_local() -> Vector2:
	var point := handle_local()
	if axis() == "vertical":
		point.x = -point.x
	else:
		point.y = -point.y
	return point

func handle_global() -> Vector2:
	return to_global(handle_local())

func begin_fold() -> void:
	if is_instance_valid(settle_tween):
		settle_tween.kill()
	folding = true
	fold_progress = 0.0
	fold_perpendicular_error = 0.0

func update_fold(global_mouse: Vector2) -> void:
	var local := to_local(global_mouse)
	var start := handle_local()
	var end := fold_end_local()
	var route := end - start
	fold_progress = clampf((local - start).dot(route) / route.length_squared(), 0.0, 1.15)
	var perpendicular := Vector2(-route.y, route.x).normalized()
	var breadth := dimensions.y if axis() == "vertical" else dimensions.x
	fold_perpendicular_error = absf((local - start).dot(perpendicular)) / breadth
	queue_redraw()

func release_fold() -> bool:
	folding = false
	var allowance := 1.0 + fold_assist
	if fold_progress < 1.0 - 0.12 * allowance or fold_perpendicular_error > 0.3 * allowance:
		settle_tween = create_tween()
		settle_tween.tween_property(self, "fold_progress", 0.0, 0.18)
		settle_tween.tween_callback(queue_redraw)
		return false
	var precision := clampf(100.0 - (absf(1.0 - fold_progress) * 150.0 + fold_perpendicular_error * 80.0) / allowance, 0.0, 100.0)
	var direction := axis()
	if direction == "vertical":
		position += Vector2(-dimensions.x / 4.0, 0.0).rotated(rotation)
		dimensions.x *= 0.5
		surface_uv.size.x *= 0.5
	else:
		position += Vector2(0.0, -dimensions.y / 4.0).rotated(rotation)
		dimensions.y *= 0.5
		surface_uv.size.y *= 0.5
	fold_scores.append(precision)
	thickness += 3.0
	fold_progress = 0.0
	queue_redraw()
	fold_completed.emit(self, precision)
	return true

func unfold_last() -> void:
	if fold_scores.is_empty() or folding:
		return
	var last_axis := folds[fold_scores.size() - 1]
	if last_axis == "vertical":
		position += Vector2(dimensions.x / 2.0, 0).rotated(rotation)
		dimensions.x *= 2.0
		surface_uv.size.x *= 2.0
	else:
		position += Vector2(0, dimensions.y / 2.0).rotated(rotation)
		dimensions.y *= 2.0
		surface_uv.size.y *= 2.0
	fold_scores.pop_back()
	thickness = maxf(0.0, thickness - 3.0)
	placed = false
	queue_redraw()

func _process(_delta: float) -> void:
	if is_instance_valid(settle_tween) and settle_tween.is_running():
		queue_redraw()

func _draw() -> void:
	if not fabric:
		return
	var rectangle := Rect2(-dimensions / 2.0, dimensions)
	# The soft shadow lifts the cloth during manipulation, folded layers remain visible.
	var shadow := rectangle
	shadow.position += Vector2(5, 7 + thickness)
	draw_style_box(_box(Color(0.0, 0.0, 0.0, 0.24), 9), shadow)
	if thickness > 0:
		var under := rectangle
		under.position += Vector2(0, thickness)
		draw_style_box(_box(Color("#444b32"), 4), under)
	if folding or fold_progress > 0.0:
		var turn := cos(minf(fold_progress, 1.0) * PI)
		if axis() == "vertical":
			_patch(Rect2(-dimensions / 2.0, Vector2(dimensions.x / 2.0, dimensions.y)), Rect2(0, 0, 0.5, 1), Color.WHITE)
			_patch(Rect2(Vector2(0, -dimensions.y / 2.0), Vector2(dimensions.x / 2.0 * turn, dimensions.y)), Rect2(0.5, 0, 0.5, 1), Color.WHITE.darkened(0.17 * sin(minf(fold_progress, 1.0) * PI)))
		else:
			_patch(Rect2(-dimensions / 2.0, Vector2(dimensions.x, dimensions.y / 2.0)), Rect2(0, 0, 1, 0.5), Color.WHITE)
			_patch(Rect2(Vector2(-dimensions.x / 2.0, 0), Vector2(dimensions.x, dimensions.y / 2.0 * turn)), Rect2(0, 0.5, 1, 0.5), Color.WHITE.darkened(0.17 * sin(minf(fold_progress, 1.0) * PI)))
	else:
		_patch(rectangle, Rect2(0, 0, 1, 1), Color.WHITE)
	if selected:
		draw_style_box(_outline(), rectangle.grow(2.0))
		if not complete():
			var start := handle_local()
			var finish := fold_end_local()
			var crease_start := Vector2(0, -dimensions.y / 2) if axis() == "vertical" else Vector2(-dimensions.x / 2, 0)
			var crease_end := -crease_start
			draw_dashed_line(crease_start, crease_end, Color(0.91, 0.87, 0.69, 0.8), 1.5, 7.0, true)
			draw_dashed_line(start, finish, Color(0.83, 0.88, 0.71, 0.35), 1.0, 6.0, true)
			draw_circle(finish, 11, Color(0.83, 0.88, 0.71, 0.18))
			draw_arc(finish, 11, 0, TAU, 24, Color("#d9c397"), 1.5, true)
			var handle := start.lerp(finish, clampf(fold_progress, 0.0, 1.0)) if folding else start
			draw_circle(handle, 15, Color("#f0d4a1"))
			draw_circle(handle, 7, Color("#273626"))

func _patch(rectangle: Rect2, uv: Rect2, tint: Color) -> void:
	if absf(rectangle.size.x) < 0.5 or absf(rectangle.size.y) < 0.5:
		return
	var points := PackedVector2Array([rectangle.position, rectangle.position + Vector2(rectangle.size.x, 0), rectangle.end, rectangle.position + Vector2(0, rectangle.size.y)])
	var coordinates := PackedVector2Array([uv.position, uv.position + Vector2(uv.size.x, 0), uv.end, uv.position + Vector2(0, uv.size.y)])
	for i in range(coordinates.size()):
		coordinates[i] = surface_uv.position + coordinates[i] * surface_uv.size
	var texture := fabric
	if fabric is AtlasTexture:
		texture = fabric.atlas
		for i in range(coordinates.size()):
			coordinates[i] = (fabric.region.position + coordinates[i] * fabric.region.size) / texture.get_size()
	draw_polygon(points, PackedColorArray([tint, tint, tint, tint]), coordinates, texture)

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box

func _outline() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = Color(0.91, 0.82, 0.59, 0.65)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	return box

