extends RefCounted

const ATLAS := preload("res://assets/art/items/px_items.png")
static var cache: Dictionary = {}

static func texture(entry: Dictionary) -> Texture2D:
	var index := int(entry.get("icon", 0))
	if not cache.has(index):
		var image := AtlasTexture.new()
		image.atlas = ATLAS
		var cell := ATLAS.get_size() / Vector2(4, 3)
		image.region = Rect2(Vector2(index % 4, index / 4) * cell, cell)
		image.filter_clip = true
		cache[index] = image
	return cache[index]

static func view(entry: Dictionary, extent: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture(entry)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = extent
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art
