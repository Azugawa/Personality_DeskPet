extends SceneTree
func _init() -> void:
	var source := Image.load_from_file("res://../asset_sources/spirit/animations/headpat/headpat_unified.png")
	var reference := Image.load_from_file("res://assets/character/spirit/idle/front_01.png")
	var reference_bounds := solid_bounds(reference)
	var factor := 1.0
	for i in 12:
		var edges := [0,340,700,1030,1380,1760,2172] if i < 6 else [0,365,710,1070,1420,1780,2172]
		edges[-1] = source.get_width()
		var x := i % 6
		var part := source.get_region(Rect2i(edges[x],0 if i < 6 else 390,edges[x+1]-edges[x],390 if i < 6 else 334))
		var bounds := solid_bounds(part)
		if i == 0: factor = float(reference_bounds.size.y) / bounds.size.y
		# One uniform scale for every frame; effects never change character scale.
		# Anchor to the pants/feet band, excluding hearts and moving hair.
		var base_y := bounds.end.y - 48
		var feet := solid_bounds(part.get_region(Rect2i(0,base_y,part.get_width(),48)))
		var foot := Vector2(feet.position.x + feet.size.x * 0.5,bounds.end.y)
		part.resize(roundi(part.get_width()*factor),roundi(part.get_height()*factor),Image.INTERPOLATE_NEAREST)
		var canvas := Image.create(512,384,false,Image.FORMAT_RGBA8)
		var origin := Vector2i(roundi(256-foot.x*factor),roundi(reference_bounds.end.y-foot.y*factor))
		canvas.blit_rect(part,Rect2i(Vector2i.ZERO,part.get_size()),origin)
		canvas.save_png("res://assets/character/spirit/headpat/%02d.png" % i)
	print("Headpat uniform scale: ", factor, " reference bounds: ",reference_bounds)
	quit()
func solid_bounds(image: Image) -> Rect2i:
	var lo := image.get_size()
	var hi := Vector2i.ZERO
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a > 0.5:
				lo.x=mini(lo.x,x)
				lo.y=mini(lo.y,y)
				hi.x=maxi(hi.x,x+1)
				hi.y=maxi(hi.y,y+1)
	return Rect2i(lo,hi-lo)
