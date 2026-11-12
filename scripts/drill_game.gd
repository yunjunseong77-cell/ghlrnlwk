extends Control

signal finished

const FIELD := Rect2(364, 126, 892, 498)
const MAP := preload("res://assets/art/world/recruit_camp.png")
const SOLDIER := preload("res://assets/art/world/recruit_walk.png")
const HEADING := preload("res://assets/fonts/BlackHanSans-Regular.ttf")
const APPEARANCE := preload("res://scripts/soldier_appearance.gd")
const PAPER := Color("#f3f0df")
const GOLD := Color("#e4be7a")
const TEAL := Color("#9ee2d0")
const MUTED := Color("#aebeb1")
const RED := Color("#efad91")
const SLOT_OFFSET := Vector2(0, 55)
const SPEED := 178.0
const PASS_SCORE := 75
const DIR_NAMES := ["앞쪽 ↑", "오른쪽 →", "뒤쪽 ↓", "왼쪽 ←"]
const PEER_OFFSETS := [Vector2(-110, -45), Vector2(0, -45), Vector2(110, -45), Vector2(-110, 55), Vector2(110, 55)]

var store: RefCounted
var token := ""
var run_mode := "story"
var return_to_home := false
var training_passed := false
var phase := "practice"
var paused_phase := "practice"
var pass_score := PASS_SCORE
var popup: Control
var rng := RandomNumberGenerator.new()
var player_position := Vector2(805, 395)
var player_direction := 0
var formation_origin := Vector2(805, 340)
var formation_direction := 0
var target_direction := 0
var target_position := Vector2(805, 395)
var move_target := Vector2.ZERO
var has_move_target := false
var player_moving := false
var commands: Array[Dictionary] = []
var command: Dictionary = {}
var command_index := -1
var stage := 0
var practice_step := 0
var phase_time := 0.0
var total_time := 0.0
var elapsed := 0.0
var correct_hold := 0.0
var acted_after_go := false
var early_action := false
var round_resolved := false
var route: PackedVector2Array = []
var route_lengths: Array[float] = []
var route_length := 0.0
var position_integral := 0.0
var facing_integral := 0.0
var samples := 0.0
var previous_position := Vector2.ZERO
var round_scores: Array[Dictionary] = []
var feedback := ""
var feedback_color := TEAL
var impact := 0.0
var final_score := 0
var final_breakdown: Dictionary = {}
var receipt: Dictionary = {}
var loadout: Dictionary = {}
var step_player: AudioStreamPlayer
var step_clock := 0.0

var stage_label: Label
var instruction_label: Label
var cue_label: Label
var direction_label: Label
var guidance_label: Label
var phase_label: Label
var counter_label: Label
var timer_label: Label
var score_label: Label
var feedback_label: Label
var practice_button: Button
var practice_hint: Label

func setup_training(progress_store: RefCounted, session_token: String) -> void:
	store = progress_store
	token = session_token
	run_mode = str(store.sessions[token].mode)
	pass_score = int(store.training("drill").get("quest", {}).get("pass_score", PASS_SCORE))
	loadout = store.profile.equipment.duplicate()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.randomize()
	step_player = AudioStreamPlayer.new()
	step_player.volume_db = -13.0
	if ResourceLoader.exists("res://assets/audio/drill_step.ogg"):
		step_player.stream = load("res://assets/audio/drill_step.ogg")
	add_child(step_player)
	_build_ui()
	_start_practice()

func _start_practice() -> void:
	_close_popup()
	phase = "practice"
	practice_step = 0
	player_direction = 0
	formation_direction = 0
	formation_origin = Vector2(805, 340)
	player_position = formation_origin + SLOT_OFFSET
	target_position = player_position
	target_direction = 1
	correct_hold = 0.0
	has_move_target = false
	feedback = "연습에서는 점수와 보상이 변하지 않습니다."
	_update_ui()

func _process(delta: float) -> void:
	elapsed += delta
	impact = maxf(0, impact - delta * 1.8)
	if phase in ["practice", "cue", "action", "feedback"]:
		phase_time += delta
		if phase != "practice":
			total_time += delta
		_update_movement(delta)
		if phase == "practice":
			_tick_practice(delta)
		elif phase == "cue" and phase_time >= float(command.cue_time):
			phase = "action"
			phase_time = 0.0
			acted_after_go = false
			feedback = "실시! 지금 움직입니다."
			feedback_color = TEAL
			impact = 0.6
		elif phase == "action":
			_tick_action(delta)
		elif phase == "feedback" and phase_time >= 1.25:
			_next_command()
	_update_ui()
	queue_redraw()

func _update_movement(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if phase == "cue":
		if direction.length_squared() > 0:
			_mark_early()
		player_moving = false
		return
	if phase == "feedback":
		player_moving = false
		return
	if direction.length_squared() > 0:
		has_move_target = false
	elif has_move_target:
		if player_position.distance_to(move_target) < 3:
			has_move_target = false
		else:
			direction = player_position.direction_to(move_target)
	var speed := SPEED
	if has_move_target:
		speed = minf(speed, player_position.distance_to(move_target) / maxf(delta, 0.001))
	previous_position = player_position
	player_position += direction.normalized() * speed * delta
	player_position = player_position.clamp(FIELD.position + Vector2(26, 75), FIELD.end - Vector2(26, 25))
	player_moving = player_position.distance_to(previous_position) > 0.1
	if player_moving:
		step_clock += delta
		if step_clock >= 0.48 and step_player.stream:
			step_clock = 0.0
			step_player.play()
	else:
		step_clock = 0.36

func _input(event: InputEvent) -> void:
	if not visible or is_instance_valid(popup):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in [KEY_Q, KEY_E]:
			_rotate(-1 if key == KEY_Q else 1)
			get_viewport().set_input_as_handled()
		elif key == KEY_SPACE:
			has_move_target = false
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or is_instance_valid(popup):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := make_input_local(event) as InputEventMouseButton
		if FIELD.has_point(local.position):
			if phase == "cue":
				_mark_early()
			elif phase in ["action", "practice"]:
				move_target = local.position.clamp(FIELD.position + Vector2(26, 75), FIELD.end - Vector2(26, 25))
				has_move_target = true
			get_viewport().set_input_as_handled()

func _rotate(amount: int) -> void:
	if phase == "cue":
		_mark_early()
		return
	if phase not in ["action", "practice"]:
		return
	player_direction = posmod(player_direction + amount, 4)
	acted_after_go = true
	impact = 0.3
	if phase == "action" and command.kind == "turn" and player_direction != target_direction:
		feedback = "방향을 확인하고 Q / E로 바로잡으세요."
		feedback_color = GOLD

func _mark_early() -> void:
	early_action = true
	feedback = "아직 준비 구령입니다. 청록색 ‘실시’를 기다리세요."
	feedback_color = GOLD

func _tick_practice(delta: float) -> void:
	if practice_step == 0:
		target_direction = 1
		if player_direction == target_direction:
			correct_hold += delta
			if correct_hold >= 0.6:
				practice_step = 1
				correct_hold = 0.0
				target_position = Vector2(990, 450)
				feedback = "좋습니다. 이제 자리까지 이동해 봅니다."
		else:
			correct_hold = 0.0
	elif practice_step == 1:
		if player_position.distance_to(target_position) < 25 and not player_moving:
			correct_hold += delta
			if correct_hold >= 0.5:
				practice_step = 2
				feedback = "조작 연습 완료! 평가 시작을 눌러 실력을 보여주세요."
		else:
			correct_hold = 0.0

func _start_assessment() -> void:
	var activated: Dictionary = store.activate_run(token)
	if not activated.ok:
		phase = "blocked"
		var box := _popup("평가 시작 대기", str(activated.message))
		box.add_child(_button("다시 시도", _start_assessment))
		box.add_child(_button("나가기", _leave))
		return
	_close_popup()
	loadout = store.profile.equipment.duplicate()
	commands.clear()
	var turns: Array[int] = [1, -1, 2, 1, -1]
	turns.shuffle()
	for turn in turns:
		commands.append({"stage": 0, "kind": "turn", "turn": turn, "cue_time": 1.65, "duration": 4.5})
	for i in range(3):
		commands.append({"stage": 1, "kind": "march", "corners": 1 if i == 0 else 2, "cue_time": 1.65, "duration": 12.0})
	for i in range(6):
		if i % 2 == 0:
			commands.append({"stage": 2, "kind": "turn", "turn": turns[(i + 1) % turns.size()], "cue_time": rng.randf_range(1.2, 1.9), "duration": 3.8})
		else:
			commands.append({"stage": 2, "kind": "march", "corners": 2, "cue_time": 1.4, "duration": 9.5})
	formation_origin = Vector2(805, 340)
	player_position = formation_origin + SLOT_OFFSET
	player_direction = 0
	formation_direction = 0
	command_index = -1
	round_scores.clear()
	total_time = 0.0
	training_passed = false
	return_to_home = false
	receipt.clear()
	_next_command()

func _next_command() -> void:
	command_index += 1
	if command_index >= commands.size():
		_finish_assessment()
		return
	command = commands[command_index]
	stage = int(command.stage)
	phase = "cue"
	phase_time = 0
	correct_hold = 0
	early_action = false
	acted_after_go = false
	round_resolved = false
	has_move_target = false
	position_integral = 0
	facing_integral = 0
	samples = 0
	target_position = formation_origin + SLOT_OFFSET
	feedback = "준비 구령을 듣고, 실시 신호에 맞춰 움직입니다."
	feedback_color = GOLD
	if command.kind == "turn":
		target_direction = posmod(formation_direction + int(command.turn), 4)
		route.clear()
	else:
		_build_route(int(command.corners))
		target_direction = _direction_for(route[1] - route[0])

func _build_route(corners: int) -> void:
	var anchors: Array[Vector2] = [Vector2(640, 300), Vector2(1015, 300), Vector2(1015, 445), Vector2(640, 445)]
	route = PackedVector2Array([formation_origin])
	var closest := 0
	var distance := INF
	for i in anchors.size():
		if formation_origin.distance_to(anchors[i]) < distance:
			distance = formation_origin.distance_to(anchors[i])
			closest = i
	var direction := 1 if rng.randi_range(0, 1) == 0 else -1
	for i in range(corners):
		route.append(anchors[posmod(closest + direction * (i + 1), 4)])
	route_lengths.clear()
	route_length = 0.0
	for i in range(1, route.size()):
		var length := route[i].distance_to(route[i - 1])
		route_lengths.append(length)
		route_length += length

func _direction_for(vector: Vector2) -> int:
	if absf(vector.x) > absf(vector.y):
		return 1 if vector.x > 0 else 3
	return 2 if vector.y > 0 else 0

func _route_position(fraction: float) -> Vector2:
	var remaining := clampf(fraction, 0, 1) * route_length
	for i in route_lengths.size():
		if remaining <= route_lengths[i] or i == route_lengths.size() - 1:
			target_direction = _direction_for(route[i + 1] - route[i])
			return route[i].lerp(route[i + 1], clampf(remaining / maxf(route_lengths[i], 0.01), 0, 1))
		remaining -= route_lengths[i]
	return route[-1]

func _tick_action(delta: float) -> void:
	if command.kind == "turn":
		var aligned := player_direction == target_direction and player_position.distance_to(target_position) < 28 and not player_moving and acted_after_go
		if aligned:
			correct_hold += delta
		else:
			correct_hold = 0
		if correct_hold >= 0.42:
			var timing := clampf(100.0 - maxf(0, phase_time - 1.1) * 23.0, 0, 100)
			_resolve_round(100, 100, timing, "정확한 방향, 흐트러짐 없는 자세!")
		elif phase_time >= float(command.duration):
			var face_score := 100.0 if player_direction == target_direction and acted_after_go else 0.0
			var position_score := _position_score(player_position.distance_to(target_position))
			var explanation := "방향을 확인하세요. Q / E로 90°씩 회전합니다."
			if face_score > 0:
				explanation = "자기 자리에서 멈춰 자세를 유지하세요."
			_resolve_round(position_score, face_score, 0, explanation)
	else:
		var travel_time := float(command.duration) - 2.0
		formation_origin = _route_position(phase_time / travel_time)
		formation_direction = target_direction
		target_position = formation_origin + SLOT_OFFSET
		if phase_time > 1.1:
			position_integral += _position_score(player_position.distance_to(target_position)) * delta
			facing_integral += (100.0 if player_direction == target_direction else 0.0) * delta
			samples += delta
		if phase_time >= travel_time:
			feedback = "제자리 정지! 원 안에서 멈추고 방향을 유지합니다."
			feedback_color = TEAL
		else:
			var distance := player_position.distance_to(target_position)
			feedback = "간격 안정 · 그대로 따라갑니다." if distance < 30 else "자기 자리 원 안으로! 간격을 좁히세요."
			feedback_color = TEAL if distance < 30 else GOLD
			if player_direction != target_direction:
				feedback = "이동 방향에 맞춰 몸도 회전하세요. Q / E"
				feedback_color = GOLD
		if phase_time >= float(command.duration):
			var stop := 100.0 if not player_moving and player_position.distance_to(target_position) < 30 else 0.0
			_resolve_round(position_integral / maxf(samples, 0.01), facing_integral / maxf(samples, 0.01), stop, "이동 구간 완료 · 간격과 방향을 함께 확인합니다.")

func _position_score(distance: float) -> float:
	return clampf(100.0 - maxf(distance - 17.0, 0) * 1.6, 0, 100)

func _resolve_round(position_score: float, face_score: float, timing_score: float, explanation: String) -> void:
	if round_resolved:
		return
	round_resolved = true
	var score := 0.0
	if command.kind == "turn":
		score = position_score * 0.20 + face_score * 0.60 + timing_score * 0.20
	else:
		score = position_score * 0.65 + face_score * 0.25 + timing_score * 0.10
	if early_action:
		score = maxf(0, score - 12)
	round_scores.append({"stage": stage, "kind": command.kind, "score": roundi(score), "position": position_score, "facing": face_score, "timing": timing_score, "early": early_action})
	formation_direction = target_direction
	phase = "feedback"
	phase_time = 0
	has_move_target = false
	player_moving = false
	feedback = ("%d점 · " % roundi(score)) + ("준비 구령 중 움직임 −12점. " if early_action else "") + explanation
	feedback_color = TEAL if score >= 75 else RED
	impact = 1.0

func breakdown() -> Dictionary:
	var total := 0.0
	var directions := 0.0
	var formation := 0.0
	var timing := 0.0
	var early := 0
	var stages := [0.0, 0.0, 0.0]
	var counts := [0, 0, 0]
	for result in round_scores:
		total += float(result.score)
		directions += float(result.facing)
		formation += float(result.position)
		timing += float(result.timing)
		early += 1 if result.early else 0
		stages[int(result.stage)] += float(result.score)
		counts[int(result.stage)] += 1
	for i in range(3):
		stages[i] = roundi(float(stages[i]) / maxi(int(counts[i]), 1))
	var count := maxi(round_scores.size(), 1)
	return {"score": roundi(total / count), "direction": roundi(directions / count), "formation": roundi(formation / count), "timing": roundi(timing / count), "early": early, "stages": stages, "complete": commands.size() == 14 and round_scores.size() == commands.size()}

func _finish_assessment() -> void:
	phase = "result"
	has_move_target = false
	player_moving = false
	final_breakdown = breakdown()
	final_score = int(final_breakdown.score)
	training_passed = bool(final_breakdown.complete) and final_score >= pass_score
	_settle()

func _settle() -> void:
	if bool(receipt.get("ok", false)):
		return
	receipt = store.finish_run(token, final_score, training_passed)
	_show_result()

func _show_result() -> void:
	var headline := "몸이 기억하는 제식" if training_passed else "한 번 더, 대형을 맞춰"
	if not receipt.ok:
		headline = "결과 저장 대기"
	var description := "조교: 동작이 좋다. 다음에도 이 정도는 보여줘야지." if training_passed else "방향은 Q/E, 자리는 WASD. 실시 신호 이후 정확하게 움직여 보세요."
	var box := _popup(headline, description)
	var result_row := HBoxContainer.new()
	result_row.add_theme_constant_override("separation", 32)
	box.add_child(result_row)
	var grade := _label(store.grade(final_score), 68, GOLD)
	grade.add_theme_font_override("font", HEADING)
	result_row.add_child(grade)
	var text := "%d점 / 합격 %d점\n방향 %d · 간격 %d · 반응/정지 %d\n성급한 동작 %d회 · 총 %.0f초" % [final_score, pass_score, final_breakdown.direction, final_breakdown.formation, final_breakdown.timing, final_breakdown.early, total_time]
	result_row.add_child(_label(text, 20, PAPER))
	var stages_text := "방향 전환 %d점     대형 이동 %d점     종합 평가 %d점" % [final_breakdown.stages[0], final_breakdown.stages[1], final_breakdown.stages[2]]
	box.add_child(_label(stages_text, 17, MUTED))
	if receipt.ok:
		if training_passed:
			box.add_child(_label("+%d %s%s" % [receipt.reward, store.catalog.currency_name, " · 제식 재도전 해금" if receipt.first_clear else ""], 23, GOLD))
		else:
			box.add_child(_label("이번 평가에는 보상이 없습니다. 연습부터 다시 할 수도 있습니다.", 16, MUTED))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 12)
		box.add_child(actions)
		actions.add_child(_button("평가 재도전", _retry.bind(false)))
		actions.add_child(_button("동작 연습", _retry.bind(true)))
		actions.add_child(_button("훈련 마치기", func() -> void:
			return_to_home = false
			finished.emit()
		))
	else:
		box.add_child(_label(str(receipt.message), 17, GOLD))
		box.add_child(_button("저장 다시 시도", _settle))
		box.add_child(_button("나가기", _leave))

func _retry(with_practice: bool = false) -> void:
	store.cancel_run(token)
	var run: Dictionary = store.begin_run("drill", run_mode)
	if not run.ok:
		return
	token = str(run.token)
	_close_popup()
	commands.clear()
	command.clear()
	round_scores.clear()
	receipt.clear()
	command_index = -1
	training_passed = false
	return_to_home = false
	phase_time = 0
	if with_practice:
		_start_practice()
	else:
		_start_assessment()

func request_pause() -> void:
	if phase == "paused":
		_close_popup()
		phase = paused_phase
		return
	if phase not in ["practice", "cue", "action", "feedback"]:
		return
	paused_phase = phase
	phase = "paused"
	step_player.stop()
	var box := _popup("잠깐 쉬어가기", "구령과 대형 이동이 멈춰 있습니다. Esc로 계속할 수 있습니다.")
	box.add_child(_button("계속하기", request_pause))
	box.add_child(_button("동작 연습부터", _retry.bind(true)))
	box.add_child(_button("훈련 나가기", _leave))

func _leave() -> void:
	store.cancel_run(token)
	return_to_home = true
	finished.emit()

func _exit_tree() -> void:
	if store:
		store.cancel_run(token)

func _build_ui() -> void:
	var title := _label("제식 훈련", 35, PAPER, Vector2(28, 22))
	title.add_theme_font_override("font", HEADING)
	add_child(title)
	add_child(_label("구령을 듣고, 자리를 지키고, 몸으로 증명한다.", 15, MUTED, Vector2(30, 70)))
	counter_label = _label("", 16, GOLD, Vector2(610, 30))
	add_child(counter_label)
	timer_label = _label("", 14, MUTED, Vector2(610, 63))
	add_child(timer_label)
	score_label = _label("", 25, PAPER, Vector2(892, 30))
	add_child(score_label)
	var pause := _button("일시정지", request_pause)
	pause.position = Vector2(1110, 27)
	pause.size = Vector2(145, 50)
	add_child(pause)
	stage_label = _label("", 15, GOLD, Vector2(44, 145))
	add_child(stage_label)
	instruction_label = _label("", 26, PAPER, Vector2(44, 182))
	instruction_label.add_theme_font_override("font", HEADING)
	instruction_label.size = Vector2(278, 76)
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(instruction_label)
	phase_label = _label("", 14, GOLD, Vector2(44, 272))
	add_child(phase_label)
	cue_label = _label("", 32, PAPER, Vector2(44, 306))
	cue_label.add_theme_font_override("font", HEADING)
	add_child(cue_label)
	direction_label = _label("", 20, TEAL, Vector2(44, 367))
	add_child(direction_label)
	guidance_label = _label("", 17, MUTED, Vector2(44, 409))
	guidance_label.size = Vector2(272, 113)
	guidance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(guidance_label)
	practice_button = _button("평가 시작", _start_assessment)
	practice_button.position = Vector2(44, 552)
	practice_button.size = Vector2(276, 48)
	add_child(practice_button)
	practice_hint = _label("", 14, MUTED, Vector2(44, 552))
	practice_hint.size = Vector2(272, 48)
	practice_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(practice_hint)
	feedback_label = _label("", 17, TEAL, Vector2(382, 642))
	feedback_label.size = Vector2(854, 46)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(feedback_label)
	add_child(_label("WASD / 방향키 · 클릭 이동     Q / E 90° 회전     Space 클릭 이동 정지     Esc 일시정지", 14, MUTED, Vector2(28, 695)))

func _update_ui() -> void:
	if not is_instance_valid(stage_label):
		return
	var practice := phase == "practice" or (phase == "paused" and paused_phase == "practice")
	practice_button.visible = practice
	practice_hint.visible = not practice
	if practice:
		practice_button.text = "평가 시작" if practice_step == 2 else "연습 건너뛰고 평가"
		stage_label.text = "동작 연습 · 무보상"
		instruction_label.text = ["몸의 방향부터\n맞춰봅시다", "내 자리까지\n이동해 봅시다", "준비 완료.\n이제 평가입니다"][practice_step]
		phase_label.text = "시간 제한 없는 연습"
		cue_label.text = ["오른쪽 보기", "원 안에 정지", "평가 시작 ↓"][practice_step]
		direction_label.text = "바라볼 방향  " + DIR_NAMES[target_direction]
		guidance_label.text = "Q는 왼쪽, E는 오른쪽으로\n90° 회전합니다.\n이동해도 몸의 방향은 유지됩니다." if practice_step == 0 else "WASD 또는 바닥 클릭으로 이동.\n청록색 원이 내 자리입니다.\nSpace를 누르면 클릭 이동 정지."
		counter_label.text = "조작을 익힌 뒤 평가 시작"
		timer_label.text = "연습은 기록과 보상을 바꾸지 않습니다."
		score_label.text = "목표 %d점" % pass_score
	else:
		stage_label.text = ["01 · 제자리 방향 전환", "02 · 이동 대형 유지", "03 · 종합 평가"][stage]
		instruction_label.text = "구령 끝까지 듣고\n정확한 방향으로" if command.get("kind", "turn") == "turn" else "원 안에서 함께\n대형을 유지하라"
		phase_label.text = "준비 구령 · 아직 움직이지 않습니다" if phase == "cue" else ("실시 · 지금 동작합니다" if phase == "action" else "동작 확인")
		phase_label.add_theme_color_override("font_color", GOLD if phase == "cue" else TEAL)
		if command.get("kind", "turn") == "turn":
			var turn := int(command.get("turn", 1))
			cue_label.text = ("우향—" if turn == 1 else ("좌향—" if turn == -1 else "뒤로—")) if phase == "cue" else ("우!" if turn == 1 else ("좌!" if turn == -1 else "돌아!"))
			guidance_label.text = "Q / E로 몸을 돌리고\n자기 자리에서 잠깐 멈춥니다.\n틀려도 시간 안에 바로잡으세요."
		else:
			cue_label.text = "대형 이동—" if phase == "cue" else ("제자리 정지!" if phase_time >= float(command.get("duration", 12)) - 2.0 else "출발!")
			guidance_label.text = "움직이는 원을 따라갑니다.\nWASD 이동 + Q / E 회전.\n경로가 꺾이면 방향도 바꿉니다."
		direction_label.text = "바라볼 방향  " + DIR_NAMES[target_direction]
		counter_label.text = "동작 %02d / %02d" % [mini(command_index + 1, commands.size()), commands.size()]
		timer_label.text = "진행 %d:%02d  ·  합격 %d점" % [int(total_time) / 60, int(total_time) % 60, pass_score]
		var current := breakdown()
		score_label.text = "평균 %d점" % current.score if not round_scores.is_empty() else "평가 중"
		practice_hint.text = "지나친 움직임보다 정확한 간격.\n준비 구령 중 동작은 −12점."
	feedback_label.text = feedback
	feedback_label.add_theme_color_override("font_color", feedback_color)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#0b1713"))
	draw_rect(Rect2(0, 101, 1280, 1), Color("#486353"))
	draw_style_box(_panel(Color("#14271f")), Rect2(24, 126, 316, 498))
	var texture_size := MAP.get_size()
	var crop := Rect2(texture_size * Vector2(0.344, 0.405), texture_size * Vector2(0.316, 0.27))
	draw_texture_rect_region(MAP, FIELD, crop, Color(0.83, 0.87, 0.78))
	draw_rect(FIELD, Color("#71846c"), false, 1)
	for i in range(3):
		var filled := stage > i or (stage == i and phase not in ["practice", "paused"])
		draw_rect(Rect2(374 + i * 291, 110, 277, 4), TEAL if filled else Color("#30463a"))
	if route.size() > 1 and phase not in ["practice", "result"]:
		for i in range(1, route.size()):
			draw_dashed_line(route[i - 1] + SLOT_OFFSET, route[i] + SLOT_OFFSET, Color(0.15, 0.31, 0.23, 0.58), 2, 10, true)
			draw_circle(route[i] + SLOT_OFFSET, 5, Color("#e8d8a6"))
	var glow := TEAL if phase != "cue" else GOLD
	var slot := target_position
	draw_set_transform(slot, 0, Vector2(1, 0.48))
	draw_circle(Vector2.ZERO, 32, Color(glow, 0.14 + impact * 0.12))
	draw_arc(Vector2.ZERO, 31 + impact * 8, 0, TAU, 64, Color(glow, 0.9), 2, true)
	draw_arc(Vector2.ZERO, 17, 0, TAU, 48, Color(glow, 0.42), 1, true)
	draw_set_transform(Vector2.ZERO)
	_draw_direction(slot + Vector2(0, -6), target_direction, glow, 25)
	var actors: Array[Dictionary] = []
	for offset in PEER_OFFSETS:
		actors.append({"position": formation_origin + offset, "direction": formation_direction, "player": false})
	actors.append({"position": player_position, "direction": player_direction, "player": true})
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.position.y < b.position.y)
	for actor in actors:
		_draw_soldier(actor.position, int(actor.direction), bool(actor.player))
	var progress := 0.0
	if phase == "cue":
		progress = phase_time / maxf(float(command.get("cue_time", 1)), 0.01)
	elif phase == "action":
		progress = 1.0 - phase_time / maxf(float(command.get("duration", 1)), 0.01)
	elif phase == "feedback":
		progress = 1.0
	draw_rect(Rect2(44, 521, 276, 4), Color("#2e4538"))
	draw_rect(Rect2(44, 521, 276 * clampf(progress, 0, 1), 4), GOLD if phase == "cue" else TEAL)
	if has_move_target and phase in ["action", "practice"]:
		draw_arc(move_target, 8, 0, TAU, 24, Color("#f1e3be"), 1.5, true)

func _draw_soldier(point: Vector2, direction: int, is_player: bool) -> void:
	var moving: bool = player_moving if is_player else phase == "action" and command.get("kind", "") == "march" and phase_time < float(command.get("duration", 12)) - 2
	var row := 1 + int(elapsed * 4.2) % 2 if moving else 0
	var column: int = [3, 2, 0, 1][direction]
	var cell := SOLDIER.get_size() / Vector2(4, 3)
	draw_set_transform(point, 0, Vector2(1, 0.42))
	draw_circle(Vector2.ZERO, 18, Color(0.04, 0.08, 0.04, 0.28))
	if is_player:
		draw_arc(Vector2.ZERO, 23, 0, TAU, 40, TEAL, 2, true)
	draw_set_transform(Vector2.ZERO)
	draw_set_transform(point + Vector2(0, -1), 0, Vector2(1.1, 1.1))
	APPEARANCE.draw_character(self, loadout if is_player else {}, column, row, Color.WHITE if is_player else Color("#bac1a6"))
	draw_set_transform(Vector2.ZERO)
	if is_player:
		draw_string(ThemeDB.fallback_font, point + Vector2(-9, 22), "나", HORIZONTAL_ALIGNMENT_CENTER, 18, 15, Color("#143c2e"))

func _draw_direction(point: Vector2, direction: int, color: Color, length: float) -> void:
	var vector: Vector2 = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][direction]
	var side := Vector2(-vector.y, vector.x)
	var tip := point + vector * length
	draw_line(point, tip, color, 3, true)
	draw_line(tip, tip - vector * 8 + side * 6, color, 3, true)
	draw_line(tip, tip - vector * 8 - side * 6, color, 3, true)

func _popup(heading: String, description: String) -> VBoxContainer:
	_close_popup()
	popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(popup)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.035, 0.025, 0.87)
	popup.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 760
	panel.add_theme_stylebox_override("panel", _panel(Color("#15291f"), 26))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)
	var title := _label(heading, 32, PAPER)
	title.add_theme_font_override("font", HEADING)
	box.add_child(title)
	var info := _label(description, 18, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", PAPER)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _panel(Color("#3a5948") if state in ["hover", "focus"] else Color("#243e31"), 12))
	button.pressed.connect(callback)
	return button

func _panel(color: Color, margin: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("#6b856d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style
