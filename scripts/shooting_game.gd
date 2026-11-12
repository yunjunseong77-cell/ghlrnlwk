extends Control

signal finished

const HEADING := preload("res://assets/fonts/BlackHanSans-Regular.ttf")
const PAPER := Color("#f5ecd7")
const GOLD := Color("#ffc96d")
const TEAL := Color("#9fe5c4")
const MUTED := Color("#b4b9a9")
const INK := Color("#101c1a")
const FIELD := Rect2(70, 160, 1140, 410)
const DURATION := 45.0
const MAGAZINE := 8
const RELOAD_TIME := 0.85
const MIN_HITS := 18
const STAGES := ["01  ·  POP-UP", "02  ·  MOVING", "03  ·  RUSH"]
const STAGE_HINTS := ["가까운 표적부터. 중앙을 맞히면 PERFECT!", "움직임을 읽고 한 발씩. 명중을 이어가세요.", "먼저 사라질 표적부터. 콤보를 끝까지 지키세요."]

var store: RefCounted
var token := ""
var run_mode := "story"
var return_to_home := false
var training_passed := false
var final_score := 0
var receipt: Dictionary = {}
var phase := "ready"
var pass_score := 70
var popup: Control
var elapsed := 0.0
var time_left := DURATION
var stage := 0
var wave := 0
var ammo := MAGAZINE
var reload_left := 0.0
var fire_cooldown := 0.0
var spawn_delay := 0.0
var shots := 0
var hits := 0
var perfects := 0
var expired := 0
var combo := 0
var best_combo := 0
var raw_score := 0
var aim := Vector2(640, 360)
var recoil := 0.0
var hit_flash := 0.0
var hit_point := Vector2.ZERO
var last_perfect := false
var stage_flash := 0.0
var targets: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var marks: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var background: Texture2D
var weapon: Texture2D
var target_texture: Texture2D
var shot_players: Array[AudioStreamPlayer] = []
var audio_index := 0
var hit_player: AudioStreamPlayer
var reload_player: AudioStreamPlayer
var score_label: Label
var record_label: Label
var timer_label: Label
var combo_label: Label
var ammo_label: Label
var stage_label: Label
var hint_label: Label
var precision_label: Label
var start_button: Button

func setup_training(progress_store: RefCounted, session_token: String) -> void:
	store = progress_store
	token = session_token
	run_mode = str(store.sessions[token].mode)
	pass_score = int(store.training("shooting").get("quest", {}).get("pass_score", 70))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.randomize()
	if ResourceLoader.exists("res://assets/art/shooting/range.png"):
		background = load("res://assets/art/shooting/range.png")
	if ResourceLoader.exists("res://assets/art/shooting/weapon.png"):
		weapon = load("res://assets/art/shooting/weapon.png")
	if ResourceLoader.exists("res://assets/art/shooting/target.png"):
		var source := load("res://assets/art/shooting/target.png") as Texture2D
		var trimmed := AtlasTexture.new()
		trimmed.atlas = source
		trimmed.region = source.get_image().get_used_rect()
		target_texture = trimmed
	for i in range(8):
		var player := _sound("res://assets/audio/title_shot.ogg", -15.0)
		shot_players.append(player)
	hit_player = _sound("res://assets/audio/shoot_hit.ogg", -12.0)
	reload_player = _sound("res://assets/audio/shoot_reload.ogg", -12.0)
	_build_ui()
	_show_ready()
	_refresh_ui()

func _sound(path: String, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = volume
	if ResourceLoader.exists(path):
		player.stream = load(path)
	add_child(player)
	return player

func _show_ready() -> void:
	var box := _popup("한 발의 감각", "45초. 표적을 쓰러뜨리고, 명중을 이어가세요.")
	box.add_child(_label("중앙 명중 PERFECT   ·   연속 명중 최대 ×5", 24, GOLD))
	box.add_child(_label("왼쪽 클릭 사격     R 재장전     Esc 일시정지\n8발을 모두 쓰면 자동 재장전합니다.", 18, MUTED))
	box.add_child(_label("합격: 18개 이상 명중 + 평가 %d점\n멈추지 않고 맞힐수록 새 표적이 빠르게 등장합니다." % pass_score, 17, PAPER))
	start_button = _button("사격 시작", _start_run)
	box.add_child(start_button)
	box.add_child(_button("돌아가기", _leave, false))

func _start_run() -> void:
	if phase == "playing":
		return
	var activated: Dictionary = store.activate_run(token)
	if not activated.ok:
		var box := _popup("시작을 저장하지 못했습니다", str(activated.message))
		box.add_child(_button("다시 시도", _start_run))
		box.add_child(_button("돌아가기", _leave, false))
		return
	_close_popup()
	phase = "playing"
	elapsed = 0.0
	time_left = DURATION
	stage = 0
	wave = 0
	ammo = MAGAZINE
	reload_left = 0.0
	fire_cooldown = 0.0
	spawn_delay = 0.0
	shots = 0
	hits = 0
	perfects = 0
	expired = 0
	combo = 0
	best_combo = 0
	raw_score = 0
	recoil = 0.0
	hit_flash = 0.0
	stage_flash = 1.5
	targets.clear()
	particles.clear()
	popups.clear()
	marks.clear()
	receipt.clear()
	training_passed = false
	final_score = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_spawn_wave()
	_refresh_ui()

func _process(delta: float) -> void:
	if phase != "playing":
		queue_redraw()
		return
	elapsed += delta
	time_left = maxf(0, DURATION - elapsed)
	fire_cooldown = maxf(0, fire_cooldown - delta)
	recoil = maxf(0, recoil - delta * 7.0)
	hit_flash = maxf(0, hit_flash - delta)
	stage_flash = maxf(0, stage_flash - delta)
	if reload_left > 0.0:
		reload_left = maxf(0, reload_left - delta)
		if reload_left == 0.0:
			ammo = MAGAZINE
	var new_stage := mini(2, int(elapsed / 15.0))
	if new_stage != stage:
		stage = new_stage
		stage_flash = 1.7
	_tick_targets(delta)
	_tick_effects(delta)
	if _live_targets() == 0:
		spawn_delay -= delta
		if spawn_delay <= 0.0 and time_left > 0.35:
			_spawn_wave()
	if time_left <= 0.0:
		_finish_run()
	_refresh_ui()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode else event.keycode
		if key == KEY_ESCAPE and phase in ["playing", "paused"]:
			request_pause()
			get_viewport().set_input_as_handled()
		elif key == KEY_R and phase == "playing":
			_reload()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		aim = make_input_local(event).position
		if phase == "playing":
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if FIELD.has_point(aim) else Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event: InputEvent) -> void:
	if phase != "playing" or is_instance_valid(popup):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		aim = make_input_local(event).position
		if FIELD.has_point(aim):
			_fire(aim)
			get_viewport().set_input_as_handled()

func _spawn_wave() -> void:
	wave += 1
	spawn_delay = 0.12
	var count := 3 + stage
	var slots := [170.0, 390.0, 620.0, 850.0, 1090.0]
	slots.shuffle()
	for i in range(count):
		var scale_factor := rng.randf_range(0.88, 1.18) if stage > 0 else rng.randf_range(1.08, 1.25)
		var base := Vector2(float(slots[i]) + rng.randf_range(-12, 12), rng.randf_range(315, 425))
		var moving := stage == 1 or (stage == 2 and i % 2 == 0)
		var amplitude := rng.randf_range(30, 65) if moving else 0.0
		targets.append({"base": base, "pos": base, "scale": scale_factor, "age": 0.0, "ttl": 5.0 - stage * 0.55 + i * 0.15, "amplitude": amplitude, "speed": rng.randf_range(1.5, 2.3), "seed": rng.randf_range(0, TAU), "dead": false, "fall": 0.0, "expired": false, "impact": Vector2.ZERO, "perfect": false})

func _live_targets() -> int:
	var count := 0
	for target in targets:
		if not target.dead:
			count += 1
	return count

func _tick_targets(delta: float) -> void:
	for target in targets:
		if target.dead:
			target.fall += delta
			continue
		target.age += delta
		target.pos = target.base + Vector2(sin(float(target.age) * float(target.speed) + float(target.seed)) * float(target.amplitude), 0)
		if float(target.age) >= float(target.ttl):
			target.dead = true
			target.expired = true
			expired += 1
			_break_combo()
	targets = targets.filter(func(target: Dictionary) -> bool: return not target.dead or float(target.fall) < 0.32)

func target_center(target: Dictionary) -> Vector2:
	return Vector2(target.pos) + Vector2(0, -10.0 * float(target.scale))

func target_contains(target: Dictionary, point: Vector2) -> bool:
	if target.dead or float(target.age) < 0.12:
		return false
	var local: Vector2 = (point - Vector2(target.pos)) / float(target.scale)
	return Rect2(-38, -36, 76, 89).has_point(local) or local.distance_to(Vector2(0, -53)) <= 23.0

func _fire(point: Vector2) -> void:
	if phase != "playing" or reload_left > 0 or fire_cooldown > 0:
		return
	if ammo <= 0:
		_reload()
		return
	shots += 1
	ammo -= 1
	fire_cooldown = 0.12
	recoil = 1.0
	var player := shot_players[audio_index % shot_players.size()]
	audio_index += 1
	player.pitch_scale = rng.randf_range(0.98, 1.025)
	if player.stream:
		player.play()
	particles.append({"kind": "case", "pos": _muzzle_position() + Vector2(125, 60), "velocity": Vector2(rng.randf_range(100, 185), rng.randf_range(-210, -140)), "life": 0.65, "max_life": 0.65})
	particles.append({"kind": "trace", "pos": point, "velocity": Vector2.ZERO, "life": 0.035, "max_life": 0.035})
	var struck: Dictionary = {}
	for i in range(targets.size() - 1, -1, -1):
		if target_contains(targets[i], point):
			struck = targets[i]
			break
	if not struck.is_empty():
		var perfect := point.distance_to(target_center(struck)) <= 17.0 * float(struck.scale)
		struck.dead = true
		struck.impact = (point - Vector2(struck.pos)) / float(struck.scale)
		struck.perfect = perfect
		hits += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		if perfect:
			perfects += 1
		var multiplier := 1 + mini(4, int(combo / 6))
		var points := (180 if perfect else 100) * multiplier
		raw_score += points
		hit_point = point
		hit_flash = 0.19
		last_perfect = perfect
		if hit_player.stream:
			hit_player.pitch_scale = 1.12 if perfect else 0.95
			hit_player.play()
		var popup_position := point + Vector2(0, -46)
		# A fresh hit replaces nearby floating text so rapid shots stay readable.
		popups = popups.filter(func(entry: Dictionary) -> bool:
			var difference: Vector2 = Vector2(entry.pos) - popup_position
			return absf(difference.x) >= 170 or absf(difference.y) >= 64
		)
		popups.append({"pos": popup_position, "text": "PERFECT +%d" % points if perfect else "+%d" % points, "life": 0.72, "perfect": perfect})
		for i in range(7 if perfect else 4):
			particles.append({"kind": "chip", "pos": point, "velocity": Vector2(rng.randf_range(-110, 110), rng.randf_range(-150, 15)), "life": 0.35, "max_life": 0.35})
	else:
		_break_combo()
		marks.append({"pos": point, "life": 1.0})
		for i in range(4):
			particles.append({"kind": "dust", "pos": point, "velocity": Vector2(rng.randf_range(-45, 45), rng.randf_range(-50, -10)), "life": 0.3, "max_life": 0.3})
	if ammo == 0:
		_reload()
	_refresh_ui()
	queue_redraw()

func _break_combo() -> void:
	if combo >= 3:
		popups.append({"pos": Vector2(640, 180), "text": "COMBO BREAK", "life": 0.8, "perfect": false})
	combo = 0

func _reload() -> void:
	if phase != "playing" or ammo >= MAGAZINE or reload_left > 0:
		return
	reload_left = RELOAD_TIME
	if reload_player.stream:
		reload_player.play()

func _tick_effects(delta: float) -> void:
	for particle in particles:
		particle.life -= delta
		if particle.kind != "trace":
			particle.velocity.y += 440 * delta
			particle.pos += Vector2(particle.velocity) * delta
	particles = particles.filter(func(particle: Dictionary) -> bool: return float(particle.life) > 0)
	for entry in popups:
		entry.life -= delta
		entry.pos.y -= 30 * delta
	popups = popups.filter(func(entry: Dictionary) -> bool: return float(entry.life) > 0)
	for mark in marks:
		mark.life -= delta
	marks = marks.filter(func(mark: Dictionary) -> bool: return float(mark.life) > 0)

func accuracy() -> float:
	return float(hits) / maxi(shots, 1)

func _finish_run() -> void:
	if phase != "playing":
		return
	phase = "result"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	final_score = roundi(accuracy() * 60.0 + minf(float(hits) / 35.0, 1.0) * 20.0 + float(perfects) / maxi(hits, 1) * 20.0)
	training_passed = elapsed >= DURATION - 0.05 and hits >= MIN_HITS and final_score >= pass_score
	_settle()

func _settle() -> void:
	if not bool(receipt.get("ok", false)):
		receipt = store.finish_run(token, final_score, training_passed, {"raw_points": raw_score, "best_combo": best_combo})
	_show_result()

func _show_result() -> void:
	var headline := "사격 종료" if receipt.get("ok", false) else "결과 저장 대기"
	var description := "조교: 방금 그 사격, 처음 해본 솜씨가 아닌데?" if training_passed else "다음 한 발은 더 정확하게. 가까운 표적부터 노려 보세요."
	var box := _popup(headline, description)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)
	var grade := _label(store.grade(final_score) if training_passed else "RETRY", 58 if training_passed else 37, GOLD)
	grade.add_theme_font_override("font", HEADING)
	row.add_child(grade)
	row.add_child(_label("%s POINTS\n평가 %d점  ·  %s" % [_number(raw_score), final_score, "합격" if training_passed else "재도전"], 25, PAPER))
	box.add_child(_label("명중 %d / %d발    정확도 %d%%    PERFECT %d\n최고 %d COMBO    놓친 표적 %d" % [hits, shots, roundi(accuracy() * 100), perfects, best_combo, expired], 20, MUTED))
	box.add_child(_label("평가: 정확도 60% · 명중량 20% · 중앙 명중 20%", 15, MUTED))
	if receipt.get("ok", false):
		if training_passed:
			if receipt.get("new_personal_best", false):
				var previous := int(receipt.get("previous_best_points", 0))
				box.add_child(_label("NEW RECORD  +%s" % _number(raw_score - previous) if previous > 0 else "첫 사격 기록을 세웠습니다!", 20, TEAL))
			else:
				box.add_child(_label("개인 최고 %s점  ·  최고 %d COMBO" % [_number(int(receipt.get("best_points", raw_score))), int(receipt.get("best_combo", best_combo))], 17, TEAL))
			box.add_child(_label("+%d %s%s" % [receipt.reward, store.catalog.currency_name, "  ·  사격 재도전 해금" if receipt.first_clear else ""], 22, GOLD))
		else:
			box.add_child(_label("18개 이상 명중 + 평가 %d점이면 통과합니다." % pass_score, 17, MUTED))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 14)
		box.add_child(actions)
		actions.add_child(_button("한 판 더", _retry))
		actions.add_child(_button("훈련 마치기", func() -> void:
			return_to_home = false
			finished.emit()
		, false))
	else:
		box.add_child(_label(str(receipt.get("message", "저장을 다시 시도해 주세요.")), 17, GOLD))
		box.add_child(_button("저장 다시 시도", _settle))
		box.add_child(_button("나가기", _leave, false))

func _retry() -> void:
	store.cancel_run(token)
	var run: Dictionary = store.begin_run("shooting", run_mode)
	if not run.ok:
		return
	token = str(run.token)
	return_to_home = false
	phase = "ready"
	_start_run()

func request_pause() -> void:
	if phase == "paused":
		_close_popup()
		phase = "playing"
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		return
	if phase != "playing":
		return
	phase = "paused"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var box := _popup("잠깐 쉬어가기", "남은 시간과 표적이 멈춰 있습니다.")
	box.add_child(_button("계속 사격", request_pause))
	box.add_child(_button("처음부터 다시", _retry, false))
	box.add_child(_button("훈련 나가기", _leave, false))

func _leave() -> void:
	store.cancel_run(token)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	return_to_home = true
	finished.emit()

func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if store:
		store.cancel_run(token)

func _build_ui() -> void:
	var title := _label("사격장", 33, PAPER, Vector2(28, 20))
	title.add_theme_font_override("font", HEADING)
	add_child(title)
	stage_label = _label("", 13, GOLD, Vector2(30, 65))
	add_child(stage_label)
	record_label = _label("", 12, MUTED, Vector2(363, 19))
	add_child(record_label)
	score_label = _label("0", 34, PAPER, Vector2(360, 39))
	add_child(score_label)
	combo_label = _label("", 23, GOLD, Vector2(594, 39))
	add_child(combo_label)
	add_child(_label("TIME", 12, MUTED, Vector2(913, 19)))
	timer_label = _label("45.0", 34, PAPER, Vector2(908, 39))
	add_child(timer_label)
	var pause := _button("일시정지", request_pause, false)
	pause.position = Vector2(1110, 27)
	pause.size = Vector2(143, 48)
	add_child(pause)
	add_child(_label("AMMO", 12, MUTED, Vector2(31, 638)))
	ammo_label = _label("", 35, PAPER, Vector2(28, 653))
	add_child(ammo_label)
	precision_label = _label("", 14, PAPER, Vector2(272, 648))
	add_child(precision_label)
	hint_label = _label("", 14, MUTED, Vector2(272, 678))
	add_child(hint_label)
	add_child(_label("LMB 사격   ·   R 재장전   ·   Esc 일시정지", 13, MUTED, Vector2(911, 683)))

func _refresh_ui() -> void:
	if not is_instance_valid(score_label):
		return
	score_label.text = _number(raw_score)
	var best_points := int(store.profile.records.get("shooting", {}).get("best_raw_points", 0))
	record_label.text = "SCORE   ·   BEST %s" % _number(best_points) if best_points > 0 else "SCORE"
	timer_label.text = "%04.1f" % time_left
	timer_label.add_theme_color_override("font_color", GOLD if time_left < 10 else PAPER)
	combo_label.text = "%d COMBO  ×%d" % [combo, 1 + mini(4, int(combo / 6))] if combo >= 2 else ""
	stage_label.text = STAGES[stage]
	ammo_label.text = "재장전" if reload_left > 0 else "%02d / 08" % ammo
	ammo_label.add_theme_color_override("font_color", GOLD if ammo <= 2 or reload_left > 0 else PAPER)
	precision_label.text = "명중 %d    PERFECT %d    정확도 %d%%" % [hits, perfects, roundi(accuracy() * 100)]
	hint_label.text = STAGE_HINTS[stage]

func _number(value: int) -> String:
	var text := str(value)
	var result := ""
	for i in range(text.length()):
		if i > 0 and (text.length() - i) % 3 == 0:
			result += ","
		result += text[i]
	return result

func _draw() -> void:
	if background:
		draw_texture_rect(background, Rect2(0, 0, 1280, 720), false)
	else:
		draw_rect(Rect2(0, 0, 1280, 720), Color("#a8b69b"))
		draw_rect(Rect2(0, 240, 1280, 480), Color("#8a8063"))
		for x in range(60, 1280, 160):
			draw_line(Vector2(x, 620), Vector2(640 + (x - 640) * 0.6, 255), Color("#c4bfa5"), 2)
	# Quiet, translucent framing leaves the range as the largest area of the screen.
	draw_rect(Rect2(0, 0, 1280, 108), Color(0.025, 0.065, 0.055, 0.94))
	draw_line(Vector2(0, 108), Vector2(1280, 108), Color("#8eaa8c"), 1)
	for i in range(3):
		var x := 28.0 + i * 414.0
		draw_rect(Rect2(x, 113, 396, 3), Color(0.08, 0.14, 0.10, 0.65))
		var progress := clampf((elapsed - i * 15.0) / 15.0, 0, 1)
		draw_rect(Rect2(x, 113, 396 * progress, 3), GOLD if i == 2 else TEAL)
	var sorted := targets.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector2(a.pos).y < Vector2(b.pos).y)
	for target in sorted:
		_draw_target(target)
	for mark in marks:
		draw_circle(mark.pos, 4, Color(0.1, 0.09, 0.06, float(mark.life) * 0.6))
	_draw_weapon()
	for particle in particles:
		var alpha: float = clampf(float(particle.life) / float(particle.max_life), 0, 1)
		var pos: Vector2 = particle.pos
		if particle.kind == "trace":
			draw_line(_muzzle_position(), pos, Color(1, 0.86, 0.55, alpha * 0.5), 1.5, true)
		elif particle.kind == "case":
			draw_set_transform(pos, float(particle.life) * 15.0)
			draw_rect(Rect2(-5, -2, 10, 4), Color(0.88, 0.64, 0.26, alpha))
			draw_set_transform(Vector2.ZERO)
		elif particle.kind == "chip":
			draw_rect(Rect2(pos, Vector2(4, 3)), Color(1, 0.86, 0.62, alpha))
		else:
			draw_circle(pos, 8 * (1 - alpha) + 2, Color(0.75, 0.66, 0.46, alpha * 0.5))
	for entry in popups:
		var color := GOLD if entry.perfect else PAPER
		color.a = minf(1, float(entry.life) * 3)
		_center_text(str(entry.text), entry.pos, 22 if entry.perfect else 18, color)
	draw_rect(Rect2(0, 624, 1280, 96), Color(0.025, 0.065, 0.055, 0.95))
	draw_line(Vector2(0, 624), Vector2(1280, 624), Color("#8eaa8c"), 1)
	if reload_left > 0:
		draw_rect(Rect2(31, 705, 180, 3), Color("#45554b"))
		draw_rect(Rect2(31, 705, 180 * (1 - reload_left / RELOAD_TIME), 3), GOLD)
	if phase == "playing":
		_draw_crosshair()
		if stage_flash > 0:
			var alpha := minf(1, stage_flash)
			_center_text(["팝업 표적", "움직이는 표적", "마지막 15초 · RUSH"][stage], Vector2(640, 154), 22, Color(1, 0.89, 0.65, alpha))

func _draw_target(target: Dictionary) -> void:
	var pos: Vector2 = target.pos
	var scale_factor: float = target.scale
	var emerge := clampf(float(target.age) / 0.16, 0, 1)
	var fall: float = clampf(float(target.fall) / 0.28, 0, 1) if target.dead else 0.0
	var squash := maxf(0.04, emerge * (1 - fall))
	var color := Color("#d7c6a4")
	if target.dead and not target.expired:
		color = Color("#ffdb8b") if target.perfect else Color("#b5d9ba")
	color.a = 1.0 - fall
	draw_set_transform(pos + Vector2(4, 68 * scale_factor), 0, Vector2(scale_factor, scale_factor * 0.15))
	draw_circle(Vector2.ZERO, 47, Color(0.08, 0.11, 0.07, 0.27))
	draw_set_transform(pos + Vector2(0, 68 * scale_factor), 0, Vector2(scale_factor, scale_factor))
	draw_rect(Rect2(-4, -83, 8, 82), Color("#3a3c32"))
	draw_set_transform(pos + Vector2(0, (1 - squash) * 54 * scale_factor), fall * 0.12, Vector2(scale_factor, scale_factor * squash))
	var shape := PackedVector2Array([Vector2(-40, 53), Vector2(-40, -28), Vector2(-24, -40), Vector2(-24, -56), Vector2(-18, -73), Vector2(18, -73), Vector2(24, -56), Vector2(24, -40), Vector2(40, -28), Vector2(40, 53)])
	var inset := PackedVector2Array([Vector2(-36, 49), Vector2(-36, -26), Vector2(-20, -37), Vector2(-20, -55), Vector2(-15, -68), Vector2(15, -68), Vector2(20, -55), Vector2(20, -37), Vector2(36, -26), Vector2(36, 49)])
	if target_texture:
		draw_texture_rect(target_texture, Rect2(-40, -73, 80, 126), false, Color(1, 1, 1, color.a))
	else:
		draw_colored_polygon(shape, Color("#3c4436"))
		draw_colored_polygon(inset, color)
		for y in range(-28, 50, 10):
			draw_line(Vector2(-32, y), Vector2(32, y), Color(0.35, 0.29, 0.18, 0.09 * color.a), 1)
	draw_circle(Vector2(0, -10), 28, Color(0.28, 0.32, 0.25, color.a), true, -1.0, true)
	draw_circle(Vector2(0, -10), 23, Color(0.75, 0.70, 0.55, color.a), true, -1.0, true)
	draw_circle(Vector2(0, -10), 17, Color(0.67, 0.25, 0.13, color.a), true, -1.0, true)
	draw_arc(Vector2(0, -10), 9, 0, TAU, 32, Color(1, 0.84, 0.49, color.a), 1.1, true)
	draw_circle(Vector2(0, -10), 3, Color(1, 0.86, 0.57, color.a), true, -1.0, true)
	draw_circle(Vector2(0, -53), 7, Color(0.3, 0.32, 0.25, color.a), true, -1.0, true)
	if target.dead and not target.expired:
		draw_polyline(PackedVector2Array([Vector2(-40, 53), Vector2(-40, -28), Vector2(-24, -40), Vector2(-24, -56), Vector2(-18, -73), Vector2(18, -73), Vector2(24, -56), Vector2(24, -40), Vector2(40, -28), Vector2(40, 53), Vector2(-40, 53)]), Color(1.0, 0.84, 0.42, color.a) if target.perfect else Color(0.62, 0.96, 0.78, color.a), 3.0, true)
		draw_circle(target.impact, 5, Color(0.10, 0.12, 0.08, color.a))
		draw_arc(target.impact, 7, 0, TAU, 10, Color(1, 0.86, 0.6, color.a), 1.5)
	if not target.dead:
		var life := clampf(1 - float(target.age) / float(target.ttl), 0, 1)
		draw_rect(Rect2(-28, 60, 56, 3), Color(0.1, 0.15, 0.1, 0.8))
		draw_rect(Rect2(-28, 60, 56 * life, 3), GOLD if life < 0.3 else TEAL)
	draw_set_transform(Vector2.ZERO)

func _weapon_rect() -> Rect2:
	var offset := Vector2((aim.x - 640) * 0.012, (aim.y - 360) * 0.008 + recoil * 18)
	if reload_left > 0:
		offset.y += sin((1 - reload_left / RELOAD_TIME) * PI) * 100
	var target_size := Vector2(444, 250)
	if weapon:
		var texture_size := weapon.get_size()
		target_size = texture_size * minf(455.0 / texture_size.x, 250.0 / texture_size.y)
	return Rect2(Vector2(1280 - target_size.x, 490) + offset, target_size)

func _muzzle_position() -> Vector2:
	var rect := _weapon_rect()
	return rect.position + rect.size * Vector2(0.233, 0.260)

func _draw_weapon() -> void:
	var rect := _weapon_rect()
	if weapon:
		draw_texture_rect(weapon, rect, false)
	else:
		# The gameplay stays usable while project art is importing.
		draw_set_transform(rect.position + Vector2(240, 178), -0.30)
		draw_colored_polygon(PackedVector2Array([Vector2(-19, -89), Vector2(18, -89), Vector2(47, 8), Vector2(84, 84), Vector2(-65, 84), Vector2(-36, 12)]), Color("#28342f"))
		draw_rect(Rect2(-9, -140, 18, 65), Color("#151d1a"))
		draw_rect(Rect2(-22, -50, 45, 72), Color("#424c3f"))
		draw_set_transform(Vector2.ZERO)
	if recoil > 0.68:
		var flash_pos := _muzzle_position()
		draw_colored_polygon(PackedVector2Array([flash_pos + Vector2(0, -30), flash_pos + Vector2(7, -6), flash_pos + Vector2(28, 0), flash_pos + Vector2(7, 7), flash_pos + Vector2(0, 22), flash_pos + Vector2(-7, 6), flash_pos + Vector2(-25, 0), flash_pos + Vector2(-7, -6)]), Color(1, 0.81, 0.35, 0.8))
		draw_circle(flash_pos, 7, Color(1, 0.98, 0.78, 0.9))

func _draw_crosshair() -> void:
	if not FIELD.has_point(aim):
		return
	var gap := 5.0 + recoil * 4.0
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(aim + direction * gap, aim + direction * (gap + 8), Color(0.02, 0.04, 0.03, 0.85), 4, true)
		draw_line(aim + direction * gap, aim + direction * (gap + 8), PAPER, 1.6, true)
	draw_circle(aim, 1.3, PAPER)
	if hit_flash > 0:
		var color := GOLD if last_perfect else TEAL
		for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(hit_point + direction * 7, hit_point + direction * 13, color, 2.5, true)

func _center_text(text: String, position: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var point := position - Vector2(extent.x / 2, 0)
	draw_string_outline(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0.02, 0.045, 0.03, color.a * 0.85))
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _popup(title: String, description: String) -> VBoxContainer:
	_close_popup()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(popup)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.04, 0.03, 0.76)
	popup.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 750
	var style := _style(true)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 27
	style.content_margin_bottom = 27
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 19)
	panel.add_child(box)
	var heading := _label(title, 34, PAPER)
	heading.add_theme_font_override("font", HEADING)
	box.add_child(heading)
	box.add_child(_label(description, 18, MUTED))
	return box

func _close_popup() -> void:
	if is_instance_valid(popup):
		popup.queue_free()
	popup = null

func _style(accent: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#172d24") if accent else Color("#17231e")
	style.border_color = Color("#8ea18a") if accent else Color("#52675a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 17
	style.content_margin_right = 17
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style

func _label(text: String, font_size: int, color: Color, position_value: Vector2 = Vector2.ZERO) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable, accent: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", GOLD if accent else PAPER)
	button.add_theme_stylebox_override("normal", _style(accent))
	button.add_theme_stylebox_override("hover", _style(true))
	button.add_theme_stylebox_override("pressed", _style(false))
	button.pressed.connect(action)
	return button
