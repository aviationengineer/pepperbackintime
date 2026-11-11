extends SceneTree

## Debug: inspect the baked navigation polygon and map state.
## Run: godot --headless --path . --script test_nav_debug.gd

func _init() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	_run.call_deferred()

func _run() -> void:
	for i in range(10):
		await process_frame
	var region := root.get_node("Main/Navigation") as NavigationRegion2D
	print("REGION: ", region)
	var poly := region.navigation_polygon as NavigationPolygon
	print("POLYGON: outlines=", poly.get_outline_count(), " baked_polygons=", poly.get_polygon_count())
	for o in range(poly.get_outline_count()):
		print("  outline ", o, ": ", poly.get_outline(o))
	var maps: Array[RID] = NavigationServer2D.get_maps()
	print("MAPS: ", maps.size(), " iteration=", NavigationServer2D.map_get_iteration_id(maps[0]) if maps.size() > 0 else -1)
	if maps.size() > 0:
		NavigationServer2D.map_force_update(maps[0])
		await process_frame
		await process_frame
		print("after force_update iteration=", NavigationServer2D.map_get_iteration_id(maps[0]))
		var p: PackedVector2Array = NavigationServer2D.map_get_path(maps[0], Vector2(790, 660), Vector2(1010, 660), true)
		print("PATH: ", p)
		# Also try the region's own map
		print("region map: ", region.get_navigation_map())
		var p2: PackedVector2Array = NavigationServer2D.map_get_path(region.get_navigation_map(), Vector2(790, 660), Vector2(1010, 660), true)
		print("PATH via region map: ", p2)
	quit()
