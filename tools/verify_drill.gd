extends SceneTree

const Store := preload("res://scripts/training_progress.gd")
var failures: Array[String] = []
var path := "res://.godot/drill-check-%d.cfg" % Time.get_ticks_usec()
var game: Control
var store: RefCounted
var held: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func key(code: Key, down: bool = true) -> void:
	if held.get(code, false) == down:
		return
	held[code] = down
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: Key) -> void:
	key(code, true)
	key(code, false)

func release() -> void:
	for code in held.keys():
		key(code, false)

func click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func advance(seconds: float) -> void:
	for i in range(ceili(seconds / 0.05)):
		game._process(0.05)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/30-drill-" + name + ".png")

func face_target() -> void:
	var difference := posmod(game.target_direction - game.player_direction, 4)
	if difference == 3:
		tap(KEY_Q)
	else:
		for i in range(difference):
			tap(KEY_E)

func _run() -> void:
	store = Store.new(path)
	# Prepared bedding food must remain untouched by drill practice and evaluation.
	store.profile.quantities.choco_pie = 2
	store.assign_quick_slot(0, "choco_pie")
	var run: Dictionary = store.begin_run("drill")
	game = load("res://scenes/training/drill.tscn").instantiate()
	game.setup_training(store, run.token)
	root.add_child(game)
	game.set_process(false)
	game.step_player.volume_db = -80
	await process_frame
	check(game.phase == "practice" and not store.sessions[run.token].active and store.profile.coins == 0, "Practice activated or rewarded a run")
	await capture("practice")
	tap(KEY_E)
	advance(0.7)
	check(game.practice_step == 1 and game.player_direction == 1, "Rotation input did not complete first practice")
	click(game.target_position)
	advance(0.2)
	var walking_from: Vector2 = game.player_position
	tap(KEY_Q)
	check(game.has_move_target and game.player_direction == 0, "Rotation cancelled click movement")
	advance(0.2)
	check(game.player_position.distance_to(walking_from) > 10, "Click movement stopped during rotation")
	advance(2.0)
	check(game.practice_step == 2 and game.player_position.distance_to(game.target_position) < 4, "Click movement did not reach practice target")
	check(store.profile.coins == 0 and store.quantity("choco_pie") == 2, "Practice granted coins or consumed food")
	game._start_assessment()
	check(game.commands.size() == 14 and store.sessions[game.token].active, "Assessment did not initialize 14 scored commands")
	check(store.quantity("choco_pie") == 2 and store.profile.quick_slots[0] == "choco_pie", "Training auto-used a recovery item or changed its quick slot")
	var before: int = game.player_direction
	tap(KEY_E)
	check(game.early_action and game.player_direction == before, "Early turn was not blocked/marked")
	game.request_pause()
	var clock: float = game.phase_time
	var location: Vector2 = game.player_position
	key(KEY_D, true)
	advance(1.0)
	key(KEY_D, false)
	check(game.phase == "paused" and game.phase_time == clock and game.player_position == location, "Pause allowed timer or movement")
	game.request_pause()
	check(game.phase == "cue" and not is_instance_valid(game.popup), "Pause did not toggle back")
	advance(2.0)
	face_target()
	advance(0.6)
	check(game.round_scores.size() == 1 and game.round_scores[0].early and game.round_scores[0].score <= 88, "Early penalty not reflected in round score")
	# Complete a full assessment using actual movement and turn input, not fabricated scores.
	game._retry(false)
	var screenshots := {"turn": false, "march": false, "mixed": false}
	var cycles := 0
	var save_failed := false
	while game.phase != "result" and cycles < 5000:
		cycles += 1
		if game.phase == "action":
			if game.command_index == 13 and game.phase_time > 6 and not save_failed:
				store.save_path = path + "/missing/profile.cfg"
				save_failed = true
			face_target()
			var delta_position: Vector2 = game.target_position - game.player_position
			key(KEY_A, delta_position.x < -6)
			key(KEY_D, delta_position.x > 6)
			key(KEY_W, delta_position.y < -6)
			key(KEY_S, delta_position.y > 6)
			if game.command.kind == "turn" and not screenshots.turn:
				await capture("turn")
				screenshots.turn = true
			if game.command.kind == "march" and game.phase_time > 4 and not screenshots.march:
				await capture("formation")
				screenshots.march = true
			if game.stage == 2 and game.command.kind == "march" and game.phase_time > 3 and not screenshots.mixed:
				await capture("mixed")
				screenshots.mixed = true
		else:
			release()
		game._process(0.05)
		release()
	check(cycles < 5000 and game.phase == "result", "Full evaluation never completed")
	check(game.training_passed and game.final_score >= 95, "Accurate play failed to achieve S grade: %d" % game.final_score)
	check(save_failed and not game.receipt.ok and store.profile.coins == 0 and store.sessions.has(game.token), "Save failure paid or discarded retryable result")
	store.save_path = path
	game._settle()
	check(store.cleared("drill") and store.profile.coins == 175, "First S clear did not reward/unlock")
	check(game.round_scores.size() == 14 and game.final_breakdown.complete, "Assessment skipped required commands")
	check(game.total_time >= 90 and game.total_time <= 180, "Evaluation duration outside intended 1.5–3 minutes")
	await capture("result")
	check(not store.finish_run(game.token, 100, true).ok, "Duplicate drill settlement paid twice")
	game._settle()
	check(game.receipt.ok and game.receipt.passed, "Duplicate result callback destroyed the successful receipt")
	var balance: int = store.profile.coins
	game._retry(true)
	check(game.phase == "practice" and game.round_scores.is_empty() and not store.sessions[game.token].active, "Retry with practice kept old score or activated early")
	game._start_assessment()
	# Standing still throughout the complete course must fail without rewards.
	cycles = 0
	while game.phase != "result" and cycles < 5000:
		cycles += 1
		game._process(0.1)
	check(not game.training_passed and game.final_score < game.pass_score and store.profile.coins == balance, "Idle play passed or earned coins")
	# Neither turning alone nor moving alone can bypass the combined skill requirement.
	for strategy in ["turn_only", "move_only"]:
		game._retry(false)
		cycles = 0
		while game.phase != "result" and cycles < 5000:
			cycles += 1
			if game.phase == "action":
				if strategy == "turn_only":
					face_target()
				else:
					var delta_position: Vector2 = game.target_position - game.player_position
					key(KEY_A, delta_position.x < -6)
					key(KEY_D, delta_position.x > 6)
					key(KEY_W, delta_position.y < -6)
					key(KEY_S, delta_position.y > 6)
			game._process(0.05)
			release()
		check(not game.training_passed and store.profile.coins == balance, strategy + " bypassed the evaluation")
	game._retry(false)
	game._finish_assessment()
	check(not game.training_passed and store.profile.coins == balance, "Incomplete assessment passed or earned coins")
	game._retry(false)
	var cancelled: String = game.token
	game._leave()
	check(not store.sessions.has(cancelled), "Exit leaked active drill session")
	game.queue_free()
	await process_frame
	var reloaded := Store.new(path)
	check(reloaded.cleared("drill") and reloaded.profile.coins == balance, "Drill result lost on reload")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for message in failures:
		push_error(message)
	print("DRILL_CHECK ", "PASS" if failures.is_empty() else "FAIL", " — practice inputs, cue/early penalty, pause toggle, full movement course, scoring, rewards, idle failure, incomplete failure, retry, exit and reload")
	quit(0 if failures.is_empty() else 1)
