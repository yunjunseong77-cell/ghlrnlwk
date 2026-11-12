extends SceneTree

const Store := preload("res://scripts/training_progress.gd")
var failures: Array[String] = []
var prefix := "res://.godot/vitals-check-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)

func _run() -> void:
	var fresh := Store.new(prefix + "-fresh.cfg")
	check(fresh.get_vitals().health == 100 and fresh.get_vitals().stamina == 100 and fresh.profile.quick_slots == ["", ""], "Fresh character has incorrect vitals or quick slots")
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "version", 2)
	legacy.set_value("profile", "coins", 321)
	legacy.set_value("profile", "inventory", ["gloves", "watch"])
	legacy.set_value("profile", "equipment", {"손": "gloves", "손목": "watch"})
	legacy.set_value("profile", "records", {"shooting": {"best": 96, "clears": 2, "best_raw_points": 8520, "best_combo": 24}})
	legacy.set_value("profile", "quantities", {"choco_pie": 2, "coffee": 1, "energy_bar": 2, "sports_drink": 1})
	legacy.set_value("profile", "prepared", "choco_pie")
	legacy.save(prefix + ".cfg")
	var store := Store.new(prefix + ".cfg")
	check(store.profile.coins == 321 and store.equipped("gloves") and store.equipped("watch") and store.profile.records.shooting.best_raw_points == 8520, "Migration lost currency, equipment, or shooting records")
	check(store.profile.quick_slots == ["choco_pie", ""] and store.profile.prepared == "" and store.quantity("choco_pie") == 2, "Legacy preparation was not migrated without consumption")
	check(store.save_vitals(), "Migrated profile did not save")
	var migrated := ConfigFile.new()
	migrated.load(prefix + ".cfg")
	check(migrated.get_value("meta", "version") == 3 and migrated.get_value("profile", "quantities").choco_pie == 2, "Schema migration was not persisted losslessly")
	check(store.assign_quick_slot(1, "choco_pie").ok and store.profile.quick_slots == ["", "choco_pie"], "Same item occupies two quick slots")
	check(store.assign_quick_slot(0, "coffee").ok and not store.assign_quick_slot(2, "coffee").ok and not store.assign_quick_slot(0, "gloves").ok, "Quick slot accepted invalid index/equipment")
	check(not store.use_item("choco_pie").ok and store.quantity("choco_pie") == 2 and store.item_cooldown_remaining() == 0, "Full health wasted an item or started cooldown")
	check(not store.use_item("coffee", "training").ok and store.quantity("coffee") == 1, "Training context allowed recovery")
	check(store.apply_damage(35).ok and store.get_vitals().health == 65, "Damage did not update health")
	var reloaded := Store.new(prefix + ".cfg")
	check(reloaded.get_vitals().health == 65, "Damage did not persist")
	var used: Dictionary = store.use_quick_slot(1, "combat")
	check(used.ok and used.healed == 30 and store.get_vitals().health == 95 and store.quantity("choco_pie") == 1, "Combat quick-slot recovery did not atomically spend and heal")
	check(not store.use_item("energy_bar").ok and store.quantity("energy_bar") == 2 and store.get_vitals().health == 95, "Shared cooldown allowed another recovery")
	while store.item_cooldown_remaining() > 0:
		await create_timer(0.05).timeout
	used = store.use_quick_slot(1)
	check(used.ok and used.healed == 5 and store.get_vitals().health == 100 and store.quantity("choco_pie") == 0, "Recovery exceeded max health or spent the wrong quantity")
	check(store.profile.quick_slots[1] == "choco_pie" and not store.use_quick_slot(1).ok, "Empty stack lost assignment or could still be used")
	store._item_cooldown_until_msec = 0
	store.tick_vitals(2.0, true)
	check(store.get_vitals().stamina == 76, "Sprinting drain is incorrect")
	reloaded = Store.new(prefix + ".cfg")
	check(reloaded.get_vitals().stamina == 100, "Frame tick wrote to disk")
	store.tick_vitals(0, false)
	store.tick_vitals(0.75, false)
	check(store.get_vitals().stamina == 76, "Stamina recovered before its delay or on a zero tick")
	store.tick_vitals(0.5, false)
	check(is_equal_approx(store.get_vitals().stamina, 78), "Delayed stamina regeneration did not account for partial time")
	check(store.save_vitals(), "Dirty stamina failed to flush")
	reloaded = Store.new(prefix + ".cfg")
	check(reloaded.get_vitals().stamina == 78 and reloaded.profile.quick_slots[1] == "choco_pie", "Stamina or empty quick slot failed to persist")
	used = store.use_quick_slot(0)
	check(used.ok and used.stamina_restored == 22 and store.get_vitals().stamina == 100 and store.quantity("coffee") == 0, "Stamina item failed to clamp to its maximum")
	store._item_cooldown_until_msec = 0
	store.apply_damage(15)
	store.tick_vitals(2.5, true)
	used = store.use_item("energy_bar")
	check(used.ok and used.healed == 15 and used.stamina_restored == 20 and store.get_vitals().health == 100 and store.get_vitals().stamina == 90 and store.quantity("energy_bar") == 1, "Combined recovery did not apply each useful effect once")
	store._item_cooldown_until_msec = 0
	# Training sessions only snapshot equipment; inventory and vitals are untouched.
	var quantities: Dictionary = store.profile.quantities.duplicate(true)
	var vitals: Dictionary = store.profile.vitals.duplicate(true)
	store.assign_quick_slot(0, "energy_bar")
	for id in ["bedding", "shooting", "drill"]:
		var run: Dictionary = store.begin_run(id)
		check(store.activate_run(run.token).ok, "Training activation failed: " + id)
		check(store.sessions[run.token].consumed == "" and store.profile.quantities == quantities and store.profile.vitals == vitals, "Training activation consumed recovery supplies: " + id)
		check(not store.sessions[run.token].effects.has("heal_hp") and not store.sessions[run.token].effects.has("restore_stamina"), "Recovery effects leaked into training bonuses")
		check(not store.use_item("energy_bar", "combat").ok, "Caller bypassed active training context")
		store.cancel_run(run.token)
	# Saving failures must preserve the currently visible live state as well as inventory.
	var broken := Store.new(prefix + "-missing/profile.cfg")
	broken.profile = store.profile.duplicate(true)
	broken.tick_vitals(1.0, true)
	var before: Dictionary = broken.profile.duplicate(true)
	check(not broken.use_item("energy_bar").ok and broken.profile == before and broken.item_cooldown_remaining() == 0, "Failed save consumed, healed, or started cooldown")
	check(not broken.apply_damage(10).ok and broken.profile == before, "Failed save applied damage")
	check(not broken.assign_quick_slot(1, "sports_drink").ok and broken.profile == before, "Failed save changed quick slots")
	check(not broken.save_vitals() and broken.profile == before, "Failed vitals flush changed live values")
	store.apply_damage(500)
	var remaining := store.quantity("energy_bar")
	check(store.get_vitals().health == 0 and not store.use_item("energy_bar").ok and store.quantity("energy_bar") == remaining, "Recovery revived an incapacitated character")
	check(not store.apply_damage(-5).ok and not store.use_quick_slot(-1).ok, "Invalid damage or quick-slot index accepted")
	for suffix in [".cfg", "-fresh.cfg"]:
		if FileAccess.file_exists(prefix + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))
	for reason in failures:
		push_error(reason)
	print("VITALS_CHECK ", "PASS" if failures.is_empty() else "FAIL", " — schema migration, manual recovery, quick slots, full-resource no-op, shared cooldown, sprint/regen, training isolation, atomic failures and reload")
	quit(0 if failures.is_empty() else 1)
