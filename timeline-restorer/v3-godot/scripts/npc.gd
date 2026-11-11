class_name Npc
extends Area2D

## Generic NPC for Timeline Restorer v3. One sprite (feet at the node origin),
## idle bob, talk bounce, faces whoever approaches. Texture + height are set
## by the game per character; falls back to a plain coloured disc if the
## texture file is missing so the game never breaks on a missing asset.

var visual: Node2D
var sprite: Sprite2D
var anim_player: AnimationPlayer
var npc_id := ""

func setup(p_npc_id: String, texture_path: String, height_px: float) -> void:
	npc_id = p_npc_id
	collision_layer = 2
	collision_mask = 0
	set_meta("hotspot_id", npc_id)

	visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)

	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	var tex: Texture2D = load(texture_path) if ResourceLoader.exists(texture_path) else null
	if tex:
		sprite.texture = tex
		var h := float(tex.get_height())
		var s := height_px / h if h > 0.0 else 0.3
		sprite.scale = Vector2(s, s)
		sprite.position = Vector2(0, -height_px / 2.0)
		var w := float(tex.get_width()) * s
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(maxf(w, 80.0), height_px)
		shape.shape = rect
		shape.position = Vector2(0, -height_px / 2.0)
		add_child(shape)
	else:
		# Fallback: a simple coloured disc so the NPC is still clickable.
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		var c := 64.0
		for y in range(128):
			for x in range(128):
				var d := Vector2(x - c, y - c).length() / c
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.9, 0.7, 0.3, a))
		sprite.texture = ImageTexture.create_from_image(img)
		sprite.scale = Vector2(1.6, 1.6)
		sprite.position = Vector2(0, -100)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(180, 220)
		shape.shape = rect
		shape.position = Vector2(0, -110)
		add_child(shape)
	visual.add_child(sprite)

	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	_build_animations()
	anim_player.play("idle")

func face_towards(x: float) -> void:
	# Face left when the other person stands to the left.
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
