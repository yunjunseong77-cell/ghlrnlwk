extends RefCounted

# Measured source-frame anchors. The original sprite and its silhouette remain intact.
const BODY := preload("res://assets/art/world/recruit_walk.png")
const CAPS := preload("res://assets/art/equipment/caps.png")
const CANTEENS := preload("res://assets/art/equipment/canteen_views.png")
const CELL := 362.0
const SCALE := 78.0 / CELL
const ORIGIN := Vector2(-39, -73)
const CAP_REGIONS := [Rect2(101,193,344,323), Rect2(559,206,475,273), Rect2(1135,206,474,273), Rect2(1720,212,359,269)]
const POUCH_REGIONS := [Rect2(124,114,307,466), Rect2(709,113,235,468), Rect2(1224,113,233,468), Rect2(1738,114,309,466)]
const CAP_FITS := [Rect2(145,15,74,49), Rect2(126,14,92,51), Rect2(145,14,92,51), Rect2(144,14,75,51)]
const HANDS := [
	[Rect2(116,188,29,30),Rect2(220,188,27,31)],
	[Rect2(167,202,33,31)], [Rect2(161,202,33,31)],
	[Rect2(115,189,27,31),Rect2(219,189,28,31)],
	[Rect2(119,178,37,38),Rect2(224,156,30,29)],
	[Rect2(96,146,36,37),Rect2(216,191,35,33)],
	[Rect2(229,146,36,37),Rect2(109,191,35,33)],
	[Rect2(107,199,31,32)],
	[Rect2(203,178,38,38),Rect2(109,159,31,29)],
	[Rect2(97,164,35,38),Rect2(215,150,33,33)],
	[Rect2(232,164,35,38),Rect2(108,150,34,33)],
	[Rect2(223,200,32,33)]
]
const BOOTS := [
	[Rect2(146,276,37,60),Rect2(183,276,36,60)],
	[Rect2(141,276,69,58)], [Rect2(152,276,70,58)],
	[Rect2(145,276,38,59),Rect2(183,276,37,59)],
	[Rect2(145,264,39,49),Rect2(172,292,41,46)],
	[Rect2(96,283,67,51),Rect2(195,275,69,55)],
	[Rect2(98,275,68,55),Rect2(202,283,65,51)],
	[Rect2(146,266,38,49),Rect2(174,294,42,44)],
	[Rect2(143,290,43,49),Rect2(183,265,38,50)],
	[Rect2(87,277,69,52),Rect2(202,278,67,51)],
	[Rect2(95,278,67,51),Rect2(208,277,66,52)],
	[Rect2(143,292,42,47),Rect2(184,266,38,49)]
]
const WRISTS := [Vector2(232,190),Vector2(185,204),Vector2(177,204),Vector2(129,192),Vector2(236,158),Vector2(117,151),Vector2(245,151),Vector2(121,202),Vector2(222,183),Vector2(231,155),Vector2(125,155),Vector2(237,203)]
const WRIST_ANGLES := [0.0,0.1,-0.1,0.0,-0.3,-0.65,0.65,0.1,0.55,-0.6,0.6,-0.1]
static var cap_cache: Array[Texture2D] = []
static var pouch_cache: Array[Texture2D] = []

static func _prepare_textures() -> void:
	if not cap_cache.is_empty():
		return
	for facing in range(4):
		var cap := AtlasTexture.new()
		cap.atlas = CAPS
		cap.region = CAP_REGIONS[facing]
		cap.filter_clip = true
		cap_cache.append(cap)
		var pouch := AtlasTexture.new()
		pouch.atlas = CANTEENS
		pouch.region = POUCH_REGIONS[facing]
		pouch.filter_clip = true
		pouch_cache.append(pouch)

static func point(source: Vector2) -> Vector2:
	return ORIGIN + source * SCALE

static func rectangle(source: Rect2) -> Rect2:
	return Rect2(point(source.position), source.size * SCALE)

static func draw_character(canvas: CanvasItem, loadout: Dictionary, facing: int, row: int = 0, tint: Color = Color.WHITE) -> void:
	facing = clampi(facing,0,3)
	row = clampi(row,0,2)
	_prepare_textures()
	if loadout.get("군장","") == "canteen" and facing == 2:
		_draw_pouch(canvas,facing,row,tint)
	canvas.draw_texture_rect_region(BODY,Rect2(ORIGIN,Vector2(78,78)),Rect2(Vector2(facing,row)*CELL,Vector2.ONE*CELL),tint)
	if loadout.get("군장","") == "shoulder_pad":
		_draw_pads(canvas,facing,row)
	if loadout.get("군장","") == "canteen" and facing != 2:
		_draw_pouch(canvas,facing,row,tint)
	var frame := row*4+facing
	if loadout.get("발","") == "boots":
		for region in BOOTS[frame]:
			_draw_body_region(canvas,region,facing,row,Color(1.72,1.62,1.28)*tint)
	var glove := str(loadout.get("손",""))
	if glove in ["gloves","precision_gloves"]:
		var tone := Color(0.33,0.47,0.36) if glove == "gloves" else Color(0.28,0.30,0.28)
		for region in HANDS[frame]:
			# Exact animated hand pixels retain finger shape and original light/shadow.
			_draw_body_region(canvas,region,facing,row,tone*tint)
			var center := point(region.get_center())
			if glove == "precision_gloves":
				canvas.draw_line(center+Vector2(-1.35,-0.5),center+Vector2(1.35,-0.5),Color("#9e8860"),1.1,true)
			else:
				canvas.draw_line(center+Vector2(-1,-1),center+Vector2(1,-1),Color(0.40,0.44,0.28,0.55),0.5,true)
	if loadout.get("손목","") == "watch":
		_draw_watch(canvas,frame)
	if loadout.get("명찰","") == "ace_badge" and facing == 0:
		var badge := rectangle(Rect2(194,111+row,25,9))
		canvas.draw_rect(badge,Color("#202d21"))
		canvas.draw_rect(badge.grow(-0.35),Color("#7c8b64"),false,0.45)
		canvas.draw_circle(badge.get_center(),0.60,Color("#e7c577"))
	if loadout.get("머리","") == "field_cap":
		var fit: Rect2 = CAP_FITS[facing]
		fit.position.y += row
		canvas.draw_texture_rect(cap_cache[facing],rectangle(fit),false,tint)

static func _draw_body_region(canvas: CanvasItem, region: Rect2, facing: int, row: int, color: Color) -> void:
	canvas.draw_texture_rect_region(BODY,rectangle(region),Rect2(region.position+Vector2(facing,row)*CELL,region.size),color)

static func _draw_pouch(canvas: CanvasItem, facing: int, row: int, tint: Color) -> void:
	var placements := [Rect2(122,207,29,43),Rect2(193,207,25,43),Rect2(143,207,23,43),Rect2(215,207,29,43)]
	var region: Rect2 = placements[facing]
	region.position.y += row*1.5
	var anchor := rectangle(region)
	canvas.draw_line(anchor.position+Vector2(anchor.size.x/2,-2),anchor.position+Vector2(anchor.size.x/2,3),Color("#3e4934"),1.5,true)
	canvas.draw_texture_rect(pouch_cache[facing],anchor,false,tint)

static func _draw_pads(canvas: CanvasItem, facing: int, row: int) -> void:
	var straps: Array = []
	if facing == 0:
		straps = [[Vector2(141,91),Vector2(143,141)],[Vector2(222,91),Vector2(219,141)]]
	elif facing == 3:
		straps = [[Vector2(139,95),Vector2(143,149)],[Vector2(222,95),Vector2(218,149)]]
	else:
		straps = [[Vector2(183 if facing==1 else 179,91),Vector2(184 if facing==1 else 178,145)]]
	for strap in straps:
		var start := point(strap[0]+Vector2(0,row))
		var end := point(strap[1]+Vector2(0,row))
		canvas.draw_line(start,end,Color("#263128"),3.3,true)
		canvas.draw_line(start,end,Color("#68714a"),2.5,true)
		canvas.draw_line(start+Vector2(-0.65,0),end+Vector2(-0.65,0),Color("#9a9d6c"),0.4,true)
		for seam in range(1,5):
			var at := start.lerp(end,seam/5.0)
			canvas.draw_line(at+Vector2(-0.85,0),at+Vector2(0.85,0),Color("#3c4733"),0.4,true)

static func _draw_watch(canvas: CanvasItem, frame: int) -> void:
	var at := point(WRISTS[frame])
	var along := Vector2.RIGHT.rotated(WRIST_ANGLES[frame])
	canvas.draw_line(at-along*2.25,at+along*2.25,Color("#202724"),1.6,true)
	canvas.draw_circle(at,1.25,Color("#72786b"))
	canvas.draw_circle(at,0.88,Color("#182d2b"))
	canvas.draw_line(at,at+Vector2(0,-0.6),Color("#c3d4b4"),0.35,true)
