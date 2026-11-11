class_name Franklin
extends Area2D

## Benjamin Franklin, NPC. Clickable (Area2D on physics layer 2), idles with a
## slow bob, turns to face whoever approaches, and bounces while talking.

var visual: Node2D
var sprite: Sprite2D
var anim_player: AnimationPlayer

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(220, 340)
	shape.shape = rect
	shape.position = Vector2(0, -160)
	add_child(shape)

	visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)

	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load("res://art/franklin.png")
	sprite.scale = Vector2(0.36, 0.36)
	# Feet at the node origin: sprite is 398x900, scaled to ~324 tall.
	sprite.position = Vector2(0, -162)
	visual.add_child(sprite)

	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	_build_animations()
	anim_player.play("idle")

func face_towards(x: float) -> void:
	# Franklin faces left when the other person stands to his left.
	sprite.flip_h = x < global_position.x

func play_talk() -> void:
	anim_player.play("talk")

func play_idle() -> void:
	anim_player.play("idle")

func _build_animations() -> void:
	# Idle: very slow bob, like breathing.
	var idle := Animation.new()
	idle.length = 3.0
	idle.loop_mode = Animation.LOOP_LINEAR
	var t := idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(t, "Visual:position:y")
	idle.track_insert_key(t, 0.0, 0.0)
	idle.track_insert_key(t, 1.5, -3.0)
	idle.track_insert_key(t, 3.0, 0.0)

	# Talk: excited bounce while speaking, then settle.
	var talk := Animation.new()
	talk.length = 0.9
	talk.loop_mode = Animation.LOOP_LINEAR
	t = talk.add_track(Animation.TYPE_VALUE)
	talk.track_set_path(t, "Visual:position:y")
	talk.track_insert_key(t, 0.0, 0.0)
	talk.track_insert_key(t, 0.15, -10.0)
	talk.track_insert_key(t, 0.3, 0.0)
	talk.track_insert_key(t, 0.45, -7.0)
	talk.track_insert_key(t, 0.6, 0.0)
	talk.track_insert_key(t, 0.9, 0.0)
	t = talk.add_track(Animation.TYPE_VALUE)
	talk.track_set_path(t, "Visual:rotation")
	talk.track_insert_key(t, 0.0, 0.0)
	talk.track_insert_key(t, 0.3, 0.03)
	talk.track_insert_key(t, 0.6, -0.02)
	talk.track_insert_key(t, 0.9, 0.0)
	# Godot 4 stores animations in named AnimationLibraries on the player.
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", idle)
	lib.add_animation("talk", talk)
	anim_player.add_animation_library("", lib)
