class_name Art
## Textures and the pixel font. Missing art falls back to a visible placeholder so the game always runs.

static var tex := {}

static func t(n: String) -> Texture2D:
	if tex.has(n): return tex[n]
	var path := "res://assets/art/%s.png" % n
	var tx: Texture2D = null
	if ResourceLoader.exists(path): tx = load(path)
	if tx == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8); img.fill(Color(1, 0, 1, 1))
		tx = ImageTexture.create_from_image(img)
	tex[n] = tx
	return tx

static func has(n: String) -> bool:
	return ResourceLoader.exists("res://assets/art/%s.png" % n)

## one frame of a sheet: frame i of row r, each frame w x h
static func frame(n: String, w: int, h: int, i: int, r := 0) -> Rect2:
	return Rect2(i * w, r * h, w, h)

## pixel text. big = the 12x16 font. align: 0 left, 1 centre, 2 right. Drawn with a 1px shadow.
static func text(ci: CanvasItem, s: String, pos: Vector2, col := Color.WHITE, big := false, align := 0, shadow := Color(0, 0, 0, 0.85)) -> void:
	var f := t("font_big" if big else "font")
	var cw := 12 if big else 6
	var ch := 16 if big else 8
	var w := s.length() * cw
	var x0: float = pos.x - (w / 2.0 if align == 1 else (float(w) if align == 2 else 0.0))
	x0 = floor(x0); var y0: float = floor(pos.y)
	for pass_i in 2:
		if pass_i == 0 and shadow.a <= 0.0: continue
		var c := shadow if pass_i == 0 else col
		var off := Vector2(1, 1) if pass_i == 0 else Vector2.ZERO
		if big and pass_i == 0: off = Vector2(1, 2)
		for i in s.length():
			var code := s.unicode_at(i) - 32
			if code <= 0 or code > 94: continue
			var src := Rect2((code % 16) * cw, (code / 16) * ch, cw, ch)
			ci.draw_texture_rect_region(f, Rect2(Vector2(x0 + i * cw, y0) + off, Vector2(cw, ch)), src, c)

static func text_w(s: String, big := false) -> int:
	return s.length() * (12 if big else 6)
