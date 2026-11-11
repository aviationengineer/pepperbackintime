extends Node2D

## Timeline Restorer — Godot PoC. ONE scene: Franklin's workshop, Act 1.
## Builds the whole scene in code (background, navigation, characters, lights,
## particles, HUD, dialogue / truth / action panels, title card).
## Content ported from v1 (DialogueData). Original art, generated for this PoC.

const VIEW_W := 1280.0
const VIEW_H := 720.0

# --- game state (PoC slice of v1) ---
var score := 0
var paradox := 15
var inventory: Array[String] = []
var flags := {}
var truths_found: Array[String] = []
var input_locked := true
var ui_blocking := false
var pending_hotspot := ""
var autodemo := false
var shot_path := ""
var shot_delay := 8.0
var _shot_taken := false
var _time := 0.0

# --- nodes ---
var cadet: Cadet
var franklin: Franklin
var audio: AudioManager
var _candle_light: PointLight2D
var _score_label: Label
var _paradox_label: Label
var _inventory_box: HBoxContainer
var _hint_label: Label
var _caption_panel: PanelContainer
var _caption_label: Label
var _toast_label: Label
var _paradox_overlay: ColorRect
var _dialogue_layer: CanvasLayer
var _dialogue_speaker: Label
var _dialogue_text: RichTextLabel
var _dialogue_choices: VBoxContainer
var _dialogue_node := ""
var _truth_layer: CanvasLayer
var _truth_title: Label
var _truth_status: Label
var _truth_object: Label
var _truth_fact: RichTextLabel
var _truth_era: Label
var _truth_conf: Label
var _truth_paradox: Label
var _action_layer: CanvasLayer
var _action_panel: PanelContainer
var _action_title: Label
var _action_buttons: VBoxContainer
var _title_layer: CanvasLayer
var _hotspot_areas := {}
var _hotspot_glows := {}
var _toast_tween: Tween
var _caption_tween: Tween

func _ready() -> void:
	_parse_args()
	audio = AudioManager.new()
	add_child(audio)
	_build_background()
	_build_navigation()
	_build_characters()
	_build_hotspots()
	_build_lights()
	_build_particles()
	_build_foreground()
	_build_hud()
	_build_dialogue_ui()
	_build_truth_ui()
	_build_action_ui()
	_show_title_card()
	_check_web_autodemo()

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
		var err := img.save_png(shot_path)
		print("SHOT_SAVED ", shot_path, " err=", err)
		get_tree().quit()

# --- setup -------------------------------------------------------------------

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autodemo":
			autodemo = true
		elif a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-delay="):
			shot_delay = float(a.trim_prefix("--shot-delay="))

func _check_web_autodemo() -> void:
	if not OS.has_feature("web"):
		return
	var search = JavaScriptBridge.eval("window.location.search", true)
	if typeof(search) == TYPE_STRING and "autodemo" in search:
		autodemo = true

func _build_background() -> void:
	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.texture = load("res://art/workshop_bg.png")
	bg.position = Vector2(VIEW_W / 2.0, VIEW_H / 2.0)
	bg.z_index = 0
	add_child(bg)

func _build_navigation() -> void:
	# Walkable floor band with the workbench and a stool carved out as holes.
	# The Cadet must path around them — no straight line through furniture.
	# (Tested: holes must sit strictly inside the outer outline — a hole that
	# touches the boundary, or a single concave outline, makes triangulation
	# fail and bakes an empty region.)
	var region := NavigationRegion2D.new()
	region.name = "Navigation"
	var poly := NavigationPolygon.new()
	poly.add_outline(PackedVector2Array([
		Vector2(30, 560), Vector2(1250, 560), Vector2(1250, 720), Vector2(30, 720),
	]))
	poly.add_outline(PackedVector2Array([  # workbench
		Vector2(60, 580), Vector2(700, 580), Vector2(700, 680), Vector2(60, 680),
	]))
	poly.add_outline(PackedVector2Array([  # stool
		Vector2(900, 620), Vector2(1000, 620), Vector2(1000, 700), Vector2(900, 700),
	]))
	poly.make_polygons_from_outlines()
	region.navigation_polygon = poly
	add_child(region)

func _build_characters() -> void:
	cadet = Cadet.new()
	cadet.name = "Cadet"
	cadet.position = Vector2(790, 660)
	cadet.audio = audio
	cadet.z_index = 10
	add_child(cadet)
	cadet.arrived.connect(_on_cadet_arrived)

	franklin = Franklin.new()
	franklin.name = "Franklin"
	franklin.position = Vector2(1090, 640)
	franklin.z_index = 9
	franklin.set_meta("hotspot_id", "franklin")
	add_child(franklin)

func _build_hotspots() -> void:
	for id in DialogueData.HOTSPOTS.keys():
		if id == "franklin":
			# Franklin's Area2D is the hotspot; only add his glow ring.
			_add_glow(Vector2(1090, 500), Color(1.0, 0.8, 0.3, 0.9), id)
			continue
		var def: Dictionary = DialogueData.HOTSPOTS[id]
		var area := Area2D.new()
		area.name = "Hotspot_" + id
		area.collision_layer = 2
		area.collision_mask = 0
		area.set_meta("hotspot_id", id)
		area.position = def["pos"]
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(110, 110)
		shape.shape = rect
		area.add_child(shape)
		add_child(area)
		_hotspot_areas[id] = area
		var glow_color := Color(1.0, 0.8, 0.3, 0.9)
		if id == "music_player":
			glow_color = Color(1.0, 0.35, 0.3, 0.95)
		_add_glow(def["pos"], glow_color, id)

func _add_glow(pos: Vector2, color: Color, id: String) -> void:
	var glow := Sprite2D.new()
	glow.texture = _ring_texture(128, color)
	glow.position = pos
	glow.scale = Vector2(0.9, 0.9)
	glow.z_index = 5
	add_child(glow)
	_hotspot_glows[id] = glow
	var tw := glow.create_tween().set_loops()
	tw.tween_property(glow, "modulate:a", 0.45, 0.8)
	tw.tween_property(glow, "modulate:a", 1.0, 0.8)

func _build_lights() -> void:
	var mod := CanvasModulate.new()
	mod.color = Color(0.62, 0.60, 0.66)
	add_child(mod)
	# Candle on the workbench: warm flickering pool of light.
	_candle_light = PointLight2D.new()
	_candle_light.position = Vector2(990, 555)
	_candle_light.texture = _radial_texture(256, Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	_candle_light.color = Color(1.0, 0.72, 0.38)
	_candle_light.energy = 0.9
	_candle_light.texture_scale = 2.4
	add_child(_candle_light)
	# Daylight from the window: cool, soft, wide.
	var window_light := PointLight2D.new()
	window_light.position = Vector2(260, 180)
	window_light.texture = _radial_texture(256, Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	window_light.color = Color(0.75, 0.88, 1.0)
	window_light.energy = 0.4
	window_light.texture_scale = 3.2
	add_child(window_light)

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
	add_child(dust)

func _build_foreground() -> void:
	# Hanging branches frame the top corners for depth (storybook framing).
	var left := Sprite2D.new()
	left.texture = load("res://art/leaves.png")
	left.position = Vector2(180, 40)
	left.scale = Vector2(0.55, 0.55)
	left.z_index = 20
	add_child(left)
	var right := Sprite2D.new()
	right.texture = load("res://art/leaves.png")
	right.position = Vector2(1150, 30)
	right.scale = Vector2(-0.45, 0.45)
	right.z_index = 20
	add_child(right)

# --- HUD ---------------------------------------------------------------------

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)

	var act := Label.new()
	act.text = "ACT 1 — PHILADELPHIA, 1764"
	act.position = Vector2(16, 12)
	act.add_theme_font_size_override("font_size", 22)
	act.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	act.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	act.add_theme_constant_override("shadow_offset_x", 2)
	act.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(act)

	var objective := Label.new()
	objective.text = "Find the humming device  •  Truth Check it  •  Talk to Franklin"
	objective.position = Vector2(16, 42)
	objective.add_theme_font_size_override("font_size", 15)
	objective.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	objective.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	objective.add_theme_constant_override("shadow_offset_x", 1)
	objective.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(objective)

	_score_label = Label.new()
	_score_label.position = Vector2(1060, 12)
	_score_label.add_theme_font_size_override("font_size", 22)
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_score_label.add_theme_constant_override("shadow_offset_x", 2)
	_score_label.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(_score_label)

	_paradox_label = Label.new()
	_paradox_label.position = Vector2(1060, 42)
	_paradox_label.add_theme_font_size_override("font_size", 15)
	_paradox_label.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0))
	_paradox_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_paradox_label.add_theme_constant_override("shadow_offset_x", 1)
	_paradox_label.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(_paradox_label)

	var mute := Button.new()
	mute.text = "Sound: On"
	mute.position = Vector2(1060, 70)
	mute.custom_minimum_size = Vector2(120, 30)
	_style_button(mute, Color(0.85, 0.75, 0.55))
	mute.pressed.connect(_on_mute_pressed.bind(mute))
	hud.add_child(mute)

	_inventory_box = HBoxContainer.new()
	_inventory_box.position = Vector2(16, 676)
	_inventory_box.add_theme_constant_override("separation", 8)
	var inv_label := Label.new()
	inv_label.text = "Inventory:"
	inv_label.add_theme_font_size_override("font_size", 16)
	inv_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	inv_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	inv_label.add_theme_constant_override("shadow_offset_x", 1)
	inv_label.add_theme_constant_override("shadow_offset_y", 1)
	_inventory_box.add_child(inv_label)
	hud.add_child(_inventory_box)

	_hint_label = Label.new()
	_hint_label.text = "Click anywhere to walk  •  Click a glowing object to investigate"
	_hint_label.position = Vector2(420, 684)
	_hint_label.add_theme_font_size_override("font_size", 15)
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
	_caption_panel.offset_top = -110
	_caption_panel.offset_bottom = -70
	_caption_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.1, 0.09, 0.07, 0.85), Color(0.72, 0.55, 0.2), 8, 2))
	_caption_panel.visible = false
	hud.add_child(_caption_panel)
	_caption_label = Label.new()
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.add_theme_font_size_override("font_size", 16)
	_caption_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.84))
	_caption_panel.add_child(_caption_label)

	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.offset_left = -400
	_toast_label.offset_right = 400
	_toast_label.offset_top = 110
	_toast_label.offset_bottom = 150
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 28)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_toast_label.add_theme_constant_override("shadow_offset_x", 2)
	_toast_label.add_theme_constant_override("shadow_offset_y", 2)
	_toast_label.visible = false
	hud.add_child(_toast_label)

	_paradox_overlay = ColorRect.new()
	_paradox_overlay.color = Color(0.25, 0.8, 1.0, 0.0)
	_paradox_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paradox_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 5
	overlay_layer.add_child(_paradox_overlay)
	add_child(overlay_layer)

	_update_labels()

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
	panel.offset_top = -260
	panel.offset_bottom = -16
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.92, 0.80), Color(0.72, 0.55, 0.20), 10, 3))
	_dialogue_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	_dialogue_speaker = Label.new()
	_dialogue_speaker.text = "Benjamin Franklin"
	_dialogue_speaker.add_theme_font_size_override("font_size", 20)
	_dialogue_speaker.add_theme_color_override("font_color", Color(0.45, 0.25, 0.08))
	vb.add_child(_dialogue_speaker)
	_dialogue_text = RichTextLabel.new()
	_dialogue_text.bbcode_enabled = false
	_dialogue_text.fit_content = true
	_dialogue_text.scroll_active = false
	_dialogue_text.custom_minimum_size = Vector2(0, 78)
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
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 440)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.92, 0.80), Color(0.72, 0.55, 0.20), 12, 3))
	_truth_layer.add_child(panel)
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
	vb.add_child(_truth_era)
	_truth_conf = Label.new()
	_truth_conf.add_theme_font_size_override("font_size", 16)
	vb.add_child(_truth_conf)
	_truth_paradox = Label.new()
	_truth_paradox.add_theme_font_size_override("font_size", 16)
	vb.add_child(_truth_paradox)
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
	_action_buttons = VBoxContainer.new()
	_action_buttons.add_theme_constant_override("separation", 6)
	vb.add_child(_action_buttons)

func _show_title_card() -> void:
	_title_layer = CanvasLayer.new()
	_title_layer.layer = 30
	add_child(_title_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(680, 300)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.10, 0.07, 0.97), Color(0.85, 0.65, 0.25), 12, 3))
	_title_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var act := Label.new()
	act.text = "ACT 1"
	act.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act.add_theme_font_size_override("font_size", 64)
	act.add_theme_color_override("font_color", Color(0.91, 0.71, 0.30))
	vb.add_child(act)
	var place := Label.new()
	place.text = "PHILADELPHIA, 1764"
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place.add_theme_font_size_override("font_size", 30)
	place.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	vb.add_child(place)
	var sub := Label.new()
	sub.text = "The Founding Mind That Shouldn't Be"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vb.add_child(sub)
	var note := Label.new()
	note.text = "A Timeline Restorer proof of concept — Godot edition"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	vb.add_child(note)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_on_title_done)

func _on_title_done() -> void:
	_title_layer.queue_free()
	_title_layer = null
	input_locked = false
	_hint_label.visible = true
	if autodemo:
		_run_autodemo()

# --- input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
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
	return Vector2(clampf(pos.x, 40.0, 1240.0), clampf(pos.y, 585.0, 695.0))

func _go_to_hotspot(id: String) -> void:
	pending_hotspot = id
	var approach: Vector2 = DialogueData.HOTSPOTS[id]["approach"]
	cadet.walk_to(approach)

func _on_cadet_arrived() -> void:
	if pending_hotspot == "":
		return
	var id := pending_hotspot
	pending_hotspot = ""
	if autodemo and id == "franklin":
		_open_dialogue("n1")
		return
	_open_action_popup(id)

# --- hotspots ------------------------------------------------------------------

func _open_action_popup(id: String) -> void:
	var def: Dictionary = DialogueData.HOTSPOTS[id]
	_action_title.text = String(def["name"])
	for child in _action_buttons.get_children():
		child.queue_free()
	for action in def["actions"]:
		var b := Button.new()
		match String(action):
			"look":
				b.text = "Look"
				b.pressed.connect(_do_look.bind(id))
			"talk":
				b.text = "Talk to Franklin"
				b.pressed.connect(_do_talk.bind(id))
			"truth":
				b.text = "Truth Check"
				b.pressed.connect(_do_truth.bind(id))
			"take":
				b.text = "Pick up"
				b.pressed.connect(_do_take.bind(id))
		_style_button(b, Color(0.85, 0.75, 0.55))
		_action_buttons.add_child(b)
	var pos: Vector2 = def["pos"]
	_action_panel.position = Vector2(clampf(pos.x - 110.0, 10.0, 1000.0), clampf(pos.y - 190.0, 10.0, 480.0))
	_action_layer.visible = true
	ui_blocking = true

func _close_action_popup() -> void:
	if _action_layer:
		_action_layer.visible = false
	if not _dialogue_layer.visible and not _truth_layer.visible:
		ui_blocking = false

func _do_look(id: String) -> void:
	_close_action_popup()
	audio.play_click()
	_show_caption(String(DialogueData.HOTSPOTS[id]["desc"]))

func _do_talk(_id: String) -> void:
	_close_action_popup()
	franklin.face_towards(cadet.global_position.x)
	_open_dialogue("n1")

func _do_truth(id: String) -> void:
	_close_action_popup()
	var truth_id := String(DialogueData.HOTSPOTS[id]["truth"])
	_open_truth(truth_id)

func _do_take(id: String) -> void:
	_close_action_popup()
	if id == "magnifier" and not inventory.has("magnifier"):
		inventory.append("magnifier")
		var slot := PanelContainer.new()
		slot.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.92, 0.80), Color(0.72, 0.55, 0.20), 6, 2))
		var label := Label.new()
		label.text = "Magnifying Glass"
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color(0.12, 0.10, 0.06))
		slot.add_child(label)
		_inventory_box.add_child(slot)
		audio.play_pickup()
		_show_toast("Picked up: Magnifying Glass")
		if _hotspot_areas.has(id):
			(_hotspot_areas[id] as Area2D).queue_free()
			_hotspot_areas.erase(id)
		if _hotspot_glows.has(id):
			(_hotspot_glows[id] as Sprite2D).queue_free()
			_hotspot_glows.erase(id)

# --- dialogue --------------------------------------------------------------------

func _open_dialogue(node_id: String) -> void:
	_dialogue_node = node_id
	franklin.face_towards(cadet.global_position.x)
	franklin.play_talk()
	audio.play_dialogue_blip()
	_show_dialogue_node(node_id)
	_dialogue_layer.visible = true
	ui_blocking = true

func _show_dialogue_node(node_id: String) -> void:
	var nodes: Dictionary = DialogueData.FRANKLIN_INTRO["nodes"]
	var node: Dictionary = nodes[node_id]
	_dialogue_text.text = String(node["text"])
	for child in _dialogue_choices.get_children():
		child.queue_free()
	for choice in node["choices"]:
		var b := Button.new()
		b.text = String(choice["text"])
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 44)
		_style_button(b, Color(0.88, 0.80, 0.62))
		b.pressed.connect(_on_choice_pressed.bind(choice))
		_dialogue_choices.add_child(b)

func _on_choice_pressed(choice: Dictionary) -> void:
	var eff: Dictionary = choice.get("effects", {})
	if eff.has("score"):
		score += int(eff["score"])
	if eff.has("paradox"):
		paradox = clampi(paradox + int(eff["paradox"]), 0, 100)
	if eff.has("flag"):
		flags[String(eff["flag"])] = true
	if eff.has("truth"):
		_mark_truth_found(String(eff["truth"]))
	_update_labels()
	audio.play_click()
	if int(eff.get("paradox", 0)) != 0:
		var p := int(eff["paradox"])
		_show_toast(("Paradox +%d" % p) if p > 0 else ("Paradox %d" % p))
	# Show the response, then continue to the next node (or close).
	_dialogue_text.text = String(choice["response"])
	for child in _dialogue_choices.get_children():
		child.queue_free()
	var next_node := String(choice.get("next", ""))
	var cont := Button.new()
	cont.text = "Continue" if next_node != "" else "End conversation"
	_style_button(cont, Color(0.85, 0.75, 0.55))
	if next_node != "":
		cont.pressed.connect(_on_continue_pressed.bind(next_node))
	else:
		cont.pressed.connect(_close_dialogue)
	_dialogue_choices.add_child(cont)

func _on_continue_pressed(next_node: String) -> void:
	_show_dialogue_node(next_node)

func _close_dialogue() -> void:
	_dialogue_layer.visible = false
	ui_blocking = false
	franklin.play_idle()

# --- truth check ---------------------------------------------------------------

func _open_truth(truth_id: String) -> void:
	var t: Dictionary = DialogueData.TRUTHS[truth_id]
	_truth_object.text = String(t["object"])
	if String(t["status"]) == "anachronistic":
		_truth_status.text = "✕ ANACHRONISTIC"
		_truth_status.add_theme_color_override("font_color", Color(0.75, 0.12, 0.10))
	else:
		_truth_status.text = "✓ AUTHENTIC"
		_truth_status.add_theme_color_override("font_color", Color(0.10, 0.55, 0.20))
	_truth_fact.text = String(t["fact"])
	_truth_era.text = "Expected era: %s    •    Current era: %s" % [String(t["expectedEra"]), String(t["currentEra"])]
	_truth_conf.text = "Truth confidence: %d%%" % int(t["confidence"])
	_truth_paradox.text = "Paradox contribution: +%d" % int(t["paradox"])
	if not truths_found.has(truth_id):
		truths_found.append(truth_id)
		score += 50
		_update_labels()
		_show_toast("Truth discovered!  +50")
	audio.play_truth()
	_truth_layer.visible = true
	ui_blocking = true

func _close_truth() -> void:
	_truth_layer.visible = false
	if not _dialogue_layer.visible:
		ui_blocking = false

func _mark_truth_found(truth_id: String) -> void:
	if truths_found.has(truth_id):
		return
	truths_found.append(truth_id)
	_show_toast("Truth discovered: " + String(DialogueData.TRUTHS[truth_id]["object"]))

# --- HUD helpers -----------------------------------------------------------------

func _update_labels() -> void:
	_score_label.text = "Score: %d" % score
	_paradox_label.text = "Paradox: %d%%" % paradox

func _on_mute_pressed(btn: Button) -> void:
	var muted := audio.toggle_mute()
	btn.text = "Sound: Off" if muted else "Sound: On"

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
	_caption_tween.tween_interval(3.5)
	_caption_tween.tween_property(_caption_panel, "modulate:a", 0.0, 0.6)
	_caption_tween.tween_callback(func() -> void: _caption_panel.visible = false)

func _run_autodemo() -> void:
	await get_tree().create_timer(0.6).timeout
	if autodemo and not input_locked:
		_go_to_hotspot("franklin")

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
	b.add_theme_font_size_override("font_size", 18)

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
