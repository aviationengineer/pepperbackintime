extends Node2D

## Timeline Restorer: Back in Time — Godot v3 (full game).
## All 5 acts, every system, ported from v1 (data in data/game_data.json).
## Builds the whole game in code: scenes, navigation, characters, lights,
## particles, HUD, dialogue / truth / puzzle / quiz / modal UI, save/load.
## Original content only; history labelled FACT vs ALTERNATE TIMELINE.
##
## v1 rules ported exactly:
##   score 0, paradox 15, stability 85 at start.
##   add_paradox(n): paradox += n (0..100); stability -= js_round(n/2).
##   add_stability(n): stability += n (0..100); paradox -= js_round(n/2).
##   Truth first discovery: +50 score, +2 stability (HUD updates at once).
##   Puzzle solved: +score, paradox += paradoxReward (-5, final code -10).
##   Item pickup: +20. Combine: +50. First scene visit: +10.
##   Repair: +300, +10 stability, key digit, then the act quiz.
##   Act complete: +5 stability. Quiz pass: >= 2/5 correct.
##   Quiz points: 5/5=+500, 4/5=+350, 3/5=+200, 2/5=+100, 0-1 = retry.
##   Endings: >=95 Perfect, >=80 Successful, >=50 Damaged, else Catastrophic.
##   Ranks: >=95 & score>=3000 S; >=80 A; >=50 B; >=30 C; else D.
##   Final code: 7319 (Kite 7, Loom 3, Lens 1, Wing 9).

const VIEW_W := 1280.0
const VIEW_H := 720.0
const FLOOR_TOP := 560.0
const FLOOR_BOTTOM := 712.0
const CADET_HOME := Vector2(180, 665)
const SAVE_PATH := "user://timeline-restorer-v3-save.json"
const ARCHIVE_PATH := "user://timeline-restorer-v3-archive.json"

const REPAIR_GATES := {
	1: {"item": "resonator", "need": ["anachronism_workshop"], "clue": "hidden_ink_clue", "digit": 7, "name": "Kite"},
	2: {"item": "grounding_wrench", "need": ["sequence_loom", "testimony"], "clue": "", "digit": 3, "name": "Loom"},
	3: {"item": "sealed_correction", "need": ["sequence_discovery", "cipher_letter"], "clue": "", "digit": 1, "name": "Lens"},
	4: {"item": "wrench", "need": ["parts_pick", "sequence_assembly"], "clue": "", "digit": 9, "name": "Wing"},
}
const PUZZLE_ACTS := {
	"anachronism_workshop": 1, "sequence_franklin": 1, "sequence_loom": 2,
	"testimony": 2, "cipher_letter": 3, "sequence_discovery": 3,
	"parts_pick": 4, "sequence_assembly": 4, "memory_recall": 5, "final_code": 5,
}

# --- loaded data ---
var DATA := {}
var ACTS := {}
var SCENES := {}
var CHARACTERS := {}
var ITEMS := {}
var RECIPES := []
var TRUTHS := {}
var PUZZLES := {}
var DIALOGUES := {}
var QUIZZES := {}
var TIMELINE_EVENTS := []
var REPAIR_REQS := {}

# --- game state (v1 parity) ---
var score := 0
var paradox := 15
var stability := 85
var current_act := 1
var current_scene := "workshop"
var inventory: Array[String] = []
var discovered_truths: Array[String] = []
var solved_puzzles: Array[String] = []
var timeline_flags := {}
var dialogue_flags := {}
var visited_scenes: Array[String] = []
var quiz_results := {}
var key_digits := {}
var categories := {"knowledge": 0, "puzzles": 0, "truths": 0, "artifacts": 0, "restoration": 0, "exploration": 0}
var game_completed := false
var archive_truths: Array[String] = []
var event_log: Array[String] = []
var selected_item := ""
var use_mode := false
var input_locked := true
var ui_blocking := false
var pending_hotspot := ""
var autodemo := ""
var autodemo_act1_only := false
# Verification helpers (CLI only; never active in the shipped game):
# --shots-dir=/path  saves viewport PNGs at key moments (title, scenes, dialogue,
#   truth, quiz, ending); --clicktest injects one real mouse click and reports.
var shots_dir := ""
var clicktest := false
var autocontinue := false
var scene_shot := ""
var _shots_taken := {}
var shot_path := ""
var shot_delay := 8.0
var _shot_taken := false
var _time := 0.0

# --- nodes ---
var cadet: Cadet
var audio: AudioManager
var scene_root: Node2D
var _candle_light: PointLight2D
var _act_label: Label
var _objective_label: Label
var _score_label: Label
var _stability_label: Label
var _paradox_label: Label
var _inventory_box: HBoxContainer
var _inventory_scroll: ScrollContainer
var _hint_label: Label
var _caption_panel: PanelContainer
var _caption_label: Label
var _toast_label: Label
var _paradox_overlay: ColorRect
var _hotspot_areas := {}
var _hotspot_glows := {}
var _hotspot_labels := {}
var _npcs := {}
var _toast_tween: Tween
var _caption_tween: Tween

# --- modal / dialogue / truth / action layers ---
var _dialogue_layer: CanvasLayer
var _dialogue_speaker: Label
var _dialogue_text: RichTextLabel
var _dialogue_choices: VBoxContainer
var _dialogue_id := ""
var _dialogue_node := ""
var _dialogue_npc := ""
var _truth_layer: CanvasLayer
var _truth_title: Label
var _truth_status: Label
var _truth_object: Label
var _truth_fact: RichTextLabel
var _truth_era: Label
var _truth_conf: Label
var _truth_paradox: Label
var _truth_clue: Label
var _truth_note: Label
var _action_layer: CanvasLayer
var _action_panel: PanelContainer
var _action_title: Label
var _action_desc: RichTextLabel
var _action_buttons: VBoxContainer
var _action_hotspot := ""
var _modal_layer: CanvasLayer
var _modal_title: Label
var _modal_box: VBoxContainer
var _modal_scroll: ScrollContainer
var _title_layer: CanvasLayer
var _debug_layer: CanvasLayer
var _debug_text: RichTextLabel

# --- puzzle / quiz runtime ---
var _puzzle_id := ""
var _puzzle_selection: Array = []
var _puzzle_step_buttons := {}
var _puzzle_code_input: LineEdit
var _quiz_id := ""
var _quiz_index := 0
var _quiz_correct := 0
var _quiz_on_done: Callable
var _quiz_answered := false

func _ready() -> void:
	_parse_args()
	_load_data()
	audio = AudioManager.new()
	add_child(audio)
	_build_hud()
	_build_dialogue_ui()
	_build_truth_ui()
	_build_action_ui()
	_build_modal_ui()
	_build_debug_ui()
	cadet = Cadet.new()
	cadet.name = "Cadet"
	cadet.position = CADET_HOME
	cadet.audio = audio
	cadet.z_index = 10
	add_child(cadet)
	cadet.arrived.connect(_on_cadet_arrived)
	_load_archive()
	_check_web_autodemo()
	if scene_shot != "":
		_new_game()
		_run_scene_shot()
	elif autocontinue:
		_show_title_screen()
		_run_autocontinue()
	elif clicktest:
		_new_game()
		_run_clicktest()
	elif autodemo != "":
		_new_game()
	else:
		_show_title_screen()

func _process(delta: float) -> void:
	_time += delta
	if _candle_light:
		_candle_light.energy = 0.85 + 0.07 * sin(_time * 11.0) + 0.05 * sin(_time * 5.7 + 1.3)
	if _paradox_overlay:
		var base := float(paradox) * 0.0012
		if paradox >= 40:
			base += 0.03 * (0.5 + 0.5 * sin(_time * 3.0))
		_paradox_overlay.color.a = base
	if shot_path != "" and not _shot_taken and _time >= shot_delay:
		_shot_taken = true
		var img := get_viewport().get_texture().get_image()
		if img == null:
			print("SHOT_SKIP ", shot_path, " (no viewport image)")
			get_tree().quit()
			return
		var err := img.save_png(shot_path)
		print("SHOT_SAVED ", shot_path, " err=", err)
		get_tree().quit()

# --- setup -------------------------------------------------------------------

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autodemo":
			autodemo = "full"
		elif a.begins_with("--autodemo="):
			autodemo = a.trim_prefix("--autodemo=")
		elif a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-delay="):
			shot_delay = float(a.trim_prefix("--shot-delay="))
		elif a.begins_with("--shots-dir="):
			shots_dir = a.trim_prefix("--shots-dir=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
		elif a == "--clicktest":
			clicktest = true
		elif a == "--autocontinue":
			autocontinue = true
		elif a.begins_with("--scene-shot="):
			scene_shot = a.trim_prefix("--scene-shot=")

func _run_scene_shot() -> void:
	# Verification: jump straight to one scene and screenshot it.
	await get_tree().create_timer(4.0).timeout
	for act_key in ACTS.keys():
		var act: Dictionary = ACTS[act_key]
		if String(scene_shot) in Array(act.get("scenes", [])):
			current_act = int(act_key)
	travel_to(scene_shot)
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()

func _run_autocontinue() -> void:
	# Verification: load the autosave from the title screen and report the
	# restored state, proving the save/load round-trip in the running game.
	await get_tree().create_timer(0.5).timeout
	_continue_game()
	await get_tree().create_timer(4.5).timeout
	print("AUTOCONTINUE act=%d scene=%s score=%d stability=%d paradox=%d inventory=%d flags=%d truths=%d puzzles=%d scenes=%d completed=%s" % [
		current_act, current_scene, score, stability, paradox,
		inventory.size(), timeline_flags.size(), discovered_truths.size(),
		solved_puzzles.size(), visited_scenes.size(), str(game_completed)])
	_capture_shot("continue", 0.5)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _capture_shot(shot_name: String, delay := 0.4) -> void:
	# Verification screenshot hook: saves one PNG per named moment.
	if shots_dir == "" or _shots_taken.has(shot_name):
		return
	_shots_taken[shot_name] = true
	await get_tree().create_timer(delay).timeout
	if shots_dir == "":
		return
	var img := get_viewport().get_texture().get_image()
	if img == null:
		# Headless runs have no rendering server; nothing to capture.
		print("SHOT_SKIP ", shot_name, " (no viewport image)")
		return
	var path := shots_dir.path_join(shot_name + ".png")
	var err := img.save_png(path)
	print("SHOT_SAVED ", path, " err=", err)

func _run_clicktest() -> void:
	# Injects a REAL mouse click (motion + press + release) at the workshop
	# magnifying-glass hotspot and reports whether the click-to-walk pipeline
	# picked it up. Runs under Xvfb; quits after reporting.
	_log("INFO", "Clicktest started")
	await get_tree().create_timer(4.5).timeout
	var area := _hotspot_areas.get("magnifier_ws", null) as Area2D
	if area == null:
		print("CLICKTEST_FAIL no magnifier_ws area; keys=", _hotspot_areas.keys())
		get_tree().quit()
		return
	var screen_pos := get_viewport().get_canvas_transform() * area.global_position
	var mv := InputEventMouseMotion.new()
	mv.position = screen_pos
	Input.parse_input_event(mv)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen_pos
	Input.parse_input_event(press)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = screen_pos
	Input.parse_input_event(rel)
	await get_tree().create_timer(1.5).timeout
	var ok := pending_hotspot == "magnifier_ws" or cadet.velocity.length() > 1.0
	print("CLICKTEST ", "PASS" if ok else "FAIL", " pending=", pending_hotspot,
		" cadet_pos=", cadet.position, " speed=", cadet.velocity.length(),
		" screen_pos=", screen_pos)
	_capture_shot("clicktest-after", 0.3)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _check_web_autodemo() -> void:
	if not OS.has_feature("web"):
		return
	var search = JavaScriptBridge.eval("window.location.search", true)
	if typeof(search) == TYPE_STRING:
		if "autodemo=act1" in search:
			autodemo = "act1"
		elif "autodemo" in search:
			autodemo = "full"

func _load_data() -> void:
	var path := "res://data/game_data.json"
	if not FileAccess.file_exists(path):
		push_error("game_data.json missing")
		return
	var text := FileAccess.get_file_as_string(path)
	var j := JSON.new()
	if j.parse(text) != OK:
		push_error("game_data.json parse error: " + j.error_string)
		return
	DATA = j.data
	ACTS = DATA.get("acts", {})
	SCENES = DATA.get("scenes", {})
	CHARACTERS = DATA.get("characters", {})
	ITEMS = DATA.get("items", {})
	RECIPES = DATA.get("recipes", [])
	TRUTHS = DATA.get("truths", {})
	PUZZLES = DATA.get("puzzles", {})
	DIALOGUES = DATA.get("dialogues", {})
	QUIZZES = DATA.get("quizzes", {})
	TIMELINE_EVENTS = DATA.get("timelineEvents", [])
	REPAIR_REQS = DATA.get("repairReqs", {})
	_sanitize_data(DATA)
	_log("INFO", "Data loaded: %d acts, %d scenes, %d characters, %d items, %d truths, %d puzzles, %d dialogues, %d quizzes" % [
		ACTS.size(), SCENES.size(), CHARACTERS.size(), ITEMS.size(), TRUTHS.size(), PUZZLES.size(), DIALOGUES.size(), QUIZZES.size()])

func _sanitize_data(v) -> void:
	# Strip emoji / symbol glyphs the web export's font cannot render, from
	# every string in the data. Keeps curly quotes, em-dashes, accents.
	if v is Dictionary:
		for k in v.keys():
			var val = v[k]
			if val is String:
				v[k] = _sanitize_text(val)
			else:
				_sanitize_data(val)
	elif v is Array:
		for i in range(v.size()):
			if v[i] is String:
				v[i] = _sanitize_text(v[i])
			else:
				_sanitize_data(v[i])

func _sanitize_text(s: String) -> String:
	var out := ""
	for ch in s:
		var cp := ch.unicode_at(0)
		if cp >= 0x1F000 or (cp >= 0x2600 and cp <= 0x27BF) or (cp >= 0x2B00 and cp <= 0x2BFF) or cp == 0xFE0F:
			continue
		out += ch
	return out

# --- v1 rules ------------------------------------------------------------------

func js_round(x: float) -> int:
	# JS Math.round: halves round toward +infinity (-2.5 -> -2).
	return int(floor(x + 0.5))

func add_paradox(n: int) -> void:
	paradox = clampi(paradox + n, 0, 100)
	stability = clampi(stability - js_round(n / 2.0), 0, 100)
	_log("INFO", "Paradox %+d -> %d%%; stability %d%%" % [n, paradox, stability])
	_update_labels()

func add_stability(n: int) -> void:
	stability = clampi(stability + n, 0, 100)
	paradox = clampi(paradox - js_round(n / 2.0), 0, 100)
	_log("INFO", "Stability +%d -> %d%%; paradox %d%%" % [n, stability, paradox])
	_update_labels()

func add_score(n: int, category: String) -> void:
	score += n
	if categories.has(category):
		categories[category] = int(categories[category]) + n
	_update_labels()

func apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	if effects.has("paradox"):
		add_paradox(int(effects["paradox"]))
	if effects.has("stability"):
		add_stability(int(effects["stability"]))
	if effects.has("score"):
		add_score(int(effects["score"]), "knowledge")
	if effects.has("flag"):
		timeline_flags[String(effects["flag"])] = true
		_log("INFO", "Timeline flag set: " + String(effects["flag"]))
	if effects.has("item"):
		_add_item(String(effects["item"]))
	if effects.has("truth"):
		_discover_truth(String(effects["truth"]), true)

func paradox_band() -> String:
	if paradox <= 20:
		return "stable"
	if paradox <= 40:
		return "minor"
	if paradox <= 60:
		return "unstable"
	if paradox <= 80:
		return "severe"
	return "critical"

func paradox_band_label() -> String:
	return {"stable": "Stable", "minor": "Minor distortion", "unstable": "Timeline unstable", "severe": "Severe distortion", "critical": "Critical paradox"}[paradox_band()]

func key_digits_text() -> String:
	var parts: Array[String] = []
	for a in [1, 2, 3, 4]:
		if key_digits.has(str(a)):
			parts.append(str(int(key_digits[str(a)])))
		else:
			parts.append("_")
	return " ".join(parts)

func _log(level: String, msg: String) -> void:
	var line := "[%s] %s" % [level, msg]
	event_log.append(line)
	if event_log.size() > 120:
		event_log.remove_at(0)
	print(line)

# --- acts & scenes -------------------------------------------------------------

func start_act(n: int) -> void:
	current_act = n
	audio.set_act(n)
	var act: Dictionary = ACTS.get(str(n), {})
	current_scene = String(act.get("scenes", ["workshop"])[0])
	_show_act_title_card(n, act)

func _show_act_title_card(n: int, act: Dictionary) -> void:
	input_locked = true
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_title_layer = layer
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 360)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.10, 0.07, 0.97), Color(0.85, 0.65, 0.25), 12, 3))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	center.add_child(panel)
	_capture_shot("act-title-%d" % n, 0.6)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var act_l := Label.new()
	act_l.text = "ACT %d" % n
	act_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act_l.add_theme_font_size_override("font_size", 58)
	act_l.add_theme_color_override("font_color", Color(0.91, 0.71, 0.30))
	vb.add_child(act_l)
	var title_l := Label.new()
	title_l.text = String(act.get("title", ""))
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.add_theme_font_size_override("font_size", 26)
	title_l.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	vb.add_child(title_l)
	var sub_l := Label.new()
	sub_l.text = String(act.get("subtitle", ""))
	sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_l.add_theme_font_size_override("font_size", 18)
	sub_l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vb.add_child(sub_l)
	var intro_l := Label.new()
	intro_l.text = String(act.get("intro", ""))
	intro_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_l.add_theme_font_size_override("font_size", 16)
	intro_l.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	vb.add_child(intro_l)
	# Ripple notes: timeline events whose flag is already set.
	var ripples: Array[String] = []
	for ev in TIMELINE_EVENTS:
		var e: Dictionary = ev
		if int(e.get("act", 0)) < n and timeline_flags.get(String(e.get("flag", "")), false):
			ripples.append(String(e.get("text", "")))
	if not ripples.is_empty():
		var rip_l := Label.new()
		rip_l.text = "\n".join(ripples)
		rip_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rip_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rip_l.add_theme_font_size_override("font_size", 15)
		rip_l.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0))
		vb.add_child(rip_l)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.5)
	tw.tween_interval(0.8 if autodemo != "" else 2.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_on_act_title_done)

func _on_act_title_done() -> void:
	if _title_layer:
		_title_layer.queue_free()
		_title_layer = null
	_load_scene(current_scene)
	input_locked = false
	_hint_label.visible = true
	_refresh_blocking()
	_save_game(true)
	if autodemo != "":
		_run_autodemo()

func _load_scene(scene_id: String) -> void:
	var scene: Dictionary = SCENES.get(scene_id, {})
	if scene.is_empty():
		_log("ERROR", "Scene not found: " + scene_id)
		_show_caption("This place cannot be reached. Choose another exit.")
		return
	current_scene = scene_id
	if not visited_scenes.has(scene_id):
		visited_scenes.append(scene_id)
		add_score(10, "exploration")
		_log("INFO", "Scene entered: " + scene_id)
	# Rebuild the scene layer.
	if scene_root:
		scene_root.queue_free()
	scene_root = Node2D.new()
	scene_root.name = "SceneRoot"
	add_child(scene_root)
	_hotspot_areas.clear()
	_hotspot_glows.clear()
	_hotspot_labels.clear()
	_npcs.clear()
	_build_background(scene_id)
	_build_navigation()
	_build_scene_hotspots(scene)
	_build_scene_lights()
	_build_particles()
	_build_foreground()
	_update_act_labels()
	cadet.position = CADET_HOME
	cadet.stop()
	cadet.z_index = 10
	# Cadet must stay on top of the fresh scene layer.
	remove_child(cadet)
	add_child(cadet)
	pending_hotspot = ""
	selected_item = ""
	_rebuild_inventory()
	_capture_shot("act%d-%s" % [current_act, scene_id], 1.1 if autodemo != "" else 3.0)

func _build_background(scene_id: String) -> void:
	var bg := Sprite2D.new()
	bg.name = "Background"
	var path := "res://art/bg-%s.png" % scene_id
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex == null:
		tex = _fallback_bg_texture()
	bg.texture = tex
	bg.position = Vector2(VIEW_W / 2.0, VIEW_H / 2.0)
	# Art is 960x540; scale to the 1280x720 viewport.
	bg.scale = Vector2(VIEW_W / 960.0, VIEW_H / 540.0)
	bg.z_index = 0
	scene_root.add_child(bg)

func _fallback_bg_texture() -> ImageTexture:
	var img := Image.create(960, 540, false, Image.FORMAT_RGB8)
	for y in range(540):
		for x in range(960):
			var t := float(y) / 540.0
			img.set_pixel(x, y, Color(0.16 + 0.1 * t, 0.12 + 0.08 * t, 0.08 + 0.06 * t))
	return ImageTexture.create_from_image(img)

func _build_navigation() -> void:
	# Walkable floor band across the bottom of the scene. Plain rectangle:
	# the backgrounds are generated paintings, so no authored obstacle
	# polygons exist; the cadet walks the floor in front of the furniture,
	# never on it. Holes must sit strictly inside the outline (PoC lesson),
	# and with no authored obstacles a single outline is the robust choice.
	var region := NavigationRegion2D.new()
	region.name = "Navigation"
	var poly := NavigationPolygon.new()
	# Direct vertex/polygon assignment (make_polygons_from_outlines is
	# deprecated in 4.7). Clockwise winding in Y-down screen space.
	poly.vertices = PackedVector2Array([
		Vector2(30, FLOOR_TOP), Vector2(1250, FLOOR_TOP),
		Vector2(1250, FLOOR_BOTTOM), Vector2(30, FLOOR_BOTTOM),
	])
	poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = poly
	scene_root.add_child(region)

func _build_scene_hotspots(scene: Dictionary) -> void:
	for hs in scene.get("hotspots", []):
		var h: Dictionary = hs
		var hid := String(h.get("id", ""))
		var pos := Vector2(float(h.get("x", 50)) / 100.0 * VIEW_W, float(h.get("y", 50)) / 100.0 * VIEW_H)
		# Collected items vanish.
		if h.has("item") and inventory.has(String(h["item"])):
			continue
		var npc_id := String(h.get("npc", ""))
		if npc_id != "":
			var ch: Dictionary = CHARACTERS.get(npc_id, {})
			var npc := Npc.new()
			npc.name = "NPC_" + npc_id
			var floor_pos := Vector2(pos.x, 665.0)
			npc.position = floor_pos
			npc.z_index = 9
			scene_root.add_child(npc)
			# chronarch_final is the same visual as the Chronarch (one sprite).
			var tex_id := "chronarch" if npc_id == "chronarch_final" else npc_id
			npc.setup(npc_id, "res://art/npc-%s.png" % tex_id, 300.0)
			npc.set_meta("hotspot_id", hid)
			_npcs[npc_id] = npc
			_hotspot_areas[hid] = npc
			_add_hotspot_label(pos, String(ch.get("name", npc_id)), Color(1.0, 0.85, 0.45))
			continue
		var area := Area2D.new()
		area.name = "Hotspot_" + hid
		area.collision_layer = 2
		area.collision_mask = 0
		area.set_meta("hotspot_id", hid)
		area.position = pos
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(110, 110)
		shape.shape = rect
		area.add_child(shape)
		scene_root.add_child(area)
		_hotspot_areas[hid] = area
		var glow_color := Color(1.0, 0.8, 0.3, 0.9)
		if bool(h.get("anomaly", false)):
			glow_color = Color(1.0, 0.35, 0.3, 0.95)
		elif h.has("puzzle"):
			glow_color = Color(0.4, 0.8, 1.0, 0.9)
		elif h.has("item"):
			glow_color = Color(0.5, 1.0, 0.5, 0.9)
		_add_glow(pos, glow_color, hid)
		_add_hotspot_label(pos, String(h.get("name", hid)), Color(0.95, 0.9, 0.78))

func _add_glow(pos: Vector2, color: Color, id: String) -> void:
	var glow := Sprite2D.new()
	glow.texture = _ring_texture(128, color)
	glow.position = pos
	glow.scale = Vector2(0.9, 0.9)
	glow.z_index = 5
	scene_root.add_child(glow)
	_hotspot_glows[id] = glow
	var tw := glow.create_tween().set_loops()
	tw.tween_property(glow, "modulate:a", 0.45, 0.8)
	tw.tween_property(glow, "modulate:a", 1.0, 0.8)

func _add_hotspot_label(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(pos.x - 70, pos.y - 78)
	l.size = Vector2(140, 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.z_index = 6
	scene_root.add_child(l)
	_hotspot_labels[text] = l

func _build_scene_lights() -> void:
	var tints := {
		1: Color(0.62, 0.60, 0.66), 2: Color(0.60, 0.62, 0.68),
		3: Color(0.64, 0.60, 0.62), 4: Color(0.68, 0.68, 0.70),
		5: Color(0.58, 0.56, 0.76),
	}
	var mod := CanvasModulate.new()
	mod.color = tints.get(current_act, Color(0.62, 0.60, 0.66))
	scene_root.add_child(mod)
	# Warm key light (candle / lamp side).
	_candle_light = PointLight2D.new()
	_candle_light.position = Vector2(990, 555)
	_candle_light.texture = _radial_texture(256, Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	_candle_light.color = Color(1.0, 0.72, 0.38)
	_candle_light.energy = 0.9
	_candle_light.texture_scale = 2.4
	scene_root.add_child(_candle_light)
	# Cool fill light (window / sky side).
	var fill := PointLight2D.new()
	fill.position = Vector2(260, 180)
	fill.texture = _radial_texture(256, Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	fill.color = Color(0.75, 0.88, 1.0)
	fill.energy = 0.4
	fill.texture_scale = 3.2
	scene_root.add_child(fill)

func _build_particles() -> void:
	var dust := CPUParticles2D.new()
	dust.name = "DustMotes"
	dust.position = Vector2(300, 260)
	dust.amount = 36
	dust.lifetime = 6.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(170, 130)
	dust.direction = Vector2(0, 1)
	dust.spread = 25.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 10.0
	dust.scale_amount_min = 1.5
	dust.scale_amount_max = 3.5
	dust.color = Color(1, 0.95, 0.8, 0.55)
	dust.texture = _radial_texture(32, Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	dust.z_index = 8
	scene_root.add_child(dust)

func _build_foreground() -> void:
	# Hanging branches frame the top corners for depth (storybook framing).
	if not ResourceLoader.exists("res://art/leaves.png"):
		return
	var left := Sprite2D.new()
	left.texture = load("res://art/leaves.png")
	left.position = Vector2(180, 40)
	left.scale = Vector2(0.55, 0.55)
	left.z_index = 20
	scene_root.add_child(left)
	var right := Sprite2D.new()
	right.texture = load("res://art/leaves.png")
	right.position = Vector2(1150, 30)
	right.scale = Vector2(-0.45, 0.45)
	right.z_index = 20
	scene_root.add_child(right)

func travel_to(scene_id: String) -> void:
	if not SCENES.has(scene_id):
		return
	audio.play_click()
	_close_action_popup()
	_load_scene(scene_id)

func _update_act_labels() -> void:
	var act: Dictionary = ACTS.get(str(current_act), {})
	var scene: Dictionary = SCENES.get(current_scene, {})
	_act_label.text = "%s  —  %s" % [String(act.get("title", "")), String(scene.get("name", ""))]
	_objective_label.text = "Anomaly: %s   •   Key digits: %s" % [String(act.get("anomaly", "")), key_digits_text()]

# --- HUD ---------------------------------------------------------------------

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)

	_act_label = Label.new()
	_act_label.position = Vector2(16, 12)
	_act_label.add_theme_font_size_override("font_size", 20)
	_act_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_act_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_act_label.add_theme_constant_override("shadow_offset_x", 2)
	_act_label.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(_act_label)

	_objective_label = Label.new()
	_objective_label.position = Vector2(16, 40)
	_objective_label.size = Vector2(760, 40)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_font_size_override("font_size", 14)
	_objective_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	_objective_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_objective_label.add_theme_constant_override("shadow_offset_x", 1)
	_objective_label.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(_objective_label)

	_score_label = Label.new()
	_score_label.position = Vector2(1020, 12)
	_score_label.add_theme_font_size_override("font_size", 20)
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_score_label.add_theme_constant_override("shadow_offset_x", 2)
	_score_label.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(_score_label)

	_stability_label = Label.new()
	_stability_label.position = Vector2(1020, 38)
	_stability_label.add_theme_font_size_override("font_size", 14)
	_stability_label.add_theme_color_override("font_color", Color(0.65, 0.95, 0.65))
	_stability_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_stability_label.add_theme_constant_override("shadow_offset_x", 1)
	_stability_label.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(_stability_label)

	_paradox_label = Label.new()
	_paradox_label.position = Vector2(1020, 58)
	_paradox_label.add_theme_font_size_override("font_size", 14)
	_paradox_label.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0))
	_paradox_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_paradox_label.add_theme_constant_override("shadow_offset_x", 1)
	_paradox_label.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(_paradox_label)

	var mute := Button.new()
	mute.text = "Sound: On"
	mute.position = Vector2(1020, 82)
	mute.custom_minimum_size = Vector2(118, 30)
	_style_button(mute, Color(0.85, 0.75, 0.55))
	mute.pressed.connect(_on_mute_pressed.bind(mute))
	hud.add_child(mute)

	var vol := Button.new()
	vol.text = "Vol: High"
	vol.position = Vector2(1146, 82)
	vol.custom_minimum_size = Vector2(118, 30)
	_style_button(vol, Color(0.85, 0.75, 0.55))
	vol.pressed.connect(_on_volume_pressed.bind(vol))
	hud.add_child(vol)

	var menu := Button.new()
	menu.text = "Menu"
	menu.position = Vector2(1020, 118)
	menu.custom_minimum_size = Vector2(118, 30)
	_style_button(menu, Color(0.85, 0.75, 0.55))
	menu.pressed.connect(_show_menu)
	hud.add_child(menu)

	var travel := Button.new()
	travel.text = "Travel"
	travel.position = Vector2(1146, 118)
	travel.custom_minimum_size = Vector2(118, 30)
	_style_button(travel, Color(0.85, 0.75, 0.55))
	travel.pressed.connect(_show_travel)
	hud.add_child(travel)

	_inventory_scroll = ScrollContainer.new()
	_inventory_scroll.position = Vector2(16, 668)
	_inventory_scroll.size = Vector2(760, 44)
	_inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	hud.add_child(_inventory_scroll)
	_inventory_box = HBoxContainer.new()
	_inventory_box.add_theme_constant_override("separation", 6)
	_inventory_scroll.add_child(_inventory_box)
	var inv_label := Label.new()
	inv_label.text = "Pack:"
	inv_label.add_theme_font_size_override("font_size", 15)
	inv_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	inv_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	inv_label.add_theme_constant_override("shadow_offset_x", 1)
	inv_label.add_theme_constant_override("shadow_offset_y", 1)
	_inventory_box.add_child(inv_label)

	_hint_label = Label.new()
	_hint_label.text = "Click to walk  •  Click glowing objects  •  F1 for debug"
	_hint_label.position = Vector2(790, 680)
	_hint_label.size = Vector2(474, 20)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_hint_label.visible = false
	hud.add_child(_hint_label)

	_caption_panel = PanelContainer.new()
	_caption_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption_panel.offset_left = -450
	_caption_panel.offset_right = 450
	_caption_panel.offset_top = -118
	_caption_panel.offset_bottom = -70
	_caption_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.1, 0.09, 0.07, 0.88), Color(0.72, 0.55, 0.2), 8, 2))
	_caption_panel.visible = false
	hud.add_child(_caption_panel)
	_caption_label = Label.new()
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.add_theme_font_size_override("font_size", 16)
	_caption_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.84))
	_caption_panel.add_child(_caption_label)

	# Toast lives on its own high layer so it shows above modals.
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 26
	add_child(toast_layer)
	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.offset_left = -400
	_toast_label.offset_right = 400
	_toast_label.offset_top = 110
	_toast_label.offset_bottom = 150
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.add_theme_font_size_override("font_size", 28)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_toast_label.add_theme_constant_override("shadow_offset_x", 2)
	_toast_label.add_theme_constant_override("shadow_offset_y", 2)
	_toast_label.visible = false
	toast_layer.add_child(_toast_label)

	_paradox_overlay = ColorRect.new()
	_paradox_overlay.color = Color(0.25, 0.8, 1.0, 0.0)
	_paradox_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paradox_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 5
	overlay_layer.add_child(_paradox_overlay)
	add_child(overlay_layer)

	_update_labels()

func _update_labels() -> void:
	# The PoC flaw: the paradox meter did not move when a Truth was found.
	# Every state change flows through here and updates ALL meters at once.
	if _score_label:
		_score_label.text = "Score: %d" % score
	if _stability_label:
		_stability_label.text = "Stability: %d%%" % stability
	if _paradox_label:
		_paradox_label.text = "Paradox: %d%% (%s)" % [paradox, paradox_band_label()]
	if _act_label and not SCENES.is_empty():
		_update_act_labels()

func _on_mute_pressed(btn: Button) -> void:
	var muted := audio.toggle_mute()
	btn.text = "Sound: Off" if muted else "Sound: On"

func _on_volume_pressed(btn: Button) -> void:
	btn.text = audio.cycle_volume()

func _show_toast(text: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.text = text
	_toast_label.visible = true
	_toast_label.modulate.a = 0.0
	_toast_tween = _toast_label.create_tween()
	_toast_tween.tween_property(_toast_label, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func() -> void: _toast_label.visible = false)

func _show_caption(text: String) -> void:
	if _caption_tween and _caption_tween.is_valid():
		_caption_tween.kill()
	_caption_label.text = text
	_caption_panel.visible = true
	_caption_panel.modulate.a = 0.0
	_caption_tween = _caption_panel.create_tween()
	_caption_tween.tween_property(_caption_panel, "modulate:a", 1.0, 0.3)
	_caption_tween.tween_interval(4.0)
	_caption_tween.tween_property(_caption_panel, "modulate:a", 0.0, 0.6)
	_caption_tween.tween_callback(func() -> void: _caption_panel.visible = false)

func _confetti() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_time * 1000.0) + 7
	var colors := [Color(1, 0.8, 0.3), Color(0.4, 0.8, 1), Color(1, 0.4, 0.4), Color(0.5, 1, 0.5), Color(0.9, 0.6, 1)]
	for i in range(36):
		var r := ColorRect.new()
		r.color = colors[rng.randi_range(0, colors.size() - 1)]
		r.size = Vector2(rng.randf_range(8, 16), rng.randf_range(8, 16))
		r.position = Vector2(rng.randf_range(80, 1200), -20)
		layer.add_child(r)
		var tw := r.create_tween()
		var fall_time := rng.randf_range(1.2, 2.2)
		tw.tween_property(r, "position:y", 760.0, fall_time)
		tw.parallel().tween_property(r, "position:x", r.position.x + rng.randf_range(-90, 90), fall_time)
		tw.parallel().tween_property(r, "rotation", rng.randf_range(-6, 6), fall_time)
		tw.tween_callback(r.queue_free)
	var clean := layer.create_tween()
	clean.tween_interval(3.0)
	clean.tween_callback(layer.queue_free)

# --- generic modal ---------------------------------------------------------------

func _build_modal_ui() -> void:
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 23
	_modal_layer.visible = false
	add_child(_modal_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 420)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.92, 0.80), Color(0.72, 0.55, 0.20), 12, 3))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.add_child(center)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_modal_title = Label.new()
	_modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_title.add_theme_font_size_override("font_size", 24)
	_modal_title.add_theme_color_override("font_color", Color(0.45, 0.25, 0.08))
	vb.add_child(_modal_title)
	_modal_scroll = ScrollContainer.new()
	_modal_scroll.custom_minimum_size = Vector2(640, 330)
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_modal_scroll)
	_modal_box = VBoxContainer.new()
	_modal_box.add_theme_constant_override("separation", 8)
	_modal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_scroll.add_child(_modal_box)

func _modal_open(title: String) -> VBoxContainer:
	for child in _modal_box.get_children():
		child.queue_free()
	_modal_title.text = title
	_modal_layer.visible = true
	_refresh_blocking()
	return _modal_box

func _modal_close() -> void:
	_modal_layer.visible = false
	_refresh_blocking()

func _modal_label(vb: VBoxContainer, text: String, font_size: int = 17, color: Color = Color(0.12, 0.10, 0.06)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	vb.add_child(l)
	return l

func _modal_button(vb: VBoxContainer, text: String, on_press: Callable, bg: Color = Color(0.85, 0.75, 0.55)) -> Button:
	var b := Button.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 44)
	_style_button(b, bg)
	b.pressed.connect(on_press)
	vb.add_child(b)
	return b

func _refresh_blocking() -> void:
	ui_blocking = input_locked or _action_layer.visible or _dialogue_layer.visible or _truth_layer.visible or _modal_layer.visible or _title_layer != null or _debug_layer.visible

# --- dialogue UI ---------------------------------------------------------------

func _build_dialogue_ui() -> void:
	_dialogue_layer = CanvasLayer.new()
	_dialogue_layer.layer = 20
	_dialogue_layer.visible = false
	add_child(_dialogue_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialogue_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -270
	panel.offset_bottom = -16
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.92, 0.80), Color(0.72, 0.55, 0.20), 10, 3))
	_dialogue_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	_dialogue_speaker = Label.new()
	_dialogue_speaker.add_theme_font_size_override("font_size", 20)
	_dialogue_speaker.add_theme_color_override("font_color", Color(0.45, 0.25, 0.08))
	vb.add_child(_dialogue_speaker)
	_dialogue_text = RichTextLabel.new()
	_dialogue_text.bbcode_enabled = false
	_dialogue_text.fit_content = true
	_dialogue_text.scroll_active = false
	_dialogue_text.custom_minimum_size = Vector2(0, 84)
	_dialogue_text.add_theme_font_size_override("normal_font_size", 18)
	_dialogue_text.add_theme_color_override("default_color", Color(0.12, 0.10, 0.06))
	vb.add_child(_dialogue_text)
	_dialogue_choices = VBoxContainer.new()
	_dialogue_choices.add_theme_constant_override("separation", 6)
	vb.add_child(_dialogue_choices)

func _build_truth_ui() -> void:
	_truth_layer = CanvasLayer.new()
	_truth_layer.layer = 21
	_truth_layer.visible = false
	add_child(_truth_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_truth_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 460)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.92, 0.80), Color(0.72, 0.55, 0.20), 12, 3))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_truth_layer.add_child(center)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_truth_title = Label.new()
	_truth_title.text = "TRUTH CHECK"
	_truth_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_truth_title.add_theme_font_size_override("font_size", 26)
	_truth_title.add_theme_color_override("font_color", Color(0.45, 0.25, 0.08))
	vb.add_child(_truth_title)
	_truth_status = Label.new()
	_truth_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_truth_status.add_theme_font_size_override("font_size", 22)
	vb.add_child(_truth_status)
	_truth_object = Label.new()
	_truth_object.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_truth_object.add_theme_font_size_override("font_size", 18)
	_truth_object.add_theme_color_override("font_color", Color(0.45, 0.25, 0.08))
	vb.add_child(_truth_object)
	_truth_fact = RichTextLabel.new()
	_truth_fact.bbcode_enabled = false
	_truth_fact.fit_content = true
	_truth_fact.scroll_active = false
	_truth_fact.custom_minimum_size = Vector2(0, 110)
	_truth_fact.add_theme_font_size_override("normal_font_size", 17)
	_truth_fact.add_theme_color_override("default_color", Color(0.12, 0.10, 0.06))
	vb.add_child(_truth_fact)
	_truth_era = Label.new()
	_truth_era.add_theme_font_size_override("font_size", 16)
	_truth_era.add_theme_color_override("font_color", Color(0.12, 0.10, 0.06))
	vb.add_child(_truth_era)
	_truth_conf = Label.new()
	_truth_conf.add_theme_font_size_override("font_size", 16)
	_truth_conf.add_theme_color_override("font_color", Color(0.12, 0.10, 0.06))
	vb.add_child(_truth_conf)
	_truth_paradox = Label.new()
	_truth_paradox.add_theme_font_size_override("font_size", 16)
	_truth_paradox.add_theme_color_override("font_color", Color(0.12, 0.10, 0.06))
	vb.add_child(_truth_paradox)
	_truth_clue = Label.new()
	_truth_clue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_truth_clue.add_theme_font_size_override("font_size", 16)
	_truth_clue.add_theme_color_override("font_color", Color(0.10, 0.45, 0.10))
	vb.add_child(_truth_clue)
	_truth_note = Label.new()
	_truth_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_truth_note.add_theme_font_size_override("font_size", 16)
	_truth_note.add_theme_color_override("font_color", Color(0.45, 0.25, 0.08))
	vb.add_child(_truth_note)
	var close := Button.new()
	close.text = "Close"
	_style_button(close, Color(0.85, 0.75, 0.55))
	close.pressed.connect(_close_truth)
	vb.add_child(close)

func _build_action_ui() -> void:
	_action_layer = CanvasLayer.new()
	_action_layer.layer = 22
	_action_layer.visible = false
	add_child(_action_layer)
	_action_panel = PanelContainer.new()
	_action_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.92, 0.80), Color(0.72, 0.55, 0.20), 8, 2))
	_action_layer.add_child(_action_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_action_panel.add_child(vb)
	_action_title = Label.new()
	_action_title.add_theme_font_size_override("font_size", 18)
	_action_title.add_theme_color_override("font_color", Color(0.45, 0.25, 0.08))
	vb.add_child(_action_title)
	_action_desc = RichTextLabel.new()
	_action_desc.bbcode_enabled = false
	_action_desc.fit_content = true
	_action_desc.scroll_active = false
	_action_desc.custom_minimum_size = Vector2(380, 60)
	_action_desc.add_theme_font_size_override("normal_font_size", 15)
	_action_desc.add_theme_color_override("default_color", Color(0.12, 0.10, 0.06))
	vb.add_child(_action_desc)
	_action_buttons = VBoxContainer.new()
	_action_buttons.add_theme_constant_override("separation", 6)
	vb.add_child(_action_buttons)

func _build_debug_ui() -> void:
	_debug_layer = CanvasLayer.new()
	_debug_layer.layer = 28
	_debug_layer.visible = false
	add_child(_debug_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 480)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.10, 0.12, 0.98), Color(0.6, 0.8, 1.0), 10, 2))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_layer.add_child(center)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "DEBUG — Timeline Restorer v3"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0))
	vb.add_child(title)
	_debug_text = RichTextLabel.new()
	_debug_text.bbcode_enabled = false
	_debug_text.fit_content = false
	_debug_text.scroll_active = true
	_debug_text.custom_minimum_size = Vector2(660, 260)
	_debug_text.add_theme_font_size_override("normal_font_size", 14)
	_debug_text.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	vb.add_child(_debug_text)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for spec in [["Score +10", "score"], ["Paradox +10", "paradox-plus"], ["Paradox -10", "paradox-minus"], ["Stability +10", "stability-plus"]]:
		var b := Button.new()
		b.text = spec[0]
		_style_button(b, Color(0.5, 0.6, 0.7))
		b.pressed.connect(_debug_action.bind(spec[1]))
		grid.add_child(b)
	for a in [1, 2, 3, 4, 5]:
		var b := Button.new()
		b.text = "Jump to Act %d" % a
		_style_button(b, Color(0.5, 0.6, 0.7))
		b.pressed.connect(_debug_jump_act.bind(a))
		grid.add_child(b)
	var close := Button.new()
	close.text = "Close (F1)"
	_style_button(close, Color(0.85, 0.75, 0.55))
	close.pressed.connect(_toggle_debug)
	vb.add_child(close)

# --- texture helpers ---------------------------------------------------------------

func _panel_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

func _style_button(b: Button, bg: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.15)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.15)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.12, 0.10, 0.06))
	b.add_theme_font_size_override("font_size", 17)

func _radial_texture(size: int, inner: Color, outer: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2.0
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			var col := inner.lerp(outer, d)
			col.a = a * inner.a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _ring_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2.0
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - c, y - c).length() / c
			var ring := 1.0 - absf(d - 0.42) / 0.10
			var glow := clampf(1.0 - d, 0.0, 1.0) * 0.25
			var col := color
			col.a = maxf(clampf(ring, 0.0, 1.0), glow) * color.a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

# --- input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_F1:
				_toggle_debug()
			elif k.keycode == KEY_M:
				audio.toggle_mute()
			elif k.keycode == KEY_ESCAPE:
				_close_topmost()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _action_layer.visible:
				# Clicking outside the popup dismisses it (PoC behaviour).
				_close_action_popup()
				return
			if input_locked or ui_blocking:
				return
			_close_action_popup()
			var pos := get_global_mouse_position()
			var hit := _pick_hotspot(pos)
			if hit != "":
				audio.play_click()
				_go_to_hotspot(hit)
			else:
				pending_hotspot = ""
				cadet.walk_to(_clamp_to_nav(pos))
				audio.play_click()

func _close_topmost() -> void:
	if _debug_layer.visible:
		_toggle_debug()
	elif _modal_layer.visible:
		_modal_close()
	elif _truth_layer.visible:
		_close_truth()
	elif _dialogue_layer.visible:
		_close_dialogue()
	elif _action_layer.visible:
		_close_action_popup()

func _pick_hotspot(pos: Vector2) -> String:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 2
	var results := space.intersect_point(query)
	for r in results:
		var area := r["collider"] as Area2D
		if area and area.has_meta("hotspot_id"):
			return String(area.get_meta("hotspot_id"))
	return ""

func _clamp_to_nav(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 40.0, 1240.0), clampf(pos.y, FLOOR_TOP + 25.0, FLOOR_BOTTOM - 17.0))

func _go_to_hotspot(id: String) -> void:
	pending_hotspot = id
	var hs := _find_hotspot(id)
	if hs.is_empty():
		pending_hotspot = ""
		return
	var hx := float(hs.get("x", 50)) / 100.0 * VIEW_W
	var approach := Vector2(hx, 665.0)
	if hs.has("npc"):
		# Stop beside the NPC instead of on top of them.
		var side := -130.0 if hx > VIEW_W / 2.0 else 130.0
		approach = Vector2(clampf(hx + side, 60.0, 1220.0), 665.0)
	cadet.walk_to(approach)

func _on_cadet_arrived() -> void:
	_ad_arrived = true
	if _ad_running:
		# Autodemo drives actions directly; do not open the popup.
		pending_hotspot = ""
		return
	if pending_hotspot == "":
		return
	var id := pending_hotspot
	pending_hotspot = ""
	_open_action_popup(id)

func _find_hotspot(id: String) -> Dictionary:
	var scene: Dictionary = SCENES.get(current_scene, {})
	for hs in scene.get("hotspots", []):
		if String(hs.get("id", "")) == id:
			return hs
	return {}

func _find_hotspot_anywhere(id: String) -> Dictionary:
	for sid in SCENES.keys():
		var scene: Dictionary = SCENES[sid]
		for hs in scene.get("hotspots", []):
			if String(hs.get("id", "")) == id:
				return hs
	return {}

# --- hotspot popup ---------------------------------------------------------------

func _open_action_popup(id: String) -> void:
	var hs := _find_hotspot(id)
	if hs.is_empty():
		return
	_action_hotspot = id
	_action_title.text = String(hs.get("name", id))
	_action_desc.text = String(hs.get("desc", ""))
	for child in _action_buttons.get_children():
		child.queue_free()
	for action in hs.get("actions", []):
		var b := Button.new()
		match String(action):
			"look":
				b.text = "Look"
				b.pressed.connect(_do_look.bind(id))
			"talk":
				var npc_id := String(hs.get("npc", ""))
				var ch: Dictionary = CHARACTERS.get(npc_id, {})
				b.text = "Talk to %s" % String(ch.get("name", "them"))
				b.pressed.connect(_do_talk.bind(id))
			"truth":
				b.text = "Truth Check"
				b.pressed.connect(_do_truth.bind(id))
			"interact":
				b.text = "Interact"
				b.pressed.connect(_do_interact.bind(id))
		_style_button(b, Color(0.85, 0.75, 0.55))
		_action_buttons.add_child(b)
	# USE: only meaningful with a selected inventory item.
	var use_b := Button.new()
	if selected_item != "" and ITEMS.has(selected_item):
		use_b.text = "Use: %s" % String(ITEMS[selected_item].get("name", selected_item))
	else:
		use_b.text = "Use... (select an item from your pack first)"
	_style_button(use_b, Color(0.72, 0.85, 0.60))
	use_b.pressed.connect(_do_use.bind(id))
	_action_buttons.add_child(use_b)
	var close_b := Button.new()
	close_b.text = "Close"
	_style_button(close_b, Color(0.75, 0.70, 0.62))
	close_b.pressed.connect(_close_action_popup)
	_action_buttons.add_child(close_b)
	# Fixed position (top centre-right) so the layout is deterministic.
	_action_panel.position = Vector2(430, 150)
	_action_panel.custom_minimum_size = Vector2(420, 0)
	_action_layer.visible = true
	_refresh_blocking()

func _close_action_popup() -> void:
	if _action_layer:
		_action_layer.visible = false
	_action_hotspot = ""
	_refresh_blocking()

func _do_look(id: String) -> void:
	_close_action_popup()
	audio.play_click()
	var hs := _find_hotspot(id)
	_show_caption(String(hs.get("desc", "")))

func _do_talk(id: String) -> void:
	_close_action_popup()
	var hs := _find_hotspot(id)
	var npc_id := String(hs.get("npc", ""))
	var npc: Npc = _npcs.get(npc_id, null)
	if npc:
		npc.face_towards(cadet.global_position.x)
		npc.play_talk()
	_start_dialogue(npc_id)

func _do_truth(id: String) -> void:
	_close_action_popup()
	var hs := _find_hotspot(id)
	if not hs.has("truth"):
		_show_caption("The Truth Check finds nothing verifiable here.")
		return
	_open_truth(String(hs["truth"]))

func _do_use(id: String) -> void:
	if selected_item == "":
		audio.play_error()
		_show_caption("Use mode: first select an item from your pack below, then click a hotspot.")
		_close_action_popup()
		return
	var hs := _find_hotspot(id)
	_close_action_popup()
	_resolve_use(selected_item, hs)

func _do_interact(id: String) -> void:
	_close_action_popup()
	var hs := _find_hotspot(id)
	if hs.is_empty():
		return
	# v1 doInteract order: puzzle -> requirement.flag -> final_seal ->
	# npc -> anomaly -> item -> useTarget text -> desc.
	if hs.has("puzzle"):
		_open_puzzle(String(hs["puzzle"]))
		return
	if hs.has("requirement") and Dictionary(hs["requirement"]).has("flag"):
		var req: Dictionary = hs["requirement"]
		if not bool(timeline_flags.get(String(req["flag"]), false)):
			audio.play_error()
			_show_caption(String(hs.get("lockedMsg", "This is locked.")))
			return
	if id == "final_seal":
		_start_quiz("final", _on_final_quiz_done)
		return
	if hs.has("npc"):
		_do_talk(id)
		return
	if bool(hs.get("anomaly", false)):
		_anomaly_info(hs)
		return
	if hs.has("item"):
		if hs.has("requirement") and Dictionary(hs["requirement"]).has("item"):
			var req2: Dictionary = hs["requirement"]
			if not inventory.has(String(req2["item"])):
				audio.play_error()
				_show_caption(String(hs.get("lockedMsg", "You need something to open this.")))
				return
		_take_item(String(hs["item"]))
		return
	if hs.has("useTarget"):
		_show_caption(String(hs.get("desc", "")) + " Try using the right tool on this. Select an item from your pack, then press USE.")
		return
	_show_caption(String(hs.get("desc", "")))

func _resolve_use(item_id: String, hs: Dictionary) -> void:
	var item: Dictionary = ITEMS.get(item_id, {})
	use_mode = false
	if item.is_empty():
		_show_caption("Unknown item.")
		return
	var target := String(hs.get("useTarget", ""))
	if target == "" or not Array(item.get("usableWith", [])).has(target):
		audio.play_error()
		_show_caption("Using the %s on the %s does nothing useful. The right tool matters — check TRUTH CHECK clues and puzzle hints." % [String(item.get("name", item_id)), String(hs.get("name", "this"))])
		selected_item = ""
		_rebuild_inventory()
		return
	_repair_anomaly(target, item)
	selected_item = ""
	_rebuild_inventory()

func _anomaly_info(hs: Dictionary) -> void:
	var req := String(REPAIR_REQS.get(str(current_act), "Find the right tool and use it here."))
	_show_caption("%s — this is the timeline anomaly. %s To repair it: %s" % [String(hs.get("name", "Anomaly")), String(hs.get("desc", "")), req])

func _repair_anomaly(target_id: String, item: Dictionary) -> void:
	var gate: Dictionary = REPAIR_GATES.get(current_act, {})
	if gate.is_empty():
		_show_caption("The Core cannot be repaired with a tool — it needs the four-key code. INTERACT with the fractured Core.")
		return
	if String(item.get("id", "")) != String(gate["item"]):
		audio.play_error()
		_show_caption("The %s is not the right tool for this anomaly." % String(item.get("name", "")))
		return
	var missing: Array[String] = []
	for p in gate["need"]:
		if not solved_puzzles.has(String(p)):
			missing.append(String(p))
	if not missing.is_empty():
		var titles: Array[String] = []
		for p in missing:
			titles.append(String(PUZZLES.get(p, {}).get("title", p)))
		audio.play_error()
		_show_caption("Not yet — the repair is not safe. First solve: %s." % ", ".join(titles))
		return
	if String(gate.get("clue", "")) != "" and not inventory.has(String(gate["clue"])):
		audio.play_error()
		_show_caption("You are missing the clue. Combine the magnifying glass with a historical document to reveal the hidden-ink clue first.")
		return
	var key_id := "temporal_key_%d" % current_act
	timeline_flags["a%d_repaired" % current_act] = true
	key_digits[str(current_act)] = int(gate["digit"])
	_add_item(key_id)
	add_score(300, "restoration")
	add_stability(10)
	audio.play_repair()
	_log("INFO", "Anomaly repaired: act %d (key digit %d)" % [current_act, int(gate["digit"])])
	_capture_shot("repair-act%d" % current_act, 0.5)
	_load_scene(current_scene)
	_save_game(true)
	var vb := _modal_open("Act %d — Anomaly Repaired" % current_act)
	_modal_label(vb, "Anomaly repaired! The distortion folds away. Timeline Stability +10%%, Paradox -5%%.", 18)
	_modal_label(vb, "You received a Temporal Key — digit %d (%s). Remember it: the Core at the end of time needs four digits." % [int(gate["digit"]), String(gate["name"])], 17)
	_modal_label(vb, "Now prove what you have learned.", 17)
	_modal_button(vb, "Take the Act Quiz", func() -> void:
		_modal_close()
		_act_quiz(current_act)
	, Color(0.72, 0.85, 0.60))

# --- inventory -------------------------------------------------------------------

func _add_item(item_id: String) -> bool:
	var def: Dictionary = ITEMS.get(item_id, {})
	if def.is_empty():
		_log("WARNING", "Tried to add unknown item: " + item_id)
		return false
	if inventory.has(item_id):
		return false
	inventory.append(item_id)
	add_score(20, "artifacts")
	audio.play_pickup()
	_log("INFO", "Item collected: " + String(def.get("name", item_id)))
	_show_toast("Collected: " + String(def.get("name", item_id)))
	_rebuild_inventory()
	_save_game(true)
	return true

func _remove_item(item_id: String) -> void:
	inventory.erase(item_id)
	if selected_item == item_id:
		selected_item = ""
	_rebuild_inventory()

func _take_item(item_id: String) -> void:
	var def: Dictionary = ITEMS.get(item_id, {})
	if _add_item(item_id):
		_show_caption("You picked up the %s. %s" % [String(def.get("name", item_id)), String(def.get("desc", ""))])
		# Collected items vanish from the scene.
		_load_scene(current_scene)

func _rebuild_inventory() -> void:
	for child in _inventory_box.get_children():
		if child is Label and String(child.text) == "Pack:":
			continue
		child.queue_free()
	for item_id in inventory:
		var def: Dictionary = ITEMS.get(item_id, {})
		var b := Button.new()
		b.text = String(def.get("name", item_id))
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		var bg := Color(0.97, 0.92, 0.80)
		if item_id == selected_item:
			bg = Color(1.0, 0.85, 0.45)
		_style_button(b, bg)
		b.pressed.connect(_on_inventory_item_pressed.bind(item_id))
		_inventory_box.add_child(b)

func _on_inventory_item_pressed(item_id: String) -> void:
	audio.play_click()
	if selected_item == item_id:
		# Click again: inspect.
		var def: Dictionary = ITEMS.get(item_id, {})
		_show_caption("%s — %s" % [String(def.get("name", item_id)), String(def.get("desc", ""))])
		selected_item = ""
	elif selected_item != "":
		_try_combine(selected_item, item_id)
	else:
		selected_item = item_id
		_show_caption("Selected: %s. Click a hotspot and press USE, or click another item to combine." % String(ITEMS.get(item_id, {}).get("name", item_id)))
	_rebuild_inventory()

func _try_combine(a: String, b: String) -> void:
	for r in RECIPES:
		var rec: Dictionary = r
		var inputs: Array = rec.get("inputs", [])
		if inputs.size() == 2 and ((inputs[0] == a and inputs[1] == b) or (inputs[0] == b and inputs[1] == a)):
			_remove_item(a)
			_remove_item(b)
			var out_id := String(rec.get("output", ""))
			_add_item(out_id)
			add_score(50, "puzzles")
			_log("INFO", "Items combined: %s + %s = %s" % [a, b, out_id])
			selected_item = ""
			var vb := _modal_open("Combined!")
			_modal_label(vb, String(rec.get("message", "")), 17)
			_modal_label(vb, "You made: %s." % String(ITEMS.get(out_id, {}).get("name", out_id)), 17)
			_modal_button(vb, "Continue", _modal_close, Color(0.72, 0.85, 0.60))
			_save_game(true)
			return
	audio.play_error()
	selected_item = ""
	_show_caption("Those two do not combine into anything useful.")
	_rebuild_inventory()

# --- dialogue --------------------------------------------------------------------

func _start_dialogue(npc_id: String) -> void:
	var ch: Dictionary = CHARACTERS.get(npc_id, {})
	var dialogue_id := String(ch.get("dialogue", npc_id + "_intro"))
	if not DIALOGUES.has(dialogue_id):
		_show_caption("They have nothing to say right now.")
		return
	_dialogue_id = dialogue_id
	_dialogue_npc = npc_id
	_dialogue_speaker.text = String(ch.get("name", npc_id))
	audio.play_dialogue_blip()
	_dialogue_layer.visible = true
	_refresh_blocking()
	_show_dialogue_node(String(DIALOGUES[dialogue_id].get("start", "n1")))
	_capture_shot("dialogue-" + npc_id, 0.5)

func _show_dialogue_node(node_id: String) -> void:
	_dialogue_node = node_id
	var dlg: Dictionary = DIALOGUES.get(_dialogue_id, {})
	var nodes: Dictionary = dlg.get("nodes", {})
	var node: Dictionary = nodes.get(node_id, {})
	_dialogue_text.text = String(node.get("text", ""))
	for child in _dialogue_choices.get_children():
		child.queue_free()
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		var end_b := Button.new()
		end_b.text = "End conversation"
		_style_button(end_b, Color(0.85, 0.75, 0.55))
		end_b.pressed.connect(_close_dialogue)
		_dialogue_choices.add_child(end_b)
		return
	for choice in choices:
		var c: Dictionary = choice
		var b := Button.new()
		b.text = String(c.get("text", ""))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 44)
		_style_button(b, Color(0.88, 0.80, 0.62))
		b.pressed.connect(_on_choice_pressed.bind(c))
		_dialogue_choices.add_child(b)

func _on_choice_pressed(choice: Dictionary) -> void:
	var eff: Dictionary = choice.get("effects", {})
	apply_effects(eff)
	audio.play_click()
	if int(eff.get("paradox", 0)) != 0:
		var p := int(eff["paradox"])
		_show_toast("Paradox %+d" % p if p > 0 else "Paradox %d" % p)
	# Show the response, then continue to the next node (or close).
	_dialogue_text.text = String(choice.get("response", ""))
	for child in _dialogue_choices.get_children():
		child.queue_free()
	# Terminal choices carry "next": null in the JSON — String(null) throws.
	var next_raw = choice.get("next", "")
	var next_node := "" if next_raw == null else String(next_raw)
	var cont := Button.new()
	cont.text = "Continue" if next_node != "" else "End conversation"
	_style_button(cont, Color(0.85, 0.75, 0.55))
	if next_node != "":
		cont.pressed.connect(_show_dialogue_node.bind(next_node))
	else:
		cont.pressed.connect(_close_dialogue)
	_dialogue_choices.add_child(cont)

func _close_dialogue() -> void:
	_dialogue_layer.visible = false
	var npc: Npc = _npcs.get(_dialogue_npc, null)
	if npc:
		npc.play_idle()
	_dialogue_npc = ""
	_dialogue_id = ""
	_refresh_blocking()
	_save_game(true)

# --- truth check -------------------------------------------------------------------

func _discover_truth(truth_id: String, silent: bool) -> Dictionary:
	var truth: Dictionary = TRUTHS.get(truth_id, {})
	if truth.is_empty():
		_log("WARNING", "Truth not found: " + truth_id)
		return truth
	if not discovered_truths.has(truth_id):
		discovered_truths.append(truth_id)
		_archive_add_truth(truth_id)
		if not silent:
			add_score(50, "truths")
			add_stability(2)
		_log("INFO", "Truth discovered: " + String(truth.get("object", truth_id)))
	return truth

func _open_truth(truth_id: String) -> void:
	var truth: Dictionary = TRUTHS.get(truth_id, {})
	if truth.is_empty():
		_show_caption("No verification record exists for this. The Truth Engine has no data — try examining it with LOOK first.")
		_log("WARNING", "Truth check with no record: " + truth_id)
		return
	var first_time := not discovered_truths.has(truth_id)
	_discover_truth(truth_id, false)
	audio.play_truth()
	_log("INFO", "Truth checked: %s (%s)" % [String(truth.get("object", "")), String(truth.get("status", ""))])
	_truth_object.text = String(truth.get("object", ""))
	if String(truth.get("status", "")) == "anachronistic":
		_truth_status.text = "TIMELINE DISTORTION — ANACHRONISTIC"
		_truth_status.add_theme_color_override("font_color", Color(0.75, 0.12, 0.10))
	else:
		_truth_status.text = "AUTHENTIC"
		_truth_status.add_theme_color_override("font_color", Color(0.10, 0.55, 0.20))
	_truth_fact.text = String(truth.get("fact", ""))
	_truth_era.text = "Expected era: %s    •    Current era: %s" % [String(truth.get("expectedEra", "?")), String(truth.get("currentEra", "?"))]
	_truth_conf.text = "Truth confidence: %d%%" % int(truth.get("confidence", 0))
	if String(truth.get("status", "")) == "anachronistic":
		_truth_paradox.text = "Paradox contribution: +%d%%" % int(truth.get("paradox", 0))
	else:
		_truth_paradox.text = "Paradox contribution: none"
	_truth_clue.text = "Clue: " + String(truth.get("clue", "")) if String(truth.get("clue", "")) != "" else ""
	if first_time:
		_truth_note.text = "First discovery! +50 points, Timeline Stability +2%."
		_show_toast("Truth discovered!  +50")
	else:
		_truth_note.text = "Already discovered — no additional points."
	_truth_layer.visible = true
	_refresh_blocking()
	_save_game(true)
	_capture_shot("truth-" + truth_id, 0.5)

func _close_truth() -> void:
	_truth_layer.visible = false
	_refresh_blocking()

# --- puzzles ---------------------------------------------------------------------

func _open_puzzle(puzzle_id: String) -> void:
	var puzzle: Dictionary = PUZZLES.get(puzzle_id, {})
	if puzzle.is_empty():
		_log("ERROR", "Puzzle not found: " + puzzle_id)
		return
	if solved_puzzles.has(puzzle_id):
		_show_caption("You already solved this puzzle.")
		return
	_puzzle_id = puzzle_id
	_puzzle_selection.clear()
	_puzzle_step_buttons.clear()
	var vb := _modal_open("Puzzle: " + String(puzzle.get("title", puzzle_id)))
	_modal_label(vb, String(puzzle.get("instructions", "")), 17)
	if _puzzle_feedback != "":
		_modal_label(vb, _puzzle_feedback, 16, Color(0.60, 0.15, 0.10))
		_puzzle_feedback = ""
	audio.play_click()
	match String(puzzle.get("type", "")):
		"anachronism":
			_puzzle_build_anachronism(vb, puzzle)
		"sequence":
			_puzzle_build_sequence(vb, puzzle)
		"testimony":
			_puzzle_build_testimony(vb, puzzle)
		"cipher":
			_puzzle_build_cipher(vb, puzzle)
		"code":
			_puzzle_build_code(vb, puzzle)
		_:
			_modal_label(vb, "This puzzle type is not supported in this build.", 17)
			_modal_button(vb, "Close", _modal_close)
			return
	_modal_button(vb, "Hint", func() -> void:
		_modal_label(vb, "Hint: " + String(puzzle.get("hint", "No hint available.")), 15, Color(0.10, 0.35, 0.55))
	, Color(0.75, 0.70, 0.62))
	_modal_button(vb, "Leave", _modal_close, Color(0.75, 0.70, 0.62))

func _puzzle_toggle_button(b: Button, selected: bool) -> void:
	_style_button(b, Color(0.72, 0.85, 0.60) if selected else Color(0.85, 0.75, 0.55))

func _puzzle_build_anachronism(vb: VBoxContainer, puzzle: Dictionary) -> void:
	# Select the options that do NOT belong (or, in "authentic" mode, the
	# ones that DO belong), then Confirm.
	var mode_authentic := String(puzzle.get("mode", "")) == "authentic"
	_modal_label(vb, "Click to select, click again to deselect. Then press Confirm.", 15, Color(0.35, 0.35, 0.35))
	for opt in puzzle.get("options", []):
		var o: Dictionary = opt
		var b := Button.new()
		b.text = String(o.get("label", ""))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 40)
		_style_button(b, Color(0.85, 0.75, 0.55))
		b.pressed.connect(func() -> void:
			var oid := String(o.get("id", ""))
			if _puzzle_selection.has(oid):
				_puzzle_selection.erase(oid)
				_puzzle_toggle_button(b, false)
			else:
				_puzzle_selection.append(oid)
				_puzzle_toggle_button(b, true)
			audio.play_click()
		)
		vb.add_child(b)
	_modal_button(vb, "Confirm", func() -> void:
		var want: Array[String] = []
		for o in puzzle.get("options", []):
			var od: Dictionary = o
			var is_anach := bool(od.get("anachronistic", false))
			if (mode_authentic and not is_anach) or (not mode_authentic and is_anach):
				want.append(String(od.get("id", "")))
		var got: Array[String] = []
		for s in _puzzle_selection:
			got.append(String(s))
		want.sort()
		got.sort()
		if got == want:
			_solve_puzzle(puzzle)
		else:
			audio.play_error()
			_puzzle_feedback = "Not quite — check each object against its era and try again. The timeline is forgiving; keep going."
			_puzzle_selection.clear()
			_open_puzzle(String(puzzle.get("id", "")))
	, Color(0.72, 0.85, 0.60))

func _puzzle_build_sequence(vb: VBoxContainer, puzzle: Dictionary) -> void:
	_modal_label(vb, "Click the steps in order, from first to last. Then press Confirm.", 15, Color(0.35, 0.35, 0.35))
	var order_label := _modal_label(vb, "Your order: (none yet)", 15, Color(0.45, 0.25, 0.08))
	for step in puzzle.get("steps", []):
		var st: Dictionary = step
		var b := Button.new()
		b.text = "%s — %s" % [String(st.get("label", "")), String(st.get("detail", ""))]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 40)
		_style_button(b, Color(0.85, 0.75, 0.55))
		b.pressed.connect(func() -> void:
			var sid := String(st.get("id", ""))
			if _puzzle_selection.has(sid):
				return
			_puzzle_selection.append(sid)
			_puzzle_toggle_button(b, true)
			var names: Array[String] = []
			for sel in _puzzle_selection:
				for s2 in puzzle.get("steps", []):
					if String(s2.get("id", "")) == String(sel):
						names.append(String(s2.get("label", "")))
			order_label.text = "Your order: " + " > ".join(names)
			audio.play_click()
		)
		vb.add_child(b)
		_puzzle_step_buttons[String(st.get("id", ""))] = b
	_modal_button(vb, "Confirm", func() -> void:
		var want: Array[String] = []
		for c in puzzle.get("correct", []):
			want.append(String(c))
		var got: Array[String] = []
		for s in _puzzle_selection:
			got.append(String(s))
		if got == want:
			_solve_puzzle(puzzle)
		else:
			audio.play_error()
			_puzzle_feedback = "That order is not right yet. Think about what must come first — and try again."
			_puzzle_selection.clear()
			_open_puzzle(String(puzzle.get("id", "")))
	, Color(0.72, 0.85, 0.60))

func _puzzle_build_testimony(vb: VBoxContainer, puzzle: Dictionary) -> void:
	_modal_label(vb, "Only one account fits all the facts. Choose it.", 15, Color(0.35, 0.35, 0.35))
	for st in puzzle.get("statements", []):
		var s: Dictionary = st
		var b := Button.new()
		b.text = String(s.get("text", ""))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 56)
		_style_button(b, Color(0.85, 0.75, 0.55))
		b.pressed.connect(func() -> void:
			if bool(s.get("correct", false)):
				_solve_puzzle(puzzle)
			else:
				audio.play_error()
				_show_caption("Not this one: " + String(s.get("why", "That does not fit the facts.")))
		)
		vb.add_child(b)

func _puzzle_build_cipher(vb: VBoxContainer, puzzle: Dictionary) -> void:
	_modal_label(vb, "Encoded: %s" % String(puzzle.get("encoded", "")), 18, Color(0.45, 0.25, 0.08))
	_modal_label(vb, "Type the decoded word (letters only):", 15, Color(0.35, 0.35, 0.35))
	_puzzle_code_input = LineEdit.new()
	_puzzle_code_input.placeholder_text = "Decoded word..."
	_puzzle_code_input.custom_minimum_size = Vector2(0, 44)
	_puzzle_code_input.add_theme_font_size_override("font_size", 20)
	vb.add_child(_puzzle_code_input)
	_modal_button(vb, "Confirm", func() -> void:
		var guess := _puzzle_code_input.text.strip_edges().to_upper()
		if guess == String(puzzle.get("answer", "")).to_upper():
			_solve_puzzle(puzzle)
		else:
			audio.play_error()
			_modal_label(vb, "That is not the word. Remember the shift: each letter marches three places forward — shift each one back by three.", 16, Color(0.60, 0.15, 0.10))
	, Color(0.72, 0.85, 0.60))

func _puzzle_build_code(vb: VBoxContainer, puzzle: Dictionary) -> void:
	_modal_label(vb, "Enter the four digits, in order: Kite, Loom, Lens, Wing.", 17)
	_modal_label(vb, "Digits found so far: %s" % key_digits_text(), 16, Color(0.45, 0.25, 0.08))
	_puzzle_code_input = LineEdit.new()
	_puzzle_code_input.placeholder_text = "Four digits, e.g. 7319"
	_puzzle_code_input.custom_minimum_size = Vector2(0, 44)
	_puzzle_code_input.add_theme_font_size_override("font_size", 22)
	_puzzle_code_input.max_length = 4
	vb.add_child(_puzzle_code_input)
	_modal_button(vb, "Seal the Core", func() -> void:
		var guess := _puzzle_code_input.text.strip_edges()
		if guess == String(puzzle.get("answer", "")):
			_solve_puzzle(puzzle)
		else:
			audio.play_error()
			_modal_label(vb, "The Core rejects that sequence. The digits are one per act — Kite, Loom, Lens, Wing.", 16, Color(0.60, 0.15, 0.10))
	, Color(0.72, 0.85, 0.60))

func _solve_puzzle(puzzle: Dictionary) -> void:
	var pid := String(puzzle.get("id", ""))
	if solved_puzzles.has(pid):
		return
	solved_puzzles.append(pid)
	add_score(int(puzzle.get("score", 150)), "puzzles")
	if int(puzzle.get("paradoxReward", 0)) != 0:
		add_paradox(int(puzzle.get("paradoxReward", 0)))
	audio.play_solved()
	_confetti()
	_log("INFO", "Puzzle completed: " + pid)
	_save_game(true)
	if pid == "final_code":
		timeline_flags["a5_core_sealed"] = true
		add_score(300, "restoration")
		add_stability(10)
		_save_game(true)
		var vb := _modal_open("The Temporal Core — Sealed")
		_modal_label(vb, "THE CORE IS SEALED. The four keys turn as one: 7 – 3 – 1 – 9. The fractures close. The eras stop bleeding into each other.", 18)
		_modal_label(vb, "One last task: the final quiz — five questions from across the whole journey.", 17)
		_modal_button(vb, "Take the Final Quiz", func() -> void:
			_modal_close()
			_start_quiz("final", _on_final_quiz_done)
		, Color(0.72, 0.85, 0.60))
		return
	var vb2 := _modal_open("Puzzle Solved: " + String(puzzle.get("title", pid)))
	_modal_label(vb2, "Excellent work. +%d points. Timeline Stability improved." % int(puzzle.get("score", 150)), 18)
	var guidance := {
		"anachronism_workshop": "You identified all three distortions. Now build the resonator — combine the magnifying glass with a document first.",
		"memory_recall": "The Core remembers your journey. The Chronarch is ready to speak — talk to them, then seal the Core.",
	}
	if guidance.has(pid):
		_modal_label(vb2, String(guidance[pid]), 17)
	_modal_button(vb2, "Continue", func() -> void:
		_modal_close()
		_on_puzzle_solved(pid)
	, Color(0.72, 0.85, 0.60))

func _on_puzzle_solved(puzzle_id: String) -> void:
	timeline_flags["puzzle_" + puzzle_id] = true
	_save_game(true)
	_log("INFO", "Puzzle flag set: puzzle_" + puzzle_id)

# --- quizzes ---------------------------------------------------------------------

func _quiz_score_for(correct: int) -> int:
	if correct == 5:
		return 500
	if correct == 4:
		return 350
	if correct == 3:
		return 200
	if correct == 2:
		return 100
	return 0

func _start_quiz(quiz_id: String, on_done: Callable) -> void:
	var quiz: Dictionary = QUIZZES.get(quiz_id, {})
	if quiz.is_empty() or Array(quiz.get("questions", [])).is_empty():
		_log("ERROR", "Quiz not found or empty: " + quiz_id)
		on_done.call(false)
		return
	_quiz_id = quiz_id
	_quiz_index = 0
	_quiz_correct = 0
	_quiz_on_done = on_done
	_quiz_answered = false
	_log("INFO", "Quiz started: " + quiz_id)
	_show_quiz_question()
	_capture_shot("quiz-" + quiz_id, 0.5)

func _show_quiz_question() -> void:
	var quiz: Dictionary = QUIZZES.get(_quiz_id, {})
	var questions: Array = quiz.get("questions", [])
	var q: Dictionary = questions[_quiz_index]
	var vb := _modal_open("Quiz: %s  (%d of %d)" % [String(quiz.get("title", _quiz_id)), _quiz_index + 1, questions.size()])
	_modal_label(vb, String(q.get("q", "")), 19)
	_quiz_answered = false
	var options: Array = q.get("options", [])
	for i in range(options.size()):
		var b := Button.new()
		b.text = String(options[i])
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 44)
		_style_button(b, Color(0.85, 0.75, 0.55))
		b.pressed.connect(_on_quiz_option.bind(i, b))
		vb.add_child(b)

func _on_quiz_option(idx: int, btn: Button) -> void:
	if _quiz_answered:
		return
	_quiz_answered = true
	var quiz: Dictionary = QUIZZES.get(_quiz_id, {})
	var questions: Array = quiz.get("questions", [])
	var q: Dictionary = questions[_quiz_index]
	var correct_idx := int(q.get("answer", -1))
	var is_right := idx == correct_idx
	if is_right:
		_quiz_correct += 1
		_style_button(btn, Color(0.55, 0.85, 0.55))
		audio.play_pickup()
	else:
		_style_button(btn, Color(0.95, 0.55, 0.50))
		audio.play_error()
	var vb := _modal_box
	_modal_label(vb, ("Correct! " if is_right else "Not quite. ") + String(q.get("explanation", "")), 16, Color(0.10, 0.45, 0.10) if is_right else Color(0.60, 0.15, 0.10))
	var next_b := _modal_button(vb, "Next" if _quiz_index + 1 < questions.size() else "See results", func() -> void:
		_quiz_index += 1
		if _quiz_index < questions.size():
			_show_quiz_question()
		else:
			_finish_quiz()
	, Color(0.72, 0.85, 0.60))
	next_b.grab_focus()

func _finish_quiz() -> void:
	var quiz: Dictionary = QUIZZES.get(_quiz_id, {})
	var total := Array(quiz.get("questions", [])).size()
	var points := _quiz_score_for(_quiz_correct)
	var passed := _quiz_correct >= 2
	quiz_results[_quiz_id] = {"correct": _quiz_correct, "total": total, "score": points if passed else 0, "passed": passed}
	if passed:
		add_score(points, "knowledge")
		audio.play_solved()
		_confetti()
	_log("INFO", "Quiz finished: %s %d/%d passed=%s" % [_quiz_id, _quiz_correct, total, str(passed)])
	var vb := _modal_open("Quiz Results")
	var stars := ""
	for i in range(_quiz_correct):
		stars += "*"
	_modal_label(vb, "%d / %d correct    Stars: %s" % [_quiz_correct, total, stars if stars != "" else "none yet"], 20)
	if passed:
		_modal_label(vb, "You earned +%d points." % points, 18)
	else:
		_modal_label(vb, "You need at least 2 correct answers to proceed. The timeline demands better.", 18)
	_modal_label(vb, "Scoring: 5/5 = +500, 4/5 = +350, 3/5 = +200, 2/5 = +100, 0-1 = retry required.", 15, Color(0.35, 0.35, 0.35))
	_save_game(true)
	if passed:
		_modal_button(vb, "Continue", func() -> void:
			_modal_close()
			_quiz_on_done.call(true)
		, Color(0.72, 0.85, 0.60))
	else:
		_modal_button(vb, "Retry the quiz", func() -> void:
			_modal_close()
			_start_quiz(_quiz_id, _quiz_on_done)
		, Color(0.72, 0.85, 0.60))
		_modal_button(vb, "Review the act first", func() -> void:
			_modal_close()
			_quiz_on_done.call(false)
		, Color(0.75, 0.70, 0.62))

func _act_quiz(act: int) -> void:
	_start_quiz("act%d" % act, func(passed: bool) -> void:
		if passed:
			_act_complete(act)
		else:
			_show_caption("Review the act and retry the quiz when ready — the Act Quiz button is on the Timeline panel (Menu > Archive shows your progress).")
	)

func _on_final_quiz_done(passed: bool) -> void:
	if passed:
		_act_complete(5)

# --- act completion & endings ------------------------------------------------------

func _act_complete(act: int) -> void:
	add_stability(5)
	audio.play_act_complete()
	_log("INFO", "Act completed: %d" % act)
	_save_game(true)
	if act < 5:
		var next_act: Dictionary = ACTS.get(str(act + 1), {})
		var vb := _modal_open("Act %d Complete" % act)
		_modal_label(vb, "Act %d complete! The era is restored — for now." % act, 19)
		_modal_label(vb, "Next: %s — %s" % [String(next_act.get("title", "")), String(next_act.get("subtitle", ""))], 17)
		_modal_button(vb, "Continue to Act %d" % (act + 1), func() -> void:
			_modal_close()
			start_act(act + 1)
		, Color(0.72, 0.85, 0.60))
	else:
		_compute_ending()

func _compute_ending() -> void:
	game_completed = true
	var s := stability
	var ending_title := ""
	var ending_text := ""
	if s >= 95:
		ending_title = "PERFECT RESTORATION"
		ending_text = "Every distortion undone, every era intact. The timeline hums exactly as it should. Franklin's kite, the looms, the scholars' manuscripts, the biplane — all stand in their proper centuries. You are a legend among Restorers."
	elif s >= 80:
		ending_title = "SUCCESSFUL RESTORATION"
		ending_text = "The timeline is stable and the anomalies are gone. A few small ripples remain — a word here, a sketch there — but history stands. The Chronarch nods: well done, Restorer."
	elif s >= 50:
		ending_title = "DAMAGED TIMELINE"
		ending_text = "The Core is sealed, but the timeline carries scars. Some things are subtly wrong — a date shifted, a name forgotten. History survives, but it will take other Restorers to smooth what you could not."
	else:
		ending_title = "CATASTROPHIC PARADOX"
		ending_text = "The Core is sealed, but the paradox was too deep. Eras bleed into each other; the past is a tangle of impossible things. The timeline endures — barely. Somewhere, a pedlar is laughing."
	var rank := ""
	if s >= 95 and score >= 3000:
		rank = "S — Master Chronologist"
	elif s >= 80:
		rank = "A — Timeline Guardian"
	elif s >= 50:
		rank = "B — Historical Investigator"
	elif s >= 30:
		rank = "C — Temporal Apprentice"
	else:
		rank = "D — Timeline Tourist"
	_save_game(true)
	_log("INFO", "Game completed. Ending: %s rank %s" % [ending_title, rank])
	audio.play_act_complete()
	_confetti()
	var vb := _modal_open(ending_title)
	_modal_label(vb, ending_text, 17)
	_modal_label(vb, "Final score: %d    •    Timeline Stability: %d%%    •    Paradox: %d%%" % [score, stability, paradox], 17)
	_modal_label(vb, "Rank: %s" % rank, 20, Color(0.45, 0.25, 0.08))
	var quiz_lines: Array[String] = []
	for qid in quiz_results.keys():
		var r: Dictionary = quiz_results[qid]
		var qt: String = String(QUIZZES.get(qid, {}).get("title", qid))
		quiz_lines.append("%s: %d/%d" % [qt, int(r.get("correct", 0)), int(r.get("total", 0))])
	if not quiz_lines.is_empty():
		_modal_label(vb, "\n".join(quiz_lines), 15, Color(0.35, 0.35, 0.35))
	_modal_label(vb, "Truths discovered: %d of %d   •   Puzzles solved: %d of %d   •   Scenes visited: %d of %d" % [discovered_truths.size(), TRUTHS.size(), solved_puzzles.size(), PUZZLES.size(), visited_scenes.size(), SCENES.size()], 15, Color(0.35, 0.35, 0.35))
	_modal_button(vb, "Play again from the beginning", func() -> void:
		_modal_close()
		_new_game()
	, Color(0.72, 0.85, 0.60))
	_modal_button(vb, "Replay Act 5", func() -> void:
		_modal_close()
		_replay_act5()
	, Color(0.85, 0.75, 0.55))
	_modal_button(vb, "Historical Archive", func() -> void:
		_modal_close()
		_show_archive()
	, Color(0.75, 0.70, 0.62))
	_capture_shot("ending", 0.8)

func _replay_act5() -> void:
	game_completed = false
	solved_puzzles.erase("final_code")
	solved_puzzles.erase("memory_recall")
	quiz_results.erase("final")
	quiz_results.erase("act5")
	timeline_flags.erase("a5_core_sealed")
	start_act(5)

# --- title screen, menu, travel ----------------------------------------------

func _show_title_screen() -> void:
	_free_title_layer()
	input_locked = true
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_title_layer = layer
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.95)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 460)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.10, 0.07, 0.97), Color(0.85, 0.65, 0.25), 12, 3))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	center.add_child(panel)
	_capture_shot("00-title", 0.6)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "TIMELINE RESTORER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.91, 0.71, 0.30))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Back in Time  —  a time-travel adventure in five acts"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	vb.add_child(sub)
	var desc := Label.new()
	desc.text = "You are a Time Cadet of the Temporal Restoration Bureau. Four eras are bleeding into each other — and a pedlar is selling tomorrow. Find what does not belong, prove it with the Truth Engine, and repair the timeline before the paradox swallows it."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	vb.add_child(desc)
	var new_b := Button.new()
	new_b.text = "New Game"
	_style_button(new_b, Color(0.72, 0.85, 0.60))
	new_b.pressed.connect(_new_game)
	vb.add_child(new_b)
	if FileAccess.file_exists(SAVE_PATH):
		var cont_b := Button.new()
		cont_b.text = "Continue"
		_style_button(cont_b, Color(0.85, 0.75, 0.55))
		cont_b.pressed.connect(_continue_game)
		vb.add_child(cont_b)
	var arch_b := Button.new()
	arch_b.text = "Historical Archive"
	_style_button(arch_b, Color(0.75, 0.70, 0.62))
	arch_b.pressed.connect(_show_archive)
	vb.add_child(arch_b)
	var how_b := Button.new()
	how_b.text = "How to Play"
	_style_button(how_b, Color(0.75, 0.70, 0.62))
	how_b.pressed.connect(_show_how_to_play)
	vb.add_child(how_b)
	_refresh_blocking()

func _free_title_layer() -> void:
	if _title_layer:
		_title_layer.queue_free()
		_title_layer = null
	_refresh_blocking()

func _new_game() -> void:
	_reset_state()
	_free_title_layer()
	_log("INFO", "New game started")
	start_act(1)

func _reset_state() -> void:
	score = 0
	paradox = 15
	stability = 85
	current_act = 1
	current_scene = "workshop"
	inventory.clear()
	discovered_truths.clear()
	solved_puzzles.clear()
	timeline_flags.clear()
	dialogue_flags.clear()
	visited_scenes.clear()
	quiz_results.clear()
	key_digits.clear()
	categories = {"knowledge": 0, "puzzles": 0, "truths": 0, "artifacts": 0, "restoration": 0, "exploration": 0}
	game_completed = false
	selected_item = ""
	use_mode = false
	_update_labels()

func _continue_game() -> void:
	var data := _load_save_dict()
	if data.is_empty():
		_show_caption("No saved game found.")
		return
	_apply_save_dict(data)
	_free_title_layer()
	_log("INFO", "Continued saved game: act %d scene %s" % [current_act, current_scene])
	if game_completed:
		_compute_ending()
	else:
		_show_act_title_card(current_act, ACTS.get(str(current_act), {}))
		_show_toast("Welcome back, Restorer.")

func _show_menu() -> void:
	audio.play_click()
	var vb := _modal_open("Menu")
	_modal_button(vb, "Save game", func() -> void:
		_save_game(false)
		_show_toast("Game saved.")
		_modal_close()
	, Color(0.72, 0.85, 0.60))
	_modal_button(vb, "Historical Archive", func() -> void:
		_modal_close()
		_show_archive()
	)
	_modal_button(vb, "How to Play", func() -> void:
		_modal_close()
		_show_how_to_play()
	)
	_modal_button(vb, "Debug panel (F1)", func() -> void:
		_modal_close()
		_toggle_debug()
	)
	_modal_button(vb, "Back to title screen", func() -> void:
		_modal_close()
		_save_game(true)
		_show_title_screen()
	, Color(0.75, 0.70, 0.62))
	_modal_button(vb, "Close", _modal_close, Color(0.75, 0.70, 0.62))

func _show_travel() -> void:
	audio.play_click()
	var scene: Dictionary = SCENES.get(current_scene, {})
	var vb := _modal_open("Travel — " + String(scene.get("name", current_scene)))
	_modal_label(vb, "Where would you like to go?", 17)
	for ex in scene.get("exits", []):
		var e: Dictionary = ex
		var dest: Dictionary = SCENES.get(String(e.get("to", "")), {})
		_modal_button(vb, String(e.get("label", String(dest.get("name", e.get("to", ""))))), func() -> void:
			_modal_close()
			travel_to(String(e.get("to", "")))
		)
	_modal_button(vb, "Stay here", _modal_close, Color(0.75, 0.70, 0.62))

func _show_how_to_play() -> void:
	var vb := _modal_open("How to Play")
	_modal_label(vb, "Click anywhere on the floor to walk. Click a glowing object, then choose Look, Talk, Truth Check or Interact.", 17)
	_modal_label(vb, "Truth Check: is this object from this era, or a distortion? First discoveries earn +50 points and +2 Stability.", 17)
	_modal_label(vb, "Pack (bottom left): click an item to select it. Click it again to inspect it. Click a second item to try combining them. With an item selected, click a hotspot and press USE to use it there.", 17)
	_modal_label(vb, "Repair: solve the act's puzzles, build the right tool, then USE it on the glowing anomaly. Repair earns a Temporal Key digit — four digits seal the Core (Kite, Loom, Lens, Wing).", 17)
	_modal_label(vb, "Quizzes: after each repair, answer 5 questions. 2 or more correct passes. 5/5 earns +500 points.", 17)
	_modal_label(vb, "Keys: F1 debug panel, M mute, Esc close a panel. Your game saves automatically; Continue on the title screen picks it up.", 17)
	_modal_button(vb, "Close", _modal_close, Color(0.72, 0.85, 0.60))

func _show_archive() -> void:
	var vb := _modal_open("Historical Archive")
	_modal_label(vb, "The timeline remembers what you have done — across replays.", 16, Color(0.35, 0.35, 0.35))
	_modal_label(vb, "Timeline events:", 18, Color(0.45, 0.25, 0.08))
	for ev in TIMELINE_EVENTS:
		var e: Dictionary = ev
		if bool(timeline_flags.get(String(e.get("flag", "")), false)):
			_modal_label(vb, "• " + String(e.get("text", "")), 16)
		else:
			_modal_label(vb, "• ??? — an event you have not lived yet.", 16, Color(0.55, 0.55, 0.55))
	_modal_label(vb, "Truths discovered (%d of %d):" % [discovered_truths.size(), TRUTHS.size()], 18, Color(0.45, 0.25, 0.08))
	for tid in archive_truths:
		var t: Dictionary = TRUTHS.get(tid, {})
		if not t.is_empty():
			_modal_label(vb, "• %s — %s" % [String(t.get("object", tid)), String(t.get("status", ""))], 16)
	if archive_truths.is_empty():
		_modal_label(vb, "No truths discovered yet. Truth Check anything that looks wrong.", 16, Color(0.55, 0.55, 0.55))
	_modal_label(vb, "Progress: score %d • stability %d%% • paradox %d%% • puzzles %d/%d • scenes %d/%d" % [score, stability, paradox, solved_puzzles.size(), PUZZLES.size(), visited_scenes.size(), SCENES.size()], 15, Color(0.35, 0.35, 0.35))
	_modal_button(vb, "Close", _modal_close, Color(0.72, 0.85, 0.60))

# --- save / load -------------------------------------------------------------------

func _state_dict() -> Dictionary:
	return {
		"score": score, "paradox": paradox, "stability": stability,
		"currentAct": current_act, "currentScene": current_scene,
		"inventory": inventory.duplicate(), "discoveredTruths": discovered_truths.duplicate(),
		"solvedPuzzles": solved_puzzles.duplicate(),
		"timelineFlags": timeline_flags.duplicate(), "dialogueFlags": dialogue_flags.duplicate(),
		"visitedScenes": visited_scenes.duplicate(), "quizResults": quiz_results.duplicate(),
		"keyDigits": key_digits.duplicate(), "categories": categories.duplicate(),
		"gameCompleted": game_completed,
	}

func _apply_save_dict(d: Dictionary) -> void:
	score = int(d.get("score", 0))
	paradox = int(d.get("paradox", 15))
	stability = int(d.get("stability", 85))
	current_act = int(d.get("currentAct", 1))
	current_scene = String(d.get("currentScene", "workshop"))
	inventory.clear()
	for it in d.get("inventory", []):
		inventory.append(String(it))
	discovered_truths.clear()
	for it in d.get("discoveredTruths", []):
		discovered_truths.append(String(it))
	solved_puzzles.clear()
	for it in d.get("solvedPuzzles", []):
		solved_puzzles.append(String(it))
	timeline_flags = Dictionary(d.get("timelineFlags", {}))
	dialogue_flags = Dictionary(d.get("dialogueFlags", {}))
	visited_scenes.clear()
	for it in d.get("visitedScenes", []):
		visited_scenes.append(String(it))
	quiz_results = Dictionary(d.get("quizResults", {}))
	key_digits = Dictionary(d.get("keyDigits", {}))
	categories = Dictionary(d.get("categories", {"knowledge": 0, "puzzles": 0, "truths": 0, "artifacts": 0, "restoration": 0, "exploration": 0}))
	game_completed = bool(d.get("gameCompleted", false))
	audio.set_act(current_act)
	_update_labels()

func _save_game(silent: bool) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_log("ERROR", "Save failed: cannot open " + SAVE_PATH)
		return false
	f.store_string(JSON.stringify(_state_dict()))
	f.close()
	if not silent:
		_log("INFO", "Game saved.")
	return true

func _load_save_dict() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var j := JSON.new()
	if j.parse(text) != OK:
		_log("ERROR", "Save parse error: " + j.error_string)
		return {}
	return j.data

func _archive_add_truth(truth_id: String) -> void:
	if archive_truths.has(truth_id):
		return
	archive_truths.append(truth_id)
	var f := FileAccess.open(ARCHIVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"truths": archive_truths}))
		f.close()

func _load_archive() -> void:
	if not FileAccess.file_exists(ARCHIVE_PATH):
		return
	var text := FileAccess.get_file_as_string(ARCHIVE_PATH)
	var j := JSON.new()
	if j.parse(text) == OK and j.data is Dictionary:
		archive_truths.clear()
		for it in Dictionary(j.data).get("truths", []):
			archive_truths.append(String(it))

# --- debug ---------------------------------------------------------------------

func _toggle_debug() -> void:
	_debug_layer.visible = not _debug_layer.visible
	if _debug_layer.visible:
		_refresh_debug_text()
	_refresh_blocking()

func _refresh_debug_text() -> void:
	var lines: Array[String] = []
	lines.append("act %d / scene %s" % [current_act, current_scene])
	lines.append("score %d  paradox %d%% (%s)  stability %d%%" % [score, paradox, paradox_band_label(), stability])
	lines.append("flags: " + JSON.stringify(timeline_flags))
	lines.append("inventory: " + ", ".join(inventory))
	lines.append("puzzles solved (%d): %s" % [solved_puzzles.size(), ", ".join(solved_puzzles)])
	lines.append("truths (%d): %s" % [discovered_truths.size(), ", ".join(discovered_truths)])
	lines.append("key digits: " + key_digits_text())
	lines.append("quiz results: " + JSON.stringify(quiz_results))
	lines.append("--- event log (latest) ---")
	for i in range(maxi(0, event_log.size() - 15), event_log.size()):
		lines.append(event_log[i])
	_debug_text.text = "\n".join(lines)

func _debug_action(kind: String) -> void:
	if kind == "score":
		add_score(10, "knowledge")
	elif kind == "paradox-plus":
		add_paradox(10)
	elif kind == "paradox-minus":
		add_paradox(-10)
	elif kind == "stability-plus":
		add_stability(10)
	_refresh_debug_text()

func _debug_jump_act(a: int) -> void:
	_toggle_debug()
	start_act(a)

# --- autodemo (scripted end-to-end verification) -----------------------------------

var _ad_running := false
var _ad_arrived := false
var _puzzle_feedback := ""

func _run_autodemo() -> void:
	if _ad_running:
		return
	_ad_running = true
	cadet.speed_scale = 3.0
	_log("INFO", "Autodemo started: " + autodemo)
	await get_tree().create_timer(0.5).timeout
	if autodemo == "act1":
		autodemo_act1_only = true
	await _ad_play_act1()
	if autodemo_act1_only:
		_ad_finish("ACT1_DONE")
		return
	await _ad_play_act2()
	await _ad_play_act3()
	await _ad_play_act4()
	await _ad_play_act5()
	_ad_finish("DONE")

func _ad_finish(marker: String) -> void:
	_ad_running = false
	var rank := ""
	if stability >= 95 and score >= 3000:
		rank = "S"
	elif stability >= 80:
		rank = "A"
	elif stability >= 50:
		rank = "B"
	elif stability >= 30:
		rank = "C"
	else:
		rank = "D"
	var msg := "AUTODEMO_%s score=%d stability=%d paradox=%d rank=%s" % [marker, score, stability, paradox, rank]
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.title = '%s';" % msg, true)
	_log("INFO", msg)
	if not OS.has_feature("web"):
		# Let pending screenshot captures (e.g. the ending shot, 0.8 s)
		# land before quitting the tree.
		await get_tree().create_timer(1.5).timeout
		get_tree().quit()

func _ad_wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ad_find_button(part: String) -> Button:
	var fallback: Button = null
	for c in _modal_box.get_children():
		if c is Button:
			var t := String(c.text)
			if t == part:
				return c
			if fallback == null and part in t:
				fallback = c
	return fallback

func _ad_press_button(part: String, quiet := false) -> bool:
	var b := _ad_find_button(part)
	if b == null:
		if not quiet:
			_log("ERROR", "Autodemo: button not found: " + part)
		return false
	b.pressed.emit()
	return true

func _ad_goto(scene_id: String, hotspot_id: String) -> void:
	if _find_hotspot_anywhere(hotspot_id).is_empty():
		_log("ERROR", "Autodemo: hotspot not found in data: " + hotspot_id)
		return
	if current_scene != scene_id:
		travel_to(scene_id)
		await _ad_wait(0.4)
	_ad_arrived = false
	_go_to_hotspot(hotspot_id)
	var waited := 0.0
	while not _ad_arrived and waited < 12.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not _ad_arrived:
		_log("ERROR", "Autodemo: walk timeout to " + hotspot_id)
	_close_action_popup()
	await _ad_wait(0.25)

func _ad_take(scene_id: String, hotspot_id: String) -> void:
	await _ad_goto(scene_id, hotspot_id)
	_do_interact(hotspot_id)
	await _ad_wait(0.4)

func _ad_truth(scene_id: String, hotspot_id: String) -> void:
	await _ad_goto(scene_id, hotspot_id)
	_do_truth(hotspot_id)
	await _ad_wait(0.5)
	_close_truth()

func _ad_talk(scene_id: String, hotspot_id: String, choice_idx: int = 0) -> void:
	await _ad_goto(scene_id, hotspot_id)
	_do_talk(hotspot_id)
	await _ad_wait(0.4)
	while _dialogue_layer.visible:
		var dlg: Dictionary = DIALOGUES.get(_dialogue_id, {})
		var node: Dictionary = Dictionary(dlg.get("nodes", {})).get(_dialogue_node, {})
		var choices: Array = node.get("choices", [])
		if choices.is_empty():
			break
		var pick: Dictionary = choices[clampi(choice_idx, 0, choices.size() - 1)]
		_on_choice_pressed(pick)
		await _ad_wait(0.4)
		# Press the Continue / End button the choice created.
		if not _dialogue_layer.visible:
			break
		var cont: Button = null
		for c in _dialogue_choices.get_children():
			if c is Button:
				cont = c
		if cont == null:
			break
		cont.pressed.emit()
		await _ad_wait(0.4)

func _ad_puzzle(scene_id: String, hotspot_id: String) -> void:
	await _ad_goto(scene_id, hotspot_id)
	_do_interact(hotspot_id)
	await _ad_wait(0.4)
	var puzzle: Dictionary = PUZZLES.get(_puzzle_id, {})
	var ptype := String(puzzle.get("type", ""))
	match ptype:
		"anachronism":
			var mode_authentic := String(puzzle.get("mode", "")) == "authentic"
			for opt in puzzle.get("options", []):
				var o: Dictionary = opt
				var is_anach := bool(o.get("anachronistic", false))
				if (mode_authentic and not is_anach) or (not mode_authentic and is_anach):
					var b := _ad_find_button(String(o.get("label", "")))
					if b:
						b.pressed.emit()
						await _ad_wait(0.15)
			_ad_press_button("Confirm")
		"sequence":
			for cid in puzzle.get("correct", []):
				for st in puzzle.get("steps", []):
					if String(st.get("id", "")) == String(cid):
						var b := _ad_find_button(String(st.get("label", "")))
						if b:
							b.pressed.emit()
							await _ad_wait(0.15)
			_ad_press_button("Confirm")
		"testimony":
			for st in puzzle.get("statements", []):
				if bool(st.get("correct", false)):
					var txt := String(st.get("text", ""))
					for c in _modal_box.get_children():
						if c is Button and String(c.text).begins_with(txt.substr(0, 20)):
							c.pressed.emit()
							break
					break
		"cipher":
			_puzzle_code_input.text = String(puzzle.get("answer", ""))
			_ad_press_button("Confirm")
		"code":
			_puzzle_code_input.text = String(puzzle.get("answer", ""))
			_ad_press_button("Seal the Core")
	await _ad_wait(0.5)
	# Dismiss the "Puzzle Solved" modal (the final-code flow shows a
	# "Sealed" modal instead — leave that for the caller).
	if _modal_layer.visible and _ad_find_button("Continue") != null:
		_ad_press_button("Continue")
		await _ad_wait(0.4)

func _ad_combine(a: String, b: String) -> void:
	_try_combine(a, b)
	await _ad_wait(0.4)
	if _modal_layer.visible:
		_ad_press_button("Continue")
		await _ad_wait(0.3)

func _ad_use(item_id: String, scene_id: String, hotspot_id: String) -> void:
	# Select AFTER travelling: _load_scene clears the selection.
	await _ad_goto(scene_id, hotspot_id)
	selected_item = item_id
	_rebuild_inventory()
	_do_use(hotspot_id)
	await _ad_wait(0.6)
	# Repair modal: take the quiz.
	if _modal_layer.visible:
		_ad_press_button("Take the Act Quiz")
		await _ad_wait(0.4)
		await _ad_quiz("act%d" % current_act)
		# Act-complete modal: continue.
		await _ad_wait(0.4)
		if _modal_layer.visible:
			_ad_press_button("Continue to Act")
			# Title card runs ~4s; wait for the next scene to load.
			await _ad_wait(4.5)

func _ad_quiz(quiz_id: String) -> void:
	while _modal_layer.visible and _quiz_id == quiz_id:
		var quiz: Dictionary = QUIZZES.get(quiz_id, {})
		var questions: Array = quiz.get("questions", [])
		if _quiz_index >= questions.size():
			break
		var q: Dictionary = questions[_quiz_index]
		var correct_idx := int(q.get("answer", 0))
		var options: Array = q.get("options", [])
		var b := _ad_find_button(String(options[correct_idx]))
		if b == null:
			_log("ERROR", "Autodemo: quiz option not found: " + String(options[correct_idx]))
			return
		b.pressed.emit()
		await _ad_wait(0.4)
		if not _ad_press_button("Next", true):
			_ad_press_button("See results")
		await _ad_wait(0.4)
	# Results modal.
	if _modal_layer.visible:
		_ad_press_button("Continue")
		await _ad_wait(0.4)

func _ad_play_act1() -> void:
	_log("INFO", "Autodemo: Act 1")
	await _ad_take("workshop", "magnifier_ws")
	await _ad_take("workshop", "workbench_notes")
	await _ad_truth("workshop", "music_player")
	await _ad_talk("workshop", "franklin_ws", 0)
	await _ad_puzzle("workshop", "bench_puzzle")
	await _ad_take("printshop", "copper_wire")
	await _ad_take("marketplace", "lodestone_stall")
	await _ad_take("library", "glass_tube")
	await _ad_puzzle("library", "franklin_timeline")
	await _ad_take("street", "notice_board")
	await _ad_take("meeting", "document_box")
	await _ad_combine("magnifier", "document")
	await _ad_combine("copper_wire", "lodestone")
	await _ad_combine("resonator_coil", "glass_tube")
	await _ad_use("resonator", "workshop", "music_player")

func _ad_play_act2() -> void:
	_log("INFO", "Autodemo: Act 2")
	await _ad_take("mill", "wrench_mill")
	await _ad_puzzle("mill", "loom_sequence")
	await _ad_talk("mill", "mill_owner", 0)
	await _ad_truth("mill", "radio_set")
	await _ad_take("warehouse", "wire_warehouse")
	await _ad_puzzle("cottage", "three_stories")
	await _ad_talk("cottage", "worker_npc", 0)
	await _ad_combine("wrench", "copper_wire")
	await _ad_use("grounding_wrench", "mill", "radio_set")

func _ad_play_act3() -> void:
	_log("INFO", "Autodemo: Act 3")
	await _ad_take("observatory", "star_chart")
	await _ad_take("apothecary", "ink_pot_apoth")
	await _ad_puzzle("apothecary", "traveller_note")
	await _ad_truth("apothecary", "germ_chart")
	await _ad_talk("apothecary", "apothecary_npc", 0)
	await _ad_take("university", "manuscript")
	await _ad_puzzle("university", "scholar_slate")
	await _ad_take("observatory", "wax_observatory")
	await _ad_combine("ink_pot", "manuscript")
	await _ad_combine("draft_correction", "sealing_wax")
	await _ad_use("sealed_correction", "apothecary", "germ_chart")

func _ad_play_act4() -> void:
	_log("INFO", "Autodemo: Act 4")
	await _ad_take("hangar", "wrench_hangar")
	await _ad_puzzle("hangar", "parts_bench")
	await _ad_talk("hangar", "mechanic_npc", 0)
	await _ad_truth("hangar", "turbine_blade")
	await _ad_puzzle("airfield", "assembly_notes")
	await _ad_talk("airfield", "pilot_npc", 0)
	await _ad_use("wrench", "hangar", "turbine_blade")

func _ad_play_act5() -> void:
	_log("INFO", "Autodemo: Act 5")
	await _ad_take("gallery", "chronarch_sigil")
	await _ad_puzzle("gallery", "memory_franklin")
	await _ad_talk("core", "chronarch_npc", 0)
	await _ad_talk("dais", "chronarch2_npc", 0)
	await _ad_puzzle("core", "core_fracture")
	# "The Core is Sealed" modal: take the final quiz.
	await _ad_wait(0.4)
	if _modal_layer.visible:
		_ad_press_button("Take the Final Quiz")
		await _ad_wait(0.4)
		await _ad_quiz("final")
