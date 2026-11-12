extends SceneTree

const Store := preload("res://scripts/training_progress.gd")
var failures: Array[String] = []
var main: Control
var camp: Control
var store: RefCounted
var prefix := "res://.godot/camp-check-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/" + filename + ".png")

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func _run() -> void:
	main = load("res://scenes/main_menu.tscn").instantiate()
	main.progress_path = prefix + "-story.cfg"
	main.camp_progress_path = prefix + "-position.cfg"
	root.add_child(main)
	await create_timer(2.5).timeout
	store = Store.new(prefix + "-profile.cfg")
	main.training_progress = store
	# A title preview must never unlock/reward training or persist a real camp position.
	main._open_camp(true)
	await create_timer(0.2).timeout
	camp = main.camp_world
	check(camp.preview and not store.cleared("bedding"), "Preview granted a training clear")
	camp._interact(camp._place("barracks"))
	check(is_instance_valid(camp.modal) and not is_instance_valid(main.overlay), "Preview launched training")
	camp._close_panel()
	camp.save_position()
	check(not FileAccess.file_exists(main.camp_progress_path), "Preview persisted a camp position")
	main._dispose_camp()
	await process_frame
	# Enter the real camp without modifying the player's real saves.
	main._open_camp()
	await create_timer(0.2).timeout
	camp = main.camp_world
	check(camp.size == Vector2(1280, 720), "Camp viewport size incorrect")
	check(not camp.preview and main.current_music == "training_morning", "Wrong camp mode or music")
	await capture("18-camp-exploration")
	# Real input events exercise keyboard movement.
	var start: Vector2 = camp.player.position
	await key(KEY_D, true)
	await create_timer(0.35).timeout
	await key(KEY_D, false)
	check(camp.player.position.x > start.x + 45, "Keyboard movement did not advance")
	# Collision must hold even when bypassing the pathfinder with direct movement.
	camp.player.position = Vector2(600, 590)
	await key(KEY_W, true)
	await create_timer(0.5).timeout
	await key(KEY_W, false)
	check(camp.player.position.y >= 567.0, "Player crossed a barracks wall")
	check(not camp.move_to(Vector2(500, 300)), "Pathfinder accepted a roof")
	check(not camp.move_to(Vector2(20, 20)), "Pathfinder accepted outside perimeter")
	# All interaction points must be reachable from spawn without crossing a roof.
	camp.player.position = Vector2(600, 610)
	for place in camp.data.places:
		var point := Vector2(place.position[0], place.position[1])
		check(camp.is_walkable(point), "Interaction point blocked: " + str(place.id))
		check(camp.move_to(point), "No path to " + str(place.id))
		for waypoint in camp.path:
			check(camp.is_walkable(waypoint), "Path crosses obstacle at " + str(waypoint))
	camp.path.clear()
	# Map click routing exercises GUI input and a route across the central ground.
	camp._show_map()
	await process_frame
	await capture("19-camp-map")
	var map: Control = camp.big_map
	var destination := Vector2(1400, 900)
	await click(map.global_position + destination / camp.world_size * map.size)
	check(not is_instance_valid(camp.modal) and not camp.path.is_empty(), "Map click did not start a route")
	await create_timer(0.2).timeout
	check(camp.player.position.distance_to(Vector2(600, 610)) > 10, "Click path movement did not advance")
	# Modal input must stop motion and ignore click-through.
	camp.request_pause()
	var paused_at: Vector2 = camp.player.position
	await key(KEY_D, true)
	await create_timer(0.2).timeout
	await key(KEY_D, false)
	check(camp.player.position.distance_to(paused_at) < 1, "Player moved behind pause menu")
	camp.request_pause()
	check(not is_instance_valid(camp.modal), "Pause did not close")
	# Clicking a peer navigates close enough, then stops to open dialogue.
	camp.player.position = Vector2(600, 610)
	check(camp.navigate_to_place("peer"), "Peer click navigation failed")
	await create_timer(0.5).timeout
	check(is_instance_valid(camp.modal) and camp.talked_to_peer, "Approaching peer did not open dialogue")
	await capture("20-camp-dialogue")
	camp._close_panel()
	# Quest cancel restores exploration, not the replay hub, and cancels its session.
	camp.player.position = Vector2(600, 610)
	await process_frame
	await click(camp.interact_button.global_position + camp.interact_button.size * 0.5)
	await create_timer(0.4).timeout
	var quest: Control = main.overlay
	check(is_instance_valid(quest) and quest.training.id == "bedding", "Camp did not open bedding quest")
	var token: String = main.active_training_token
	var anchor: Vector2 = camp.player.position
	await key(KEY_D, true)
	await create_timer(0.15).timeout
	await key(KEY_D, false)
	check(camp.player.position.distance_to(anchor) < 1, "Camp moved behind quest")
	quest.request_close()
	await process_frame
	check(main.state == "camp" and not is_instance_valid(main.overlay) and not store.sessions.has(token), "Cancelled quest did not restore camp cleanly")
	# A real scene launch and exit must keep camp identity, location and BGM.
	camp._interact(camp._place("barracks"))
	await create_timer(0.4).timeout
	main.overlay._accept()
	await create_timer(0.2).timeout
	check(main.state == "training" and not camp.visible, "Camp did not suspend for training")
	var game: Control = main.overlay
	game._leave()
	await create_timer(0.2).timeout
	check(main.state == "camp" and main.camp_world == camp and camp.visible, "Training did not return to same world")
	check(camp.player.position.distance_to(anchor) < 1 and main.current_music == "training_morning", "Training changed world position or BGM")
	check(store.profile.coins == 0 and store.sessions.is_empty(), "Abandoned camp training paid or leaked session")
	# PX opens the existing economy; close returns to the same camp.
	camp._interact(camp._place("px"))
	await process_frame
	check(main.overlay.tab == "shop", "PX did not open shop")
	main._close_overlay()
	await process_frame
	check(main.state == "camp" and main.camp_world == camp, "PX close lost camp")
	await key(KEY_K, true)
	await key(KEY_K, false)
	check(is_instance_valid(main.overlay) and main.overlay.tab == "equipment", "K did not open equipment from camp")
	await key(KEY_I, true)
	await key(KEY_I, false)
	check(is_instance_valid(main.overlay) and main.overlay.tab == "inventory", "I did not switch to inventory")
	await key(KEY_I, true)
	await key(KEY_I, false)
	check(not is_instance_valid(main.overlay) and main.state == "camp", "I did not close inventory back to camp")
	# A legitimate training clear opens the next NPC dialogue without granting drill clear.
	var run: Dictionary = store.begin_run("bedding")
	store.finish_run(run.token, 100, true)
	main._complete_campaign_training("bedding")
	camp._interact(camp._place("instructor"))
	await process_frame
	check(is_instance_valid(camp.modal) and not store.cleared("drill"), "Instructor briefing unlocked training before evaluation")
	await capture("21-camp-next-quest")
	camp._close_panel()
	# Save/reload restores position and conversation flag to the isolated test save.
	camp.player.position = Vector2(1120, 900)
	camp.save_position()
	main._dispose_camp()
	await process_frame
	main._open_camp()
	await process_frame
	camp = main.camp_world
	check(camp.has_saved_position and camp.player.position.distance_to(Vector2(1120, 900)) < 1 and camp.talked_to_peer, "World save/reload lost state")
	await capture("22-camp-parade-ground")
	main.queue_free()
	await process_frame
	for suffix in ["-story.cfg", "-position.cfg", "-profile.cfg"]:
		if FileAccess.file_exists(prefix + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))
	if failures.is_empty():
		print("CAMP_CHECK PASS — preview isolation, movement/collision, reachable routes, map clicks, dialogue/pause, quest cancel, training/PX return and save/reload")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
