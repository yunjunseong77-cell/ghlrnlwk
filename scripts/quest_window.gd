extends Control

signal accepted
signal dismissed

const HEADING_FONT := preload("res://assets/fonts/BlackHanSans-Regular.ttf")
const PAPER := Color("#eef5ec")
const CYAN := Color("#8cd6cc")
const MUTED := Color("#a8bcb4")
var training: Dictionary
var store: RefCounted
var replay := false
var decision_sent := false
var opened := false
var accept_button: Button
var cancel_button: Button
var panel: PanelContainer
var shade: ColorRect

func setup(training_id: String, progress_store: RefCounted, is_replay: bool) -> void:
	store = progress_store
	training = store.training(training_id)
	replay = is_replay

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.005, 0.02, 0.025, 0.84)
	shade.modulate.a = 0.0
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(1080, 610)
	panel.add_theme_stylebox_override("panel", _frame())
	panel.modulate.a = 0.0
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	panel.add_child(layout)
	layout.add_child(_label("재도전 퀘스트" if replay else "새로운 퀘스트", 14, CYAN))
	var title := _label(str(training.name), 39, PAPER)
	title.add_theme_font_override("font", HEADING_FONT)
	layout.add_child(title)
	# The heading and image share one panel, the mission content scrolls independently.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var details: Dictionary = training.get("quest", {})
	_add_artwork(body, details)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 18)
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var mission := VBoxContainer.new()
	mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission.add_theme_constant_override("separation", 17)
	scroll.add_child(mission)
	var description := _label(str(details.get("description", training.description)), 17, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission.add_child(description)
	var goals := VBoxContainer.new()
	goals.add_theme_constant_override("separation", 10)
	mission.add_child(goals)
	var objectives: Array = details.get("objectives", [training.description])
	for objective in objectives:
		var line := _label("□  " + str(objective), 19, PAPER)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goals.add_child(line)
	var conditions: Array[String] = []
	var effects: Dictionary = store.preview_effects(str(training.id))
	if details.has("time_limit"):
		conditions.append("%d초 제한" % (int(details.time_limit) + int(effects.get("bedding_time", 0))))
	if details.has("pass_score"):
		conditions.append("%d점 이상 통과" % int(details.pass_score))
	if not conditions.is_empty():
		mission.add_child(_label("  ·  ".join(conditions), 20, CYAN))
	var reward := VBoxContainer.new()
	reward.add_theme_constant_override("separation", 7)
	var first: bool = not store.cleared(str(training.id))
	var minimum := int(details.get("pass_score", 0))
	var low: int = store.reward_for_score(str(training.id), minimum, first)
	var high: int = store.reward_for_score(str(training.id), 100, first)
	reward.add_child(_label("보상  %d~%d %s" % [low, high, store.catalog.currency_name], 24, PAPER))
	if first:
		reward.add_child(_label("첫 완료 추가 보상 +%d 포함 · 재도전 해금" % training.first_bonus, 14, CYAN))
	else:
		reward.add_child(_label("통과 성적에 따라 지급", 14, MUTED))
	mission.add_child(reward)
	if not effects.is_empty():
		var applied := _label(store.effect_text(effects), 14, CYAN)
		applied.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mission.add_child(applied)
	if details.has("controls"):
		var controls := _label(str(details.controls), 15, MUTED)
		controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mission.add_child(controls)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	right.add_child(actions)
	cancel_button = _button("나중에", request_close, false)
	cancel_button.custom_minimum_size.x = 112
	actions.add_child(cancel_button)
	accept_button = _button("재도전 수락" if replay else "퀘스트 수락", _accept, true)
	accept_button.custom_minimum_size.x = 228
	actions.add_child(accept_button)
	_animate_open.call_deferred()

func _add_artwork(parent: Control, details: Dictionary) -> void:
	var frame := Control.new()
	frame.clip_contents = true
	frame.custom_minimum_size = Vector2(360, 450)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	var texture := TextureRect.new()
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := str(details.get("image", "res://assets/art/title.png"))
	if ResourceLoader.exists(path):
		texture.texture = load(path)
	frame.add_child(texture)
	var thought := str(details.get("thought", ""))
	if thought.is_empty() or replay:
		return
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.05, 0.05, 0.0))
	gradient.set_color(1, Color(0.02, 0.05, 0.05, 0.96))
	var fade_texture := GradientTexture2D.new()
	fade_texture.gradient = gradient
	fade_texture.fill_from = Vector2(0, 0)
	fade_texture.fill_to = Vector2(0, 1)
	var fade := TextureRect.new()
	fade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_top = -135
	fade.texture = fade_texture
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fade)
	var caption := _label(thought, 16, PAPER)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_left = 18
	caption.offset_right = -18
	caption.offset_top = -65
	caption.offset_bottom = -14
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame.add_child(caption)

func _animate_open() -> void:
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.965, 0.965)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(shade, "modulate:a", 1.0, 0.24)
	tween.tween_property(panel, "modulate:a", 1.0, 0.24)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	opened = true
	accept_button.disabled = false
	cancel_button.disabled = false
	accept_button.grab_focus()

func _accept() -> void:
	if not opened or decision_sent:
		return
	decision_sent = true
	accept_button.disabled = true
	cancel_button.disabled = true
	accepted.emit()

func request_close() -> void:
	if decision_sent:
		return
	decision_sent = true
	dismissed.emit()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _frame() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#10292d")
	style.border_color = Color(0.45, 0.76, 0.73, 0.75)
	style.set_border_width_all(1)
	style.shadow_color = Color(0.12, 0.49, 0.46, 0.16)
	style.shadow_size = 17
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 26
	return style

func _button(text: String, action: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = true
	button.custom_minimum_size.y = 49
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", PAPER)
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#286464") if primary else Color("#172f32")
		style.border_color = Color("#9ad7cc") if primary else Color("#527778")
		if key in ["hover", "focus", "pressed"]:
			style.bg_color = style.bg_color.lightened(0.13)
		style.set_border_width_all(1)
		style.content_margin_left = 20
		style.content_margin_right = 20
		button.add_theme_stylebox_override(key, style)
	button.pressed.connect(action)
	return button

