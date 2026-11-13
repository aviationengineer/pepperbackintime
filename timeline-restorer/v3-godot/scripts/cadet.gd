class_name Cadet
extends CharacterBody2D

## The player character. Walks with NavigationAgent2D (real pathfinding
## around obstacles) and flips to face the walk direction.
##
## v3.1: REAL frame animation. The old procedural bob made the single
## front-facing sprite slide; now a painted 8-frame side-profile walk
## cycle (art/cadet-walk.png — sliced from one generated sprite sheet by
## scripts/process_walk.py, so every frame is the same character) plays
## while moving. Frame choice is driven by DISTANCE TRAVELLED, not wall
## clock, so the stride stays glued to the ground at any frame rate:
## one full cycle per CYCLE_DISTANCE pixels, one footstep sound per
## half-cycle (each footfall). Idle returns to the front-facing sprite
## with a gentle breathing bob (halved amplitude — breathing, not
## bouncing).

signal arrived

const SPEED := 190.0
const WALK_SHEET := "res://art/cadet-walk.png"
const WALK_CELL_W := 447.0
# v3.2: the optional Colonial Coat costume swaps both sprite sets.
const COAT_IDLE := "res://art/cadet-coat.png"
const COAT_SHEET := "res://art/cadet-walk-coat.png"
const COAT_CELL_W := 535.0
const CYCLE_DISTANCE := 190.0  # one full walk cycle per 190 px

var agent: NavigationAgent2D
var visual: Node2D
var sprite: Sprite2D
var anim_player: AnimationPlayer
var audio: AudioManager
var moving := false
var speed_scale := 1.0
var walk_distance := 0.0  # px travelled on the current/last trip
var walk_frame_index := -1  # live cycle frame while walking (-1 = idle)
var _step_accum := 0.0
var _idle_texture: Texture2D
var _walk_frames: Array[Texture2D] = []
var coat_worn := false
var _idle_texture_coat: Texture2D
var _walk_frames_coat: Array[Texture2D] = []

func _load_frames(sheet_path: String, cell_w: float) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var sheet := load(sheet_path) as Texture2D
	if sheet:
		var count := int(sheet.get_width() / cell_w)
		for i in count:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * cell_w, 0, cell_w, sheet.get_height())
			frames.append(at)
	return frames

func _active_frames() -> Array[Texture2D]:
	return _walk_frames_coat if coat_worn else _walk_frames

func _active_idle() -> Texture2D:
	return _idle_texture_coat if coat_worn else _idle_texture

## v3.2: toggle the Colonial Coat costume. Sprites swap immediately,
## whether the Cadet is standing or mid-walk.
func set_coat(worn: bool) -> void:
	coat_worn = worn
	if moving:
		if walk_frame_index >= 0:
			_set_walk_frame(mini(walk_frame_index,
					_active_frames().size() - 1))
	else:
		_show_idle()

func _ready() -> void:
	agent = NavigationAgent2D.new()
	agent.path_desired_distance = 4.0
	agent.target_desired_distance = 10.0
	add_child(agent)

	_idle_texture = load("res://art/cadet.png")
	_idle_texture_coat = load(COAT_IDLE)
	_walk_frames = _load_frames(WALK_SHEET, WALK_CELL_W)
	_walk_frames_coat = _load_frames(COAT_SHEET, COAT_CELL_W)

	visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)

	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = _idle_texture
	sprite.scale = Vector2(0.34, 0.34)
	# Feet at the node origin: sprite is 372x900, scaled to ~306 tall.
	sprite.position = Vector2(0, -153)
	visual.add_child(sprite)

	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	_build_animations()
	anim_player.play("idle")

func walk_to(target: Vector2) -> void:
	agent.target_position = target
	moving = true
	walk_distance = 0.0
	_step_accum = 0.0
	# Frame animation replaces the procedural walk bob entirely.
	anim_player.stop()
	visual.position = Vector2.ZERO
	visual.scale = Vector2.ONE
	if not _active_frames().is_empty():
		_set_walk_frame(0)

func stop() -> void:
	moving = false
	velocity = Vector2.ZERO
	_show_idle()

func _physics_process(delta: float) -> void:
	if not moving:
		return
	if agent.is_navigation_finished():
		_stop()
		return
	var next_pos := agent.get_next_path_position()
	var dir := next_pos - global_position
	if dir.length() < 4.0:
		return
	velocity = dir.normalized() * SPEED * speed_scale
	var before := global_position
	move_and_slide()
	if velocity.x < -5.0:
		sprite.flip_h = true
	elif velocity.x > 5.0:
		sprite.flip_h = false
	var travelled := global_position.distance_to(before)
	if travelled <= 0.0:
		return
	walk_distance += travelled
	# Stride sync: frame = position inside the current cycle.
	var frames := _active_frames()
	if not frames.is_empty():
		var phase := fmod(walk_distance, CYCLE_DISTANCE) / CYCLE_DISTANCE
		var idx := int(phase * frames.size()) % frames.size()
		if idx != walk_frame_index:
			_set_walk_frame(idx)
	# One footstep per half-cycle — each time a foot lands.
	_step_accum += travelled
	if _step_accum >= CYCLE_DISTANCE * 0.5:
		_step_accum = 0.0
		if audio:
			audio.play_step()

func _stop() -> void:
	moving = false
	velocity = Vector2.ZERO
	_show_idle()
	emit_signal("arrived")

func _set_walk_frame(i: int) -> void:
	walk_frame_index = i
	sprite.texture = _active_frames()[i]
	# Walk cells share the idle art's 900 px height: the same 0.34 scale
	# keeps the Cadet the same size, feet at the origin.
	sprite.scale = Vector2(0.34, 0.34)
	sprite.position = Vector2(0, -153)

func _show_idle() -> void:
	walk_frame_index = -1
	sprite.texture = _active_idle()
	sprite.scale = Vector2(0.34, 0.34)
	sprite.position = Vector2(0, -153)
	anim_player.play("idle")

func _build_animations() -> void:
	# Idle only (walking is frame-animated now): a slow, shallow breath.
	var idle := Animation.new()
	idle.length = 2.4
	idle.loop_mode = Animation.LOOP_LINEAR
	var t := idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(t, "Visual:position:y")
	idle.track_insert_key(t, 0.0, 0.0)
	idle.track_insert_key(t, 1.2, -2.0)
	idle.track_insert_key(t, 2.4, 0.0)
	t = idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(t, "Visual:scale")
	idle.track_insert_key(t, 0.0, Vector2(1, 1))
	idle.track_insert_key(t, 1.2, Vector2(1.005, 0.995))
	idle.track_insert_key(t, 2.4, Vector2(1, 1))
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", idle)
	anim_player.add_animation_library("", lib)
