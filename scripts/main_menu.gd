extends Control

const ART := "res://assets/art/"
const INK := Color("#111a18")
const PAPER := Color("#fff4de")
const GOLD := Color("#e4c38c")
const TITLE_FONT := preload("res://assets/fonts/BlackHanSans-Regular.ttf")
const START_FONT := preload("res://assets/fonts/ArchivoBlack-Regular.ttf")
const TitleImpacts := preload("res://scripts/title_impacts.gd")
const TrainingProgress := preload("res://scripts/training_progress.gd")
const TrainingHub := preload("res://scripts/training_hub.gd")
const QuestWindow := preload("res://scripts/quest_window.gd")
const CampWorld := preload("res://scripts/camp_world.gd")
const MUSIC := {
	"title": "res://assets/audio/title.ogg",
	"discharge_morning": "res://assets/audio/dawns_quiet_call.mp3",
	"farewell": "res://assets/audio/dawns_quiet_call.mp3",
	"training_morning": "res://assets/audio/recruit_morning.mp3",
	"bedding": "res://assets/audio/ceremonial_charge.mp3",
	"drill": "res://assets/audio/ceremonial_charge.mp3",
	"shooting": "res://assets/audio/ceremonial_charge.mp3"
}
const RECORDED_SFX := {
	"reveille": {"file": "res://assets/audio/reveille_11s.ogg", "volume_db": -8.0},
	"horn": {"file": "res://assets/audio/horn.ogg", "volume_db": -4.0},
	"impact": {"file": "res://assets/audio/impact.ogg", "volume_db": -3.0},
	"laugh": {"file": "res://assets/audio/laugh.ogg", "volume_db": -12.0}
}

var story: Array = []
var index := -1
var player_name := "윤준성"
var current_scene := ""
var current_music := ""
var state := "title"
var busy := false
var elapsed := 0.0
var typing := 0.0
var full_text := ""
var history: Array[String] = []
var progress := ConfigFile.new()
var bg: TextureRect
var bg_shade: ColorRect
var title_ui: Control
var start_button: Button
var resume_button: Button
var dialogue_ui: Control
var speaker_label: Label
var dialogue_label: RichTextLabel
var aside_label: Label
var location_label: Label
var chapter_label: Label
var count_label: Label
var next_label: Label
var curtain: ColorRect
var flash: ColorRect
var overlay: Control
var music_player: AudioStreamPlayer
var effect_player: AudioStreamPlayer
var scene_tween: Tween
var text_speed := 38.0
var master_volume := 0.8
var training_progress: RefCounted
var active_training_token := ""
var home_profile_label: Label
var home_balance_label: Label
var title_impacts: Control
var title_extras: Array[CanvasItem] = []
var title_tween: Tween
var title_shake_remaining := 0.0
var music_fade: Tween
var reaction_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer
var pending_reaction := ""
var active_effect := ""
var nickname_form: Control
var nickname_preview: Label
var nickname_hint: Label
var nickname_draft := ""
var nickname_dialog_open := false
var camp_world: Control
var camp_button: Button
var progress_path := "user://progress.cfg"
var camp_progress_path := "user://camp_progress.cfg"
var campaign_clears: Dictionary = {"bedding": false, "drill": false, "shooting": false}
var cinematic_remaining := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if training_progress == null:
		training_progress = TrainingProgress.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/prologue.json"))
	if parsed is Array:
		story = parsed
	progress.load(progress_path)
	var saved_clears: Variant = progress.get_value("campaign", "clears") if progress.has_section_key("campaign", "clears") else null
	if saved_clears is Dictionary:
		for id in campaign_clears:
			campaign_clears[id] = bool(saved_clears.get(id, false))
	elif int(progress.get_value("story", "index", -1)) >= story.size() - 1 or bool(progress.get_value("world", "active", false)):
		for id in campaign_clears:
			campaign_clears[id] = training_progress.cleared(id)
	player_name = str(progress.get_value("player", "name", "윤준성"))
	master_volume = float(progress.get_value("settings", "volume", 0.8))
	text_speed = float(progress.get_value("settings", "text_speed", 38.0))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.finished.connect(_loop_music)
	effect_player = AudioStreamPlayer.new()
	add_child(effect_player)
	reaction_player = AudioStreamPlayer.new()
	add_child(reaction_player)
	voice_player = AudioStreamPlayer.new()
	add_child(voice_player)
	_build_ui()
	_show_title()


func _process(delta: float) -> void:
	elapsed += delta
	if is_instance_valid(camp_world):
		camp_world.visible = state == "camp"
		camp_world.suspended = state != "camp" or is_instance_valid(overlay)
	if title_shake_remaining > 0.0:
		title_shake_remaining = maxf(0.0, title_shake_remaining - delta)
		var strength := title_shake_remaining / 0.16
		var offset := Vector2(sin(elapsed * 139.0), cos(elapsed * 173.0)) * 5.0 * strength
		title_ui.position = offset
		bg.position = offset * 0.55
		if title_shake_remaining == 0.0:
			title_ui.position = Vector2.ZERO
			bg.position = Vector2.ZERO
	if state == "title" and is_instance_valid(start_button):
		start_button.modulate.a = 0.50 + 0.50 * (sin(elapsed * 3.1) + 1.0) / 2.0
	if state == "story" and not busy and not is_instance_valid(overlay):
		if cinematic_remaining >= 0.0:
			cinematic_remaining -= delta
			if cinematic_remaining <= 0.0:
				cinematic_remaining = -1.0
				_advance()
			return
		typing += delta * text_speed
		dialogue_label.visible_characters = mini(int(typing), full_text.length())
		next_label.visible = int(typing) >= full_text.length()
		if next_label.visible and not pending_reaction.is_empty():
			_sfx(pending_reaction)
			pending_reaction = ""
		next_label.modulate.a = 0.55 + 0.45 * absf(sin(elapsed * 2.5))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var mode := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and not busy:
			if is_instance_valid(overlay):
				if overlay.has_method("request_close"):
					overlay.request_close()
				elif overlay.has_method("request_pause"):
					overlay.request_pause()
				else:
					_close_overlay()
			elif state == "story":
				_pause()
			elif state == "camp" and is_instance_valid(camp_world):
				camp_world.request_pause()
			get_viewport().set_input_as_handled()
			return
	if busy or is_instance_valid(overlay):
		return
	var proceed := event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton:
		proceed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if proceed and state == "story":
		if cinematic_remaining >= 0.0:
			get_viewport().set_input_as_handled()
			return
		if int(typing) < full_text.length():
			typing = float(full_text.length())
			dialogue_label.visible_characters = full_text.length()
		else:
			_advance()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	bg = TextureRect.new()
	_full(bg)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	bg_shade = ColorRect.new()
	_full(bg_shade)
	bg_shade.color = Color(0.02, 0.035, 0.03, 0.25)
	add_child(bg_shade)

	title_ui = Control.new()
	_full(title_ui)
	add_child(title_ui)
	var left_gradient := Gradient.new()
	left_gradient.set_color(0, Color(0.015, 0.03, 0.025, 0.88))
	left_gradient.set_color(1, Color(0.015, 0.03, 0.025, 0.0))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = left_gradient
	gradient_texture.fill_from = Vector2.ZERO
	gradient_texture.fill_to = Vector2(1, 0)
	var left := TextureRect.new()
	_full(left)
	left.texture = gradient_texture
	title_ui.add_child(left)
	var eyebrow := _label("끝난 줄 알았던 군생활이, 다시 시작된다.", 18, GOLD)
	eyebrow.position = Vector2(84, 87)
	title_ui.add_child(eyebrow)
	var title_lines := ["훈련병장", "회귀자는", "전역하고 싶어"]
	for i in range(title_lines.size()):
		var line := _label(title_lines[i], 82 if i < 2 else 74, PAPER)
		line.name = "Title%d" % i
		line.position = Vector2(79, 126 + i * 92)
		line.add_theme_font_override("font", TITLE_FONT)
		line.add_theme_constant_override("outline_size", 1)
		line.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.05, 0.55))
		line.add_theme_constant_override("shadow_offset_x", 0)
		line.add_theme_constant_override("shadow_offset_y", 4)
		title_ui.add_child(line)
	var rule := ColorRect.new()
	rule.position = Vector2(85, 421)
	rule.size = Vector2(72, 3)
	rule.color = GOLD
	title_ui.add_child(rule)
	var subtitle := _label("몸은 훈련병. 머릿속은 말년 병장.", 20, PAPER)
	subtitle.position = Vector2(85, 446)
	title_ui.add_child(subtitle)
	start_button = Button.new()
	start_button.text = "GAME START"
	start_button.position = Vector2(79, 527)
	start_button.size = Vector2(430, 69)
	start_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	start_button.add_theme_font_override("font", START_FONT)
	start_button.add_theme_font_size_override("font_size", 32)
	start_button.add_theme_color_override("font_color", PAPER)
	start_button.add_theme_color_override("font_hover_color", GOLD)
	for key in ["normal", "hover", "pressed", "focus"]:
		start_button.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	start_button.pressed.connect(_name_entry)
	title_ui.add_child(start_button)
	var prompt := _label("클릭하여 새로운 군생활 시작", 15, Color("#c5cebd"))
	prompt.position = Vector2(85, 604)
	title_ui.add_child(prompt)
	var help := _label("F11 전체 화면   ·   클릭 / Enter / Space 대사 진행", 14, Color("#dad8c9"))
	help.position = Vector2(84, 674)
	title_ui.add_child(help)
	var settings := _button("설정", _settings)
	settings.position = Vector2(1060, 654)
	settings.size = Vector2(76, 38)
	title_ui.add_child(settings)
	var quit := _button("종료", func() -> void: get_tree().quit())
	quit.position = Vector2(1148, 654)
	quit.size = Vector2(76, 38)
	title_ui.add_child(quit)
	resume_button = _button("이어서 보기", _resume)
	resume_button.position = Vector2(1054, 604)
	resume_button.size = Vector2(170, 38)
	title_ui.add_child(resume_button)
	camp_button = _button("훈련소 탐색", func() -> void:
		var unlocked: bool = campaign_clears.bedding or int(progress.get_value("story", "index", -1)) >= story.size() - 1
		_open_camp(not unlocked)
	)
	camp_button.position = Vector2(1054, 367)
	camp_button.size = Vector2(170, 40)
	title_ui.add_child(camp_button)
	var training_button := _button("훈련 나가기", func() -> void: _open_training_hub("training"))
	training_button.position = Vector2(1054, 490)
	training_button.size = Vector2(170, 44)
	title_ui.add_child(training_button)
	var shooting_button := _button("사격 바로하기", _quick_shooting)
	shooting_button.position = Vector2(860, 490)
	shooting_button.size = Vector2(180, 44)
	shooting_button.add_theme_color_override("font_color", GOLD)
	var shooting_style := _panel_style()
	shooting_style.bg_color = Color("#30473d")
	shooting_style.border_color = GOLD
	shooting_style.content_margin_top = 7
	shooting_style.content_margin_bottom = 7
	shooting_button.add_theme_stylebox_override("normal", shooting_style)
	title_ui.add_child(shooting_button)
	var px_button := _button("PX", func() -> void: _open_training_hub("shop"))
	px_button.position = Vector2(1054, 546)
	px_button.size = Vector2(170, 44)
	title_ui.add_child(px_button)
	var equipment_button := _button("아이템 · 장비", func() -> void: _open_training_hub("equipment"))
	equipment_button.position = Vector2(860, 546)
	equipment_button.size = Vector2(180, 44)
	title_ui.add_child(equipment_button)
	home_profile_label = _label("", 18, PAPER)
	home_profile_label.position = Vector2(860, 422)
	home_profile_label.size.x = 364
	home_profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_ui.add_child(home_profile_label)
	home_balance_label = _label("", 15, GOLD)
	home_balance_label.position = Vector2(860, 454)
	home_balance_label.size.x = 364
	home_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_ui.add_child(home_balance_label)
	title_extras.assign([eyebrow, rule, subtitle, prompt, help, settings, quit, resume_button, camp_button, training_button, shooting_button, px_button, equipment_button, home_profile_label, home_balance_label])
	title_impacts = TitleImpacts.new()
	_full(title_impacts)
	title_ui.add_child(title_impacts)

	dialogue_ui = Control.new()
	_full(dialogue_ui)
	dialogue_ui.hide()
	add_child(dialogue_ui)
	var top := ColorRect.new()
	top.color = Color(0.015, 0.025, 0.02, 0.86)
	top.size = Vector2(1280, 52)
	dialogue_ui.add_child(top)
	chapter_label = _label("", 14, GOLD)
	chapter_label.position = Vector2(40, 16)
	dialogue_ui.add_child(chapter_label)
	location_label = _label("", 14, PAPER)
	location_label.position = Vector2(720, 16)
	location_label.size.x = 520
	location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dialogue_ui.add_child(location_label)
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(36, 491)
	panel.size = Vector2(1208, 193)
	var panel_style := _panel_style()
	panel_style.bg_color = Color(0.035, 0.055, 0.047, 0.94)
	panel.add_theme_stylebox_override("panel", panel_style)
	dialogue_ui.add_child(panel)
	var accent := ColorRect.new()
	accent.position = Vector2(36, 491)
	accent.size = Vector2(4, 193)
	accent.color = GOLD
	dialogue_ui.add_child(accent)
	speaker_label = _label("", 22, GOLD)
	speaker_label.position = Vector2(70, 511)
	dialogue_ui.add_child(speaker_label)
	dialogue_label = RichTextLabel.new()
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_label.position = Vector2(70, 551)
	dialogue_label.size = Vector2(1115, 88)
	dialogue_label.bbcode_enabled = false
	dialogue_label.scroll_active = false
	dialogue_label.add_theme_font_size_override("normal_font_size", 24)
	dialogue_label.add_theme_color_override("default_color", PAPER)
	dialogue_label.add_theme_constant_override("line_separation", 8)
	dialogue_ui.add_child(dialogue_label)
	aside_label = _label("", 15, Color("#b3bbae"))
	aside_label.position = Vector2(71, 646)
	dialogue_ui.add_child(aside_label)
	next_label = _label("다음  ▸", 15, GOLD)
	next_label.position = Vector2(1123, 650)
	dialogue_ui.add_child(next_label)
	count_label = _label("", 12, Color("#a7aea1"))
	count_label.position = Vector2(40, 695)
	dialogue_ui.add_child(count_label)
	var log_button := _button("대화 기록", _show_history)
	log_button.custom_minimum_size.y = 24
	log_button.add_theme_font_size_override("font_size", 13)
	log_button.position = Vector2(1037, 691)
	log_button.size = Vector2(100, 24)
	dialogue_ui.add_child(log_button)
	var pause_button := _button("메뉴", _pause)
	pause_button.custom_minimum_size.y = 24
	pause_button.add_theme_font_size_override("font_size", 13)
	pause_button.position = Vector2(1151, 691)
	pause_button.size = Vector2(80, 24)
	dialogue_ui.add_child(pause_button)

	flash = ColorRect.new()
	_full(flash)
	flash.color = Color.WHITE
	flash.modulate.a = 0.0
	add_child(flash)
	curtain = ColorRect.new()
	_full(curtain)
	curtain.color = Color("#040706")
	add_child(curtain)


func _show_title() -> void:
	effect_player.stop()
	reaction_player.stop()
	voice_player.stop()
	pending_reaction = ""
	state = "title"
	busy = true
	if is_instance_valid(title_tween):
		title_tween.kill()
	title_shake_remaining = 0.0
	title_ui.position = Vector2.ZERO
	title_impacts.reset()
	_refresh_home_profile()
	resume_button.visible = int(progress.get_value("story", "index", -1)) >= 0
	title_ui.show()
	dialogue_ui.hide()
	_set_background("title")
	_play_music("title")
	curtain.modulate.a = 1.0
	start_button.disabled = true
	start_button.hide()
	for extra in title_extras:
		extra.modulate.a = 0.0
		if extra is BaseButton:
			extra.disabled = true
	title_tween = create_tween()
	title_tween.tween_property(curtain, "modulate:a", 0.0, 0.65)
	for i in range(3):
		var line := title_ui.get_node("Title%d" % i) as Label
		line.modulate.a = 0.0
		line.pivot_offset = Vector2(0, 46)
		line.scale = Vector2(1.14, 1.14)
		title_tween.tween_callback(_strike_title.bind(i))
		title_tween.tween_property(line, "modulate:a", 1.0, 0.035)
		title_tween.parallel().tween_property(line, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		title_tween.tween_interval(0.19)
	title_tween.tween_method(_set_title_extras_opacity, 0.0, 1.0, 0.30)
	title_tween.tween_callback(func() -> void:
		start_button.show()
		start_button.disabled = false
		for extra in title_extras:
			if extra is BaseButton:
				extra.disabled = false
		busy = false
		start_button.grab_focus()
	)


func _strike_title(number: int) -> void:
	var line := title_ui.get_node("Title%d" % number) as Label
	var text_size := line.get_minimum_size()
	var point := line.position + Vector2(text_size.x + 17.0, text_size.y * 0.56)
	if number == 1:
		point = line.position + Vector2(-18.0, text_size.y * 0.57)
	title_impacts.strike(point, number)
	title_shake_remaining = 0.16
	flash.modulate.a = 0.055
	create_tween().tween_property(flash, "modulate:a", 0.0, 0.10)


func _set_title_extras_opacity(value: float) -> void:
	for extra in title_extras:
		extra.modulate.a = value


func _set_background(scene: String) -> void:
	if active_effect == "reveille" and scene in ["office", "title"]:
		effect_player.stop()
	current_scene = scene
	if is_instance_valid(scene_tween):
		scene_tween.kill()
	bg.position = Vector2.ZERO
	bg.scale = Vector2.ONE
	if scene == "black":
		bg.texture = null
		bg_shade.color = Color("#040706")
		return
	var path := ART + scene + ".png"
	bg.texture = load(path) if ResourceLoader.exists(path) else null
	bg_shade.color = Color(0.02, 0.035, 0.03, 0.13 if state == "story" else 0.20)
	if state == "story":
		scene_tween = create_tween().set_loops()
		scene_tween.tween_property(bg, "scale", Vector2(1.035, 1.035), 28.0)
		scene_tween.tween_property(bg, "scale", Vector2.ONE, 28.0)


func _name_entry() -> void:
	if busy or is_instance_valid(overlay):
		return
	var box := _modal("전역하는 병장의 이름", "이 이름으로 당신의 군생활이 시작됩니다.")
	nickname_form = overlay
	nickname_draft = player_name
	nickname_preview = _label(nickname_draft, 38, PAPER)
	nickname_preview.name = "NicknamePreview"
	nickname_preview.custom_minimum_size.y = 60
	box.add_child(nickname_preview)
	box.add_child(_button("이름 입력 / 변경", _edit_native_nickname))
	nickname_hint = _label("이름 1~12자", 14, Color("#b4beac"))
	box.add_child(nickname_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	row.add_child(_button("뒤로", _close_overlay))
	row.add_child(_button("이야기 시작", _confirm_nickname))
	# Draw the game confirmation card before opening the OS-owned edit control.
	_edit_native_nickname.call_deferred()


func _edit_native_nickname() -> void:
	if nickname_dialog_open or not is_instance_valid(nickname_form) or overlay != nickname_form:
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_INPUT):
		nickname_hint.text = "이 환경에서 이름 입력창을 열 수 없습니다. Windows에서 실행해주세요."
		return
	nickname_dialog_open = true
	var form_id := nickname_form.get_instance_id()
	# Windows creates a native EDIT control with its own IME composition handling.
	# Only the complete UTF-16 value is returned, never intermediate Hangul syllables.
	var result := DisplayServer.dialog_input_text(
		"훈련병장 · 닉네임 설정",
		"사용할 이름을 입력하세요. (1~12자)",
		nickname_draft,
		func(value: String) -> void:
			_receive_native_nickname.call_deferred(value, form_id)
	)
	nickname_dialog_open = false
	if result != OK and is_instance_valid(nickname_hint):
		nickname_hint.text = "이름 입력창을 열지 못했습니다. 이름 입력 / 변경을 눌러 다시 시도하세요."


func _receive_native_nickname(value: String, form_id: int) -> void:
	if not is_instance_valid(nickname_form) or overlay != nickname_form or nickname_form.get_instance_id() != form_id:
		return
	var nickname := value.replace("\r", "").replace("\n", "").replace("\t", " ").strip_edges()
	nickname_draft = nickname
	if nickname.is_empty() or nickname.length() > 12:
		nickname_preview.text = "이름을 다시 입력해주세요"
		nickname_hint.text = "이름을 1~12자로 입력해주세요. 이름 입력 / 변경에서 수정할 수 있습니다."
		nickname_hint.add_theme_color_override("font_color", Color("#edab8e"))
		return
	nickname_preview.text = nickname
	nickname_hint.text = "이 이름으로 시작하려면 이야기 시작을 누르세요."
	nickname_hint.add_theme_color_override("font_color", Color("#b4beac"))


func _confirm_nickname() -> void:
	if nickname_dialog_open or not is_instance_valid(nickname_form) or overlay != nickname_form:
		return
	if nickname_draft.is_empty() or nickname_draft.length() > 12:
		nickname_hint.text = "이름을 1~12자로 입력해주세요."
		return
	progress.set_value("player", "name", nickname_draft)
	if progress.save(progress_path) != OK:
		nickname_hint.text = "이름을 저장하지 못했습니다. 다시 시도해주세요."
		return
	player_name = nickname_draft
	_close_overlay()
	_start_story(0)


func _start_story(at: int) -> void:
	_dispose_camp()
	if at == 0:
		campaign_clears = {"bedding": false, "drill": false, "shooting": false}
		progress.set_value("campaign", "clears", campaign_clears)
		progress.set_value("world", "active", false)
		var fresh_camp := ConfigFile.new()
		fresh_camp.save(camp_progress_path)
	busy = true
	var tween := create_tween()
	tween.tween_property(curtain, "modulate:a", 1.0, 0.85)
	await tween.finished
	title_ui.hide()
	dialogue_ui.show()
	state = "story"
	history.clear()
	current_scene = ""
	index = at - 1
	busy = false
	_advance()


func _advance() -> void:
	if busy:
		return
	cinematic_remaining = -1.0
	reaction_player.stop()
	voice_player.stop()
	pending_reaction = ""
	index += 1
	if index >= story.size():
		_ending()
		return
	busy = true
	var beat: Dictionary = story[index]
	var target_scene := str(beat.get("scene", current_scene))
	# Recover stage metadata when loading a saved position.
	if current_scene.is_empty():
		for i in range(index + 1):
			var previous: Dictionary = story[i]
			if previous.has("scene"):
				target_scene = str(previous.scene)
			if previous.has("chapter"):
				chapter_label.text = str(previous.chapter)
			if previous.has("location"):
				location_label.text = str(previous.location)
			if previous.has("music") and (i < index or previous.get("cue", "") != "horn"):
				_play_music(str(previous.music))
	if target_scene != current_scene:
		var fade := create_tween()
		fade.tween_property(curtain, "modulate:a", 1.0, 0.28)
		await fade.finished
		_set_background(target_scene)
	if beat.has("chapter"):
		chapter_label.text = str(beat.chapter)
	if beat.has("location"):
		location_label.text = str(beat.location)
	if beat.has("music") and beat.get("cue", "") != "horn":
		_play_music(str(beat.music))
	speaker_label.text = _names(str(beat.get("speaker", "")))
	full_text = _names(str(beat.get("text", "")))
	pending_reaction = str(beat.get("reaction", ""))
	dialogue_label.text = full_text
	aside_label.text = str(beat.get("aside", ""))
	typing = 0.0
	dialogue_label.visible_characters = 0
	next_label.hide()
	count_label.text = "PROLOGUE  /  %02d" % (index + 1)
	history.append(speaker_label.text + "\n" + full_text)
	progress.set_value("story", "index", index)
	progress.save(progress_path)
	var reveal := create_tween()
	reveal.tween_property(curtain, "modulate:a", 0.0, 0.40)
	await reveal.finished
	if beat.has("cue"):
		await _cue(str(beat.cue))
	if beat.has("auto_advance"):
		typing = full_text.length()
		dialogue_label.visible_characters = full_text.length()
		next_label.hide()
		cinematic_remaining = float(beat.auto_advance)
	busy = false


func _names(value: String) -> String:
	var korean_name := player_name.length() == 3
	for character in player_name:
		korean_name = korean_name and character.unicode_at(0) >= 0xAC00 and character.unicode_at(0) <= 0xD7A3
	var given := player_name.substr(1) if korean_name else player_name
	return value.replace("[name]", player_name).replace("[given]", given)


func _cue(cue: String) -> void:
	if cue == "impact":
		_sfx("impact")
		typing = float(full_text.length())
		var tween := create_tween()
		flash.modulate.a = 1.0
		tween.tween_property(flash, "modulate:a", 0.0, 0.24)
		for i in range(6):
			tween.tween_property(bg, "position", Vector2(randf_range(-18, 18), randf_range(-12, 12)), 0.04)
		tween.tween_property(curtain, "modulate:a", 1.0, 0.4)
		await tween.finished
		_set_background("black")
		curtain.modulate.a = 0.0
	elif cue == "horn":
		_play_music("silence")
		_sfx("horn")
		var tween := create_tween()
		tween.tween_property(flash, "modulate:a", 0.30, 0.1)
		tween.tween_property(flash, "modulate:a", 0.0, 0.45)
		await tween.finished
	elif cue == "reveille":
		_sfx("reveille")
	elif cue == "salute":
		_sfx("salute")
	elif cue == "ending":
		# The final line remains on screen until the player advances.
		pass


func _ending() -> void:
	busy = false
	if campaign_clears.bedding:
		_open_camp()
		return
	_start_bedding_quest()


func _start_bedding_quest() -> void:
	var run: Dictionary = training_progress.begin_run("bedding", "story")
	if run.ok:
		_offer_training_quest("bedding", str(run.token))


func _return_to_training_hub() -> void:
	_close_overlay()
	_dispose_camp()
	state = "title"
	title_ui.show()
	dialogue_ui.hide()
	_set_background("title")
	_play_music("title")
	_refresh_home_profile()
	resume_button.visible = int(progress.get_value("story", "index", -1)) >= 0
	_open_training_hub("training")


func _resume() -> void:
	if bool(progress.get_value("world", "active", false)) and campaign_clears.bedding:
		_open_camp()
		return
	_start_story(clampi(int(progress.get_value("story", "index", 0)), 0, story.size() - 1))


func _pause() -> void:
	if busy or is_instance_valid(overlay):
		return
	var box := _modal("잠깐 쉬어가기", "진행한 장면은 자동으로 저장됩니다.")
	box.add_child(_button("계속 보기", _close_overlay))
	box.add_child(_button("설정", func() -> void:
		_close_overlay()
		_settings()
	))
	box.add_child(_button("타이틀로", _return_title))


func _return_title() -> void:
	_close_overlay()
	_dispose_camp()
	index = -1
	busy = false
	_show_title()


func _open_training_hub(tab: String = "training") -> void:
	if busy or is_instance_valid(overlay):
		return
	if state == "camp" and is_instance_valid(camp_world):
		camp_world.suspended = true
	var hub := TrainingHub.new()
	hub.setup(training_progress, player_name, tab)
	hub.close_requested.connect(_close_overlay)
	hub.launch_requested.connect(_offer_training_quest)
	overlay = hub
	add_child(hub)


func _offer_training_quest(id: String, token: String) -> void:
	if not training_progress.sessions.has(token):
		return
	var from_story := state == "story"
	var from_camp := state == "camp"
	var mode: String = training_progress.sessions[token].mode
	_close_overlay()
	if from_camp and is_instance_valid(camp_world):
		camp_world.suspended = true
	var quest := QuestWindow.new()
	quest.setup(id, training_progress, mode == "replay")
	active_training_token = token
	overlay = quest
	quest.accepted.connect(func() -> void:
		if overlay != quest or not training_progress.sessions.has(token):
			return
		# Transfer the pending session to the game without cancelling it on close.
		active_training_token = ""
		_launch_training(id, token)
	)
	quest.dismissed.connect(func() -> void:
		if overlay != quest:
			return
		_close_overlay()
		if not from_story and not from_camp:
			_open_training_hub("training")
	)
	add_child(quest)


func _quick_shooting() -> void:
	if busy or is_instance_valid(overlay):
		return
	var run: Dictionary = training_progress.begin_run("shooting", "replay" if training_progress.cleared("shooting") else "story")
	if run.ok:
		_launch_training("shooting", str(run.token))


func _launch_training(id: String, token: String) -> void:
	var entry: Dictionary = training_progress.training(id)
	var packed := load(str(entry.scene)) as PackedScene
	if not packed:
		training_progress.cancel_run(token)
		return
	var game := packed.instantiate()
	if not game.has_method("setup_training") or not game.has_signal("finished"):
		training_progress.cancel_run(token)
		game.free()
		return
	var from_story := state == "story"
	var from_camp := state == "camp"
	_close_overlay()
	active_training_token = token
	game.setup_training(training_progress, token)
	state = "training"
	# Native-drawn training fields pass their pointer events through to unhandled_input.
	# Hide the previous screen so its buttons cannot intercept a shot behind the game.
	title_ui.hide()
	dialogue_ui.hide()
	if is_instance_valid(camp_world):
		camp_world.suspended = true
		camp_world.hide()
	effect_player.stop()
	reaction_player.stop()
	voice_player.stop()
	pending_reaction = ""
	_play_music(id)
	game.finished.connect(func() -> void:
		var return_home: bool = game.return_to_home
		var receipt: Dictionary = game.get("receipt")
		var passed: bool = bool(game.get("training_passed")) and bool(receipt.get("ok", false)) and bool(receipt.get("passed", false))
		var score: int = int(game.get("final_score"))
		if passed and (from_story or from_camp):
			_complete_campaign_training(id)
		_close_overlay()
		if from_camp:
			_open_camp()
			camp_world.on_training_return(id, passed, score)
		elif from_story and not return_home:
			state = "story"
			_play_music("training_morning")
			_ending()
			if is_instance_valid(camp_world):
				camp_world.on_training_return(id, passed, score)
		else:
			_return_to_training_hub()
	)
	overlay = game
	add_child(game)


func _open_camp(preview: bool = false) -> void:
	_close_overlay()
	busy = false
	state = "camp"
	title_ui.hide()
	dialogue_ui.hide()
	curtain.modulate.a = 0.0
	_play_music("training_morning")
	if not is_instance_valid(camp_world):
		camp_world = CampWorld.new()
		camp_world.setup(training_progress, player_name, preview, campaign_clears)
		camp_world.save_path = camp_progress_path
		camp_world.training_requested.connect(func(id: String) -> void:
			if is_instance_valid(overlay) or camp_world.preview:
				return
			var run: Dictionary = training_progress.begin_run(id, "replay" if training_progress.cleared(id) else "story")
			if run.ok:
				_offer_training_quest(id, str(run.token))
		)
		camp_world.hub_requested.connect(_open_training_hub)
		camp_world.exit_requested.connect(_return_title)
		add_child(camp_world)
	camp_world.show()
	camp_world.suspended = false
	if not preview:
		progress.set_value("world", "active", true)
		progress.save(progress_path)


func _complete_campaign_training(id: String) -> void:
	if not campaign_clears.has(id):
		return
	campaign_clears[id] = true
	progress.set_value("campaign", "clears", campaign_clears)
	progress.save(progress_path)


func _dispose_camp() -> void:
	if is_instance_valid(camp_world):
		camp_world.save_position()
		camp_world.hide()
		camp_world.queue_free()
	camp_world = null


func _settings() -> void:
	var box := _modal("설정", "F11 키로 전체 화면을 전환할 수 있습니다.")
	box.add_child(_label("전체 음량", 18, PAPER))
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.01
	volume.value = master_volume
	volume.value_changed.connect(func(value: float) -> void:
		master_volume = value
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.001)))
		progress.set_value("settings", "volume", value)
		progress.save(progress_path)
	)
	box.add_child(volume)
	box.add_child(_label("대사 표시 속도", 18, PAPER))
	var speed := HSlider.new()
	speed.min_value = 15
	speed.max_value = 90
	speed.value = text_speed
	speed.value_changed.connect(func(value: float) -> void:
		text_speed = value
		progress.set_value("settings", "text_speed", value)
		progress.save(progress_path)
	)
	box.add_child(speed)
	box.add_child(_button("닫기", _close_overlay))


func _show_history() -> void:
	if busy or is_instance_valid(overlay):
		return
	var box := _modal("대화 기록", "최근에 읽은 장면부터 표시합니다.")
	var log := RichTextLabel.new()
	log.custom_minimum_size = Vector2(620, 330)
	log.add_theme_font_size_override("normal_font_size", 19)
	for i in range(history.size() - 1, -1, -1):
		log.add_text(history[i] + "\n\n")
	box.add_child(log)
	box.add_child(_button("닫기", _close_overlay))


func _modal(heading: String, description: String) -> VBoxContainer:
	_close_overlay()
	overlay = Control.new()
	_full(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade := ColorRect.new()
	_full(shade)
	shade.color = Color(0.01, 0.02, 0.015, 0.84)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	var center := CenterContainer.new()
	_full(center)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 610
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)
	box.add_child(_label(heading, 30, PAPER))
	var desc := _label(description, 17, Color("#bec8b6"))
	box.add_child(desc)
	return box


func _close_overlay() -> void:
	if not active_training_token.is_empty():
		training_progress.cancel_run(active_training_token)
		active_training_token = ""
	if is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	if state == "camp" and is_instance_valid(camp_world):
		camp_world.suspended = false
	_refresh_home_profile()


func _refresh_home_profile() -> void:
	if not is_instance_valid(home_profile_label):
		return
	home_profile_label.text = player_name + (" · 에이스" if training_progress.equipped("ace_badge") else "")
	home_balance_label.text = "%d  %s" % [training_progress.profile.coins, training_progress.catalog.currency_name]
	if is_instance_valid(camp_button):
		var unlocked: bool = campaign_clears.bedding or int(progress.get_value("story", "index", -1)) >= story.size() - 1
		camp_button.text = "훈련소 탐색" if unlocked else "훈련소 미리보기"


func _button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 42
	result.add_theme_font_size_override("font_size", 17)
	result.add_theme_color_override("font_color", PAPER)
	for key in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#394539") if key in ["hover", "focus"] else Color(0.08, 0.12, 0.09, 0.88)
		style.border_color = GOLD if key in ["hover", "focus"] else Color("#616c56")
		style.set_border_width_all(1)
		style.content_margin_left = 18
		style.content_margin_right = 18
		result.add_theme_stylebox_override(key, style)
	result.pressed.connect(action)
	return result


func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	result.add_theme_constant_override("shadow_offset_y", 2)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#1d2922")
	box.border_color = Color("#9e946f")
	box.set_border_width_all(1)
	box.content_margin_left = 30
	box.content_margin_right = 30
	box.content_margin_top = 26
	box.content_margin_bottom = 26
	return box


func _full(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _play_music(key: String) -> void:
	if key == current_music:
		return
	current_music = key
	var next_path := str(MUSIC.get(key, ""))
	var target_volume := -15.0 if key == "shooting" else -6.0
	# Morning and farewell share one track and retain the current playback position.
	if music_player.playing and music_player.stream and music_player.stream.resource_path == next_path:
		if is_instance_valid(music_fade):
			music_fade.kill()
		music_fade = create_tween()
		music_fade.tween_property(music_player, "volume_db", target_volume, 0.35)
		return
	if is_instance_valid(music_fade):
		music_fade.kill()
	music_player.stop()
	music_player.stream = null
	if not next_path.is_empty() and ResourceLoader.exists(next_path):
		music_player.stream = load(next_path)
		if music_player.stream is AudioStreamMP3 or music_player.stream is AudioStreamOggVorbis:
			music_player.stream.loop = true
		music_player.volume_db = -36.0
		music_player.play()
		music_fade = create_tween()
		music_fade.tween_property(music_player, "volume_db", target_volume, 0.75)


func _loop_music() -> void:
	if current_music != "silence" and music_player.stream:
		music_player.play()


func _sfx(kind: String) -> void:
	var path := ""
	var volume := -6.0
	if kind == "salute":
		# Recorded Korean dialogue can be supplied in any supported format.
		for extension in ["ogg", "mp3", "wav"]:
			var candidate: String = "res://assets/audio/salute." + str(extension)
			if ResourceLoader.exists(candidate):
				path = candidate
				break
	elif RECORDED_SFX.has(kind):
		path = str(RECORDED_SFX[kind].file)
		volume = float(RECORDED_SFX[kind].volume_db)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var player := effect_player
	if kind == "laugh":
		player = reaction_player
	elif kind == "salute":
		player = voice_player
	else:
		active_effect = kind
	if kind in ["horn", "impact"]:
		reaction_player.stop()
		voice_player.stop()
		pending_reaction = ""
	player.stream = load(path)
	player.volume_db = volume
	player.play()

