extends SceneTree

const Store := preload("res://scripts/training_progress.gd")
const Hub := preload("res://scripts/training_hub.gd")
const Camp := preload("res://scripts/camp_world.gd")
var failures: Array[String] = []
var prefix := "res://.godot/rpg-ui-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func click(control: Control) -> void:
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.global_position + control.size * 0.5
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	await physics_frame
	await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/" + name + ".png")

func _run() -> void:
	var store := Store.new(prefix + "-profile.cfg")
	store.profile.coins = 5000
	store.profile.vitals = {"health": 45.0, "stamina": 30.0}
	var hub := Hub.new()
	hub.setup(store, "윤준성", "shop")
	root.add_child(hub)
	await create_timer(0.25).timeout
	await click(hub.item_buttons.gloves)
	await click(hub.primary_action)
	check(store.owned("gloves"), "PX purchase button did not purchase gloves")
	await click(hub.primary_action)
	check(store.equipped("gloves"), "PX equip button did not equip gloves")
	for entry in store.catalog.items:
		if not store.owned(entry.id):
			check(store.buy(entry.id).ok, "Could not stock " + str(entry.id))
		if entry.kind == "consumable":
			store.buy(entry.id)
			store.buy(entry.id)
	for id in ["field_cap", "boots", "watch", "canteen", "ace_badge"]:
		store.toggle_equipment(id)
	# The largest card (two recovery effects plus shop price/actions) must expose both slots.
	hub._switch_tab("shop")
	hub.category = "consumable"
	for id in ["choco_pie", "coffee", "energy_bar", "sports_drink"]:
		hub.selected_item = id
		hub._refresh()
		await process_frame
		check(hub.quick_slot_buttons[1].get_global_rect().end.y <= 646.0, "Shop recovery controls clipped for " + id)
	hub.selected_item = "energy_bar"
	hub._refresh()
	await process_frame
	var energy_count: int = store.quantity("energy_bar")
	await click(hub.primary_action)
	check(store.quantity("energy_bar") == energy_count + 1, "Consumable purchase button did not add one item")
	await capture("54-rpg-px-recovery")
	hub._switch_tab("inventory")
	hub.category = "consumable"
	hub.selected_item = "choco_pie"
	hub._refresh()
	await process_frame
	await click(hub.primary_action)
	check(store.get_vitals().health == 75.0 and store.quantity("choco_pie") == 2, "Inventory use did not heal and consume exactly one item")
	await click(hub.quick_slot_buttons[0])
	check(store.profile.quick_slots[0] == "choco_pie" and store.quantity("choco_pie") == 2, "Quick-slot registration consumed or assigned incorrectly")
	await click(hub.item_buttons.coffee)
	await click(hub.quick_slot_buttons[1])
	check(store.profile.quick_slots[1] == "coffee", "Second quick slot did not assign")
	await click(hub.item_buttons.choco_pie)
	await capture("52-rpg-inventory")
	store.profile.vitals.health = 100.0
	await create_timer(1.6).timeout
	await click(hub.primary_action)
	check(store.quantity("choco_pie") == 2 and hub.status_label.text.contains("소모하지"), "Full HP item use spent a recovery item")
	hub._switch_tab("equipment")
	await process_frame
	await click(hub.direction_buttons[1])
	check(hub.portrait_view.facing == 1, "Left equipment preview did not rotate")
	await click(hub.walk_button)
	check(hub.portrait_view.moving, "Equipment walk preview did not start")
	await create_timer(0.2).timeout
	await capture("51-rpg-equipment")
	await click(hub.direction_buttons[3])
	check(hub.portrait_view.facing == 3, "Rear equipment preview did not rotate")
	await click(hub.walk_button)
	check(not hub.portrait_view.moving, "Equipment walk preview did not stop")
	hub.queue_free()
	await process_frame
	# The real world controls spend SP only when the actor is actually running.
	var camp := Camp.new()
	camp.setup(store, "윤준성", false, {"bedding": true, "shooting": false})
	camp.save_path = prefix + "-camp.cfg"
	root.add_child(camp)
	await create_timer(0.15).timeout
	camp.player.position = Vector2(1100, 900)
	store.profile.vitals = {"health": 65.0, "stamina": 55.0}
	await key(KEY_SHIFT, true)
	await key(KEY_D, true)
	await create_timer(0.4).timeout
	await key(KEY_D, false)
	await key(KEY_SHIFT, false)
	check(store.get_vitals().stamina < 51.0 and camp.player.position.x > 1200, "Sprint did not move the player and spend SP")
	camp.request_pause()
	var paused_sp: float = store.get_vitals().stamina
	var paused_quantity: int = store.quantity("coffee")
	await key(KEY_2, true)
	await key(KEY_2, false)
	await create_timer(0.3).timeout
	check(is_equal_approx(store.get_vitals().stamina, paused_sp) and store.quantity("coffee") == paused_quantity, "Pause menu changed SP or used a quick item")
	camp.request_pause()
	await key(KEY_2, true)
	await key(KEY_2, false)
	check(store.quantity("coffee") == paused_quantity - 1 and store.get_vitals().stamina > paused_sp + 34.0, "Quick-slot keyboard use did not restore SP")
	var after_use: int = store.quantity("coffee")
	await key(KEY_2, true)
	await key(KEY_2, false)
	check(store.quantity("coffee") == after_use, "Repeated quick key bypassed shared cooldown")
	await create_timer(1.6).timeout
	await click(camp.quick_slot_buttons[0])
	check(store.get_vitals().health == 95.0 and store.quantity("choco_pie") == 1, "HUD click did not use assigned healing item")
	await capture("53-rpg-hud")
	store.profile.vitals.stamina = 40.0
	camp.player.position = Vector2(600, 568)
	await key(KEY_SHIFT, true)
	await key(KEY_W, true)
	await create_timer(0.3).timeout
	await key(KEY_W, false)
	await key(KEY_SHIFT, false)
	check(store.get_vitals().stamina >= 39.8, "Running against a wall consumed SP")
	store.profile.vitals.stamina = 0.0
	camp.player.position = Vector2(1100, 900)
	await key(KEY_SHIFT, true)
	await key(KEY_D, true)
	await create_timer(0.15).timeout
	check(camp.player.get_real_velocity().length() <= 275.0, "Exhaustion did not fall back to equipped walking speed")
	await key(KEY_D, false)
	await key(KEY_SHIFT, false)
	var tired: float = store.get_vitals().stamina
	await create_timer(1.3).timeout
	check(store.get_vitals().stamina > tired, "Rest did not recover stamina")
	camp.save_position()
	var saved_sp: float = store.get_vitals().stamina
	camp.queue_free()
	await process_frame
	var restored := Store.new(prefix + "-profile.cfg")
	check(is_equal_approx(restored.get_vitals().stamina, saved_sp) and restored.profile.quick_slots == store.profile.quick_slots, "Camp state or quick slots did not persist")
	# Preview consumes neither items nor live profile resources and writes no camp save.
	var before := store.profile.duplicate(true)
	var preview := Camp.new()
	preview.setup(store, "윤준성", true)
	preview.save_path = prefix + "-preview.cfg"
	root.add_child(preview)
	await process_frame
	preview.player.position = Vector2(1100, 900)
	await key(KEY_SHIFT, true)
	await key(KEY_D, true)
	await key(KEY_1, true)
	await key(KEY_1, false)
	await create_timer(0.25).timeout
	await key(KEY_D, false)
	await key(KEY_SHIFT, false)
	preview.save_position()
	check(store.profile == before and not FileAccess.file_exists(preview.save_path), "Preview changed the player's resources or saved state")
	preview.queue_free()
	await process_frame
	for suffix in ["-profile.cfg", "-camp.cfg", "-preview.cfg"]:
		if FileAccess.file_exists(prefix + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))
	for failure in failures:
		push_error(failure)
	print("RPG_UI_CHECK ", "PASS" if failures.is_empty() else "FAIL", " — purchase/equip, recovery use, two quick slots, four-view/walk preview, sprint/rest/wall, pause, save/reload and preview isolation")
	quit(0 if failures.is_empty() else 1)
