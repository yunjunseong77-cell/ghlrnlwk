extends Control

signal training_requested(training_id: String)
signal hub_requested(tab: String)
signal exit_requested

const Actor := preload("res://scripts/camp_actor.gd")
const Minimap := preload("res://scripts/camp_minimap.gd")
const MAP := preload("res://assets/art/world/recruit_camp.png")
const HEADING := preload("res://assets/fonts/BlackHanSans-Regular.ttf")
const ItemArt := preload("res://scripts/item_art.gd")
const PAPER := Color("#f1f1df")
const GOLD := Color("#eac17e")
const MUTED := Color("#b5c5b7")
const CELL := 24.0
var store: RefCounted
var nickname := "윤준성"
var preview := false
var save_path := "user://camp_progress.cfg"
var data: Dictionary
var world_size := Vector2(2400, 1600)
var walk_bounds: Rect2
var obstacles: Array[Rect2] = []
var world: Node2D
var player: CharacterBody2D
var camera := Vector2.ZERO
var navigation := AStarGrid2D.new()
var path := PackedVector2Array()
var pending_interaction := ""
var nearest: Dictionary = {}
var suspended := false
var modal: Control
var mini: Control
var big_map: Control
var objective_label: Label
var wallet_label: Label
var interact_button: Button
var hint_label: Label
var location_label: Label
var day_label: Label
var route_point := Vector2.ZERO
var marker_layer: Node2D
var markers: Dictionary = {}
var elapsed := 0.0
var save_timer := 0.0
var has_saved_position := false
var talked_to_peer := false
var notice_label: Label
var campaign_clears: Dictionary = {}
var drill_debriefed := false
var bedding_greeted := false
var drill_briefed := false
var shooting_debriefed := false
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var health_label: Label
var stamina_label: Label
var quick_slot_buttons: Array[Button] = []
var quick_slot_icons: Array[TextureRect] = []
var quick_slot_counts: Array[Label] = []
var quick_slot_cooldowns: Array[Label] = []
var sprint_exhausted := false

func setup(progress_store: RefCounted, player_name: String, is_preview: bool = false, clears: Dictionary = {}) -> void:
	store = progress_store
	nickname = player_name
	preview = is_preview
	campaign_clears = clears

func _exit_tree() -> void:
	if not preview and store:
		store.save_vitals()

func completed(id: String) -> bool:
	return bool(campaign_clears.get(id, store.cleared(id)))

func objective_id() -> String:
	if not completed("bedding"):
		return "barracks"
	if completed("shooting"):
		return "px" if shooting_debriefed else "peer"
	if drill_briefed:
		return "range"
	return "instructor" if talked_to_peer else "peer"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/camp_world.json"))
	world_size = _vector(data.size)
	var bounds: Array = data.walk_bounds
	walk_bounds = Rect2(bounds[0], bounds[1], bounds[2], bounds[3])
	world = Node2D.new()
	add_child(world)
	var ground := Sprite2D.new()
	ground.texture = MAP
	ground.centered = false
	ground.scale = world_size / MAP.get_size()
	world.add_child(ground)
	for values in data.buildings:
		_add_wall(Rect2(values[0], values[1], values[2], values[3]))
	_add_boundary_walls()
	_build_navigation()
	var actors := Node2D.new()
	actors.y_sort_enabled = true
	world.add_child(actors)
	player = Actor.new()
	player.selected = true
	player.position = _vector(data.spawn)
	actors.add_child(player)
	for place in data.places:
		if place.get("actor", false):
			var actor := Actor.new()
			actor.position = _vector(place.position)
			actor.facing = int(place.get("facing", 0))
			actor.tint = Color("#c8d0b9") if place.id == "instructor" else Color("#eddfc8")
			actors.add_child(actor)
	_load_position()
	camera = player.position
	marker_layer = Node2D.new()
	world.add_child(marker_layer)
	_build_markers()
	_build_hud()
	_update_view(1.0)
	_refresh_status()

func _physics_process(delta: float) -> void:
	if suspended or is_instance_valid(modal) or not visible:
		player.step(Vector2.ZERO, 0, delta)
		return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if direction.length_squared() > 0:
		path.clear()
		pending_interaction = ""
	else:
		while not path.is_empty() and player.position.distance_to(path[0]) < 9:
			path.remove_at(0)
		if not path.is_empty():
			direction = player.position.direction_to(path[0])
	var vitals: Dictionary = store.get_vitals()
	if float(vitals.stamina) >= 15.0 or not Input.is_physical_key_pressed(KEY_SHIFT):
		sprint_exhausted = false
	if float(vitals.stamina) <= 0.0:
		sprint_exhausted = true
	var wants_sprint := Input.is_physical_key_pressed(KEY_SHIFT) and (preview or not sprint_exhausted)
	var speed := 305.0 if wants_sprint else 220.0
	speed *= 1.0 + float(store.equipment_effects().get("move_speed", 0))
	if not path.is_empty():
		speed = minf(speed, player.position.distance_to(path[0]) / maxf(delta, 0.001))
	player.step(direction.normalized(), speed, delta)
	if not preview:
		store.tick_vitals(delta, wants_sprint and player.get_real_velocity().length() > 8.0)
	if not pending_interaction.is_empty():
		var place := _place(pending_interaction)
		if player.position.distance_to(_vector(place.position)) <= 112:
			pending_interaction = ""
			_interact(place)
	save_timer += delta
	if save_timer > 2.0:
		save_timer = 0.0
		save_position()

func _process(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	_update_view(delta)
	_refresh_status()
	player.equipment = store.profile.equipment
	player.queue_redraw()
	for id in markers:
		var label: Label = markers[id]
		label.modulate.a = 1.0 if nearest.get("id", "") == id else 0.77
	queue_redraw()

func _input(event: InputEvent) -> void:
	if suspended or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode else event.keycode
		if key in [KEY_1, KEY_2] and not is_instance_valid(modal):
			_use_quick_slot(0 if key == KEY_1 else 1)
			get_viewport().set_input_as_handled()
			return
		if (event.physical_keycode in [KEY_I, KEY_K] or event.keycode in [KEY_I, KEY_K]) and not is_instance_valid(modal):
			if preview:
				_show_dialogue("보급품", "아이템과 장비 관리는 본편과 타이틀의 PX에서 이용할 수 있습니다.")
			else:
				path.clear()
				pending_interaction = ""
				hub_requested.emit("equipment" if event.physical_keycode == KEY_K or event.keycode == KEY_K else "inventory")
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_M or event.keycode == KEY_M:
			if is_instance_valid(modal):
				_close_panel()
			else:
				_show_map()
			get_viewport().set_input_as_handled()
		elif (event.physical_keycode == KEY_E or event.keycode == KEY_E) and not is_instance_valid(modal):
			interact_nearest()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if suspended or not visible or is_instance_valid(modal):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local := make_input_local(event) as InputEventMouseButton
		# GUI controls have consumed HUD clicks before unhandled input reaches the world.
		var target := world.to_local(local.position)
		var clicked := _nearest_to(target, 56.0)
		if not clicked.is_empty():
			navigate_to_place(str(clicked.id))
		else:
			move_to(target)
		get_viewport().set_input_as_handled()

func _update_view(delta: float) -> void:
	var half := size * 0.5
	var target := player.position.clamp(half, world_size - half)
	camera = camera.lerp(target, 1.0 - exp(-9.0 * delta))
	world.position = (half - camera).round()
	if is_instance_valid(mini):
		mini.player_position = player.position
		mini.objective = objective_position()
		mini.queue_redraw()
	if is_instance_valid(big_map):
		big_map.player_position = player.position
		big_map.queue_redraw()

func _refresh_status() -> void:
	nearest = _nearest_to(player.position, 112.0)
	interact_button.visible = not nearest.is_empty() and not is_instance_valid(modal) and not suspended
	if not nearest.is_empty():
		interact_button.text = "E   %s · %s" % [nearest.name, nearest.hint]
	var target := objective_id()
	var objectives := {"barracks": "생활관에서 침상 정리 퀘스트 확인", "peer": "옆자리 동기와 이야기하기", "instructor": "연병장 집합 · 조교와 이야기하기", "range": "동쪽 사격장 이동로 · 첫 사격에 도전", "px": "사격 평가 통과 · PX와 자유 탐색"}
	objective_label.text = str(objectives[target])
	location_label.text = "한 발로 증명하다" if completed("shooting") else ("몸이 기억하는 감각" if drill_briefed else "다시 밟는 연병장")
	day_label.text = "CHAPTER 01   /   육군훈련소   /   첫 사격 훈련일" if drill_briefed or completed("shooting") else "CHAPTER 01   /   육군훈련소   /   이틀 차 아침"
	if preview:
		objective_label.text = "자유롭게 둘러보기 · 본편 진행은 저장하지 않음"
	wallet_label.text = "%s  ·  %d %s" % [nickname, store.profile.coins, store.catalog.currency_name]
	var distance := int(player.position.distance_to(objective_position()))
	hint_label.text = "목표까지 %dm  ·  M 지도" % (distance / 20)
	_refresh_vitals()
	for id in markers:
		var place := _place(str(id))
		var active: bool = id == target and not preview
		markers[id].text = ("◆  " if active else "") + str(place.name)
		markers[id].add_theme_color_override("font_color", GOLD if active else PAPER)

func objective_position() -> Vector2:
	return _vector(_place(objective_id()).position)

func _add_wall(rect: Rect2, record: bool = true) -> void:
	if record:
		obstacles.append(rect)
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)

func _add_boundary_walls() -> void:
	_add_wall(Rect2(0, 0, world_size.x, walk_bounds.position.y), false)
	_add_wall(Rect2(0, walk_bounds.end.y, world_size.x, world_size.y - walk_bounds.end.y), false)
	_add_wall(Rect2(0, 0, walk_bounds.position.x, world_size.y), false)
	_add_wall(Rect2(walk_bounds.end.x, 0, world_size.x - walk_bounds.end.x, world_size.y), false)

func _build_navigation() -> void:
	navigation.region = Rect2i(0, 0, ceili(world_size.x / CELL), ceili(world_size.y / CELL))
	navigation.cell_size = Vector2.ONE * CELL
	navigation.offset = Vector2.ONE * CELL * 0.5
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	navigation.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	navigation.update()
	for x in navigation.region.size.x:
		for y in navigation.region.size.y:
			var point := Vector2(x + 0.5, y + 0.5) * CELL
			if not is_walkable(point):
				navigation.set_point_solid(Vector2i(x, y))

func is_walkable(point: Vector2) -> bool:
	if not walk_bounds.grow(-16).has_point(point):
		return false
	for rect in obstacles:
		if rect.grow(17).has_point(point):
			return false
	return true

func move_to(target: Vector2) -> bool:
	pending_interaction = ""
	if not is_walkable(target):
		_notice("건물이나 담장 밖으로는 이동할 수 없습니다.")
		return false
	var start := Vector2i(player.position / CELL)
	var end := Vector2i(target / CELL)
	if not navigation.is_in_boundsv(end) or navigation.is_point_solid(end):
		return false
	path = navigation.get_point_path(start, end)
	if path.is_empty():
		_notice("이곳으로 이어지는 길을 찾지 못했습니다.")
		return false
	path.append(target)
	route_point = target
	return true

func navigate_to_place(id: String) -> bool:
	var place := _place(id)
	if place.is_empty():
		return false
	var target := _vector(place.position)
	if player.position.distance_to(target) <= 112:
		_interact(place)
		return true
	if move_to(target):
		pending_interaction = id
		return true
	return false

func interact_nearest() -> void:
	nearest = _nearest_to(player.position, 112.0)
	if not nearest.is_empty():
		_interact(nearest)

func _place(id: String) -> Dictionary:
	for place in data.places:
		if place.id == id:
			return place
	return {}

func _nearest_to(point: Vector2, radius: float) -> Dictionary:
	var result: Dictionary = {}
	var shortest := radius
	for place in data.places:
		var distance := point.distance_to(_vector(place.position))
		if distance < shortest:
			shortest = distance
			result = place
	return result

func _interact(place: Dictionary) -> void:
	path.clear()
	pending_interaction = ""
	match str(place.action):
		"bedding":
			if preview:
				_show_dialogue("생활관", "이야기에서 회귀한 뒤 침상 정리 퀘스트를 받을 수 있습니다. 지금은 훈련소를 자유롭게 둘러보세요.")
			else:
				save_position()
				training_requested.emit("bedding")
		"shop":
			if preview:
				_show_dialogue("PX", "훈련을 완료해 모은 코인으로 물품을 구매하는 곳입니다. 본편에서 방문할 수 있습니다.")
			else:
				save_position()
				hub_requested.emit("shop")
		"equipment":
			if preview:
				_show_dialogue("훈련 준비실", "완료한 훈련의 기록을 확인하고 다시 도전할 수 있습니다.")
			else:
				save_position()
				hub_requested.emit("training")
		"peer":
			talked_to_peer = true
			if completed("shooting"):
				shooting_debriefed = true
				_show_dialogue("옆자리 훈련병", "야, 너 진짜 처음 쏜 거 맞아? 표적 올라오자마자 다 눕던데.\n\n%s: 운이 좋았지.\n(운은 무슨. 몸이 아직 기억하네.)\n\n녀석이 웃으며 PX 쪽을 가리켰다. 이제 잠깐 쉴 시간이다." % nickname)
			elif drill_briefed:
				_show_dialogue("옆자리 훈련병", "드디어 사격이다. 넌 왜 또 그렇게 태연하냐?\n\n(태연한 척이라도 해야지.)\n\n동쪽 사격장 이동로에 집합하래. 먼저 가 있어!")
			elif completed("bedding"):
				_show_dialogue("옆자리 훈련병", "%s, 침구 개는 거 어디서 배웠냐? 손이 안 멈추던데.\n\n(이걸 몇 번이나 했는지 말해 줘도 안 믿겠지.)\n\n조교가 연병장으로 나오래. 같이 가자." % nickname)
			else:
				_show_dialogue("옆자리 훈련병", "야, 너는 안 떨리냐? 난 조교만 보면 굳는다.\n\n(어제까지 나도 병장이었는데. 설명해 봐야 믿지도 않겠지.)")
			save_position()
		"dining":
			_show_dialogue("식당 앞", "식판 부딪히는 소리, 줄을 맞춰 들어가는 훈련병들.\n\n(이 냄새까지 다시 맡게 될 줄은 몰랐다. 아침부터 배는 또 고프네.)")
		"drill":
			if not completed("bedding"):
				_show_dialogue("조교", "훈련병! 생활관 침상 정리부터 끝내고 온다. 실시!\n\n(일병한테 지시받는 게 아직도 적응이 안 되네.)")
			else:
				_show_next_quest()
		"shooting":
			if preview:
				_show_dialogue("사격장 이동로", "교육대에서 사격장으로 이동하는 길입니다.\n홈의 '사격 바로하기'에서 지금 도전할 수도 있습니다.")
			elif not drill_briefed and not completed("shooting"):
				_show_dialogue("사격장 이동로", "아직 사격 집합 전입니다. 연병장 조교에게 다음 일과를 확인하세요.")
			else:
				save_position()
				training_requested.emit("shooting")
		"departure":
			_show_dialogue("교육대 출입로", "출입로 너머로 군용 버스 한 대가 지나간다.\n지금은 교육대 밖으로 나갈 수 없다.\n\n(저 버스 탈 때쯤이면 어디로 가게 될까.\n일단 오늘부터 버티자.)")

func _build_markers() -> void:
	for place in data.places:
		var label := _label(str(place.name), 15, PAPER)
		label.position = _vector(place.position) + Vector2(-110, -108)
		label.size.x = 220
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color(0.07, 0.12, 0.09, 0.80))
		marker_layer.add_child(label)
		markers[place.id] = label

func _build_hud() -> void:
	var header := _panel_at(Rect2(24, 22, 470, 74))
	day_label = _label("", 14, GOLD)
	header.add_child(day_label)
	location_label = _label("다시 밟는 연병장", 25, PAPER)
	location_label.add_theme_font_override("font", HEADING)
	header.add_child(location_label)
	var objectives := _panel_at(Rect2(24, 108, 470, 85))
	objectives.add_child(_label("탐색 미리보기" if preview else "현재 목표", 12, GOLD))
	objective_label = _label("", 18, PAPER)
	objectives.add_child(objective_label)
	hint_label = _label("", 12, MUTED)
	objectives.add_child(hint_label)
	var vitals_panel := _panel_at(Rect2(24, 205, 255, 76))
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 8)
	vitals_panel.add_child(health_row)
	health_row.add_child(_label("HP", 12, Color("#e6b49a")))
	health_bar = _vital_bar(Color("#ba775b"))
	health_row.add_child(health_bar)
	health_label = _label("", 12, PAPER)
	health_label.custom_minimum_size.x = 61
	health_row.add_child(health_label)
	var stamina_row := HBoxContainer.new()
	stamina_row.add_theme_constant_override("separation", 8)
	vitals_panel.add_child(stamina_row)
	stamina_row.add_child(_label("SP", 12, Color("#a7d4bb")))
	stamina_bar = _vital_bar(Color("#7dbb9c"))
	stamina_row.add_child(stamina_bar)
	stamina_label = _label("", 12, PAPER)
	stamina_label.custom_minimum_size.x = 61
	stamina_row.add_child(stamina_label)
	vitals_panel.add_child(_label("미리보기 · 상태 유지" if preview else "달리면 지구력 소모 · 쉬면 회복", 11, MUTED))
	var mini_panel := PanelContainer.new()
	mini_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mini_panel.position = Vector2(-242, 22)
	mini_panel.size = Vector2(218, 151)
	mini_panel.add_theme_stylebox_override("panel", _style())
	add_child(mini_panel)
	mini = Minimap.new()
	mini.custom_minimum_size = Vector2(202, 135)
	mini.markers.assign(_place_positions())
	mini.destination_requested.connect(func(point: Vector2) -> void:
		if not suspended and not is_instance_valid(modal):
			move_to(point)
	)
	mini_panel.add_child(mini)
	var bar := _panel_at(Rect2(24, 642, 1232, 57))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	bar.add_child(row)
	row.add_child(_label("WASD 이동 · Shift 달리기 · 클릭 이동 · E 대화 · M 지도 · I 아이템 · K 장비 · 1/2 회복", 14, MUTED))
	var menu := _button("메뉴", request_pause)
	menu.custom_minimum_size = Vector2(90, 34)
	row.add_child(menu)
	wallet_label = _label("", 13, PAPER)
	wallet_label.position = Vector2(26, 613)
	add_child(wallet_label)
	interact_button = _button("", interact_nearest)
	interact_button.position = Vector2(430, 550)
	interact_button.size = Vector2(420, 48)
	add_child(interact_button)
	notice_label = _label("", 15, GOLD)
	notice_label.position = Vector2(330, 602)
	notice_label.size = Vector2(620, 30)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.add_theme_constant_override("outline_size", 4)
	notice_label.add_theme_color_override("font_outline_color", Color("#17271e"))
	add_child(notice_label)
	for slot in range(2):
		var button := _button("", func() -> void: _use_quick_slot(slot))
		button.position = Vector2(1034 + slot * 112, 550)
		button.size = Vector2(102, 80)
		button.tooltip_text = "아이템창에서 회복 아이템을 등록하세요."
		add_child(button)
		quick_slot_buttons.append(button)
		var number := _label(str(slot + 1), 14, GOLD)
		number.position = Vector2(8, 4)
		button.add_child(number)
		var icon := TextureRect.new()
		icon.position = Vector2(23, 8)
		icon.size = Vector2(58, 52)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		quick_slot_icons.append(icon)
		var count := _label("비어 있음", 11, MUTED)
		count.position = Vector2(5, 60)
		count.size.x = 92
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(count)
		quick_slot_counts.append(count)
		var cooldown := _label("", 17, PAPER)
		cooldown.position = Vector2(5, 27)
		cooldown.size.x = 92
		cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cooldown.add_theme_constant_override("outline_size", 5)
		cooldown.add_theme_color_override("font_outline_color", Color("#10211a"))
		button.add_child(cooldown)
		quick_slot_cooldowns.append(cooldown)

func _vital_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(130, 13)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#283c32")
	background.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func _refresh_vitals() -> void:
	if not is_instance_valid(health_bar):
		return
	var vitals: Dictionary = store.get_vitals()
	health_bar.max_value = float(vitals.max_health)
	health_bar.value = float(vitals.health)
	stamina_bar.max_value = float(vitals.max_stamina)
	stamina_bar.value = float(vitals.stamina)
	health_label.text = "%d / %d" % [ceili(vitals.health), vitals.max_health]
	stamina_label.text = "%d / %d" % [ceili(vitals.stamina), vitals.max_stamina]
	var cooldown: float = store.item_cooldown_remaining()
	for slot in range(quick_slot_buttons.size()):
		var id := str(store.profile.quick_slots[slot])
		var item: Dictionary = store.item(id)
		var count: int = store.quantity(id)
		quick_slot_icons[slot].texture = ItemArt.texture(item) if not item.is_empty() else null
		quick_slot_icons[slot].modulate.a = 0.4 if count <= 0 or cooldown > 0 else 1.0
		quick_slot_counts[slot].text = "%d개" % count if not id.is_empty() else "비어 있음"
		quick_slot_cooldowns[slot].text = "%.1f" % cooldown if cooldown > 0 and not item.is_empty() else ""
		quick_slot_buttons[slot].disabled = preview or suspended or is_instance_valid(modal) or item.is_empty() or count <= 0 or cooldown > 0
		quick_slot_buttons[slot].tooltip_text = str(item.get("name", "아이템창에서 회복 아이템을 등록하세요."))

func _use_quick_slot(slot: int) -> void:
	if preview or suspended or is_instance_valid(modal) or not visible:
		return
	var result: Dictionary = store.use_quick_slot(slot)
	_notice(str(result.message))
	_refresh_vitals()

func _place_positions() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for place in data.places:
		points.append(_vector(place.position))
	return points

func _panel_at(rect: Rect2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _style())
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	return box

func _show_dialogue(speaker: String, text: String) -> void:
	var box := _open_panel(speaker)
	var content := _label(text, 21, PAPER)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.custom_minimum_size = Vector2(700, 160)
	box.add_child(content)
	box.add_child(_button("확인", _close_panel))

func _show_next_quest() -> void:
	var box := _open_panel("연병장 · 조교")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var art := TextureRect.new()
	art.texture = load("res://assets/art/quests/drill_quest.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.custom_minimum_size = Vector2(224, 280)
	row.add_child(art)
	var speech := "조교: 우향우!\n\n생각하기도 전에 발이 돌아갔다.\n옆 동기는 반대로 돌다 내 팔에 부딪혔다.\n\n동기: 야, 너 제식 어디서 배웠냐?\n\n(이걸 몇 년을 했는데.)\n\n조교: 거기 두 명, 떠들지 않습니다!"
	if drill_briefed:
		speech = "조교: 사격장 이동로에 집합합니다.\n표적 앞에서도 지금처럼 침착하게 합니다.\n\n(제식보다 이쪽이 낫지.\n손끝의 감각도 그대로일까.)\n\n동쪽 사격장 이동로에서\n첫 사격 퀘스트를 확인합니다."
	var description := _label(speech, 18, PAPER)
	row.add_child(description)
	if not preview and not drill_briefed:
		box.add_child(_button("다음 일과로", _advance_to_shooting_day))
	box.add_child(_button("확인" if drill_briefed or preview else "잠깐 기다리기", _close_panel))

func _advance_to_shooting_day() -> void:
	drill_briefed = true
	save_position()
	_show_dialogue("며칠 뒤 · 첫 사격 훈련일", "제식과 교육, 끝없는 집합이 며칠을 채웠다.\n어느새 첫 사격 훈련일이다.\n\n안전교육을 마친 훈련병들이 이동로에 줄을 선다.\n\n(전역하려면, 이번에도 제대로 보여 줘야겠지.)\n\n동쪽 사격장 이동로에서 퀘스트를 확인하세요.")

func on_training_return(id: String, passed: bool, score: int) -> void:
	if id == "bedding" and passed and not bedding_greeted:
		bedding_greeted = true
		_show_dialogue("조교", "침상 정리 확인했습니다. 전원 연병장으로 집합합니다!\n\n생활관 밖으로 나오자 옆자리 훈련병이 말을 걸려는 듯 다가왔다.\n\n(몸이 먼저 움직였다. 짬이 사라진 건 아니구나.)")
	elif id == "shooting" and passed:
		var praise := "표적을 놓치지 않네요. 오늘 사격은 이 훈련병이 기준입니다." if score >= 95 else ("사격 좋습니다. 다음에도 지금처럼 침착하게 합니다." if score >= 85 else "사격 평가 통과했습니다. 다음에는 더 정확하게 합니다.")
		_show_dialogue("조교", praise + "\n\n귀마개 너머로 동기들의 웅성거림이 들린다.\n옆자리 녀석이 할 말이 많아 보이는 얼굴로 다가온다.")
	elif not passed:
		_notice("언제든 다시 도전할 수 있습니다. 탐색하던 위치로 돌아왔습니다.")
	save_position()

func _show_map() -> void:
	var box := _open_panel("훈련소 지도")
	box.add_child(_label("목적지를 클릭하면 창을 닫고 해당 위치로 이동합니다.", 16, MUTED))
	big_map = Minimap.new()
	big_map.custom_minimum_size = Vector2(600, 400)
	big_map.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	big_map.player_position = player.position
	big_map.objective = objective_position()
	big_map.markers.assign(_place_positions())
	for place in data.places:
		if place.id != "peer":
			big_map.labels[str(place.name)] = _vector(place.position)
	big_map.destination_requested.connect(func(point: Vector2) -> void:
		_close_panel()
		move_to(point)
	)
	box.add_child(big_map)
	box.add_child(_button("닫기 · M", _close_panel))

func request_pause() -> void:
	if is_instance_valid(modal):
		_close_panel()
		return
	path.clear()
	pending_interaction = ""
	var box := _open_panel("잠깐 쉬어가기")
	box.add_child(_label("탐색 위치는 자동 저장됩니다." if not preview else "미리보기에서는 본편 탐색 위치와 보상이 바뀌지 않습니다.", 18, MUTED))
	box.add_child(_button("계속 탐색", _close_panel))
	box.add_child(_button("지도 보기", _show_map))
	box.add_child(_button("타이틀로", func() -> void:
		save_position()
		exit_requested.emit()
	))

func _open_panel(heading: String) -> VBoxContainer:
	_close_panel()
	path.clear()
	pending_interaction = ""
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.04, 0.03, 0.82)
	modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(24))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 720
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var title := _label(heading, 28, GOLD)
	title.add_theme_font_override("font", HEADING)
	box.add_child(title)
	return box

func _close_panel() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
	modal = null
	big_map = null

func save_position() -> void:
	if preview or not is_instance_valid(player):
		return
	store.save_vitals()
	var config := ConfigFile.new()
	config.set_value("camp", "position", player.position)
	config.set_value("camp", "talked_to_peer", talked_to_peer)
	config.set_value("camp", "drill_debriefed", drill_debriefed)
	config.set_value("camp", "bedding_greeted", bedding_greeted)
	config.set_value("camp", "drill_briefed", drill_briefed)
	config.set_value("camp", "shooting_debriefed", shooting_debriefed)
	config.save(save_path)

func _load_position() -> void:
	if preview:
		return
	var config := ConfigFile.new()
	if config.load(save_path) == OK:
		var saved: Variant = config.get_value("camp", "position", player.position)
		if saved is Vector2 and is_walkable(saved):
			player.position = saved
			has_saved_position = true
		talked_to_peer = bool(config.get_value("camp", "talked_to_peer", false))
		drill_debriefed = bool(config.get_value("camp", "drill_debriefed", false))
		bedding_greeted = bool(config.get_value("camp", "bedding_greeted", false))
		drill_briefed = bool(config.get_value("camp", "drill_briefed", completed("drill")))
		shooting_debriefed = bool(config.get_value("camp", "shooting_debriefed", false))

func _notice(text: String) -> void:
	notice_label.text = text
	var tween := create_tween()
	notice_label.modulate.a = 1.0
	tween.tween_interval(2.0)
	tween.tween_property(notice_label, "modulate:a", 0.0, 0.4)

func _draw() -> void:
	if not path.is_empty():
		var destination := world.position + route_point
		var radius := 11.0 + sin(elapsed * 4) * 2
		draw_arc(destination, radius, 0, TAU, 32, Color("#b7e4c6"), 2, true)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", PAPER)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := _style(10)
		style.bg_color = Color("#365348") if state in ["hover", "focus"] else Color("#20382f")
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	return button

func _style(margin: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.085, 0.065, 0.93)
	style.border_color = Color("#738b77")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _vector(values: Array) -> Vector2:
	return Vector2(values[0], values[1])
