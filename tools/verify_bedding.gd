extends SceneTree

const Store := preload("res://scripts/training_progress.gd")
var main: Control
var game: Control
var store: RefCounted
var errors: Array[String] = []
var test_path := "res://.godot/bedding-check-%d.cfg" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, reason: String) -> void:
	if not condition:
		errors.append(reason)

func click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, down: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = button
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame

func move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	Input.parse_input_event(event)
	await process_frame

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/" + filename + ".png")
	await create_timer(0.05).timeout

func fold(piece: Node2D, fraction: float = 1.0, snapshot: bool = false) -> void:
	game._select(piece)
	var start: Vector2 = piece.handle_global()
	var end: Vector2 = piece.to_global(piece.fold_end_local())
	await click(start)
	check(piece.folding, "Mouse did not grab fold corner")
	for ratio in [0.2, 0.4, 0.65, 0.85, 1.0]:
		await move(start.lerp(end, float(ratio) * fraction))
		if snapshot and ratio == 0.4:
			await capture("13-bedding-folding")
	await click(start.lerp(end, fraction), MOUSE_BUTTON_LEFT, false)
	await create_timer(0.22).timeout

func align(piece: Node2D, offset: Vector2) -> void:
	var start: Vector2 = piece.to_global(offset)
	var origin_angle: float = (start - piece.position).angle()
	var end: Vector2 = piece.position + Vector2.from_angle(origin_angle - piece.rotation) * offset.length()
	await click(start, MOUSE_BUTTON_RIGHT)
	await move(end)
	await click(end, MOUSE_BUTTON_RIGHT, false)
	check(absf(piece.rotation_degrees) < 0.01, "Right-drag rotation did not align " + str(piece.id))

func drag(piece: Node2D, offset: Vector2, center: Vector2) -> void:
	var start: Vector2 = piece.to_global(offset)
	var end: Vector2 = center + offset.rotated(piece.rotation)
	await click(start)
	await move(end)
	await click(end, MOUSE_BUTTON_LEFT, false)

func _run() -> void:
	main = load("res://scenes/main_menu.tscn").instantiate()
	main.progress_path = test_path + "-story.cfg"
	main.camp_progress_path = test_path + "-camp.cfg"
	root.add_child(main)
	await create_timer(2.6).timeout
	store = Store.new(test_path)
	main.training_progress = store
	main.state = "story"
	main.title_ui.hide()
	main.dialogue_ui.show()
	main._set_background("training")
	main._play_music("training_morning")
	check(main.music_player.stream.resource_path.ends_with("recruit_morning.mp3"), "Wrong wake-up BGM")
	main._ending()
	check(is_instance_valid(main.overlay), "Story quest did not appear")
	var quest: Control = main.overlay
	await create_timer(0.4).timeout
	check(quest.training.id == "bedding" and quest.opened, "Illustrated quest did not initialize")
	check(ResourceLoader.exists(quest.training.quest.image), "Quest illustration missing")
	check(main.current_music == "training_morning" and store.profile.coins == 0, "Quest changed BGM or paid before acceptance")
	await capture("17-quest-window")
	# Closing the quest must cancel its pending session without granting anything.
	var cancelled_token: String = main.active_training_token
	quest.request_close()
	await process_frame
	check(not store.sessions.has(cancelled_token) and not store.cleared("bedding"), "Dismissed quest left a run or clear behind")
	main._ending()
	quest = main.overlay
	await create_timer(0.4).timeout
	quest._accept()
	quest._accept()
	await create_timer(0.3).timeout
	game = main.overlay
	check(game.name == "BeddingTraining", "Quest did not launch bedding game")
	check(main.music_player.stream.resource_path.ends_with("ceremonial_charge.mp3"), "Wrong training BGM")
	check(game.phase == "playing" and not is_instance_valid(game.popup), "Quest acceptance showed a duplicate briefing")
	check(store.sessions.size() == 1, "Quest acceptance duplicated the run")
	check(game.pieces.blanket.fold_scores.is_empty() and game.pieces.mattress.fold_scores.is_empty(), "Game started with folded bedding")
	game._begin()
	await process_frame
	await capture("12-bedding-start")
	var pillow: Node2D = game.pieces.pillow
	await drag(pillow, Vector2.ZERO, game.TARGETS.pillow)
	check(game.stack.is_empty(), "Pillow accepted before mattress")
	await drag(pillow, Vector2.ZERO, Vector2(282, 230))
	var blanket: Node2D = game.pieces.blanket
	await fold(blanket, 0.4)
	check(blanket.fold_scores.is_empty(), "Partial fold counted")
	await fold(blanket, 1.0, true)
	await fold(blanket)
	check(blanket.complete(), "Blanket folding failed")
	var mattress: Node2D = game.pieces.mattress
	await fold(mattress)
	check(mattress.complete(), "Mattress folding failed")
	await align(mattress, Vector2(145, 65))
	await drag(mattress, Vector2(145, 65), game.TARGETS.mattress)
	check(game.stack == ["mattress"], "Bottom mattress placement failed")
	await align(blanket, Vector2(60, 0))
	await drag(blanket, Vector2(60, 0), game.TARGETS.blanket)
	await align(pillow, Vector2(60, 0))
	await drag(pillow, Vector2(60, 0), game.TARGETS.pillow)
	check(game.stack == ["mattress", "blanket", "pillow"], "Stack order incorrect")
	check(game.breakdown().score == 100, "Exact fold/alignment did not score 100")
	game._remove_from_stack("mattress")
	check(game.stack.is_empty() and game._pick(pillow.position) == pillow, "Unstacked upper bedding became inaccessible")
	game._try_place(mattress)
	check(game._pick(pillow.position) == pillow, "Replaced bottom layer hid loose upper bedding")
	game._try_place(blanket)
	game._try_place(pillow)
	# Poor angular alignment must cost points even when the stack is complete.
	pillow.rotation_degrees = 30
	check(game.breakdown().score < game.PASS_SCORE, "Severely rotated pillow still passed grading")
	pillow.rotation_degrees = 0
	await capture("14-bedding-stacked")
	game.request_pause()
	var paused_time: float = game.time_left
	await create_timer(0.2).timeout
	check(game.time_left == paused_time, "Timer continued while paused")
	game._close_popup()
	game.phase = "playing"
	game._evaluate()
	check(game.training_passed and store.cleared("bedding") and int(store.profile.coins) == 175, "First clear did not grant reward/unlock")
	await capture("15-bedding-result")
	var first_balance: int = store.profile.coins
	check(not store.finish_run(game.token, 100, true).ok and int(store.profile.coins) == first_balance, "Duplicate reward granted")
	game.finished.emit()
	await process_frame
	check(main.state == "camp" and is_instance_valid(main.camp_world) and main.music_player.stream.resource_path.ends_with("recruit_morning.mp3"), "Camp/BGM not restored after first training")
	main._return_to_training_hub()
	var hub: Control = main.overlay
	hub._launch("bedding")
	await process_frame
	quest = main.overlay
	await create_timer(0.4).timeout
	check(quest.replay, "Replay did not show a replay quest")
	check(store.reward_for_score("bedding", 80) == 50 and store.reward_for_score("bedding", 100) == 75, "Replay reward preview differs from settlement")
	quest._accept()
	await process_frame
	game = main.overlay
	check(game.name == "BeddingTraining" and game.run_mode == "replay", "Unlocked replay did not launch")
	game._begin()
	game.time_left = 0.01
	await create_timer(0.05).timeout
	check(game.phase == "result" and not game.training_passed and int(store.profile.coins) == first_balance, "Unfinished timeout paid a reward")
	game._retry()
	check(game.phase == "playing" and game.time_left > 59 and game.stack.is_empty(), "Retry did not reset the round")
	game._leave()
	await process_frame
	check(main.overlay.name != "BeddingTraining" and main.state == "title", "Exit did not restore hub")
	var reload := Store.new(test_path)
	check(reload.cleared("bedding") and int(reload.profile.coins) == first_balance, "Clear or coins lost on reload")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	for suffix in ["-story.cfg", "-camp.cfg"]:
		if FileAccess.file_exists(test_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path + suffix))
	for error in errors:
		push_error(error)
	print("BEDDING_CHECK ", "PASS" if errors.is_empty() else "FAIL", " — mouse folds, rotation, stacking, grades, timer/pause, rewards, replay, retry, story BGM and persistence")
	quit(0 if errors.is_empty() else 1)

