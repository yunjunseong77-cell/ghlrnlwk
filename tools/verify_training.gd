extends SceneTree

const Store := preload("res://scripts/training_progress.gd")
const Hub := preload("res://scripts/training_hub.gd")
var failures: Array[String] = []
var path := "res://.godot/training-test-%d.cfg" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var store := Store.new(path)
	check(store.grade(69) == "C" and store.grade(70) == "B" and store.grade(85) == "A" and store.grade(95) == "S", "Grade boundaries incorrect")
	check(not store.begin_run("shooting", "replay").ok, "Locked replay accepted")
	check(not store.buy("gloves").ok, "Purchase without coins accepted")
	var failed: Dictionary = store.begin_run("shooting")
	store.finish_run(failed.token, 25, false)
	check(not store.cleared("shooting") and store.profile.coins == 0, "Failure unlocked or rewarded")
	var first: Dictionary = store.begin_run("shooting")
	check(not store.finish_run(first.token, 101, true).ok, "Out-of-range result accepted")
	var result: Dictionary = store.finish_run(first.token, 95, true, {"raw_points": 3200, "best_combo": 18})
	check(result.ok and result.first_clear and result.reward == 175, "First clear reward incorrect")
	check(result.new_personal_best and result.best_points == 3200 and result.previous_best_points == 0, "First shooting points were not stored")
	check(not store.finish_run(first.token, 95, true).ok, "Duplicate result paid twice")
	var replay: Dictionary = store.begin_run("shooting", "replay")
	result = store.finish_run(replay.token, 85, true, {"raw_points": 2500, "best_combo": 20})
	check(result.ok and not result.first_clear and result.reward == 60, "Replay bonus incorrectly repeated")
	check(not result.new_personal_best and result.best_points == 3200 and result.best_combo == 20, "A lower score replaced the best, or combo improvement was lost")
	check(store.profile.coins == 235, "Balance incorrect")
	check(store.buy("gloves").ok, "Purchase failed")
	check(store.profile.coins == 115 and store.owned("gloves"), "Purchase not deducted or owned")
	check(not store.buy("gloves").ok and store.profile.coins == 115, "Duplicate purchase accepted")
	check(not store.buy("shoulder_pad").ok, "Overspend accepted")
	check(not store.toggle_equipment("ace_badge").ok, "Unowned equipment accepted")
	check(store.toggle_equipment("gloves").ok and store.equipped("gloves"), "Equip failed")
	var loaded := Store.new(path)
	check(loaded.profile.coins == 115 and loaded.cleared("shooting") and loaded.equipped("gloves"), "Saved state lost")
	check(loaded.profile.records.shooting.best_raw_points == 3200 and loaded.profile.records.shooting.best_combo == 20, "Shooting personal records were lost on reload")
	var cancelled: Dictionary = loaded.begin_run("shooting", "replay")
	loaded.cancel_run(cancelled.token)
	check(not loaded.finish_run(cancelled.token, 100, true).ok, "Cancelled run paid")
	var broken := Store.new("res://.godot/missing-test-directory/profile.cfg")
	var unsaved: Dictionary = broken.begin_run("shooting")
	check(not broken.finish_run(unsaved.token, 100, true, {"raw_points": 9999, "best_combo": 30}).ok and broken.profile.coins == 0 and not broken.cleared("shooting"), "Failed save still granted reward or personal record")
	var hub := Hub.new()
	hub.setup(loaded, "윤준성", "training")
	root.add_child(hub)
	await create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/05-training.png")
	hub._switch_tab("shop")
	await create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/06-px.png")
	hub._switch_tab("inventory")
	await create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/07-inventory.png")
	hub.queue_free()
	await process_frame
	# The test uses its own file and never changes the player's profile.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for message in failures:
		push_error(message)
	print("TRAINING_CHECK: ", "PASS" if failures.is_empty() else "FAIL", " — unlock, failure, first/replay rewards, duplicate settlement, purchases, equipment, save/reload")
	quit(0 if failures.is_empty() else 1)

