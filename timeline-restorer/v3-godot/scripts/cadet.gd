class_name Cadet
extends CharacterBody2D

## The player character. Walks with NavigationAgent2D (real pathfinding around
## obstacles), flips to face the walk direction, bobs via AnimationPlayer, and
## plays a footstep sound every ~95 px travelled.

signal arrived

const SPEED := 190.0
const STEP_DISTANCE := 95.0

var agent: NavigationAgent2D
var visual: Node2D
var sprite: Sprite2D
var anim_player: AnimationPlayer
var audio: AudioManager
var moving := false
var _step_accum := 0.0

func _ready() -> void:
	agent = NavigationAgent2D.new()
	agent.path_desired_distance = 4.0
	agent.target_desired_distance = 10.0
	add_child(agent)

	visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)

	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load("res://art/cadet.png")
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
	anim_player.play("walk")

func stop() -> void:
	moving = false
	velocity = Vector2.ZERO
	anim_player.play("idle")

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
	velocity = dir.normalized() * SPEED
	move_and_slide()
	if velocity.x < -5.0:
		sprite.flip_h = true
	elif velocity.x > 5.0:
		sprite.flip_h = false
	_step_accum += velocity.length() * delta
	if _step_accum >= STEP_DISTANCE:
		_step_accum = 0.0
		if audio:
			audio.play_step()

func _stop() -> void:
	moving = false
	velocity = Vector2.ZERO
	anim_player.play("idle")
	emit_signal("arrived")

func _build_animations() -> void:
	# Idle: slow gentle bob + breathing squash.
	var idle := Animation.new()
	idle.length = 2.0
	idle.loop_mode = Animation.LOOP_LINEAR
	var t := idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(t, "Visual:position:y")
	idle.track_insert_key(t, 0.0, 0.0)
	idle.track_insert_key(t, 1.0, -4.0)
	idle.track_insert_key(t, 2.0, 0.0)
	t = idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(t, "Visual:scale")
	idle.track_insert_key(t, 0.0, Vector2(1, 1))
	idle.track_insert_key(t, 1.0, Vector2(1.01, 0.99))
	idle.track_insert_key(t, 2.0, Vector2(1, 1))

	# Walk: quicker bob + squash, four beats per 0.5s cycle.
	var walk := Animation.new()
	walk.length = 0.5
	walk.loop_mode = Animation.LOOP_LINEAR
	t = walk.add_track(Animation.TYPE_VALUE)
	walk.track_set_path(t, "Visual:position:y")
	walk.track_insert_key(t, 0.0, 0.0)
	walk.track_insert_key(t, 0.125, -7.0)
	walk.track_insert_key(t, 0.25, 0.0)
	walk.track_insert_key(t, 0.375, -7.0)
	walk.track_insert_key(t, 0.5, 0.0)
	t = walk.add_track(Animation.TYPE_VALUE)
	walk.track_set_path(t, "Visual:scale")
	walk.track_insert_key(t, 0.0, Vector2(1, 1))
	walk.track_insert_key(t, 0.125, Vector2(1.04, 0.96))
	walk.track_insert_key(t, 0.25, Vector2(1, 1))
	walk.track_insert_key(t, 0.375, Vector2(1.04, 0.96))
	walk.track_insert_key(t, 0.5, Vector2(1, 1))
	# Godot 4 stores animations in named AnimationLibraries on the player.
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", idle)
	lib.add_animation("walk", walk)
	anim_player.add_animation_library("", lib)
