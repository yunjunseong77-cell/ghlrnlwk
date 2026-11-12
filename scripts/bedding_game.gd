extends Control

signal finished
const Piece := preload("res://scripts/bedding_piece.gd")
const TITLE_FONT := preload("res://assets/fonts/BlackHanSans-Regular.ttf")
const ROOM := preload("res://assets/art/bedding/bedding_room.png")
const TIME_LIMIT := 60.0
const PASS_SCORE := 80
const ORDER := ["mattress", "blanket", "pillow"]
const NAMES := {"mattress": "매트리스", "blanket": "모포", "pillow": "베개"}
const TARGETS := {
	"mattress": Vector2(710, 444),
	"blanket": Vector2(710, 419),
	"pillow": Vector2(710, 388)
}
const PAPER := Color("#fff4de")
const GOLD := Color("#e4c38c")
const MUTED := Color("#b8c2ad")
const WORK_AREA := Rect2(35, 155, 875, 505)

var store: RefCounted
var token := ""
var run_mode := "story"
var phase := "intro"
var time_left := TIME_LIMIT
var time_limit := TIME_LIMIT
var pass_score := PASS_SCORE
var pieces: Dictionary = {}
var stack: Array[String] = []
var selected: Node2D
var dragging := false
var rotating := false
var grab_local := Vector2.ZERO
var rotation_origin := 0.0
var mouse_angle_origin := 0.0
var return_to_home := false
var training_passed := false
var final_score := 0
var final_breakdown: Dictionary = {}
var receipt: Dictionary = {}
var timer_label: Label
var selection_label: Label
var direction_label: Label
var step_label: Label
var angle_label: Label
var score_label: Label
var status_label: Label
var inspect_button: Button
var unfold_button: Button
var popup: Control
var hud: Control
var fabric_textures: Dictionary = {}
var loadout_effects: Dictionary = {}
var loadout_label: Label

func setup_training(progress_store: RefCounted, session_token: String) -> void:
	store = progress_store
	token = session_token
	run_mode = str(store.sessions[token].mode)
	var quest: Dictionary = store.training("bedding").get("quest", {})
	time_limit = float(quest.get("time_limit", TIME_LIMIT))
	pass_score = int(quest.get("pass_score", PASS_SCORE))
	time_left = time_limit

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_pieces()
	_build_hud()
	_update_hud()
	_begin()

func _process(delta: float) -> void:
	if phase == "playing":
		time_left = maxf(0.0, time_left - delta)
		_update_hud()
		if time_left == 0.0:
			_evaluate()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if phase != "playing":
		return
	if not event is InputEventMouse:
		return
	var pointer := make_input_local(event) as InputEventMouse
	var mouse := pointer.position
	if event is InputEventMouseMotion:
		if selected and selected.folding:
			selected.update_fold(mouse)
			get_viewport().set_input_as_handled()
		elif dragging and selected:
			selected.position = mouse - grab_local.rotated(selected.rotation)
			_constrain(selected)
			get_viewport().set_input_as_handled()
		elif rotating and selected:
			var angle := (mouse - selected.position).angle()
			selected.rotation = rotation_origin + wrapf(angle - mouse_angle_origin, -PI, PI)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
		if selected and (selected.contains_point(mouse) or dragging):
			var degrees := 1.0 if event.shift_pressed else 3.0
			selected.rotation += deg_to_rad(degrees * (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0))
			if dragging:
				selected.position = mouse - grab_local.rotated(selected.rotation)
			_update_hud()
			get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and WORK_AREA.has_point(mouse):
			var piece := _pick(mouse)
			if piece:
				_select(piece)
				_remove_from_stack(piece.id)
				rotating = true
				rotation_origin = piece.rotation
				mouse_angle_origin = (mouse - piece.position).angle()
				get_viewport().set_input_as_handled()
		elif rotating:
			rotating = false
			_try_place(selected)
			get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if not WORK_AREA.has_point(mouse):
			return
		if selected and not selected.complete() and mouse.distance_to(selected.handle_global()) <= 24.0:
			_remove_from_stack(selected.id)
			selected.begin_fold()
			selected.z_index = 40
			status_label.text = "밝은 귀퉁이를 반대편 원까지 끌어 접으세요."
			get_viewport().set_input_as_handled()
			return
		var piece := _pick(mouse)
		if piece:
			_select(piece)
			_remove_from_stack(piece.id)
			grab_local = piece.to_local(mouse)
			dragging = true
			piece.z_index = 40
			get_viewport().set_input_as_handled()
	else:
		if selected and selected.folding:
			if not selected.release_fold():
				status_label.text = "조금 더 끝선까지. 반대편 원에 맞춰 놓으세요."
			_constrain(selected)
			selected.z_index = 20 + ORDER.find(selected.id)
			get_viewport().set_input_as_handled()
		elif dragging and selected:
			dragging = false
			selected.z_index = 20 + ORDER.find(selected.id)
			_try_place(selected)
			get_viewport().set_input_as_handled()
	_update_hud()

func _draw() -> void:
	draw_texture_rect(ROOM, Rect2(Vector2.ZERO, Vector2(1280, 720)), false, Color("#c4c9b7"))
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.025, 0.01, 0.15))
	draw_rect(Rect2(0, 0, 1280, 137), Color(0.025, 0.045, 0.03, 0.94))
	draw_rect(Rect2(930, 137, 350, 583), Color(0.025, 0.045, 0.03, 0.96))
	draw_rect(Rect2(0, 671, 930, 49), Color(0.025, 0.045, 0.03, 0.92))
	draw_rect(Rect2(0, 133, 1280 * time_left / time_limit, 3), GOLD if time_left > 10.0 else Color("#e88f73"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(610, 229), "적재 위치 · 기준각 0°", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, PAPER)
	var target := Rect2(TARGETS.mattress - Vector2(180, 110), Vector2(360, 220))
	draw_style_box(_panel(Color(0.06, 0.09, 0.05, 0.20)), target.grow(16))
	for id in ORDER:
		var size := Vector2(360, 220)
		if id == "blanket":
			size = Vector2(200, 180)
		elif id == "pillow":
			size = Vector2(166, 86)
		var rect := Rect2(TARGETS[id] - size / 2.0, size)
		var color := Color(0.87, 0.85, 0.65, 0.34)
		if stack.size() < ORDER.size() and id == ORDER[stack.size()]:
			color = Color(0.98, 0.88, 0.61, 0.75)
		_dashed_rectangle(rect, color)
	# The alignment cross remains outside the silhouette and can be read during a drag.
	draw_line(Vector2(710, 275), Vector2(710, 305), Color(0.9, 0.86, 0.66, 0.5), 1, true)
	draw_line(Vector2(695, 290), Vector2(725, 290), Color(0.9, 0.86, 0.66, 0.5), 1, true)

func _create_pieces() -> void:
	_add_piece("mattress", Vector2(300, 415), Vector2(360, 440), ["horizontal"], -4.0)
	_add_piece("blanket", Vector2(317, 416), Vector2(400, 360), ["vertical", "horizontal"], 7.0)
	_add_piece("pillow", Vector2(282, 230), Vector2(166, 86), [], -12.0)
	_select(pieces.blanket)

func _add_piece(id: String, start: Vector2, extent: Vector2, folds: Array[String], angle: float) -> void:
	var piece := Piece.new()
	piece.configure(id, NAMES[id], _fabric(id), extent, folds)
	piece.fold_assist = float(loadout_effects.get("fold_assist", 0))
	piece.position = start
	piece.rotation_degrees = angle
	piece.fold_completed.connect(_on_fold)
	piece.z_index = 20 + pieces.size()
	pieces[id] = piece
	add_child(piece)

func _fabric(id: String) -> Texture2D:
	if fabric_textures.has(id):
		return fabric_textures[id]
	var texture := load("res://assets/art/bedding/" + id + ".png") as Texture2D
	var image := texture.get_image()
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i.ZERO
	# Ignore almost transparent edge pixels when fitting the sprite to its hit box.
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			if image.get_pixel(x, y).a > 0.25:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = Rect2i(minimum, maximum - minimum + Vector2i(4, 4)).grow(3).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	fabric_textures[id] = crop
	return crop

func _on_fold(piece: Node2D, precision: float) -> void:
	status_label.text = "%s 접기  %d점. %s" % [piece.display_name, roundi(precision), "적재 위치로 옮기세요." if piece.complete() else "다음 접는 선을 맞추세요."]
	_update_hud()

func _pick(point: Vector2) -> Node2D:
	var candidates: Array = pieces.values()
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		if a.z_index == b.z_index:
			return a.get_index() > b.get_index()
		return a.z_index > b.z_index
	)
	for piece in candidates:
		if piece.contains_point(point):
			return piece
	return null

func _select(piece: Node2D) -> void:
	for other in pieces.values():
		other.selected = other == piece
		other.queue_redraw()
	selected = piece
	if is_instance_valid(selection_label):
		_update_hud()

func _constrain(piece: Node2D) -> void:
	var radius: float = piece.dimensions.length() / 2.0
	piece.position.x = clampf(piece.position.x, 60 + minf(radius, 110), 895 - minf(radius, 100))
	piece.position.y = clampf(piece.position.y, 165 + minf(radius, 100), 655 - minf(radius, 95))

func _remove_from_stack(id: String) -> void:
	var at := stack.find(id)
	if at < 0:
		return
	while stack.size() > at:
		var removed: String = stack.pop_back()
		pieces[removed].placed = false
		pieces[removed].z_index = 20 + ORDER.find(removed)
	_update_hud()

func _try_place(piece: Node2D) -> bool:
	if not piece.complete():
		status_label.text = "%s의 밝은 귀퉁이를 잡아 먼저 접으세요." % piece.display_name
		return false
	if piece.position.distance_to(TARGETS[piece.id]) > 100.0:
		status_label.text = "접기를 마쳤습니다. 오른쪽 점선 안에 적재하세요."
		return false
	if stack.size() >= ORDER.size() or piece.id != ORDER[stack.size()]:
		var next: String = NAMES[ORDER[mini(stack.size(), ORDER.size() - 1)]]
		status_label.text = "%s부터 놓으세요. 매트리스 → 모포 → 베개 순서입니다." % next
		return false
	stack.append(piece.id)
	var snap := float(loadout_effects.get("snap_degrees", 0))
	if snap > 0 and absf(wrapf(piece.rotation_degrees, -180.0, 180.0)) <= snap:
		piece.rotation = 0.0
	piece.placed = true
	piece.z_index = 10 + stack.size()
	status_label.text = "%s 적재. %s" % [piece.display_name, "위치와 각도를 확인하고 검사받으세요." if stack.size() == 3 else "다음은 " + NAMES[ORDER[stack.size()]] + "입니다."]
	_update_hud()
	return true

func breakdown() -> Dictionary:
	var fold_total := 0.0
	var fold_count := 0
	var position_total := 0.0
	var angle_total := 0.0
	for id in ORDER:
		var piece: Node2D = pieces[id]
		for precision in piece.fold_scores:
			fold_total += float(precision)
			fold_count += 1
		if piece.placed:
			position_total += clampf(100.0 - piece.position.distance_to(TARGETS[id]) * 1.35, 0.0, 100.0)
			var error := absf(wrapf(piece.rotation, -PI, PI))
			angle_total += clampf(100.0 - rad_to_deg(error) * 4.0, 0.0, 100.0)
	var fold_score := fold_total / 3.0
	var placement := position_total / 3.0
	# All three layers contribute to the same stack alignment allowance.
	var alignment := clampf(angle_total - 200.0, 0.0, 100.0)
	var score := roundi(fold_score * 0.45 + placement * 0.30 + alignment * 0.25)
	return {"fold": roundi(fold_score), "position": roundi(placement), "angle": roundi(alignment), "score": score, "complete": stack.size() == 3 and fold_count == 3}

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.z_index = 100
	add_child(hud)
	var heading := _label("침상 정리", 35, PAPER, Vector2(40, 25))
	heading.add_theme_font_override("font", TITLE_FONT)
	hud.add_child(heading)
	hud.add_child(_label("모포와 매트리스를 접고, 각을 맞춰 적재하세요.", 17, MUTED, Vector2(42, 83)))
	loadout_label = _label("", 12, GOLD, Vector2(42, 111))
	loadout_label.size = Vector2(1020, 18)
	loadout_label.clip_text = true
	hud.add_child(loadout_label)
	timer_label = _label("60.0", 38, GOLD, Vector2(702, 29))
	hud.add_child(timer_label)
	hud.add_child(_label("남은 시간", 14, MUTED, Vector2(709, 82)))
	var pause := _button("일시정지", request_pause)
	pause.position = Vector2(1094, 42)
	pause.size = Vector2(140, 44)
	hud.add_child(pause)
	hud.add_child(_label("선택한 침구", 14, GOLD, Vector2(958, 166)))
	selection_label = _label("", 29, PAPER, Vector2(956, 195))
	hud.add_child(selection_label)
	direction_label = _label("", 17, PAPER, Vector2(958, 251))
	direction_label.size = Vector2(272, 68)
	direction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(direction_label)
	angle_label = _label("", 18, GOLD, Vector2(958, 329))
	hud.add_child(angle_label)
	step_label = _label("", 17, MUTED, Vector2(958, 381))
	step_label.size = Vector2(280, 90)
	hud.add_child(step_label)
	score_label = _label("", 24, PAPER, Vector2(958, 486))
	hud.add_child(score_label)
	unfold_button = _button("한 번 펼치기", _undo_fold)
	unfold_button.position = Vector2(958, 543)
	unfold_button.size = Vector2(275, 44)
	hud.add_child(unfold_button)
	inspect_button = _button("검사받기", _evaluate)
	inspect_button.position = Vector2(958, 601)
	inspect_button.size = Vector2(275, 48)
	hud.add_child(inspect_button)
	status_label = _label("밝은 귀퉁이를 반대편 원까지 끌어 접으세요.", 16, PAPER, Vector2(36, 681))
	status_label.size.x = 874
	status_label.clip_text = true
	hud.add_child(status_label)
	hud.add_child(_label("왼쪽 드래그  이동 / 접기     휠  3° 회전     오른쪽 드래그  정밀 회전", 13, MUTED, Vector2(36, 148)))

func _update_hud() -> void:
	if not is_instance_valid(timer_label):
		return
	timer_label.text = "%04.1f" % time_left
	timer_label.add_theme_color_override("font_color", GOLD if time_left > 10 else Color("#ee9479"))
	if selected:
		selection_label.text = selected.display_name
		var complete: bool = selected.complete()
		direction_label.text = "접기 완료\n몸통을 잡아 옮기세요" if complete else "접기 %d / %d\n밝은 귀퉁이 → 반대편 원" % [selected.fold_scores.size() + 1, selected.folds.size()]
		angle_label.text = "회전  %+.1f°  /  기준 0°" % wrapf(selected.rotation_degrees, -180.0, 180.0)
		unfold_button.disabled = selected.fold_scores.is_empty()
	var lines := ""
	for id in ORDER:
		lines += ("✓  " if pieces[id].placed else "·  ") + str(NAMES[id]) + "\n"
	step_label.text = lines.strip_edges()
	var result := breakdown()
	score_label.text = "현재 %d점 / 합격 %d점" % [result.score, pass_score]
	inspect_button.disabled = stack.size() != 3
	inspect_button.text = "검사받기" if stack.size() == 3 else "세 침구를 적재하세요"

func _undo_fold() -> void:
	if phase != "playing" or not selected:
		return
	_remove_from_stack(selected.id)
	selected.unfold_last()
	_constrain(selected)
	status_label.text = "다시 펼쳤습니다. 접는 선에 맞춰 다듬으세요."
	_update_hud()

func _begin() -> void:
	if not _activate_loadout():
		return
	_close_popup()
	time_left = time_limit
	phase = "playing"

func _activate_loadout() -> bool:
	var activated: Dictionary = store.activate_run(token)
	if not activated.ok:
		phase = "blocked"
		var box := _popup("훈련 시작 확인", str(activated.message))
		box.add_child(_button("다시 시작", _retry))
		box.add_child(_button("훈련 나가기", _leave))
		return false
	loadout_effects = store.sessions[token].effects.duplicate()
	var quest: Dictionary = store.training("bedding").get("quest", {})
	time_limit = float(quest.get("time_limit", TIME_LIMIT)) + float(loadout_effects.get("bedding_time", 0))
	for piece in pieces.values():
		piece.fold_assist = float(loadout_effects.get("fold_assist", 0))
	loadout_label.text = store.effect_text(loadout_effects, "  ·  ")
	loadout_label.tooltip_text = store.effect_text(loadout_effects)
	return true

func request_pause() -> void:
	if phase == "paused":
		_close_popup()
		phase = "playing"
		return
	if phase != "playing":
		return
	# A partially folded flap settles back before pausing.
	dragging = false
	rotating = false
	if selected and selected.folding:
		selected.folding = false
		selected.fold_progress = 0.0
		selected.queue_redraw()
	phase = "paused"
	var box := _popup("일시정지", "남은 시간은 멈춰 있습니다.")
	box.add_child(_button("계속하기", func() -> void:
		_close_popup()
		phase = "playing"
	))
	box.add_child(_button("처음부터 다시", _retry))
	box.add_child(_button("훈련 나가기", _leave))

func _evaluate() -> void:
	if phase != "playing":
		return
	phase = "result"
	dragging = false
	rotating = false
	if selected:
		selected.folding = false
		selected.fold_progress = 0.0
		selected.queue_redraw()
	final_breakdown = breakdown()
	final_score = int(final_breakdown.score)
	training_passed = bool(final_breakdown.complete) and final_score >= pass_score
	_settle()

func _settle() -> void:
	receipt = store.finish_run(token, final_score, training_passed)
	_show_result()

func _show_result() -> void:
	var headline := "훈련 통과" if training_passed else "다시, 각 잡고"
	if not receipt.ok:
		headline = "결과 저장 대기"
	var reason := "모든 침구를 정확하게 정리했습니다." if training_passed else ("적재를 끝내지 못했습니다." if not final_breakdown.complete else "정확도를 다듬어 %d점을 넘겨보세요." % pass_score)
	var box := _popup(headline, reason)
	var score := _label("%d점" % final_score, 52, GOLD)
	score.add_theme_font_override("font", TITLE_FONT)
	box.add_child(score)
	box.add_child(_label("접기 %d   ·   위치 %d   ·   각도 %d\n남은 시간 %.1f초" % [final_breakdown.fold, final_breakdown.position, final_breakdown.angle, time_left], 19, PAPER))
	if receipt.ok:
		if training_passed:
			var first: bool = receipt.first_clear
			box.add_child(_label("+%d %s%s" % [receipt.reward, store.catalog.currency_name, "  ·  재도전 해금!" if first else ""], 21, GOLD))
			if int(receipt.get("bonus_reward", 0)) > 0:
				box.add_child(_label("장비 추가 보상 +%d 포함" % receipt.bonus_reward, 16, MUTED))
		else:
			box.add_child(_label("모포와 매트리스의 접기, 적재 순서와 기준각을 확인하세요.", 16, MUTED))
		box.add_child(_button("한 번 더 도전", _retry))
		box.add_child(_button("계속하기" if run_mode == "story" and training_passed else "훈련 나가기", func() -> void:
			return_to_home = not training_passed or run_mode == "replay"
			finished.emit()
		))
	else:
		box.add_child(_label(str(receipt.message), 18, GOLD))
		box.add_child(_button("저장 다시 시도", _settle))
		box.add_child(_button("훈련 나가기", _leave))

func _retry() -> void:
	store.cancel_run(token)
	var run: Dictionary = store.begin_run("bedding", run_mode)
	if not run.ok:
		return
	token = str(run.token)
	if not _activate_loadout():
		return
	for piece in pieces.values():
		remove_child(piece)
		piece.queue_free()
	pieces.clear()
	stack.clear()
	selected = null
	time_left = time_limit
	training_passed = false
	return_to_home = false
	receipt.clear()
	_close_popup()
	_create_pieces()
	phase = "playing"
	status_label.text = "다시 시작합니다. 정확하게 접고, 순서대로 적재하세요."
	_update_hud()

func _leave() -> void:
	store.cancel_run(token)
	return_to_home = true
	finished.emit()

func _exit_tree() -> void:
	if store:
		store.cancel_run(token)

func _popup(heading: String, description: String) -> VBoxContainer:
	_close_popup()
	popup = Control.new()
	popup.z_index = 200
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(popup)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.025, 0.02, 0.84)
	popup.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 650
	panel.add_theme_stylebox_override("panel", _panel(Color("#18291f")))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)
	box.add_child(_label(heading, 31, PAPER))
	box.add_child(_label(description, 18, MUTED))
	return box

func _close_popup() -> void:
	if is_instance_valid(popup):
		popup.queue_free()
	popup = null

func _label(text: String, font_size: int, color: Color, at: Vector2 = Vector2.ZERO) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 45
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", PAPER)
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := _panel(Color("#344634") if key in ["hover", "pressed", "focus"] else Color("#202e23"))
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(key, style)
	button.pressed.connect(action)
	return button

func _panel(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("#8f9470")
	box.set_border_width_all(1)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 24
	box.content_margin_bottom = 24
	return box

func _dashed_rectangle(rect: Rect2, color: Color) -> void:
	var points := [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y), rect.position]
	for i in range(4):
		draw_dashed_line(points[i], points[i + 1], color, 1.5, 9, true)

