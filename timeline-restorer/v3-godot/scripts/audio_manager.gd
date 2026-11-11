class_name AudioManager
extends Node

## Procedural audio: every sound is synthesised at startup into AudioStreamWAV
## resources (no audio files). A gentle 12-second motif loops as background
## music; the motif's root and mode change per act (set_act). Short tones
## serve as click / footstep / truth / pickup / solved / error SFX.

const MIX_RATE := 22050

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var step_player: AudioStreamPlayer
var muted := false
var volume_step := 0  # 0 = full, 1 = medium, 2 = quiet
var act := 1

# Per-act motif: [root Hz, is_minor, melody scale degrees (semitones from root)]
const ACT_MOTIFS := {
	1: [261.63, false, [0, 4, 7, 12, 7, 4, 2, 4, 7, 12, 16, 12, 7, 4, 2, 0, 4, 2, 0, -5, -2, 0, 2]],
	2: [293.66, true, [0, 3, 7, 12, 10, 7, 5, 7, 10, 12, 15, 12, 10, 7, 5, 3, 7, 5, 3, 0, -2, 0, 3]],
	3: [392.00, false, [0, 4, 7, 12, 14, 12, 9, 7, 9, 12, 16, 14, 12, 9, 7, 4, 7, 4, 2, 0, 2, 4, 7]],
	4: [220.00, true, [0, 3, 7, 10, 12, 10, 7, 5, 3, 7, 10, 12, 15, 12, 10, 7, 5, 3, 5, 3, 0, -2, 0]],
	5: [329.63, true, [0, 3, 7, 12, 15, 12, 10, 7, 10, 12, 15, 19, 15, 12, 10, 7, 5, 7, 10, 7, 5, 3, 0]],
}

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "Music"
	music_player.stream = _make_music_loop(act)
	music_player.volume_db = -16.0
	add_child(music_player)
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "Sfx"
	add_child(sfx_player)
	step_player = AudioStreamPlayer.new()
	step_player.name = "Steps"
	step_player.volume_db = -16.0
	add_child(step_player)
	music_player.play()

func set_act(p_act: int) -> void:
	if p_act == act and music_player.stream != null:
		return
	act = clampi(p_act, 1, 5)
	var was_playing := music_player.playing
	music_player.stream = _make_music_loop(act)
	if was_playing:
		music_player.play()

func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted

func cycle_volume() -> String:
	volume_step = (volume_step + 1) % 3
	var vols := [-16.0, -22.0, -30.0]
	var labels := ["Vol: High", "Vol: Med", "Vol: Low"]
	music_player.volume_db = vols[volume_step]
	step_player.volume_db = vols[volume_step]
	return labels[volume_step]

func play_click() -> void:
	sfx_player.stream = _tone(880.0, 0.07, 0.25, 0.0)
	sfx_player.play()

func play_step() -> void:
	step_player.stream = _thump(95.0, 0.09, 0.30)
	step_player.play()

func play_truth() -> void:
	sfx_player.stream = _chime()
	sfx_player.play()

func play_pickup() -> void:
	sfx_player.stream = _arpeggio([523.25, 659.25, 783.99], 0.12, 0.22)
	sfx_player.play()

func play_dialogue_blip() -> void:
	sfx_player.stream = _tone(520.0, 0.12, 0.18, 0.0)
	sfx_player.play()

func play_solved() -> void:
	# Bright rising fanfare.
	sfx_player.stream = _arpeggio([523.25, 659.25, 783.99, 1046.50], 0.13, 0.24)
	sfx_player.play()

func play_act_complete() -> void:
	sfx_player.stream = _arpeggio([392.00, 523.25, 659.25, 783.99, 1046.50, 1318.51], 0.14, 0.22)
	sfx_player.play()

func play_error() -> void:
	sfx_player.stream = _tone(130.0, 0.25, 0.30, 0.0)
	sfx_player.play()

func play_repair() -> void:
	sfx_player.stream = _arpeggio([659.25, 783.99, 1046.50, 783.99, 1046.50], 0.12, 0.22)
	sfx_player.play()

# --- synthesis helpers -------------------------------------------------------

func _samples_to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav

func _tone(freq: float, seconds: float, amp: float, _unused: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / MIX_RATE
		var env := exp(-6.0 * t / seconds)
		samples[i] = amp * env * sin(TAU * freq * t)
	return _samples_to_wav(samples)

func _thump(freq: float, seconds: float, amp: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(count):
		var t := float(i) / MIX_RATE
		var env := exp(-9.0 * t / seconds)
		samples[i] = amp * env * (0.7 * sin(TAU * freq * t) + 0.3 * (rng.randf() * 2.0 - 1.0))
	return _samples_to_wav(samples)

func _chime() -> AudioStreamWAV:
	var seconds := 0.6
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / MIX_RATE
		var v := 0.0
		v += 0.22 * exp(-4.0 * t) * sin(TAU * 660.0 * t)
		if t > 0.15:
			var t2 := t - 0.15
			v += 0.22 * exp(-4.0 * t2) * sin(TAU * 990.0 * t2)
		samples[i] = v
	return _samples_to_wav(samples)

func _arpeggio(freqs: Array, note_len: float, amp: float) -> AudioStreamWAV:
	var seconds := note_len * freqs.size() + 0.15
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / MIX_RATE
		var idx := int(t / note_len)
		if idx >= freqs.size():
			continue
		var age := t - idx * note_len
		var env := exp(-5.0 * age / note_len)
		samples[i] = amp * env * sin(TAU * float(freqs[idx]) * t)
	return _samples_to_wav(samples)

func _make_music_loop(p_act: int) -> AudioStreamWAV:
	# 12 seconds: soft pad (root + third + fifth) + a gentle plucked melody
	# in the act's scale. Loop edges fade to avoid clicks.
	var motif: Array = ACT_MOTIFS.get(p_act, ACT_MOTIFS[1])
	var root: float = motif[0]
	var is_minor: bool = motif[1]
	var melody: Array = motif[2]
	var third := root * pow(2.0, (3.0 if is_minor else 4.0) / 12.0)
	var fifth := root * pow(2.0, 7.0 / 12.0)
	var seconds := 12.0
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var eighth := 0.5
	for i in range(count):
		var t := float(i) / MIX_RATE
		var v := 0.0
		# Soft pad: root + third + fifth, slow swell.
		var swell := 0.75 + 0.25 * sin(TAU * t / seconds)
		v += 0.045 * swell * sin(TAU * root * t)
		v += 0.035 * swell * sin(TAU * third * t)
		v += 0.035 * swell * sin(TAU * fifth * t)
		# Plucked melody note.
		var idx := int(t / eighth) % melody.size()
		var age := t - idx * eighth
		if age < eighth:
			var f := root * pow(2.0, float(melody[idx]) / 12.0)
			var env := exp(-3.0 * age / eighth)
			v += 0.16 * env * sin(TAU * f * t)
			v += 0.05 * env * sin(TAU * f * 2.0 * t)
		# Fade the loop edges so the wrap is seamless.
		var edge := minf(t, seconds - t)
		if edge < 0.05:
			v *= edge / 0.05
		samples[i] = v
	var wav := _samples_to_wav(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	return wav
