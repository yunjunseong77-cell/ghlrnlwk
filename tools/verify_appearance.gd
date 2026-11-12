extends SceneTree

const Appearance := preload("res://scripts/soldier_appearance.gd")
const Portrait := preload("res://scripts/equipment_portrait.gd")
const Actor := preload("res://scripts/camp_actor.gd")
const FULL := {"머리":"field_cap","손":"gloves","발":"boots","손목":"watch","명찰":"ace_badge","군장":"canteen"}
var failures: Array[String] = []

class ReviewBoard extends Control:
	var kit: Dictionary = {}
	var individual := false
	func _draw() -> void:
		if individual:
			_draw_individual()
			return
		draw_rect(Rect2(0,0,1280,960),Color("#18241f"))
		draw_string(ThemeDB.fallback_font,Vector2(28,36),"장비 정합 검수 · 4방향 × 서기 / 걷기 두 프레임",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("#f4ecd7"))
		draw_string(ThemeDB.fallback_font,Vector2(28,66),"각 칸 왼쪽: 기본 복장    오른쪽: 장착    |    원본 캐릭터의 몸·손·발 위치를 공유합니다.",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("#b5c7b4"))
		for row in range(3):
			for facing in range(4):
				var origin := Vector2(facing*320,row*250+92)
				draw_rect(Rect2(origin+Vector2(8,0),Vector2(304,242)),Color("#26362b"))
				draw_string(ThemeDB.fallback_font,origin+Vector2(20,25),["앞","왼쪽","오른쪽","뒤"][facing]+" · "+["서기","걷기 A","걷기 B"][row],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("#e7c577"))
				for equipped in [false,true]:
					var feet := origin+Vector2(222 if equipped else 85,217)
					draw_set_transform(feet,0,Vector2(2.35,0.98))
					draw_circle(Vector2.ZERO,17,Color(0,0,0,0.3))
					draw_set_transform(feet,0,Vector2.ONE*2.35)
					Appearance.draw_character(self,kit if equipped else {},facing,row)
					draw_set_transform(Vector2.ZERO)
		draw_string(ThemeDB.fallback_font,Vector2(28,875),"실제 탐색 크기",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("#b5c7b4"))
		for facing in range(4):
			draw_set_transform(Vector2(300+facing*120,940))
			Appearance.draw_character(self,kit,facing)
			draw_set_transform(Vector2.ZERO)
	func _draw_individual() -> void:
		draw_rect(Rect2(0,0,1280,960),Color("#18241f"))
		draw_string(ThemeDB.fallback_font,Vector2(28,42),"장비별 단독 착용 · 왼쪽 기본 / 오른쪽 착용",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("#f4ecd7"))
		var entries := [["머리","field_cap","A급 전투모"],["손","gloves","훈련용 장갑"],["손","precision_gloves","정밀 작업 장갑"],["발","boots","경량 전투화"],["손목","watch","군용 손목시계"],["군장","shoulder_pad","군장 어깨 패드"],["군장","canteen","휴대 수통"],["명찰","ace_badge","에이스 명찰"]]
		for index in range(entries.size()):
			var origin := Vector2((index%4)*320,(index/4)*420+86)
			draw_rect(Rect2(origin+Vector2(8,0),Vector2(304,400)),Color("#26362b"))
			draw_string(ThemeDB.fallback_font,origin+Vector2(20,35),entries[index][2],HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("#e7c577"))
			for equipped in [false,true]:
				var feet := origin+Vector2(223 if equipped else 83,340)
				draw_set_transform(feet,0,Vector2.ONE*3.6)
				Appearance.draw_character(self,{entries[index][0]:entries[index][1]} if equipped else {},0)
				draw_set_transform(Vector2.ZERO)

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)

func capture(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)

func _run() -> void:
	root.size=Vector2i(1280,960)
	root.content_scale_size=Vector2i(1280,960)
	check(Appearance.BODY.get_size()==Vector2(1448,1086),"Original animation source dimensions changed")
	for i in range(4):
		check(Rect2(Vector2.ZERO,Appearance.CAPS.get_size()).encloses(Appearance.CAP_REGIONS[i]),"Cap region outside asset")
		check(Rect2(Vector2.ZERO,Appearance.CANTEENS.get_size()).encloses(Appearance.POUCH_REGIONS[i]),"Canteen region outside asset")
	var board:=ReviewBoard.new()
	board.kit=FULL.duplicate()
	root.add_child(board)
	await process_frame
	await capture("res://docs/previews/50-equipment-angles.png")
	board.kit["군장"]="shoulder_pad"
	board.kit["손"]="precision_gloves"
	board.queue_redraw()
	await process_frame
	await capture("res://docs/previews/51-equipment-alternate.png")
	board.individual=true
	board.queue_redraw()
	await process_frame
	await capture("res://docs/previews/52-equipment-slots.png")
	board.queue_free()
	await process_frame
	var portrait:=Portrait.new()
	portrait.size=Vector2(220,270)
	portrait.equipment=FULL.duplicate()
	root.add_child(portrait)
	if DisplayServer.get_name() != "headless":
		portrait.equipment={}
		await RenderingServer.frame_post_draw
		var plain := root.get_texture().get_image().get_region(Rect2i(0,0,220,270)).get_data()
		for entry in [["머리","field_cap"],["손","gloves"],["손","precision_gloves"],["발","boots"],["손목","watch"],["군장","shoulder_pad"],["군장","canteen"],["명찰","ace_badge"]]:
			portrait.equipment={entry[0]:entry[1]}
			portrait.queue_redraw()
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().get_region(Rect2i(0,0,220,270)).get_data()!=plain,"Standalone equipment has no visible appearance: "+entry[1])
	portrait.equipment=FULL.duplicate()
	portrait.rotate_preview(-1)
	check(portrait.facing==3,"Portrait rotation did not wrap")
	portrait.moving=true
	var previous_time:float=portrait.animation_time
	await create_timer(0.2).timeout
	check(portrait.animation_time>previous_time,"Portrait walk preview is not animated")
	portrait.queue_free()
	var actor:=Actor.new()
	actor.equipment=FULL.duplicate()
	root.add_child(actor)
	actor.step(Vector2.RIGHT,100,0.1)
	check(actor.facing==2,"World actor did not preserve right-facing convention")
	actor.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("APPEARANCE_CHECK ","PASS" if failures.is_empty() else "FAIL"," — source preserved, directional atlas regions, 12-pose kit render, rotating/walking portrait and world direction")
	quit(0 if failures.is_empty() else 1)
