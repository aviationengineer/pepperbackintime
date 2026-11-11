extends SceneTree

## Headless navigation test: loads the PoC scene, waits for the navigation map
## to bake, then checks that NavigationServer2D routes AROUND both obstacles
## (workbench hole and stool hole) instead of straight through them.
## Run: godot --headless --path . --script test_nav.gd
## Exit code 0 = pass, 1 = fail.

var _failures := 0

func _init() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	_run.call_deferred()

func _check(name: String, cond: bool, detail: String) -> void:
	if cond:
		print("PASS ", name, " — ", detail)
	else:
		_failures += 1
		print("FAIL ", name, " — ", detail)

func _inside_rect(p: Vector2, r: Rect2) -> bool:
	return r.has_point(p)

func _path_avoids(path: PackedVector2Array, holes: Array, label: String) -> bool:
	# Every path vertex and every segment midpoint must stay out of the holes.
	for i in range(path.size()):
		for h in holes:
			if _inside_rect(path[i], h):
				print("  vertex inside hole: ", path[i], " in ", h)
				return false
	for i in range(path.size() - 1):
		var mid := (path[i] + path[i + 1]) * 0.5
		for h in holes:
			if _inside_rect(mid, h):
				print("  segment midpoint inside hole: ", mid, " in ", h)
				return false
	return true

func _run() -> void:
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var maps: Array[RID] = NavigationServer2D.get_maps()
	_check("nav map exists", maps.size() > 0, "maps=%d" % maps.size())
	if maps.is_empty():
		quit(1)
		return
	var map: RID = maps[0]
	var workbench := Rect2(60, 580, 640, 100)  # x60-700, y580-680
	var stool := Rect2(900, 620, 100, 80)      # x900-1000, y620-700

	# Route 1: Cadet start (790,660) -> Franklin approach (1010,660).
	# Direct line crosses the stool; the path must route around it.
	var p1: PackedVector2Array = NavigationServer2D.map_get_path(map, Vector2(790, 660), Vector2(1010, 660), true)
	print("PATH_TO_FRANKLIN: ", p1)
	_check("route1 has waypoints", p1.size() >= 3, "points=%d" % p1.size())
	_check("route1 avoids stool", _path_avoids(p1, [stool], "route1"), "avoids stool")
	_check("route1 reaches target", p1.size() > 0 and p1[p1.size() - 1].distance_to(Vector2(1010, 660)) < 15.0, "end=%s" % str(p1[p1.size() - 1]) if p1.size() > 0 else "empty")

	# Route 2: Cadet start (790,660) -> magnifier approach (300,690).
	# Direct line clips the workbench hole; the path must route around it.
	var p2: PackedVector2Array = NavigationServer2D.map_get_path(map, Vector2(790, 660), Vector2(300, 690), true)
	print("PATH_TO_MAGNIFIER: ", p2)
	_check("route2 has waypoints", p2.size() >= 3, "points=%d" % p2.size())
	_check("route2 avoids workbench", _path_avoids(p2, [workbench], "route2"), "avoids workbench")
	_check("route2 reaches target", p2.size() > 0 and p2[p2.size() - 1].distance_to(Vector2(300, 690)) < 15.0, "end=%s" % str(p2[p2.size() - 1]) if p2.size() > 0 else "empty")

	# Route 3: to the music player approach (860,665) — straight corridor, sanity.
	var p3: PackedVector2Array = NavigationServer2D.map_get_path(map, Vector2(790, 660), Vector2(860, 665), true)
	print("PATH_TO_DEVICE: ", p3)
	_check("route3 reaches target", p3.size() > 0 and p3[p3.size() - 1].distance_to(Vector2(860, 665)) < 15.0, "points=%d" % p3.size())

	print("NAV TEST FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
