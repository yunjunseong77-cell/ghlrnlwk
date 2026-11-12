extends RefCounted

# Training scenes call begin_run at entry, then finish_run once the result is settled.
# The hub never writes a clear record or grants coins just for opening a menu.
const CATALOG_PATH := "res://data/training_catalog.json"
const RANK_REWARD_RATE := {"S": 1.5, "A": 1.2, "B": 1.0, "C": 0.6}
const SLOTS := ["머리", "손", "발", "군장", "손목", "명찰"]
const MAX_HEALTH := 100.0
const MAX_STAMINA := 100.0
const ITEM_COOLDOWN := 1.5
const SPRINT_DRAIN := 12.0
const STAMINA_RECOVERY := 8.0
const STAMINA_RECOVERY_DELAY := 1.0
var catalog: Dictionary = {}
var profile: Dictionary = {"coins": 0, "records": {}, "inventory": [], "equipment": {}, "quantities": {}, "prepared": "", "quick_slots": ["", ""], "vitals": {"health": MAX_HEALTH, "stamina": MAX_STAMINA}}
var save_path: String
var sessions: Dictionary = {}
var serial := 0
var _dirty_vitals := false
var _recovery_delay := 0.0
var _item_cooldown_until_msec := 0

func _init(path: String = "user://training_profile.cfg") -> void:
	save_path = path
	catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	catalog.items = JSON.parse_string(FileAccess.get_file_as_string("res://data/px_items.json"))
	var config := ConfigFile.new()
	if config.load(save_path) == OK:
		profile.coins = maxi(0, int(config.get_value("profile", "coins", 0)))
		for key in ["records", "equipment", "quantities"]:
			var value: Variant = config.get_value("profile", key, {})
			if value is Dictionary:
				profile[key] = value
		var inventory: Variant = config.get_value("profile", "inventory", [])
		if inventory is Array:
			profile.inventory = inventory
		profile.prepared = str(config.get_value("profile", "prepared", ""))
		var quick_slots: Variant = config.get_value("profile", "quick_slots", ["", ""])
		if quick_slots is Array:
			for slot in range(mini(2, quick_slots.size())):
				profile.quick_slots[slot] = str(quick_slots[slot])
		var vitals: Variant = config.get_value("profile", "vitals", {})
		if vitals is Dictionary:
			profile.vitals.health = _valid_vital(vitals.get("health", MAX_HEALTH), MAX_HEALTH)
			profile.vitals.stamina = _valid_vital(vitals.get("stamina", MAX_STAMINA), MAX_STAMINA)
		_dirty_vitals = int(config.get_value("meta", "version", 1)) < 3
	# Migrate old equipment IDs/slots, keeping coins, records and owned equipment.
	for id in profile.inventory.duplicate():
		if item(str(id)).is_empty() or item(str(id)).kind != "equipment":
			profile.inventory.erase(id)
	for slot in profile.equipment.keys():
		var entry := item(str(profile.equipment[slot]))
		if entry.is_empty() or not owned(str(entry.id)) or entry.slot != slot or entry.kind != "equipment":
			profile.equipment.erase(slot)
	for id in profile.quantities.keys():
		var entry := item(str(id))
		if entry.is_empty() or entry.kind != "consumable":
			profile.quantities.erase(id)
		else:
			profile.quantities[id] = clampi(int(profile.quantities[id]), 0, 99)
	# Former training preparations become a manual quick slot; migration never spends an item.
	for slot in range(2):
		if item(str(profile.quick_slots[slot])).get("kind", "") != "consumable":
			profile.quick_slots[slot] = ""
	var legacy_prepared := str(profile.prepared)
	if str(profile.quick_slots[0]).is_empty() and quantity(legacy_prepared) > 0 and item(legacy_prepared).get("kind", "") == "consumable":
		profile.quick_slots[0] = legacy_prepared
	if profile.quick_slots[0] == profile.quick_slots[1]:
		profile.quick_slots[1] = ""
	profile.prepared = ""

func _valid_vital(value: Variant, maximum: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return maximum
	return clampf(float(value), 0.0, maximum)

func get_vitals() -> Dictionary:
	return {"health": float(profile.vitals.health), "max_health": MAX_HEALTH, "stamina": float(profile.vitals.stamina), "max_stamina": MAX_STAMINA}

func tick_vitals(delta: float, sprinting: bool) -> void:
	if delta <= 0.0 or not is_finite(delta) or float(profile.vitals.health) <= 0.0:
		return
	var before := float(profile.vitals.stamina)
	if sprinting:
		profile.vitals.stamina = maxf(0.0, before - SPRINT_DRAIN * delta)
		_recovery_delay = STAMINA_RECOVERY_DELAY
	else:
		var recovery_time := maxf(0.0, delta - _recovery_delay)
		_recovery_delay = maxf(0.0, _recovery_delay - delta)
		profile.vitals.stamina = minf(MAX_STAMINA, before + STAMINA_RECOVERY * recovery_time)
	if not is_equal_approx(before, float(profile.vitals.stamina)):
		_dirty_vitals = true

func save_vitals() -> bool:
	return _commit(profile.duplicate(true)) if _dirty_vitals else true

func apply_damage(amount: float) -> Dictionary:
	if not is_finite(amount) or amount <= 0.0:
		return {"ok": false, "message": "유효하지 않은 피해량입니다.", "damage": 0.0}
	var damage := minf(amount, float(profile.vitals.health))
	if damage <= 0.0:
		return {"ok": false, "message": "이미 행동 불능 상태입니다.", "damage": 0.0}
	var next := profile.duplicate(true)
	next.vitals.health = float(next.vitals.health) - damage
	if not _commit(next):
		return {"ok": false, "message": "체력 변화를 저장하지 못했습니다.", "damage": 0.0}
	return {"ok": true, "message": "체력 -%d" % ceili(damage), "damage": damage, "health": float(profile.vitals.health)}

func assign_quick_slot(index: int, id: String) -> Dictionary:
	if index < 0 or index >= 2:
		return {"ok": false, "message": "퀵슬롯을 찾을 수 없습니다."}
	if not id.is_empty() and (item(id).get("kind", "") != "consumable" or quantity(id) <= 0):
		return {"ok": false, "message": "보유한 소모품만 등록할 수 있습니다."}
	var next := profile.duplicate(true)
	for other in range(2):
		if other != index and not id.is_empty() and str(next.quick_slots[other]) == id:
			next.quick_slots[other] = ""
	next.quick_slots[index] = id
	next.prepared = ""
	if not _commit(next):
		return {"ok": false, "message": "퀵슬롯을 저장하지 못했습니다."}
	return {"ok": true, "message": "퀵슬롯 %d 비움" % (index + 1) if id.is_empty() else "%s · 퀵슬롯 %d 등록" % [str(item(id).name), index + 1]}

func item_cooldown_remaining() -> float:
	return maxf(0.0, float(_item_cooldown_until_msec - Time.get_ticks_msec()) / 1000.0)

func use_quick_slot(index: int, context: String = "exploration") -> Dictionary:
	if index < 0 or index >= 2:
		return {"ok": false, "message": "퀵슬롯을 찾을 수 없습니다.", "healed": 0.0, "stamina_restored": 0.0}
	var id := str(profile.quick_slots[index])
	if id.is_empty():
		return {"ok": false, "message": "아이템창에서 퀵슬롯에 소모품을 등록하세요.", "healed": 0.0, "stamina_restored": 0.0}
	return use_item(id, context)

func use_item(id: String, context: String = "exploration") -> Dictionary:
	var result := {"ok": false, "message": "", "healed": 0.0, "stamina_restored": 0.0}
	if context not in ["exploration", "combat"] or sessions.values().any(func(run: Dictionary) -> bool: return bool(run.get("active", false))):
		result.message = "훈련 평가 중에는 회복 물품을 사용하지 않습니다."
		return result
	var entry := item(id)
	if entry.get("kind", "") != "consumable" or quantity(id) <= 0:
		result.message = "사용할 소모품이 없습니다."
		return result
	if float(profile.vitals.health) <= 0.0:
		result.message = "행동 불능 상태에서는 회복 물품을 사용할 수 없습니다."
		return result
	if item_cooldown_remaining() > 0.0:
		result.message = "다음 물품 사용까지 %.1f초" % (ceilf(item_cooldown_remaining() * 10.0) / 10.0)
		return result
	var healed := minf(float(entry.effects.get("heal_hp", 0.0)), MAX_HEALTH - float(profile.vitals.health))
	var restored := minf(float(entry.effects.get("restore_stamina", 0.0)), MAX_STAMINA - float(profile.vitals.stamina))
	if healed <= 0.0 and restored <= 0.0:
		result.message = "이미 회복된 상태입니다. 물품은 소모하지 않았습니다."
		return result
	var next := profile.duplicate(true)
	next.vitals.health = float(next.vitals.health) + healed
	next.vitals.stamina = float(next.vitals.stamina) + restored
	next.quantities[id] = quantity(id) - 1
	if not _commit(next):
		result.message = "회복과 사용 내역을 저장하지 못했습니다. 물품은 그대로입니다."
		return result
	_item_cooldown_until_msec = Time.get_ticks_msec() + roundi(ITEM_COOLDOWN * 1000.0)
	var changes: Array[String] = []
	if healed > 0.0:
		changes.append("체력 +%d" % ceili(healed))
	if restored > 0.0:
		changes.append("지구력 +%d" % ceili(restored))
	return {"ok": true, "message": str(entry.name) + " 사용 · " + " / ".join(changes), "healed": healed, "stamina_restored": restored}

func training(id: String) -> Dictionary:
	for entry in catalog.training:
		if entry.id == id:
			return entry
	return {}

func item(id: String) -> Dictionary:
	for entry in catalog.items:
		if entry.id == id:
			return entry
	return {}

func cleared(id: String) -> bool:
	return profile.records.has(id)

func owned(id: String) -> bool:
	return quantity(id) > 0

func quantity(id: String) -> int:
	return int(profile.quantities.get(id, 0)) if item(id).get("kind", "") == "consumable" else (1 if id in profile.inventory else 0)

func equipped(id: String) -> bool:
	var entry := item(id)
	return not entry.is_empty() and profile.equipment.get(entry.slot, "") == id

func begin_run(id: String, mode: String = "story") -> Dictionary:
	if training(id).is_empty() or mode not in ["story", "replay"]:
		return {"ok": false, "message": "훈련을 찾을 수 없습니다."}
	if mode == "replay" and not cleared(id):
		return {"ok": false, "message": "스토리에서 먼저 이 훈련을 완료하세요."}
	serial += 1
	var token := "%d-%d" % [Time.get_ticks_usec(), serial]
	sessions[token] = {"training": id, "mode": mode, "active": false, "effects": {}}
	return {"ok": true, "token": token}

func activate_run(token: String) -> Dictionary:
	if not sessions.has(token):
		return {"ok": false, "message": "유효하지 않은 도전입니다."}
	if sessions[token].active:
		return {"ok": true}
	var id := str(sessions[token].training)
	var effects := preview_effects(id)
	sessions[token].effects = effects
	sessions[token].consumed = ""
	sessions[token].active = true
	return {"ok": true}

func prepare_item(id: String) -> Dictionary:
	# Compatibility for older callers: preparation now only toggles the first quick slot.
	return assign_quick_slot(0, "" if str(profile.quick_slots[0]) == id else id)

func equipment_effects(replacing: String = "") -> Dictionary:
	var effects: Dictionary = {}
	var equipment: Dictionary = profile.equipment.duplicate()
	if not replacing.is_empty():
		var entry := item(replacing)
		if entry.get("kind", "") == "equipment":
			equipment[entry.slot] = replacing
	for id in equipment.values():
		_add_effects(effects, item(str(id)).get("effects", {}))
	return effects

func preview_effects(training_id: String = "bedding") -> Dictionary:
	var effects := equipment_effects()
	effects.erase("move_speed")
	if training_id != "bedding":
		for key in ["bedding_time", "fold_assist", "snap_degrees"]:
			effects.erase(key)
	return effects

func _add_effects(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		target[key] = float(target.get(key, 0)) + float(source[key])

func effect_text(effects: Dictionary, separator: String = "\n") -> String:
	var lines: Array[String] = []
	if float(effects.get("bedding_time", 0)) > 0:
		lines.append("침상 정리 시간 +%d초" % int(effects.bedding_time))
	if float(effects.get("fold_assist", 0)) > 0:
		lines.append("침구 접기 오차 허용 +%d%%" % roundi(float(effects.fold_assist) * 100))
	if float(effects.get("snap_degrees", 0)) > 0:
		lines.append("침구 기준각 ±%d° 자동 정렬" % int(effects.snap_degrees))
	if float(effects.get("move_speed", 0)) > 0:
		lines.append("탐색 이동 속도 +%d%%" % roundi(float(effects.move_speed) * 100))
	if float(effects.get("reward_bonus", 0)) > 0:
		lines.append("훈련 기본 보상 +%d%%" % roundi(float(effects.reward_bonus) * 100))
	if float(effects.get("heal_hp", 0)) > 0:
		lines.append("사용 시 체력 +%d" % int(effects.heal_hp))
	if float(effects.get("restore_stamina", 0)) > 0:
		lines.append("사용 시 지구력 +%d" % int(effects.restore_stamina))
	return separator.join(lines) if not lines.is_empty() else "적용 중인 추가 효과 없음"

func finish_run(token: String, score: int, passed: bool, metrics: Dictionary = {}) -> Dictionary:
	if not sessions.has(token):
		return {"ok": false, "message": "이미 정산했거나 유효하지 않은 도전입니다."}
	if score < 0 or score > 100:
		return {"ok": false, "message": "점수 범위가 올바르지 않습니다."}
	var run: Dictionary = sessions[token]
	if not passed:
		sessions.erase(token)
		return {"ok": true, "passed": false, "reward": 0, "first_clear": false}
	var first := not cleared(str(run.training))
	var rank := grade(score)
	var effects: Dictionary = run.get("effects", {})
	var reward := reward_for_score(str(run.training), score, first, effects)
	var base_reward := reward_for_score(str(run.training), score, first, {})
	var next := profile.duplicate(true)
	var record: Dictionary = next.records.get(run.training, {"best": 0, "clears": 0})
	var previous_best_points := int(record.get("best_raw_points", 0))
	var new_personal_best := false
	if run.training == "shooting" and metrics.has("raw_points"):
		var points := clampi(int(metrics.raw_points), 0, 1000000000)
		new_personal_best = points > previous_best_points
		record.best_raw_points = maxi(previous_best_points, points)
		record.best_combo = maxi(int(record.get("best_combo", 0)), clampi(int(metrics.get("best_combo", 0)), 0, 100000))
	record.best = maxi(int(record.best), score)
	record.clears = int(record.clears) + 1
	next.records[run.training] = record
	next.coins = int(next.coins) + reward
	if not _commit(next):
		return {"ok": false, "message": "보상을 저장하지 못했습니다. 다시 정산해주세요."}
	sessions.erase(token)
	return {"ok": true, "passed": true, "reward": reward, "bonus_reward": reward - base_reward, "rank": rank, "first_clear": first, "balance": profile.coins, "new_personal_best": new_personal_best, "previous_best_points": previous_best_points, "best_points": int(record.get("best_raw_points", 0)), "best_combo": int(record.get("best_combo", 0))}

func cancel_run(token: String) -> void:
	sessions.erase(token)

func buy(id: String) -> Dictionary:
	var entry := item(id)
	if entry.is_empty():
		return {"ok": false, "message": "판매 중인 물품이 아닙니다."}
	if owned(id) and entry.kind == "equipment":
		return {"ok": false, "message": "이미 보유한 물품입니다."}
	if entry.kind == "consumable" and quantity(id) >= 99:
		return {"ok": false, "message": "물품은 종류별로 99개까지 보관할 수 있습니다."}
	if int(profile.coins) < int(entry.price):
		return {"ok": false, "message": "훈련 보상을 더 모아주세요."}
	var next := profile.duplicate(true)
	next.coins = int(next.coins) - int(entry.price)
	if entry.kind == "consumable":
		next.quantities[id] = quantity(id) + 1
	else:
		next.inventory.append(id)
	if not _commit(next):
		return {"ok": false, "message": "구매 내역을 저장하지 못했습니다."}
	return {"ok": true, "message": entry.name + (" 구매 완료 · 아이템창에서 사용하거나 퀵슬롯에 등록하세요." if entry.kind == "consumable" else " 구매 완료 · 장비창에서 장착할 수 있습니다.")}

func toggle_equipment(id: String) -> Dictionary:
	var entry := item(id)
	if entry.is_empty() or not owned(id) or entry.get("kind", "") != "equipment":
		return {"ok": false, "message": "보유한 장비만 장착할 수 있습니다."}
	var next := profile.duplicate(true)
	if equipped(id):
		next.equipment.erase(entry.slot)
	else:
		next.equipment[entry.slot] = id
	if not _commit(next):
		return {"ok": false, "message": "장착 상태를 저장하지 못했습니다."}
	return {"ok": true, "message": entry.name + (" 장착 완료" if equipped(id) else " 장착 해제")}

func grade(score: int) -> String:
	if score >= 95:
		return "S"
	if score >= 85:
		return "A"
	if score >= 70:
		return "B"
	return "C"

func reward_for_score(id: String, score: int, first_clear: bool = false, applied_effects: Variant = null) -> int:
	var entry := training(id)
	if entry.is_empty() or score < 0 or score > 100:
		return 0
	var reward := roundi(float(entry.base_reward) * float(RANK_REWARD_RATE[grade(score)]))
	var effects: Dictionary = preview_effects(id) if applied_effects == null else applied_effects
	reward += roundi(reward * float(effects.get("reward_bonus", 0)))
	if first_clear:
		reward += int(entry.first_bonus)
	return reward

func _commit(next: Dictionary) -> bool:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 3)
	for key in next:
		config.set_value("profile", key, next[key])
	var staging := save_path + ".tmp"
	if config.save(staging) != OK:
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(staging), ProjectSettings.globalize_path(save_path)) != OK:
		return false
	profile = next
	_dirty_vitals = false
	return true

