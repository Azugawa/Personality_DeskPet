extends SceneTree
func _init() -> void:
	var centers: Array[float] = []
	for i in 12:
		var im := Image.load_from_file("res://assets/character/spirit/headpat/%02d.png" % i)
		var left := 512
		var right := 0
		for y in range(336,384):
			for x in 512:
				if im.get_pixel(x,y).a > 0.5:
					left=mini(left,x)
					right=maxi(right,x+1)
		centers.append((left+right)*0.5)
	print("HEADPAT FOOT CENTERS: ", centers)
	assert(centers.max()-centers.min() <= 1.0)
	quit()
