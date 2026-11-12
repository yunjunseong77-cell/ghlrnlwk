extends SceneTree

const Store := preload("res://scripts/training_progress.gd")
const Hub := preload("res://scripts/training_hub.gd")
const Camp := preload("res://scripts/camp_world.gd")
const Piece := preload("res://scripts/bedding_piece.gd")
var failures: Array[String] = []
var prefix := "res://.godot/loadout-check-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/" + name + ".png")

func click(control: Control) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.global_position + control.size * 0.5
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await physics_frame
	await physics_frame

func _run() -> void:
	# A real v1 save must retain purchases, equipment, records and balance.
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "version", 1)
	legacy.set_value("profile", "coins", 3000)
	legacy.set_value("profile", "inventory", ["gloves", "shoulder_pad", "ace_badge"])
	legacy.set_value("profile", "equipment", {"손": "gloves", "군장": "shoulder_pad", "명찰": "ace_badge"})
	legacy.set_value("profile", "records", {"shooting": {"best": 95, "clears": 2}})
	legacy.save(prefix + ".cfg")
	var store := Store.new(prefix + ".cfg")
	check(store.profile.coins == 3000 and store.equipped("gloves") and store.cleared("shooting"), "Legacy save migration lost state")
	check(store.profile.prepared == "" and store.profile.quantities.is_empty() and store.profile.quick_slots == ["", ""], "Legacy save gained consumables or quick slots")
	var hub := Hub.new()
	hub.setup(store, "윤준성", "shop")
	root.add_child(hub)
	await create_timer(0.2).timeout
	await click(hub.item_buttons.boots)
	await click(hub.primary_action)
	check(store.owned("boots") and store.profile.coins == 2840, "Actual PX purchase button did not purchase boots")
	await click(hub.primary_action)
	check(store.equipped("boots"), "Actual equip button did not equip purchase")
	for entry in store.catalog.items:
		if not store.owned(str(entry.id)):
			check(store.buy(str(entry.id)).ok, "Could not purchase " + str(entry.id))
	check(store.buy("choco_pie").ok and store.quantity("choco_pie") == 2, "Consumables do not stack")
	check(not store.toggle_equipment("coffee").ok, "Consumable occupied an equipment slot")
	check(not store.buy("boots").ok, "Duplicate permanent purchase accepted")
	check(store.toggle_equipment("precision_gloves").ok and not store.equipped("gloves"), "Same-slot replacement retained both effects")
	check(store.equipment_effects().get("fold_assist", 0) == 0 and store.equipment_effects().snap_degrees == 3, "Replaced glove effect leaked")
	store.toggle_equipment("gloves")
	for id in ["field_cap", "watch"]:
		store.toggle_equipment(id)
	check(is_equal_approx(store.equipment_effects().move_speed, 0.22), "Boots and pack effects did not stack")
	hub._switch_tab("shop")
	await process_frame
	await capture("23-px-items")
	hub.category = "consumable"
	hub.selected_item = "coffee"
	hub._refresh()
	await process_frame
	await capture("27-px-consumables")
	hub._switch_tab("inventory")
	hub.category = "consumable"
	hub.selected_item = "choco_pie"
	hub._refresh()
	await process_frame
	await click(hub.quick_slot_buttons[0])
	check(store.profile.quick_slots[0] == "choco_pie" and store.quantity("choco_pie") == 2, "Quick-slot registration consumed an item")
	store.apply_damage(50)
	await process_frame
	await click(hub.primary_action)
	check(store.get_vitals().health == 80 and store.quantity("choco_pie") == 1, "Actual use button did not heal and spend exactly one item")
	await capture("24-inventory")
	hub._switch_tab("equipment")
	await process_frame
	await capture("25-equipment")
	var restored := Store.new(prefix + ".cfg")
	check(restored.equipped("watch") and restored.quantity("choco_pie") == 1 and restored.profile.quick_slots[0] == "choco_pie" and restored.get_vitals().health == 80, "Inventory/equipment/quick-slot/vitals reload failed")
	var cancelled: Dictionary = store.begin_run("bedding")
	store.cancel_run(cancelled.token)
	check(store.quantity("choco_pie") == 1 and store.profile.quick_slots[0] == "choco_pie", "Quest cancel spent a recovery item")
	hub.queue_free()
	await process_frame
	# Training applies equipment only. Recovery supplies are never used automatically.
	var run: Dictionary = store.begin_run("bedding")
	var game: Control = load("res://scenes/training/bedding.tscn").instantiate()
	game.setup_training(store, run.token)
	root.add_child(game)
	await process_frame
	check(game.time_limit == 66 and store.quantity("choco_pie") == 1 and store.profile.quick_slots[0] == "choco_pie", "Training consumed recovery supplies or added a consumable time bonus")
	check(is_equal_approx(game.pieces.blanket.fold_assist, 0.15), "Gloves did not reach the folding mechanic")
	store.activate_run(run.token)
	check(store.quantity("choco_pie") == 1, "Repeated activation consumed recovery supplies")
	store.toggle_equipment("precision_gloves")
	check(is_equal_approx(game.loadout_effects.fold_assist, 0.15), "Equipment mutation changed an active run")
	await capture("26-bedding-equipment-effects")
	game._retry()
	check(game.time_limit == 66 and store.quantity("choco_pie") == 1, "Retry spent recovery supplies or retained an obsolete consumable buff")
	check(game.loadout_effects.get("fold_assist", 0) == 0 and game.loadout_effects.snap_degrees == 3, "Retry did not capture updated equipment")
	var mattress: Node2D = game.pieces.mattress
	mattress.fold_scores.assign([100.0])
	mattress.position = game.TARGETS.mattress
	mattress.rotation_degrees = 2.5
	check(game._try_place(mattress) and mattress.rotation == 0, "Precision gloves did not snap a near-correct angle")
	game._remove_from_stack("mattress")
	mattress.rotation_degrees = 30
	game._try_place(mattress)
	check(mattress.rotation_degrees > 29, "Angle assist corrected a large error")
	game.queue_free()
	await process_frame
	# Fold tolerance changes the actual release gate, not just a cosmetic stat label.
	for assist in [0.0, 0.15]:
		var piece := Piece.new()
		piece.dimensions = Vector2(300, 300)
		piece.folds.assign(["horizontal"])
		piece.fold_assist = assist
		piece.fold_progress = 0.87
		root.add_child(piece)
		check(piece.release_fold() == (assist > 0), "Glove tolerance does not affect fold release")
		piece.queue_free()
	await process_frame
	# The bonus uses the snapshotted effects and never multiplies the first-clear bonus.
	store.assign_quick_slot(1, "coffee")
	check(store.reward_for_score("bedding", 100, true) == 186, "Reward preview retained the obsolete coffee bonus or multiplies the first bonus")
	var boosted: Dictionary = store.begin_run("bedding")
	store.activate_run(boosted.token)
	store.toggle_equipment("ace_badge")
	store.toggle_equipment("field_cap")
	var result: Dictionary = store.finish_run(boosted.token, 100, true)
	check(result.reward == 186 and result.bonus_reward == 11 and store.quantity("coffee") == 1, "Reward lost equipment snapshot or consumed recovery supplies")
	check(not store.finish_run(boosted.token, 100, true).ok, "Boosted reward paid twice")
	var failed: Dictionary = store.begin_run("bedding", "replay")
	store.activate_run(failed.token)
	var coins: int = store.profile.coins
	store.finish_run(failed.token, 10, false)
	check(store.quantity("choco_pie") == 1 and store.profile.coins == coins, "Failed run consumed supplies or paid")
	store._item_cooldown_until_msec = 0
	check(store.use_item("choco_pie").ok and store.quantity("choco_pie") == 0, "Manual recovery did not use the remaining item")
	check(not store.assign_quick_slot(0, "choco_pie").ok, "Empty stack could be newly registered")
	store.profile.quantities.energy_bar = 99
	check(not store.buy("energy_bar").ok and store.profile.coins == coins, "Stack limit overspent coins")
	# A failed disk transaction must not mutate either inventory or a pending run.
	var broken := Store.new(prefix + "/missing/profile.cfg")
	broken.profile = store.profile.duplicate(true)
	broken.profile.quantities.choco_pie = 1
	broken.profile.vitals.health = 50.0
	var pending: Dictionary = broken.begin_run("bedding")
	check(broken.activate_run(pending.token).ok and broken.quantity("choco_pie") == 1, "Training attempted to save or spend recovery supplies")
	broken.cancel_run(pending.token)
	check(not broken.use_item("choco_pie").ok and broken.quantity("choco_pie") == 1 and broken.get_vitals().health == 50, "Failed recovery save changed health or inventory")
	check(not broken.buy("sports_drink").ok and broken.profile.coins == coins, "Failed purchase save mutated balance")
	# The actual explorer must use the equipped walking multiplier.
	var camp := Camp.new()
	camp.setup(store, "윤준성")
	camp.save_path = prefix + "-camp.cfg"
	root.add_child(camp)
	await process_frame
	camp.player.position = Vector2(1100, 900)
	await key(KEY_D, true)
	check(is_equal_approx(camp.player.velocity.x, 268.4), "Equipment did not change actual walking speed")
	await key(KEY_D, false)
	store.toggle_equipment("boots")
	await key(KEY_D, true)
	check(is_equal_approx(camp.player.velocity.x, 242.0), "Unequipping boots did not remove speed effect")
	await key(KEY_D, false)
	camp.queue_free()
	await process_frame
	for suffix in [".cfg", "-camp.cfg"]:
		if FileAccess.file_exists(prefix + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))
	for message in failures:
		push_error(message)
	print("LOADOUT_CHECK ", "PASS" if failures.is_empty() else "FAIL", " — legacy saves, GUI purchase/equip/use/quick-slot, slot replacement, manual recovery, training isolation, save failures, gear effects and reward snapshots")
	quit(0 if failures.is_empty() else 1)
