extends Control

signal close_requested
signal launch_requested(training_id: String, token: String)

const ProgressStore := preload("res://scripts/training_progress.gd")
const ItemArt := preload("res://scripts/item_art.gd")
const Portrait := preload("res://scripts/equipment_portrait.gd")
const GOLD := Color("#e4c38c")
const PAPER := Color("#fff4de")
const MUTED := Color("#a9b5a3")
var store: RefCounted
var player_name := "윤준성"
var tab := "training"
var content: VBoxContainer
var balance_label: Label
var status_label: Label
var identity_label: Label
var tab_buttons: Dictionary = {}
var selected_item := "gloves"
var category := "all"
var slot_filter := ""
var item_buttons: Dictionary = {}
var primary_action: Button
var item_scroll: ScrollContainer
var item_scroll_value := 0
var quick_slot_buttons: Array[Button] = []
var use_action: Button
var vitals_label: Label
var portrait_view: Control
var preview_facing := 0
var preview_walking := false
var direction_buttons: Array[Button] = []
var walk_button: Button

func setup(progress_store: RefCounted, nickname: String, initial_tab: String) -> void:
	store = progress_store
	player_name = nickname
	tab = initial_tab

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.035, 0.025, 0.94)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + key, 48)
	for key in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + key, 30)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 17)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_child(_label("다시 쌓는, 나의 짬", 14, GOLD))
	identity_label = _label("", 25, PAPER)
	brand.add_child(identity_label)
	header.add_child(brand)
	var wallet := VBoxContainer.new()
	wallet.add_child(_label(str(store.catalog.currency_name), 14, MUTED))
	balance_label = _label("", 27, GOLD)
	wallet.add_child(balance_label)
	header.add_child(wallet)
	var back := _button("닫기", func() -> void: close_requested.emit())
	back.custom_minimum_size.x = 115
	header.add_child(back)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 12)
	layout.add_child(navigation)
	for entry in [["training", "훈련 나가기"], ["shop", "PX"], ["inventory", "아이템창"], ["equipment", "장비창"]]:
		var id := str(entry[0])
		var button := _button(str(entry[1]), func() -> void: _switch_tab(id))
		button.custom_minimum_size.x = 170
		navigation.add_child(button)
		tab_buttons[id] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	status_label = _label("", 16, GOLD)
	status_label.custom_minimum_size.y = 27
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)
	_refresh()

func _process(_delta: float) -> void:
	if is_instance_valid(vitals_label):
		var vitals: Dictionary = store.get_vitals()
		vitals_label.text = "HP  %d / %d     SP  %d / %d" % [ceili(vitals.health), vitals.max_health, ceili(vitals.stamina), vitals.max_stamina]
	if is_instance_valid(use_action):
		var cooldown: float = store.item_cooldown_remaining()
		use_action.disabled = store.quantity(selected_item) <= 0 or cooldown > 0
		use_action.text = "사용 대기 %.1f초" % cooldown if cooldown > 0 else "사용하기"

func _switch_tab(id: String) -> void:
	tab = id
	category = "all"
	slot_filter = ""
	item_scroll_value = 0
	item_scroll = null
	status_label.text = ""
	_refresh()

func _refresh() -> void:
	if is_instance_valid(item_scroll):
		item_scroll_value = item_scroll.scroll_vertical
	item_scroll = null
	use_action = null
	vitals_label = null
	portrait_view = null
	direction_buttons.clear()
	quick_slot_buttons.clear()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	balance_label.text = "%s" % store.profile.coins
	identity_label.text = player_name + (" · 에이스" if store.equipped("ace_badge") else " · 훈련 기록")
	for id in tab_buttons:
		var button: Button = tab_buttons[id]
		button.add_theme_color_override("font_color", GOLD if id == tab else PAPER)
		button.add_theme_stylebox_override("normal", _style(id == tab))
	if tab == "training":
		_training()
	elif tab == "shop":
		_shop()
	elif tab == "equipment":
		_equipment()
	else:
		_inventory()

func _training() -> void:
	content.add_child(_label("훈련 나가기", 30, PAPER))
	var visible_training: Array = store.catalog.training.filter(func(entry: Dictionary) -> bool: return not entry.get("retired", false))
	var completed: int = visible_training.filter(func(entry: Dictionary) -> bool: return store.cleared(str(entry.id))).size()
	content.add_child(_label("완료한 훈련  %d / %d   ·   사격은 지금 바로 도전할 수 있습니다." % [completed, visible_training.size()], 16, MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	content.add_child(grid)
	for entry in visible_training:
		var unlocked: bool = store.cleared(str(entry.id))
		var quick_play: bool = bool(entry.get("quick_play", false))
		var box := _card(grid)
		box.add_child(_label(("해금 완료" if unlocked else ("바로 플레이" if quick_play else "잠김")) + "   /   " + str(entry.tag), 13, GOLD if unlocked or quick_play else MUTED))
		box.add_child(_label(str(entry.name), 25, PAPER if unlocked or quick_play else Color("#879480")))
		var description := _label(str(entry.description), 15, MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(description)
		if unlocked:
			var record: Dictionary = store.profile.records[entry.id]
			box.add_child(_label("최고 %d점 · %s등급   |   완료 %d회" % [record.best, store.grade(int(record.best)), record.clears], 15, PAPER))
			if entry.id == "shooting" and record.has("best_raw_points"):
				box.add_child(_label("최고 %d POINTS   ·   %d COMBO" % [record.best_raw_points, record.get("best_combo", 0)], 16, GOLD))
			var minimum_score := int(entry.get("quest", {}).get("pass_score", 0))
			box.add_child(_label("재도전 보상  %d ~ %d   ·   등급에 따라 지급" % [store.reward_for_score(str(entry.id), minimum_score), store.reward_for_score(str(entry.id), 100)], 14, GOLD))
		else:
			box.add_child(_label(str(entry.unlock), 15, MUTED))
			box.add_child(_label("첫 완료 추가 보상  +%d" % entry.first_bonus, 14, GOLD))
		var button := _button("다시 도전" if unlocked else ("바로 도전" if quick_play else "완료 후 해금"), func() -> void: _launch(str(entry.id)))
		button.disabled = not unlocked and not quick_play
		box.add_child(button)

func _shop() -> void:
	_item_browser(true)

func _inventory() -> void:
	_item_browser(false)

func _item_browser(shop: bool) -> void:
	item_buttons.clear()
	primary_action = null
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	content.add_child(heading)
	var title := _label("PX · 보급의 즐거움" if shop else "아이템창 · 나의 보급품", 26, PAPER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	for pair in [["all", "전체"], ["equipment", "장비"], ["consumable", "소모품"]]:
		var key := str(pair[0])
		var filter := _button(str(pair[1]), func() -> void:
			category = key
			slot_filter = ""
			item_scroll_value = 0
			item_scroll = null
			_refresh()
		)
		filter.add_theme_stylebox_override("normal", _style(category == key))
		heading.add_child(filter)
	var entries: Array[Dictionary] = []
	for entry in store.catalog.items:
		if not shop and not store.owned(str(entry.id)):
			continue
		if category != "all" and entry.kind != category:
			continue
		if not slot_filter.is_empty() and entry.slot != slot_filter:
			continue
		entries.append(entry)
	if entries.is_empty():
		var empty := _card(content)
		empty.add_child(_label("보관 중인 물품이 없습니다." if slot_filter.is_empty() else slot_filter + " 부위의 장비가 없습니다.", 24, PAPER))
		empty.add_child(_label("훈련을 완료해 모은 코인으로 첫 장비와 간식을 골라보세요.", 17, MUTED))
		empty.add_child(_button("PX 둘러보기", func() -> void: _switch_tab("shop")))
		return
	if not entries.any(func(entry: Dictionary) -> bool: return entry.id == selected_item):
		selected_item = str(entries[0].id)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	content.add_child(body)
	var scroll := ScrollContainer.new()
	item_scroll = scroll
	scroll.custom_minimum_size = Vector2(740, 382)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for entry in entries:
		_item_tile(grid, entry, shop)
	scroll.set_deferred("scroll_vertical", item_scroll_value)
	_item_details(body, store.item(selected_item), shop)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in [KEY_I, KEY_K]:
			var target := "equipment" if key == KEY_K else "inventory"
			if tab == target:
				close_requested.emit()
			else:
				_switch_tab(target)
			get_viewport().set_input_as_handled()

func _item_tile(parent: Control, entry: Dictionary, shop: bool) -> void:
	var id := str(entry.id)
	var tile := _button("", func() -> void:
		selected_item = id
		_refresh()
	)
	tile.custom_minimum_size = Vector2(231, 174)
	tile.add_theme_stylebox_override("normal", _style(id == selected_item))
	parent.add_child(tile)
	item_buttons[id] = tile
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_right = -12
	box.offset_top = 9
	box.offset_bottom = -9
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 5)
	tile.add_child(box)
	var state_text: String = str(entry.slot)
	if store.equipped(id):
		state_text += "  ·  장착 중"
	elif id in store.profile.quick_slots:
		state_text += "  ·  퀵슬롯 %d" % (store.profile.quick_slots.find(id) + 1)
	elif store.owned(id):
		state_text += "  ·  보유 %d" % store.quantity(id)
	box.add_child(_label(state_text, 12, GOLD if store.owned(id) else MUTED))
	box.add_child(ItemArt.view(entry, Vector2(0, 82)))
	box.add_child(_label(str(entry.name), 18, PAPER))
	box.add_child(_label("%d 코인" % entry.price if shop else ("수량 %d" % store.quantity(id) if entry.kind == "consumable" else "클릭하여 효과 확인"), 13, GOLD))

func _item_details(parent: Control, entry: Dictionary, shop: bool) -> void:
	var id := str(entry.id)
	var box := _card(parent)
	box.custom_minimum_size.x = 300
	box.add_theme_constant_override("separation", 5)
	if entry.kind == "consumable":
		var identity := HBoxContainer.new()
		identity.add_theme_constant_override("separation", 8)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_child(_label(str(entry.name), 23, PAPER))
		copy.add_child(_label("회복 아이템 · 직접 사용할 때 1개 소모", 13, GOLD))
		identity.add_child(copy)
		identity.add_child(ItemArt.view(entry, Vector2(52, 52)))
		box.add_child(identity)
	else:
		box.add_child(_label(str(entry.name), 23, PAPER))
		box.add_child(_label(str(entry.slot) + " 슬롯 · 영구 장비", 13, GOLD))
		box.add_child(ItemArt.view(entry, Vector2(0, 72)))
	var description := _label(str(entry.description), 15, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	var effects := _label(store.effect_text(entry.effects), 16, Color("#a8dcc3"))
	effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(effects)
	if entry.kind == "equipment":
		var current: Dictionary = store.item(str(store.profile.equipment.get(entry.slot, "")))
		box.add_child(_label("현재 장비: " + str(current.get("name", "미착용")), 13, MUTED))
	else:
		vitals_label = _label("", 14, PAPER)
		box.add_child(vitals_label)
		box.add_child(_label("보유 %d개 · 회복이 필요할 때 사용\n공유 대기시간 1.5초 · 훈련 중 자동 소모 없음" % store.quantity(id), 13, MUTED))
	if shop and (entry.kind == "consumable" or not store.owned(id)):
		box.add_child(_label("%d  %s" % [entry.price, store.catalog.currency_name], 22, GOLD))
		primary_action = _button("1개 구매" if entry.kind == "consumable" else "장비 구매", func() -> void: _purchase(id))
		primary_action.disabled = int(store.profile.coins) < int(entry.price) or (entry.kind == "consumable" and store.quantity(id) >= 99)
		if primary_action.disabled:
			primary_action.text = "보관 한도 도달" if store.quantity(id) >= 99 else "코인 부족"
	elif entry.kind == "equipment":
		primary_action = _button("장착 해제" if store.equipped(id) else "장착하기", func() -> void: _equip(id))
	else:
		primary_action = _button("사용하기", func() -> void: _use_item(id))
		use_action = primary_action
	if entry.kind == "consumable":
		_compact_action(primary_action)
	if shop and store.owned(id) and entry.kind == "consumable":
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		primary_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(primary_action)
		use_action = _button("사용하기", func() -> void: _use_item(id))
		_compact_action(use_action)
		use_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(use_action)
		box.add_child(actions)
	else:
		box.add_child(primary_action)
	if entry.kind == "consumable" and store.owned(id):
		var quick_row := HBoxContainer.new()
		quick_row.add_theme_constant_override("separation", 8)
		for slot in range(2):
			var assigned: bool = store.profile.quick_slots[slot] == id
			var button := _small_button("퀵슬롯 %d %s" % [slot + 1, "해제" if assigned else "등록"], func() -> void: _assign_quick(slot, "" if assigned else id))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			quick_row.add_child(button)
			quick_slot_buttons.append(button)
		box.add_child(quick_row)

func _equipment() -> void:
	content.add_child(_label("장비창 · 준비된 훈련병", 28, PAPER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)
	var portrait_box := _card(row)
	portrait_box.custom_minimum_size.x = 220
	portrait_box.add_theme_constant_override("separation", 8)
	portrait_view = Portrait.new()
	portrait_view.equipment = store.profile.equipment.duplicate()
	portrait_view.facing = preview_facing
	portrait_view.moving = preview_walking
	portrait_view.custom_minimum_size = Vector2(220, 250)
	portrait_box.add_child(portrait_view)
	var directions := HBoxContainer.new()
	directions.add_theme_constant_override("separation", 5)
	for index in range(4):
		var button := _small_button(["앞", "왼쪽", "오른쪽", "뒤"][index], func() -> void: _set_preview_direction(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		directions.add_child(button)
		direction_buttons.append(button)
	portrait_box.add_child(directions)
	walk_button = _small_button("걷기 멈추기" if preview_walking else "걸어보기", _toggle_preview_walk)
	portrait_box.add_child(walk_button)
	portrait_box.add_child(_label("%d / 6 부위 착용" % store.profile.equipment.size(), 15, GOLD))
	_set_preview_direction(preview_facing)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	row.add_child(grid)
	for slot in ProgressStore.SLOTS:
		var id := str(store.profile.equipment.get(slot, ""))
		var entry: Dictionary = store.item(id)
		var button := _button("", func() -> void:
			tab = "inventory"
			category = "equipment"
			slot_filter = slot
			selected_item = id
			_refresh()
		)
		button.custom_minimum_size = Vector2(214, 123)
		grid.add_child(button)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 14
		box.offset_top = 10
		box.offset_right = -14
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(box)
		box.add_child(_label(slot, 13, GOLD))
		if not entry.is_empty():
			box.add_child(ItemArt.view(entry, Vector2(0, 57)))
		else:
			var empty := _label("＋", 30, MUTED)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.custom_minimum_size.y = 57
			box.add_child(empty)
		box.add_child(_label(str(entry.get("name", "장비 선택")), 16, PAPER))
	var stats := _card(row)
	stats.custom_minimum_size.x = 285
	stats.add_theme_constant_override("separation", 8)
	stats.add_child(_label("적용 중인 장비 효과", 20, GOLD))
	var effects := _label(store.effect_text(store.equipment_effects()), 16, PAPER)
	effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_child(effects)
	stats.add_child(_label("부위당 하나 · 슬롯을 눌러 교체", 13, MUTED))
	stats.add_child(HSeparator.new())
	stats.add_child(_label("현재 상태", 18, GOLD))
	vitals_label = _label("", 14, PAPER)
	stats.add_child(vitals_label)
	stats.add_child(_label("회복 퀵슬롯 · 탐색 중 1 / 2", 17, GOLD))
	for slot in range(2):
		var item: Dictionary = store.item(str(store.profile.quick_slots[slot]))
		stats.add_child(_label("%d  %s" % [slot + 1, str(item.get("name", "비어 있음"))], 16, PAPER))
	stats.add_child(_small_button("아이템창 열기", func() -> void: _switch_tab("inventory")))

func _set_preview_direction(direction: int) -> void:
	preview_facing = direction
	if is_instance_valid(portrait_view):
		portrait_view.facing = direction
		portrait_view.queue_redraw()
	for index in direction_buttons.size():
		direction_buttons[index].add_theme_stylebox_override("normal", _compact_style(index == direction))

func _toggle_preview_walk() -> void:
	preview_walking = not preview_walking
	if is_instance_valid(portrait_view):
		portrait_view.moving = preview_walking
		portrait_view.queue_redraw()
	walk_button.text = "걷기 멈추기" if preview_walking else "걸어보기"

func _use_item(id: String) -> void:
	var result: Dictionary = store.use_item(id)
	status_label.text = str(result.message)
	_refresh()

func _assign_quick(slot: int, id: String) -> void:
	var result: Dictionary = store.assign_quick_slot(slot, id)
	status_label.text = str(result.message)
	_refresh()

func _purchase(id: String) -> void:
	var result: Dictionary = store.buy(id)
	status_label.text = str(result.message)
	_refresh()

func _equip(id: String) -> void:
	var result: Dictionary = store.toggle_equipment(id)
	status_label.text = str(result.message)
	_refresh()

func _launch(id: String) -> void:
	var entry: Dictionary = store.training(id)
	if entry.get("retired", false) or (not store.cleared(id) and not entry.get("quick_play", false)):
		status_label.text = str(entry.get("unlock", "스토리에서 먼저 완료하세요."))
		return
	if not ResourceLoader.exists(str(entry.scene)):
		status_label.text = "이 훈련의 플레이 화면을 준비하고 있습니다."
		return
	var run: Dictionary = store.begin_run(id, "replay" if store.cleared(id) else "story")
	if not run.ok:
		status_label.text = str(run.message)
		return
	launch_requested.emit(id, str(run.token))

func _card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(false))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color("#788571"))
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(key, _style(key in ["hover", "pressed", "focus"]))
	button.pressed.connect(action)
	return button

func _small_button(text: String, action: Callable) -> Button:
	var button := _button(text, action)
	button.custom_minimum_size.y = 32
	button.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _compact_style(state in ["hover", "pressed", "focus"]))
	return button

func _compact_action(button: Button) -> void:
	button.custom_minimum_size.y = 42
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := _compact_style(state in ["hover", "pressed", "focus"])
		style.content_margin_top = 9
		style.content_margin_bottom = 9
		button.add_theme_stylebox_override(state, style)

func _compact_style(selected: bool) -> StyleBoxFlat:
	var style := _style(selected)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d3b2c") if selected else Color("#17231d")
	style.border_color = GOLD if selected else Color("#4b5c47")
	style.set_border_width_all(1)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

