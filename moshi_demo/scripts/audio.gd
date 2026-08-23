extends Node
## AudioMgr —— 程序化音效：AudioStreamWAV 现场合成，零音频文件。
## 击杀"啵"声音高随连杀递增（play_later 串成一片）。

var _players: Array[AudioStreamPlayer] = []
var _sfx: Dictionary = {}
var _bgm_player: AudioStreamPlayer

## BGM 键 → 文件（assets/audio/）。主音频为 BGM_04_FinalClock_B。
const BGM_PATHS := {
	"main": "res://assets/audio/BGM_04_FinalClock_B_SOURCE.mp3",
	"dial": "res://assets/audio/BGM_04_FinalClock_B_SOURCE.mp3",
}

func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_bgm_player = AudioStreamPlayer.new()
	add_child(_bgm_player)
	_sfx["kill"] = _tone(540.0, 0.16, 22.0, 0)
	_sfx["dash"] = _noise(0.28, 9.0, 0.5)
	_sfx["burst"] = _tone(85.0, 0.4, 7.0, 2)
	_sfx["mark"] = _tone(1500.0, 0.05, 60.0, 0)
	_sfx["hit"] = _tone(120.0, 0.22, 14.0, 2)
	_sfx["draw"] = _tone(760.0, 0.05, 50.0, 0)
	_sfx["cancel"] = _tone(320.0, 0.12, 26.0, 0)
	_sfx["rewind"] = _sweep(180.0, 1400.0, 0.55)
	_sfx["wave"] = _tone(660.0, 0.28, 9.0, 0)
	_sfx["clock"] = _tone(990.0, 0.3, 8.0, 0)
	_sfx["over"] = _sweep(420.0, 55.0, 1.4)
	_sfx["upgrade"] = _tone(880.0, 0.4, 6.0, 0)

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

func play_bgm(key: String, volume_db: float = -10.0) -> void:
	var path: String = BGM_PATHS.get(key, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var stream = load(path)
	if stream == null:
		return
	if _bgm_player.stream == stream and _bgm_player.playing:
		return
	_bgm_player.stream = stream
	_bgm_player.volume_db = volume_db
	_bgm_player.play()

func stop_bgm() -> void:
	_bgm_player.stop()

func _assign(p: AudioStreamPlayer, sfx_name: String, pitch: float, volume_db: float) -> void:
	p.stream = _sfx[sfx_name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()

func _tone(freq: float, dur: float, decay: float, kind: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * decay)
		var v := 0.0
		match kind:
			2:
				v = signf(sin(TAU * freq * t)) * env * 0.35
			_:
				v = sin(TAU * freq * t) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32760.0))
	return _wav(data, rate)

func _noise(dur: float, decay: float, gain: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := minf(t * 40.0, 1.0) * exp(-t * decay)
		var v := (randf() * 2.0 - 1.0) * env * gain
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32760.0))
	return _wav(data, rate)

func _sweep(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var f := lerpf(f0, f1, t / dur)
		ph += TAU * f / float(rate)
		var env := exp(-t * 2.0) * minf(t * 30.0, 1.0)
		var v := sin(ph) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32760.0))
	return _wav(data, rate)

func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
