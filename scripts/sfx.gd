# 効果音。素材ファイルを使わず、起動時にプログラムで波形を合成して作る。
# （ライセンスの心配がなく、音の調整もこのファイルの数値だけで完結する）
# project.godot の [autoload] で "Sfx" として登録している。
#
#   Sfx.play("cut")                 … 鳴らす
#   Sfx.play("mince", -3.0, 0.15)   … 音量(dB)と、ピッチのばらつき
extends Node

const RATE := 22050
const POOL_SIZE := 10

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}
var _rng := RandomNumberGenerator.new()
var _lp_state := [0.0, 0.0, 0.0, 0.0]


func _ready() -> void:
	_rng.seed = 12345
	_streams["cut"] = _make(0.18, _cut)            # ザクッ（玉ねぎを切る）
	_streams["mince"] = _make(0.1, _mince)         # トン（みじん切り）
	_streams["knock"] = _make(0.09, _knock)        # コツ（まな板だけ叩いた）
	_streams["whoosh"] = _make(0.35, _whoosh)      # シュッ（玉ねぎを回す・かき集める）
	_streams["plop"] = _make(0.28, _plop)          # ぽとっ（ボウルに入る）
	_streams["coin"] = _make(0.55, _coin)          # チャリン（報酬）
	_streams["bell"] = _make(1.8, _bell)           # チーン（開店・仕込み終了）
	_streams["sniff"] = _make(0.75, _sniff)        # ずびっ（涙で目が開かない）
	_streams["click"] = _make(0.04, _click)        # UIのクリック
	_streams["processor"] = _make(1.0, _processor, true)  # フードプロセッサーの回転音（ループ）
	_streams["ambience"] = _make(3.0, _ambience, true)    # 厨房の環境音（ループ）

	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	set_loop("ambience", true, -20.0)


func play(sound: String, volume_db: float = 0.0, pitch_jitter: float = 0.05, pitch: float = 1.0) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter))
	p.play()


## 少し遅れて鳴らす（物が落ちきったタイミングなど）
func play_later(delay: float, sound: String, volume_db: float = 0.0) -> void:
	get_tree().create_timer(delay).timeout.connect(func(): play(sound, volume_db))


func set_loop(sound: String, on: bool, volume_db: float = 0.0) -> void:
	if not _loops.has(sound):
		var p := AudioStreamPlayer.new()
		p.stream = _streams[sound]
		add_child(p)
		_loops[sound] = p
	var player: AudioStreamPlayer = _loops[sound]
	player.volume_db = volume_db
	if on and not player.playing:
		player.play()
	elif not on and player.playing:
		player.stop()


func set_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(0, muted)


func get_stream(sound: String) -> AudioStreamWAV:
	return _streams[sound]


# ================================================================ 合成の道具

## 長さ dur 秒の波形を generator(t, dur) で作り、16bit の AudioStreamWAV にする。
## 単発の音は末尾をフェードアウト。ループ音は、末尾の続きを先頭にクロスフェードしてつなぎ目のプチッという音を消す。
func _make(dur: float, generator: Callable, loop: bool = false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var fade := int(0.1 * RATE) if loop else 0
	var g := PackedFloat32Array()
	g.resize(n + fade)
	_lp_state = [0.0, 0.0, 0.0, 0.0]
	for i in n + fade:
		g[i] = generator.call(float(i) / RATE, dur)
	for i in fade:
		g[i] = lerpf(g[n + i], g[i], float(i) / fade)
	if not loop:
		# 単発の音は最後を短くフェードアウトして、切れ目のプチッを防ぐ
		var tail := mini(n, int(0.015 * RATE))
		for i in tail:
			g[n - 1 - i] *= float(i) / tail
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(g[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s


## 1次ローパスフィルタ（slot ごとに状態を持つ）。cutoff は Hz。
func _lp(slot: int, x: float, cutoff: float) -> float:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	_lp_state[slot] += (x - _lp_state[slot]) * a
	return _lp_state[slot]


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


# ================================================================ 各効果音

func _cut(t: float, _d: float) -> float:
	# 繊維を断つシャリシャリ音 ＋ 最後にまな板に当たるトン
	var n := _noise()
	var crackle := n if _rng.randf() < 0.35 else n * 0.25
	var bright := crackle - _lp(0, crackle, 1800.0)
	var crunch := bright * exp(-t * 28.0) * 0.9
	var tt := t - 0.055
	var thump := 0.0
	if tt > 0.0:
		thump = sin(TAU * 150.0 * tt) * exp(-tt * 45.0) * 0.7
	return crunch + thump


func _mince(t: float, _d: float) -> float:
	# 低いトン ＋ 水気のある小さなシャク
	var f := 140.0 + 90.0 * exp(-t * 60.0)
	var body := sin(TAU * f * t) * exp(-t * 42.0) * 0.6
	var click := _lp(0, _noise(), 3500.0) * exp(-t * 220.0) * 0.6
	var n := _noise()
	var wet := (n - _lp(1, n, 2500.0)) * exp(-t * 55.0) * 0.25
	return body + click + wet


func _knock(t: float, _d: float) -> float:
	var tone := sin(TAU * 260.0 * t) + sin(TAU * 610.0 * t) * 0.3
	return tone * exp(-t * 55.0) * 0.6 + _lp(0, _noise(), 3000.0) * exp(-t * 300.0) * 0.4


func _whoosh(t: float, d: float) -> float:
	var x := t / d
	var cutoff := 400.0 + 2400.0 * sin(PI * x)
	var n := _noise()
	var band := _lp(0, n, cutoff) - _lp(1, n, cutoff * 0.3)
	return band * pow(sin(PI * x), 2.0) * 1.6


func _plop(t: float, _d: float) -> float:
	var f := 180.0 + 480.0 * exp(-t * 30.0)
	var drop := sin(TAU * f * t) * exp(-t * 20.0) * 0.55
	var shh := _lp(0, _noise(), 1200.0) * exp(-t * 14.0) * 0.5
	return drop + shh


func _coin(t: float, _d: float) -> float:
	var v := 0.0
	for note in [[0.0, 1318.5], [0.07, 1760.0]]:
		var tt: float = t - note[0]
		if tt > 0.0:
			var f: float = note[1]
			v += (sin(TAU * f * tt) + sin(TAU * f * 2.0 * tt) * 0.25) * exp(-tt * 9.0) * 0.35
	return v


func _bell(t: float, _d: float) -> float:
	# 金属のベル：整数倍でない倍音を重ねる
	var attack := minf(1.0, t * 400.0)
	var v := sin(TAU * 1046.5 * t) * exp(-t * 2.5)
	v += sin(TAU * 1046.5 * 2.76 * t) * exp(-t * 4.5) * 0.45
	v += sin(TAU * 1046.5 * 5.4 * t) * exp(-t * 8.0) * 0.2
	return v * attack * 0.45


func _sniff(t: float, _d: float) -> float:
	# 鼻をすする音を2回
	var v := 0.0
	for start in [0.0, 0.32]:
		var tt: float = t - start
		if tt > 0.0 and tt < 0.3:
			var x := tt / 0.3
			var cutoff := 900.0 + 2600.0 * x
			var n := _noise()
			v += (_lp(0, n, cutoff) - _lp(1, n, 500.0)) * sin(PI * x) * 1.3
	return v


func _click(t: float, _d: float) -> float:
	return (sin(TAU * 1800.0 * t) * 0.5 + _noise() * 0.3) * exp(-t * 260.0)


func _processor(t: float, _d: float) -> float:
	# 1秒でちょうど周期が合う周波数にして、ループのつなぎ目を目立たなくする
	var saw := fmod(t * 95.0, 1.0) * 2.0 - 1.0
	var motor := _lp(0, saw, 900.0) * 0.5 + sin(TAU * 190.0 * t) * 0.15
	var chop := _lp(1, _noise(), 2500.0) * (0.5 + 0.5 * sin(TAU * 12.0 * t)) * 0.3
	return (motor + chop) * (0.85 + 0.15 * sin(TAU * 3.0 * t))


func _ambience(t: float, _d: float) -> float:
	# 換気扇の低いゴーッという音 ＋ 冷蔵庫のうなり
	var rumble := _lp(0, _lp(1, _noise(), 300.0), 150.0) * 3.0
	var hum := sin(TAU * 50.0 * t) * 0.05 + sin(TAU * 100.0 * t) * 0.03
	return rumble + hum
