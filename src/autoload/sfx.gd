extends Node
## Autoload "Sfx": tiny procedural sound effects. Every sound is a generated
## 16-bit WAV (no asset files), played through a small pool of players.
## GDD: "Strong visual and audio feedback".

const MIX_RATE := 22050
const POOL_SIZE := 12

var _streams := {}
var _pool: Array = []
var _pool_next := 0
var _seq_queue: Array = []
var _seq_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_build_library()


func _process(delta: float) -> void:
	if _seq_queue.is_empty():
		return
	_seq_t += delta
	while not _seq_queue.is_empty():
		var head: Array = _seq_queue[0]
		if _seq_t < float(head[1]):
			break
		_seq_queue.pop_front()
		play(str(head[0]))


# ---------------------------------------------------------------- public api


func play(sound: String, pitch_jitter := 0.0, volume_db := 0.0) -> void:
	if Meta.muted or not _streams.has(sound):
		return
	var player: AudioStreamPlayer = _find_player()
	player.stream = _streams[sound]
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = volume_db
	player.play()


func play_sequence(steps: Array) -> void:
	## steps: Array of [name, at_seconds] relative to now.
	_seq_queue = steps.duplicate()
	_seq_t = 0.0


func jingle_win() -> void:
	play_sequence([["note_c", 0.0], ["note_e", 0.12], ["note_g", 0.24], ["note_c2", 0.4]])


func jingle_lose() -> void:
	play_sequence([["note_g", 0.0], ["note_e", 0.16], ["note_c_low", 0.34]])


# ---------------------------------------------------------------- library


func _find_player() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _pool:
		if not p.playing:
			return p
	_pool_next = (_pool_next + 1) % _pool.size()
	return _pool[_pool_next]


func _build_library() -> void:
	_streams = {
		"shoot": _tone(880.0, 560.0, 0.05, "square", 0.16),
		"hit": _tone(240.0, 180.0, 0.05, "saw", 0.2),
		"peon_die": _tone(340.0, 110.0, 0.12, "saw", 0.26),
		"elite_die": _tone(520.0, 80.0, 0.28, "saw", 0.34),
		"hurt": _tone(150.0, 90.0, 0.14, "square", 0.3),
		"ball_tick": _tone(1250.0, 1400.0, 0.03, "sine", 0.14),
		"gate_mult": _tone(620.0, 1240.0, 0.13, "tri", 0.3),
		"gate_sub": _tone(300.0, 130.0, 0.16, "saw", 0.3),
		"bounce": _tone(380.0, 950.0, 0.1, "sine", 0.26),
		"mystery": _tone(700.0, 1500.0, 0.22, "tri", 0.3),
		"drop_start": _tone(500.0, 700.0, 0.09, "sine", 0.24),
		"upgrade": _tone(523.0, 1046.0, 0.2, "tri", 0.3),
		"reroll": _tone(400.0, 300.0, 0.08, "square", 0.2),
		"button": _tone(660.0, 660.0, 0.04, "sine", 0.18),
		"boss_roar": _tone(110.0, 55.0, 0.5, "saw", 0.4),
		"charge_warn": _tone(220.0, 220.0, 0.12, "square", 0.22),
		"second_wind": _tone(330.0, 990.0, 0.35, "tri", 0.34),
		"note_c": _tone(523.0, 523.0, 0.12, "tri", 0.3),
		"note_e": _tone(659.0, 659.0, 0.12, "tri", 0.3),
		"note_g": _tone(784.0, 784.0, 0.12, "tri", 0.3),
		"note_c2": _tone(1046.0, 1046.0, 0.2, "tri", 0.3),
		"note_c_low": _tone(262.0, 262.0, 0.25, "saw", 0.3),
	}


func _tone(f0: float, f1: float, dur: float, shape: String, vol: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var freq := lerpf(f0, f1, t)
		phase += freq / MIX_RATE
		var s := _sample(shape, phase)
		# Fast attack, exponential-ish decay envelope.
		var env := minf(1.0, t * 30.0) * pow(1.0 - t, 1.6)
		var v := int(clampf(s * env * vol, -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _sample(shape: String, phase: float) -> float:
	var p := fmod(phase, 1.0)
	match shape:
		"square":
			return 1.0 if p < 0.5 else -1.0
		"saw":
			return 2.0 * p - 1.0
		"tri":
			return 4.0 * absf(p - 0.5) - 1.0
		"noise":
			return randf_range(-1.0, 1.0)
	return sin(p * TAU)
