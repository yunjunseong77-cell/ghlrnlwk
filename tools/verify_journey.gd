extends SceneTree

class JourneyMain extends "res://scripts/main_menu.gd":
	func _edit_native_nickname() -> void:
		# Native IME itself is verified separately; this supplies the complete native result.
		_receive_native_nickname("윤준성", nickname_form.get_instance_id())

const Store := preload("res://scripts/training_progress.gd")
var failures: Array[String] = []
var prefix := "res://.godot/journey-%d" % Time.get_ticks_usec()
var main: Control

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)

func button_in(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption:
		return node
	for child in node.get_children():
		var found := button_in(child, caption)
		if found:
			return found
	return null

func has_text(node: Node, phrase: String) -> bool:
	if (node is Label or node is Button) and phrase in str(node.text):
		return true
	for child in node.get_children():
		if has_text(child, phrase):
			return true
	return false

func click_button(node: Node, caption: String) -> void:
	await process_frame
	var button := button_in(node, caption)
	check(button != null, "Missing visible button: " + caption)
	if button == null:
		return
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.global_position + button.size * 0.5
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func press_space() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func capture(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/" + filename + ".png")

func settle_shooting(game: Control, store: RefCounted) -> void:
	# Shooting mechanics are covered by verify_shooting; exercise the real result UI here.
	game._start_run()
	game.set_process(false)
	game.phase = "result"
	game.training_passed = true
	game.final_score = 96
	game.raw_score = 8600
	game.hits = 36
	game.shots = 38
	game.perfects = 30
	game.best_combo = 24
	game.receipt = store.finish_run(game.token, 96, true, {"raw_points": game.raw_score, "best_combo": game.best_combo})
	game._show_result()

func _run() -> void:
	main = JourneyMain.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.progress_path = prefix + "-story.cfg"
	main.camp_progress_path = prefix + "-camp.cfg"
	root.add_child(main)
	await create_timer(2.6).timeout
	var store := Store.new(prefix + "-profile.cfg")
	for id in ["bedding", "drill"]:
		var old: Dictionary = store.begin_run(id)
		store.finish_run(old.token, 100, true)
	main.training_progress = store
	main.campaign_clears = {"bedding": true, "drill": true, "shooting": false}
	main._refresh_home_profile()
	await capture("31-journey-title")
	main._open_training_hub("training")
	await process_frame
	check(not has_text(main.overlay, "제식 훈련"), "Retired drill remained in training list")
	check(button_in(main.overlay, "바로 도전") != null, "Uncleared shooting quick entry is missing")
	await click_button(main.overlay, "바로 도전")
	await create_timer(0.35).timeout
	check(main.overlay.training.id == "shooting" and not store.cleared("shooting"), "Uncleared shooting was blocked or opening quest awarded clear")
	main.overlay.request_close()
	await process_frame
	main._close_overlay()
	# The new game can be tested immediately from the title without clearing the story.
	await click_button(main, "사격 바로하기")
	await process_frame
	check(main.state == "training" and main.overlay.phase == "ready", "Title quick play did not reach shooting ready screen")
	check(not store.cleared("shooting") and not main.campaign_clears.shooting, "Opening quick play granted a clear")
	var quick_game: Control = main.overlay
	await click_button(quick_game, "사격 시작")
	await create_timer(0.2).timeout
	var shot_count: int = quick_game.shots
	# This point overlaps the old title's camp button. It must fire, not reopen camp.
	for down in [true, false]:
		var shot_event := InputEventMouseButton.new()
		shot_event.position = Vector2(1140, 390)
		shot_event.button_index = MOUSE_BUTTON_LEFT
		shot_event.pressed = down
		Input.parse_input_event(shot_event)
		await process_frame
	check(main.overlay == quick_game and main.state == "training" and quick_game.shots == shot_count + 1, "Shooting pointer input clicked through to the title screen")
	check(not main.title_ui.visible and not main.dialogue_ui.visible, "Underlying story/title remained interactive during training")
	await create_timer(0.85).timeout
	check(absf(main.music_player.volume_db + 15.0) < 0.1, "Shooting BGM did not make room for gunfire")
	settle_shooting(main.overlay, store)
	await click_button(main.overlay, "훈련 마치기")
	await process_frame
	check(store.cleared("shooting") and not main.campaign_clears.shooting, "Title clear incorrectly completed the campaign")
	check(main.state == "title" and main.overlay.tab == "training", "Title shooting result did not return to training hub")
	check(has_text(main.overlay, "최고 8600 POINTS") and has_text(main.overlay, "24 COMBO"), "Training hub did not show shooting personal best")
	await capture("38-journey-shooting-records")
	main._close_overlay()
	main._play_music("bedding")
	await create_timer(0.8).timeout
	main._play_music("shooting")
	await create_timer(0.4).timeout
	check(absf(main.music_player.volume_db + 15.0) < 0.1, "Shared BGM stream did not lower volume for shooting")
	main._play_music("bedding")
	await create_timer(0.4).timeout
	check(absf(main.music_player.volume_db + 6.0) < 0.1, "Shared BGM stream kept shooting volume in bedding")
	main._play_music("title")
	main.player_name = "ABC"
	check(main._names("[given]") == "ABC", "Three-letter nickname was truncated")
	main.player_name = "윤준성"
	await click_button(main, "GAME START")
	await create_timer(0.1).timeout
	check(main.nickname_draft == "윤준성", "Native full-name callback lost characters")
	await click_button(main, "이야기 시작")
	check(not main.campaign_clears.bedding and not main.campaign_clears.drill and not main.campaign_clears.shooting and store.cleared("bedding") and store.cleared("shooting"), "New campaign reset permanent rewards or retained story clears")
	main.text_speed = 5000
	var seen: Dictionary = {}
	var auto_seen := 0
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and not is_instance_valid(main.overlay):
		await create_timer(0.02).timeout
		if main.busy or main.state != "story":
			continue
		var index: int = main.index
		if index >= 0 and index < main.story.size() and not seen.has(index):
			seen[index] = true
			var beat: Dictionary = main.story[index]
			if beat.get("cue", "") == "horn":
				check(main.current_music == "silence", "BGM continued into truck horn")
			if beat.get("cue", "") == "reveille":
				check(absf(main.effect_player.stream.get_length() - 11.0) < 0.02, "Bugle exceeded the requested 11 seconds")
			if beat.has("auto_advance"):
				auto_seen += 1
				if auto_seen == 1:
					main._pause()
					var remaining: float = main.cinematic_remaining
					await create_timer(0.2).timeout
					check(main.cinematic_remaining == remaining, "Accident cinematic progressed behind pause menu")
					main._close_overlay()
			if beat.get("scene", "") == "office":
				await capture("32-journey-office")
			if beat.get("scene", "") == "training":
				check(main.current_music == "training_morning", "Regression did not start assigned BGM")
				await capture("33-journey-regression")
		if main.cinematic_remaining < 0:
			await press_space()
	check(seen.size() == main.story.size(), "First-run story skipped or stalled on a beat")
	check(auto_seen == 3, "Truck accident did not play as three timed beats")
	check(is_instance_valid(main.overlay) and main.overlay.training.id == "bedding", "Existing clear caused first training to be skipped")
	await create_timer(0.35).timeout
	await click_button(main.overlay, "퀘스트 수락")
	await process_frame
	var bedding: Control = main.overlay
	var before: int = store.profile.coins
	# Mechanics are tested with mouse drags in check_bedding; here exercise the full story/result route.
	for id in bedding.ORDER:
		var piece: Node2D = bedding.pieces[id]
		for fold in piece.folds:
			piece.fold_scores.append(100.0)
		piece.position = bedding.TARGETS[id]
		piece.rotation = 0
		bedding._try_place(piece)
	bedding._evaluate()
	await click_button(bedding, "계속하기")
	await process_frame
	check(main.state == "camp" and main.campaign_clears.bedding and not main.campaign_clears.drill, "First result did not advance campaign to camp")
	check(store.profile.coins == before + 75, "New story paid a duplicate first-clear bonus")
	var camp: Control = main.camp_world
	camp._close_panel()
	check(camp.objective_id() == "peer", "Next objective did not introduce the peer")
	camp.navigate_to_place("peer")
	await create_timer(0.5).timeout
	check(camp.talked_to_peer, "Peer interaction did not progress objective")
	camp._close_panel()
	check(camp.objective_id() == "instructor", "Next objective did not lead to parade ground")
	camp.navigate_to_place("instructor")
	var arrival_deadline := Time.get_ticks_msec() + 8000
	while not is_instance_valid(camp.modal) and Time.get_ticks_msec() < arrival_deadline:
		await create_timer(0.1).timeout
	await capture("34-journey-drill-story")
	await click_button(camp, "다음 일과로")
	check(camp.drill_briefed and camp.objective_id() == "range" and not is_instance_valid(main.overlay), "Short drill event did not unlock range objective")
	check(not main.campaign_clears.shooting, "Drill event granted shooting completion")
	await capture("36-journey-time-skip")
	await click_button(camp, "확인")
	check(camp.navigate_to_place("range"), "Shooting access path is unreachable")
	arrival_deadline = Time.get_ticks_msec() + 9000
	while not is_instance_valid(main.overlay) and Time.get_ticks_msec() < arrival_deadline:
		await create_timer(0.1).timeout
	await create_timer(0.35).timeout
	check(main.overlay.training.id == "shooting", "Range access did not open shooting quest")
	await capture("35-journey-shooting-quest")
	# Permanent replay unlocks may already exist, but campaign completion still requires a pass.
	main.overlay._accept()
	await process_frame
	var shooting: Control = main.overlay
	check(main.state == "training" and shooting.phase == "ready", "Shooting did not start in ready screen")
	check(main.current_music == "shooting", "Shooting BGM missing")
	var position: Vector2 = camp.player.position
	shooting._leave()
	await process_frame
	check(main.state == "camp" and main.camp_world == camp and camp.player.position == position, "Actual shooting exit lost exploration origin")
	check(not main.campaign_clears.shooting, "Exiting ready screen completed the campaign quest")
	# The old bedding replay exit bug must also stay fixed.
	camp.training_requested.emit("bedding")
	await create_timer(0.35).timeout
	main.overlay._accept()
	await process_frame
	main.overlay._leave()
	await process_frame
	check(main.state == "camp" and camp.player.position == position, "Actual bedding replay exit returned to title")
	# Shooting mechanics/settlement are verified in verify_shooting; inject a settled result here
	# to exercise the real result button and the complete campaign/debrief/PX route.
	camp.training_requested.emit("shooting")
	await create_timer(0.35).timeout
	main.overlay._accept()
	await process_frame
	shooting = main.overlay
	settle_shooting(shooting, store)
	await click_button(shooting, "훈련 마치기")
	await process_frame
	check(main.state == "camp" and main.campaign_clears.shooting and is_instance_valid(camp.modal), "Passing shooting did not unlock campaign debrief")
	check(camp.objective_id() == "peer", "Shooting result did not lead to peer reaction")
	camp._close_panel()
	camp._interact(camp._place("peer"))
	check(camp.shooting_debriefed and camp.objective_id() == "px", "Peer reaction did not open free-time goal")
	camp._close_panel()
	camp._interact(camp._place("px"))
	await process_frame
	check(main.overlay.tab == "shop" and main.state == "camp", "Post-training free time did not reach PX")
	main._close_overlay()
	var saved := ConfigFile.new()
	saved.load(main.progress_path)
	check(saved.get_value("campaign", "clears").shooting, "Shooting campaign completion was not saved")
	main._dispose_camp()
	main.queue_free()
	await process_frame
	for suffix in ["-story.cfg", "-camp.cfg", "-profile.cfg"]:
		if FileAccess.file_exists(prefix + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))
	for failure in failures:
		push_error(failure)
	print("JOURNEY_CHECK ", "PASS" if failures.is_empty() else "FAIL", " — title quick shooting, account/campaign separation, shared BGM mix, full prologue, bedding→peer→short drill→time skip→shooting, exits, result→debrief→PX and campaign save")
	quit(0 if failures.is_empty() else 1)
