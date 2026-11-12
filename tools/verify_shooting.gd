extends SceneTree

const Store := preload("res://scripts/training_progress.gd")
var failures: Array[String] = []
var path := "res://.godot/shooting-check-%d.cfg" % Time.get_ticks_usec()
var game: Control
var store: RefCounted

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func tap(key: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func advance(seconds: float) -> void:
	for i in range(ceili(seconds / 0.05)):
		game._process(0.05)

func capture(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		game.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/" + filename + ".png")

func target() -> Dictionary:
	for entry in game.targets:
		if not entry.dead and float(entry.age) >= 0.16:
			return entry
	return {}

func button_in(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := button_in(child, text)
		if found:
			return found
	return null

func _run() -> void:
	store = Store.new(path)
	store.profile.quantities.choco_pie = 2
	store.assign_quick_slot(0, "choco_pie")
	var run: Dictionary = store.begin_run("shooting")
	game = load("res://scenes/training/shooting.tscn").instantiate()
	game.setup_training(store, run.token)
	root.add_child(game)
	game.set_process(false)
	AudioServer.set_bus_mute(0, true)
	await process_frame
	check(game.phase == "ready" and not store.sessions[run.token].active and store.profile.coins == 0, "Opening shooting spent or settled a run")
	check(game.background != null and game.weapon != null and game.target_texture != null and game.hit_player.stream != null and game.reload_player.stream != null, "Shooting production art or audio missing")
	await capture("39-shooting-ready")
	click(game.start_button.global_position + game.start_button.size * 0.5)
	await process_frame
	check(game.phase == "playing" and store.sessions[run.token].active and game._live_targets() == 3, "Start button did not immediately open targets")
	check(store.quantity("choco_pie") == 2 and store.profile.quick_slots[0] == "choco_pie", "Shooting auto-used a recovery item or changed its quick slot")
	game.rng.seed = 21841
	advance(0.2)
	var first := target()
	click(game.target_center(first))
	check(game.hits == 1 and game.perfects == 1 and game.combo == 1 and game.raw_score == 180 and game.ammo == 7, "Precise mouse hit failed to score PERFECT or spend one round")
	click(Vector2(80, 170))
	check(game.shots == 1, "Shot cooldown failed")
	advance(0.15)
	tap(KEY_R)
	check(game.reload_left > 0 and game.ammo == 7, "R did not start reload")
	click(game.target_center(target()))
	check(game.shots == 1, "Shot fired during reload")
	var before_time: float = game.time_left
	var before_reload: float = game.reload_left
	var before_target: Vector2 = target().pos
	tap(KEY_ESCAPE)
	advance(0.8)
	check(game.phase == "paused" and game.time_left == before_time and game.reload_left == before_reload and target().pos == before_target, "Pause advanced timer, reload, or targets")
	tap(KEY_ESCAPE)
	await process_frame
	check(game.phase == "playing" and not is_instance_valid(game.popup), "Esc did not resume shooting")
	advance(0.9)
	check(game.ammo == 8 and game.reload_left == 0, "Reload did not restore magazine")
	click(Vector2(80, 170))
	check(game.shots == 2 and game.hits == 1 and game.combo == 0, "Miss did not break combo or track accuracy")
	# Ending before the complete course must not earn a clear/reward.
	game._finish_run()
	check(not game.training_passed and store.profile.coins == 0, "Incomplete course earned a reward")
	game._retry()
	await process_frame
	game.rng.seed = 5004
	var saved_path: String = store.save_path
	var saw_auto_reload := false
	var captured := false
	var seen_stages := {}
	var cycles := 0
	# Every counted hit below is delivered through an actual mouse event, without fabricating scores.
	while game.phase == "playing" and cycles < 2000:
		cycles += 1
		advance(0.05)
		seen_stages[game.stage] = true
		if game.elapsed > 44.5:
			store.save_path = "res://.godot/missing-shooting-directory/profile.cfg"
		if game.reload_left > 0:
			saw_auto_reload = saw_auto_reload or game.ammo == 0
			continue
		if game.fire_cooldown <= 0:
			var current := target()
			if not current.is_empty():
				click(game.target_center(current))
		if game.elapsed > 18.0 and not captured:
			await capture("40-shooting-play")
			captured = true
	check(game.phase == "result" and game.training_passed and game.final_score == 100 and game.hits >= 35, "Full precise course did not pass with matching grade")
	check(seen_stages.size() == 3 and saw_auto_reload, "Three stages or automatic empty-magazine reload missing")
	check(game.perfects == game.hits and game.best_combo == game.hits and game.raw_score > game.hits * 180, "Precise combo multiplier did not reward the full chain")
	check(not game.receipt.ok and store.profile.coins == 0 and store.sessions.has(game.token), "Failed save paid out or lost the pending result")
	store.save_path = saved_path
	game._settle()
	check(game.receipt.ok and game.receipt.first_clear and game.receipt.reward == 175 and store.cleared("shooting"), "Retrying result save did not settle first clear")
	check(game.receipt.new_personal_best and store.profile.records.shooting.best_raw_points == game.raw_score, "Raw personal best was not saved with reward")
	var paid: int = store.profile.coins
	game._settle()
	check(store.profile.coins == paid, "Duplicate result settlement paid twice")
	await capture("41-shooting-result")
	var completed := {"count": 0}
	game.finished.connect(func() -> void: completed.count += 1)
	await process_frame
	var finish := button_in(game, "훈련 마치기")
	check(finish != null, "Result finish button missing")
	click(finish.global_position + finish.size * 0.5)
	check(completed.count == 1 and not game.return_to_home, "Actual result button did not return through normal finish contract")
	# Body hits are enough for a basic pass, while S needs central precision.
	for count in [18, 35]:
		game._retry()
		await process_frame
		cycles = 0
		while game.phase == "playing" and cycles < 2000:
			cycles += 1
			advance(0.05)
			if game.hits < count and game.reload_left == 0 and game.fire_cooldown == 0:
				var current := target()
				if not current.is_empty():
					click(game.target_center(current) + Vector2(26 * float(current.scale), 0))
		check(game.hits == count and game.perfects == 0 and game.training_passed, "%d body hits failed basic pass" % count)
		check(game.final_score == (70 if count == 18 else 80), "%d body hits did not get intended basic grade" % count)
		check(store.profile.records.shooting.best_raw_points > game.raw_score, "Lower body-hit score overwrote personal best")
	paid = store.profile.coins
	game._retry()
	await process_frame
	advance(45.1)
	check(not game.training_passed and game.final_score == 0 and store.profile.coins == paid, "Idle play passed or paid coins")
	game._retry()
	await process_frame
	cycles = 0
	while game.phase == "playing" and cycles < 1000:
		cycles += 1
		advance(0.15)
		click(Vector2(640, 350))
	check(not game.training_passed and store.profile.coins == paid, "Fixed-position spray bypassed aiming requirement")
	game._retry()
	await process_frame
	var cancelled: String = game.token
	game._leave()
	check(not store.sessions.has(cancelled) and game.return_to_home, "Leaving shooting leaked a session or return flag")
	game.queue_free()
	await process_frame
	var loaded := Store.new(path)
	check(loaded.cleared("shooting") and loaded.profile.coins == paid and loaded.profile.records.shooting.best_raw_points > 0, "Restart lost shooting reward or personal best")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for message in failures:
		push_error(message)
	print("SHOOTING_CHECK ", "PASS" if failures.is_empty() else "FAIL", " — actual aim/fire, perfect/combo, misses, reload, pause, full three-stage course, save retry, records, payout, idle/fixed-position failure, retry and exit")
	quit(0 if failures.is_empty() else 1)
