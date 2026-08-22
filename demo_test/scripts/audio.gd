extends Node
## AudioMgr —— 程序化音效：AudioStreamWAV 现场合成，零音频文件。
## 老版《墨时》质感移植：双层合成（sweep 扫频 + noise 噪声爆发）+ 高增益。
## 击杀"啵"声音高随连杀递增（play_later 串成一片）。

const RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _sfx: Dictionary = {}

func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.volume_db = 4.0
		add_child(p)
		_players.append(p)
	_sfx["start"] = _concat(_sweep(440.0, 440.0, 0.08, 0, 0.4), _sweep(660.0, 990.0, 0.22, 0, 0.35))
	_sfx["draw"] = _sweep(180.0, 90.0, 0.12, 0, 0.3)
	_sfx["dash"] = _whoosh(0.2, 0.34)
	_sfx["burst"] = _concat(_sweep(110.0, 38.0, 0.28, 0, 0.8), _noise_burst(0.3, 0.55))
	_sfx["kill"] = _concat(_noise_burst(0.05, 0.5), _sweep(900.0, 400.0, 0.12, 0, 0.3))
	_sfx["hit"] = _sweep(160.0, 55.0, 0.3, 0, 0.65)
	_sfx["rewind"] = _sweep(160.0, 900.0, 0.5, 0, 0.35)
	_sfx["ready"] = _concat(_sweep(660.0, 660.0, 0.09, 1, 0.28), _sweep(880.0, 880.0, 0.14, 1, 0.28))
	_sfx["over"] = _sweep(200.0, 50.0, 0.8, 0, 0.65)
	_sfx["mark"] = _tone(1500.0, 0.05, 60.0)
	_sfx["cancel"] = _tone(320.0, 0.12, 26.0)
	_sfx["wave"] = _tone(660.0, 0.28, 9.0)
	_sfx["clock"] = _tone(990.0, 0.3, 8.0)
	_sfx["upgrade"] = _tone(880.0, 0.4, 6.0)

func play(sfx_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _sfx.has(sfx_name):
		return
	for p in _players:
		if not p.playing:
			_assign(p, sfx_name, pitch, volume_db)
			return
	_assign(_players[0], sfx_name, pitch, volume_db)

func play_later(sfx_name: String, delay: float, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	get_tree().create_timer(delay).timeout.connect(
		func() -> void: play(sfx_name, pitch, volume_db))

func _assign(p: AudioStreamPlayer, sfx_name: String, pitch: float, volume_db: float) -> void:
	p.stream = _sfx[sfx_name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()

## 正弦(0) / 方波(1) 扫频，指数衰减
func _sweep(f0: float, f1: float, dur: float, wave: int, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var freq := lerpf(f0, f1, t)
		phase += TAU * freq / RATE
		var s := 0.0
		if wave == 0:
			s = sin(phase)
		else:
			s = 1.0 if sin(phase) >= 0.0 else -1.0
		var env := exp(-3.5 * t)
		var v := int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return _wav(bytes)

func _noise_burst(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / float(n)
		var s := randf_range(-1.0, 1.0)
		var env := exp(-4.0 * t)
		var v := int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return _wav(bytes)

## 低通噪声扫掠（风切声），sin 包络更圆润
func _whoosh(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var prev := 0.0
	for i in n:
		var t := float(i) / float(n)
		var raw := randf_range(-1.0, 1.0)
		prev = lerpf(prev, raw, 0.35)
		var env := sin(PI * t)
		var v := int(clampf(prev * env * vol, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return _wav(bytes)

## 单音（mark/wave/clock 等 UI 提示用）
func _tone(freq: float, dur: float, decay: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / float(RATE)
		var env := exp(-t * decay)
		var v := sin(TAU * freq * t) * env
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return _wav(bytes)

func _concat(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	return _wav(a.data + b.data)

func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
