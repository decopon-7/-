# 厨房の部屋まわり（ゲームの手元＝作業台・まな板・ボウル・玉ねぎ以外の、背景の全部）を組み立てる。
#
# 舞台は、港町の小さな食堂の厨房。大将がひとりで切り盛りしていて、主人公は住み込みで朝の仕込みをする。
# 「海外から見たニッポン」（提灯・桜・鳥居・赤と黒の和柄）ではなく、日本の町の食堂に
# 本当にありそうなものだけで組み立てる：
#   - 壁は100角（10cm角）の白タイル。上の方は少し黄ばんだクリーム色の塗り壁
#   - アルミサッシの型板ガラスの窓と、外の面格子の影。窓辺には、水に挿した青ねぎの根っこ
#   - 壁付けのプロペラ換気扇（油で黄ばんだ枠と、引きひも）
#   - 業務用のガステーブルと寸胴鍋（カレーの仕込み中）、雪平鍋、オレンジのガス管、棚下の一斗缶
#   - ステンレスの業務用冷蔵庫と、マグネットで留めた仕入れのメモ
#   - 酒屋さんからもらった日めくりカレンダー（土曜は青、日曜は赤。六曜つき）と丸い掛け時計
#   - 「火の用心」の札、逆富士型の蛍光灯、床の排水溝のグレーチング
#   - 客席との境の紺の暖簾、その奥の客席の赤い丸椅子
#   - 漁師さんから届いた発泡スチロールの箱、白い長靴、青いポリバケツ
#   - 玉ねぎは産地の印刷が入った段ボール箱と、赤いネット袋
#   - 作業台の奥には菜箸立て、醤油の一升瓶、マスキングテープに手書きの「塩」「砂糖」
#
# 座標の目安：作業台の奥の壁の面が z = BACK_Z。プレイ中のカメラには壁の下の方（作業台から
# 20cmほど）しか映らないので、部屋全体はタイトル画面の引きのカメラで見せる。
extends Node3D

const TILE_SHADER := preload("res://shaders/tile.gdshader")
const STEEL_SHADER := preload("res://shaders/brushed_steel.gdshader")
const CLOTH_SHADER := preload("res://shaders/cloth.gdshader")
const GLASS_SHADER := preload("res://shaders/frosted_glass.gdshader")
const NET_SHADER := preload("res://shaders/net.gdshader")
const ONION_SHADER := preload("res://shaders/onion_whole.gdshader")
const FONT := preload("res://fonts/NotoSansJP-Bold.ttf")

const BACK_Z := -0.54      # 奥の壁の表面
const COUNTER_Y := 0.94    # 作業台の天板の上面
const ROOM_HALF_X := 2.9
const CEILING_Y := 2.45
const FRONT_Z := 2.9
const TILE_TOP := 1.62     # ここまでタイル、ここから上は塗り壁
const WINDOW := Rect2(-0.45, 1.3, 0.9, 0.65)    # 窓の開口（x, y, 幅, 高さ）
const DOORWAY := Rect2(1.3, 0.0, 0.75, 1.95)    # 客席へ抜ける出入り口

# 日めくりカレンダー：1日目を4月1日（火曜）とする。新年度・新生活の始まり
const START_WEEKDAY := 2   # 0=日曜
const MONTH_DAYS := [30, 31, 30, 31, 31, 30, 31, 30, 31, 31, 28, 31]  # 4月〜翌3月
const WEEKDAYS := ["日", "月", "火", "水", "木", "金", "土"]
const ROKUYO := ["先勝", "友引", "先負", "仏滅", "大安", "赤口"]

var rng: RandomNumberGenerator
var _fan: Node3D
var _noren: Array[Node3D] = []
var _second_hand: Node3D
var _cal_month: Label3D
var _cal_date: Label3D
var _cal_week: Label3D
var _cal_rokuyo: Label3D
var _time := 0.0


func build(crate_pos: Vector3, random: RandomNumberGenerator) -> void:
	rng = random
	_build_shell()
	_build_window()
	_build_stove_corner()
	_build_fridge()
	_build_wall_things()
	_build_doorway()
	_build_floor_things()
	_build_work_table()
	_build_counter_back()
	_build_onion_box(crate_pos)
	_build_lights()


func _process(delta: float) -> void:
	_time += delta
	if _fan:
		_fan.rotate_z(-delta * 9.0)
	for i in _noren.size():
		_noren[i].rotation.x = sin(_time * 0.8 + i * 1.3) * 0.025 + sin(_time * 0.37 + i) * 0.015
	if _second_hand:
		# 秒針はカチッ、カチッと1秒ずつ進む
		_second_hand.rotation.z = -TAU * float(int(Time.get_ticks_msec() / 1000.0) % 60) / 60.0


## 日めくりカレンダーを「その日」にめくる
func set_day(day: int) -> void:
	if _cal_date == null:
		return
	var d := maxi(day, 1) - 1
	var month_index := 0
	var date := d
	while date >= MONTH_DAYS[month_index % 12]:
		date -= MONTH_DAYS[month_index % 12]
		month_index += 1
	var month := (3 + month_index) % 12 + 1
	var weekday := (START_WEEKDAY + d) % 7
	var col := Color(0.12, 0.11, 0.1)
	if weekday == 0:
		col = Color(0.78, 0.12, 0.1)
	elif weekday == 6:
		col = Color(0.14, 0.3, 0.66)
	_cal_month.text = "%d月" % month
	_cal_date.text = str(date + 1)
	_cal_date.modulate = col
	_cal_week.text = "%s曜日" % WEEKDAYS[weekday]
	_cal_week.modulate = col
	_cal_rokuyo.text = ROKUYO[d % 6]


# ================================================================ 部屋の箱

func _build_shell() -> void:
	var tiles := ShaderMaterial.new()
	tiles.shader = TILE_SHADER
	tiles.set_shader_parameter("tile_color", Color(0.8, 0.79, 0.74))
	tiles.set_shader_parameter("grout_color", Color(0.64, 0.62, 0.58))
	tiles.set_shader_parameter("grout", 0.003)
	var paint := _mat(Color(0.82, 0.75, 0.6), 0.92)
	var floor_mat := _mat(Color(0.3, 0.3, 0.29), 0.5)
	var ceiling := _mat(Color(0.8, 0.79, 0.75), 0.95)

	# 奥の壁：窓と出入り口のところを抜いて、タイル（下）と塗り壁（上）を貼り分ける
	var t := 0.06
	var wz := BACK_Z - t * 0.5
	var wx0 := -ROOM_HALF_X
	var wx1 := ROOM_HALF_X
	var win_x0 := WINDOW.position.x
	var win_x1 := WINDOW.end.x
	var door_x0 := DOORWAY.position.x
	var door_x1 := DOORWAY.end.x
	for r in [
		[wx0, win_x0, 0.0, TILE_TOP, tiles], [win_x0, win_x1, 0.0, WINDOW.position.y, tiles],
		[win_x1, door_x0, 0.0, TILE_TOP, tiles], [door_x1, wx1, 0.0, TILE_TOP, tiles],
		[wx0, win_x0, TILE_TOP, CEILING_Y, paint], [win_x0, win_x1, WINDOW.end.y, CEILING_Y, paint],
		[win_x1, door_x0, TILE_TOP, CEILING_Y, paint], [door_x0, door_x1, DOORWAY.end.y, CEILING_Y, paint],
		[door_x1, wx1, TILE_TOP, CEILING_Y, paint],
	]:
		var w: float = r[1] - r[0]
		var h: float = r[3] - r[2]
		_box(Vector3(w, h, t), Vector3(r[0] + w * 0.5, r[2] + h * 0.5, wz), r[4])
	# タイルと塗り壁の境の見切り（細いステンレスの縁）
	var trim := _mat(Color(0.62, 0.62, 0.6), 0.4, 0.7)
	_box(Vector3(win_x0 - wx0, 0.012, 0.012), Vector3((wx0 + win_x0) * 0.5, TILE_TOP, BACK_Z + 0.004), trim)
	_box(Vector3(door_x0 - win_x1, 0.012, 0.012), Vector3((win_x1 + door_x0) * 0.5, TILE_TOP, BACK_Z + 0.004), trim)
	_box(Vector3(wx1 - door_x1, 0.012, 0.012), Vector3((door_x1 + wx1) * 0.5, TILE_TOP, BACK_Z + 0.004), trim)

	# 左右の壁・手前の壁（カメラの背中側）・床・天井
	var depth := FRONT_Z - BACK_Z
	var cz := (FRONT_Z + BACK_Z) * 0.5
	for side in [-1.0, 1.0]:
		_box(Vector3(t, TILE_TOP, depth), Vector3(side * ROOM_HALF_X, TILE_TOP * 0.5, cz), tiles)
		_box(Vector3(t, CEILING_Y - TILE_TOP, depth), Vector3(side * ROOM_HALF_X, (TILE_TOP + CEILING_Y) * 0.5, cz), paint)
	_box(Vector3(ROOM_HALF_X * 2.0, CEILING_Y, t), Vector3(0, CEILING_Y * 0.5, FRONT_Z), paint)
	_box(Vector3(ROOM_HALF_X * 2.0, 0.1, depth), Vector3(0, -0.05, cz), floor_mat)
	_box(Vector3(ROOM_HALF_X * 2.0, 0.04, depth), Vector3(0, CEILING_Y + 0.02, cz), ceiling)

	# 床の排水溝（作業台の手前を横切るステンレスのグレーチング）
	var grate := _mat(Color(0.55, 0.56, 0.56), 0.45, 0.75)
	var gutter := _mat(Color(0.08, 0.08, 0.08), 0.9)
	var gz := 0.78
	_box(Vector3(ROOM_HALF_X * 2.0 - 0.1, 0.004, 0.16), Vector3(0, 0.001, gz), gutter)
	_box(Vector3(ROOM_HALF_X * 2.0 - 0.1, 0.008, 0.012), Vector3(0, 0.004, gz - 0.08), grate)
	_box(Vector3(ROOM_HALF_X * 2.0 - 0.1, 0.008, 0.012), Vector3(0, 0.004, gz + 0.08), grate)
	var n := int((ROOM_HALF_X * 2.0 - 0.2) / 0.035)
	for i in n:
		_box(Vector3(0.006, 0.008, 0.15), Vector3(-ROOM_HALF_X + 0.1 + i * 0.035, 0.004, gz), grate)


## 作業台の奥の窓：アルミサッシの引き違い窓に、型板ガラス。外には面格子
func _build_window() -> void:
	var alu := _mat(Color(0.72, 0.72, 0.7), 0.35, 0.6)
	var x0 := WINDOW.position.x
	var x1 := WINDOW.end.x
	var y0 := WINDOW.position.y
	var y1 := WINDOW.end.y
	var w := WINDOW.size.x
	var cx := (x0 + x1) * 0.5
	var z := BACK_Z - 0.03
	# 外枠
	var f := 0.03
	_box(Vector3(w, f, 0.06), Vector3(cx, y0 + f * 0.5, z), alu)
	_box(Vector3(w, f, 0.06), Vector3(cx, y1 - f * 0.5, z), alu)
	_box(Vector3(f, y1 - y0, 0.06), Vector3(x0 + f * 0.5, (y0 + y1) * 0.5, z), alu)
	_box(Vector3(f, y1 - y0, 0.06), Vector3(x1 - f * 0.5, (y0 + y1) * 0.5, z), alu)
	# 2枚の障子（左は奥のレール、右は手前のレール。真ん中で少し重なる）
	var inner_h := (y1 - y0) - f * 2.0
	var sash_w := (w - f * 2.0) * 0.5 + 0.02
	for i in 2:
		var sx := x0 + f + sash_w * 0.5 + (w - f * 2.0 - sash_w) * float(i)
		var sz := z - 0.012 + 0.022 * float(i)
		var sf := 0.022
		_box(Vector3(sash_w, sf, 0.02), Vector3(sx, y0 + f + sf * 0.5, sz), alu)
		_box(Vector3(sash_w, sf, 0.02), Vector3(sx, y1 - f - sf * 0.5, sz), alu)
		_box(Vector3(sf, inner_h, 0.02), Vector3(sx - sash_w * 0.5 + sf * 0.5, (y0 + y1) * 0.5, sz), alu)
		_box(Vector3(sf, inner_h, 0.02), Vector3(sx + sash_w * 0.5 - sf * 0.5, (y0 + y1) * 0.5, sz), alu)
		var glass := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(sash_w - sf * 2.0, inner_h - sf * 2.0)
		glass.mesh = q
		var gm := ShaderMaterial.new()
		gm.shader = GLASS_SHADER
		gm.set_shader_parameter("bar_count", 3.5)
		glass.material_override = gm
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glass.position = Vector3(sx, (y0 + y1) * 0.5, sz)
		add_child(glass)
	# クレセント錠
	_box(Vector3(0.03, 0.012, 0.012), Vector3(cx, (y0 + y1) * 0.5, z + 0.025), _mat(Color(0.8, 0.8, 0.78), 0.3, 0.8))
	# 窓台（タイル張りの奥行きのある台）と、水を入れたコップに挿した青ねぎの根っこ
	var sill := _mat(Color(0.82, 0.81, 0.76), 0.3)
	_box(Vector3(w + 0.04, 0.02, 0.1), Vector3(cx, y0 - 0.01, BACK_Z + 0.02), sill)
	var cup_glass := _mat(Color(0.85, 0.92, 0.95, 0.35), 0.05)
	cup_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cup_pos := Vector3(x0 + 0.17, y0, BACK_Z + 0.03)
	_lathe_prop([Vector2(0, 0), Vector2(0.026, 0), Vector2(0.03, 0.09), Vector2(0, 0.09)], cup_glass, cup_pos)
	var water := _mat(Color(0.8, 0.9, 0.95, 0.25), 0.05)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var root_white := _mat(Color(0.92, 0.92, 0.84), 0.6)
	var leaf := _mat(Color(0.3, 0.55, 0.2), 0.6)
	for i in 5:
		var stalk := Node3D.new()
		stalk.position = cup_pos + Vector3(rng.randf_range(-0.012, 0.012), 0.01, rng.randf_range(-0.012, 0.012))
		stalk.rotation = Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		add_child(stalk)
		_cyl(0.004, 0.005, 0.07, Vector3(0, 0.035, 0), root_white, stalk)
		var h := rng.randf_range(0.06, 0.12)
		_cyl(0.0015, 0.0035, h, Vector3(0, 0.07 + h * 0.5, 0), leaf, stalk)


## 左奥：業務用のガステーブルと寸胴鍋（カレーの仕込み中）、壁付けの換気扇
func _build_stove_corner() -> void:
	var steel := _steel(Color(0.56, 0.56, 0.55))
	var iron := _mat(Color(0.1, 0.1, 0.1), 0.65, 0.4)
	var cx := -1.6
	var w := 0.75
	var d := 0.6
	var cz := BACK_Z + d * 0.5 + 0.02
	# 天板の箱と脚、下の棚
	_box(Vector3(w, 0.16, d), Vector3(cx, 0.72, cz), steel)
	_box(Vector3(w + 0.01, 0.012, d + 0.01), Vector3(cx, 0.806, cz), _mat(Color(0.2, 0.2, 0.2), 0.6, 0.5))
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			_box(Vector3(0.035, 0.64, 0.035), Vector3(cx + lx * (w * 0.5 - 0.03), 0.32, cz + lz * (d * 0.5 - 0.03)), steel)
	_box(Vector3(w - 0.02, 0.015, d - 0.04), Vector3(cx, 0.14, cz), steel)
	# つまみ
	for i in 2:
		var knob := _cyl(0.018, 0.018, 0.025, Vector3(cx - 0.17 + i * 0.34, 0.72, cz + d * 0.5 + 0.012), iron)
		knob.rotation.x = PI / 2
	# 五徳と火
	var flame := _mat(Color(0.25, 0.45, 1.0), 0.5)
	flame.emission_enabled = true
	flame.emission = Color(0.3, 0.5, 1.0)
	flame.emission_energy_multiplier = 3.0
	for i in 2:
		var bx := cx - 0.18 + i * 0.36
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.1
		tm.outer_radius = 0.115
		ring.mesh = tm
		ring.material_override = iron
		ring.position = Vector3(bx, 0.83, cz)
		add_child(ring)
		for k in 4:
			var spoke := _box(Vector3(0.012, 0.03, 0.06), Vector3(0, 0.0, 0), iron, ring)
			var a := TAU * k / 4.0 + PI / 4.0
			spoke.position = Vector3(cos(a) * 0.09, 0.0, sin(a) * 0.09)
			spoke.rotation.y = -a
		_cyl(0.045, 0.05, 0.02, Vector3(bx, 0.815, cz), iron)
		if i == 1:
			var fl := MeshInstance3D.new()
			var fm := TorusMesh.new()
			fm.inner_radius = 0.045
			fm.outer_radius = 0.055
			fl.mesh = fm
			fl.material_override = flame
			fl.position = Vector3(bx, 0.828, cz)
			add_child(fl)
	# 寸胴鍋（右の口）と中身のカレー、立ちのぼる湯気
	var pot_x := cx + 0.18
	var pot_r := 0.155
	var pot_h := 0.3
	var pot_steel := _mat(Color(0.74, 0.75, 0.77), 0.25, 0.85)
	_lathe_prop([
		Vector2(0, 0), Vector2(pot_r, 0), Vector2(pot_r, pot_h), Vector2(pot_r + 0.006, pot_h + 0.004),
		Vector2(pot_r - 0.004, pot_h), Vector2(pot_r - 0.004, 0.006), Vector2(0, 0.006),
	], pot_steel, Vector3(pot_x, 0.835, cz))
	for s in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.015, 0.025), Vector3(pot_x + s * (pot_r + 0.02), 0.835 + pot_h - 0.04, cz), pot_steel)
	_cyl(pot_r - 0.005, pot_r - 0.005, 0.004, Vector3(pot_x, 0.835 + pot_h - 0.05, cz), _mat(Color(0.42, 0.24, 0.08), 0.35))
	_add_steam(Vector3(pot_x, 0.835 + pot_h, cz))
	# 雪平鍋（左の口）。木の柄が手前に伸びる
	var pan_x := cx - 0.18
	var hammered := _mat(Color(0.8, 0.8, 0.8), 0.32, 0.85)
	_lathe_prop([
		Vector2(0, 0), Vector2(0.085, 0), Vector2(0.095, 0.075), Vector2(0.091, 0.075),
		Vector2(0.081, 0.005), Vector2(0, 0.005),
	], hammered, Vector3(pan_x, 0.835, cz))
	var handle := _cyl(0.011, 0.013, 0.17, Vector3(pan_x - 0.06, 0.88, cz + 0.17), _mat(Color(0.42, 0.28, 0.15), 0.6))
	handle.rotation = Vector3(PI / 2 - 0.25, -0.35, 0)
	# オレンジのガス管（壁の元栓からテーブルの裏へ）
	var hose := _mat(Color(0.95, 0.45, 0.12), 0.6)
	_box(Vector3(0.04, 0.05, 0.04), Vector3(cx + w * 0.5 + 0.05, 0.62, BACK_Z + 0.02), _mat(Color(0.75, 0.62, 0.2), 0.4, 0.8))
	var h1 := _cyl(0.009, 0.009, 0.2, Vector3(cx + w * 0.5 + 0.05, 0.52, BACK_Z + 0.04), hose)
	h1.rotation.z = 0.15
	var h2 := _cyl(0.009, 0.009, 0.14, Vector3(cx + w * 0.5 - 0.01, 0.43, BACK_Z + 0.06), hose)
	h2.rotation.z = PI / 2 - 0.3
	# 棚下の一斗缶（サラダ油）
	var can := _box(Vector3(0.24, 0.35, 0.24), Vector3(cx - 0.15, 0.15 + 0.008 + 0.175, cz), _mat(Color(0.7, 0.71, 0.7), 0.35, 0.85))
	_tape_label("サラダ油", Vector3(0, 0.05, 0.121), 0.026, can)

	# 壁付けのプロペラ換気扇（油で黄ばんだ枠、回る羽根、引きひも）
	var fan_y := 1.95
	var frame := _mat(Color(0.74, 0.7, 0.58), 0.75)
	var fz := BACK_Z + 0.03
	var fs := 0.42
	_box(Vector3(fs, 0.04, 0.06), Vector3(cx, fan_y + fs * 0.5 - 0.02, fz), frame)
	_box(Vector3(fs, 0.04, 0.06), Vector3(cx, fan_y - fs * 0.5 + 0.02, fz), frame)
	_box(Vector3(0.04, fs, 0.06), Vector3(cx - fs * 0.5 + 0.02, fan_y, fz), frame)
	_box(Vector3(0.04, fs, 0.06), Vector3(cx + fs * 0.5 - 0.02, fan_y, fz), frame)
	_box(Vector3(fs - 0.06, fs - 0.06, 0.01), Vector3(cx, fan_y, BACK_Z + 0.002), _mat(Color(0.06, 0.06, 0.05), 0.9))
	_fan = Node3D.new()
	_fan.position = Vector3(cx, fan_y, fz)
	add_child(_fan)
	var blade_mat := _mat(Color(0.7, 0.67, 0.56), 0.6)
	for k in 4:
		var b := _box(Vector3(0.055, 0.14, 0.006), Vector3(0.012, 0.085, 0), blade_mat)
		remove_child(b)
		var arm := Node3D.new()
		arm.rotation.z = TAU * k / 4.0
		_fan.add_child(arm)
		arm.add_child(b)
		b.rotation = Vector3(0, 0.45, 0.18)
	var hub := _cyl(0.035, 0.035, 0.03, Vector3.ZERO, frame, _fan)
	hub.rotation.x = PI / 2
	var string_mat := _mat(Color(0.9, 0.88, 0.8), 0.9)
	_cyl(0.0015, 0.0015, 0.32, Vector3(cx + fs * 0.5 - 0.03, fan_y - fs * 0.5 - 0.16, fz + 0.035), string_mat)
	_cyl(0.008, 0.008, 0.025, Vector3(cx + fs * 0.5 - 0.03, fan_y - fs * 0.5 - 0.33, fz + 0.035), string_mat)

	# 「火の用心」の札
	var plate := _box(Vector3(0.075, 0.24, 0.006), Vector3(-1.08, 1.86, BACK_Z + 0.003), _mat(Color(0.93, 0.91, 0.86), 0.8))
	_label("火\nの\n用\n心", Vector3(0, 0, 0.004), 0.042, Color(0.75, 0.1, 0.08), plate, 0.82)


## 左端：ステンレスの業務用冷蔵庫（4枚扉）と、仕入れのメモ
func _build_fridge() -> void:
	var w := 0.8
	var h := 1.9
	var d := 0.66
	var cx := -ROOM_HALF_X + w * 0.5 + 0.05
	var cz := BACK_Z + d * 0.5 + 0.02
	var body := _steel(Color(0.66, 0.66, 0.65))
	_box(Vector3(w, h - 0.08, d), Vector3(cx, 0.08 + (h - 0.08) * 0.5, cz), body)
	_box(Vector3(w - 0.04, 0.08, d - 0.06), Vector3(cx, 0.04, cz), _mat(Color(0.12, 0.12, 0.12), 0.8))
	var fz := cz + d * 0.5
	var seam := _mat(Color(0.18, 0.18, 0.18), 0.6)
	_box(Vector3(0.006, 1.55, 0.004), Vector3(cx, 0.08 + 0.78, fz + 0.001), seam)
	_box(Vector3(w, 0.006, 0.004), Vector3(cx, 0.08 + 0.78, fz + 0.001), seam)
	_box(Vector3(w, 0.006, 0.004), Vector3(cx, 1.64, fz + 0.001), seam)
	var handle := _mat(Color(0.8, 0.8, 0.8), 0.3, 0.85)
	for sx in [-1.0, 1.0]:
		for y in [0.62, 1.12]:
			_box(Vector3(0.02, 0.3, 0.03), Vector3(cx + sx * 0.06, y, fz + 0.02), handle)
	# 上の操作パネルと、温度表示
	var panel := _box(Vector3(0.12, 0.05, 0.004), Vector3(cx + 0.22, 1.76, fz + 0.002), _mat(Color(0.05, 0.06, 0.05), 0.4))
	var temp := _label("3.0℃", Vector3(0, 0, 0.003), 0.03, Color(0.45, 1.0, 0.55), panel, 1.0)
	temp.shaded = false
	# マグネットで留めた仕入れのメモ
	var paper := _mat(Color(0.95, 0.94, 0.88), 0.9)
	var memo := _box(Vector3(0.13, 0.17, 0.002), Vector3(cx - 0.2, 1.3, fz + 0.002), paper)
	memo.rotation.z = 0.04
	_label("玉ねぎ\n２箱\n火曜", Vector3(0, 0.01, 0.002), 0.03, Color(0.15, 0.15, 0.3), memo, 0.8)
	var magnet := _cyl(0.012, 0.012, 0.01, Vector3(0, 0.07, 0.005), _mat(Color(0.8, 0.2, 0.15), 0.4), memo)
	magnet.rotation.x = PI / 2
	var memo2 := _box(Vector3(0.1, 0.12, 0.002), Vector3(cx + 0.21, 1.42, fz + 0.002), paper)
	memo2.rotation.z = -0.06
	_label("米\n30kg", Vector3(0, 0.0, 0.002), 0.03, Color(0.15, 0.15, 0.3), memo2, 0.8)
	var magnet2 := _cyl(0.012, 0.012, 0.01, Vector3(0, 0.05, 0.005), _mat(Color(0.2, 0.4, 0.8), 0.4), memo2)
	magnet2.rotation.x = PI / 2


## 壁のもの：皿の棚、ラジオ、日めくりカレンダー、掛け時計、蛍光灯
func _build_wall_things() -> void:
	var steel := _mat(Color(0.65, 0.66, 0.66), 0.35, 0.75)
	var china := _mat(Color(0.93, 0.92, 0.88), 0.25)
	var blue_line := _mat(Color(0.16, 0.25, 0.55), 0.3)
	# 窓の左の棚：洋皿と丼
	var sy := 1.5
	_box(Vector3(0.6, 0.015, 0.26), Vector3(-0.8, sy, BACK_Z + 0.13), steel)
	for bx in [-1.02, -0.58]:
		_box(Vector3(0.015, 0.1, 0.2), Vector3(bx, sy - 0.05, BACK_Z + 0.1), steel)
	for i in 6:
		_lathe_prop([
			Vector2(0, 0), Vector2(0.07, 0), Vector2(0.115, 0.014), Vector2(0.112, 0.016),
			Vector2(0.068, 0.004), Vector2(0, 0.004),
		], china, Vector3(-0.95, sy + 0.008 + i * 0.016, BACK_Z + 0.13))
	for i in 3:
		var y := sy + 0.008 + i * 0.05
		_lathe_prop([
			Vector2(0, 0), Vector2(0.035, 0), Vector2(0.04, 0.008), Vector2(0.072, 0.06),
			Vector2(0.068, 0.062), Vector2(0.034, 0.012), Vector2(0, 0.012),
		], china, Vector3(-0.7, y, BACK_Z + 0.13))
		var rim := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.068
		tm.outer_radius = 0.073
		rim.mesh = tm
		rim.material_override = blue_line
		rim.position = Vector3(-0.7, y + 0.055, BACK_Z + 0.13)
		add_child(rim)

	# 窓の右の棚：ステンレスのバットと、古いラジオ
	_box(Vector3(0.6, 0.015, 0.26), Vector3(0.84, sy, BACK_Z + 0.13), steel)
	for bx in [0.6, 1.08]:
		_box(Vector3(0.015, 0.1, 0.2), Vector3(bx, sy - 0.05, BACK_Z + 0.1), steel)
	for i in 3:
		_box(Vector3(0.22, 0.02, 0.16), Vector3(0.7, sy + 0.018 + i * 0.022, BACK_Z + 0.12), _mat(Color(0.75, 0.76, 0.77), 0.3, 0.8))
	var radio := _box(Vector3(0.22, 0.13, 0.08), Vector3(0.98, sy + 0.073, BACK_Z + 0.12), _mat(Color(0.55, 0.38, 0.24), 0.5))
	_box(Vector3(0.09, 0.09, 0.004), Vector3(-0.05, 0, 0.041), _mat(Color(0.2, 0.18, 0.16), 0.9), radio)
	_box(Vector3(0.08, 0.025, 0.004), Vector3(0.055, 0.03, 0.041), _mat(Color(0.85, 0.8, 0.6), 0.4), radio)
	var dial := _cyl(0.014, 0.014, 0.012, Vector3(0.055, -0.025, 0.045), _mat(Color(0.85, 0.83, 0.78), 0.4), radio)
	dial.rotation.x = PI / 2
	var antenna := _cyl(0.002, 0.002, 0.3, Vector3(0.08, 0.2, 0), _mat(Color(0.85, 0.85, 0.85), 0.3, 0.9), radio)
	antenna.rotation.z = -0.5

	# 日めくりカレンダー（酒屋さんの名入り）
	var cal := Node3D.new()
	cal.position = Vector3(0.84, 1.88, BACK_Z + 0.004)
	add_child(cal)
	_box(Vector3(0.17, 0.27, 0.004), Vector3.ZERO, _mat(Color(0.6, 0.12, 0.1), 0.7), cal)
	_box(Vector3(0.145, 0.19, 0.012), Vector3(0, 0.02, 0.006), _mat(Color(0.96, 0.95, 0.92), 0.85), cal)
	_cal_month = _label("4月", Vector3(-0.045, 0.095, 0.013), 0.022, Color(0.15, 0.14, 0.12), cal, 0.8)
	_cal_rokuyo = _label("大安", Vector3(0.045, 0.095, 0.013), 0.018, Color(0.15, 0.14, 0.12), cal, 0.8)
	_cal_date = _label("1", Vector3(0, 0.025, 0.013), 0.1, Color(0.12, 0.11, 0.1), cal, 0.8)
	_cal_week = _label("火曜日", Vector3(0, -0.05, 0.013), 0.022, Color(0.12, 0.11, 0.1), cal, 0.8)
	_label("みなと酒店", Vector3(0, -0.108, 0.004), 0.02, Color(0.98, 0.92, 0.75), cal, 0.8)
	set_day(1)

	# 丸い掛け時計（出入り口の上）。朝の仕込みの時間、6時45分
	var clock := Node3D.new()
	clock.position = Vector3(DOORWAY.get_center().x, 2.2, BACK_Z + 0.02)
	add_child(clock)
	var rim_mesh := _cyl(0.135, 0.135, 0.035, Vector3.ZERO, _mat(Color(0.35, 0.22, 0.12), 0.5), clock)
	rim_mesh.rotation.x = PI / 2
	var face := _cyl(0.12, 0.12, 0.01, Vector3(0, 0, 0.015), _mat(Color(0.95, 0.94, 0.9), 0.4), clock)
	face.rotation.x = PI / 2
	var ink := _mat(Color(0.1, 0.1, 0.1), 0.5)
	for k in 12:
		var a := TAU * k / 12.0
		var tick := _box(Vector3(0.006 if k % 3 else 0.01, 0.02, 0.003), Vector3(sin(a) * 0.1, cos(a) * 0.1, 0.022), ink, clock)
		tick.rotation.z = -a
	_clock_hand(clock, 0.06, 0.008, -TAU * (6.75 / 12.0), ink, 0.024)
	_clock_hand(clock, 0.09, 0.005, -TAU * (45.0 / 60.0), ink, 0.026)
	_second_hand = _clock_hand(clock, 0.1, 0.002, 0.0, _mat(Color(0.8, 0.1, 0.08), 0.5), 0.028)

	# 逆富士型の蛍光灯（天井）
	for p in [Vector3(0, CEILING_Y, 0.05), Vector3(-1.75, CEILING_Y, 0.4), Vector3(1.6, CEILING_Y, 1.2)]:
		_fluorescent(p)


func _clock_hand(clock: Node3D, length: float, width: float, angle: float, material: Material, z: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position.z = z
	pivot.rotation.z = angle
	clock.add_child(pivot)
	_box(Vector3(width, length, 0.002), Vector3(0, length * 0.4, 0), material, pivot)
	return pivot


## 逆富士型の蛍光灯器具：天井側が広い台形の箱の下に、むき出しの直管が1本
func _fluorescent(pos: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := 0.64
	var top := 0.08
	var bot := 0.03
	var h := 0.07
	var pts := [Vector2(-top, 0), Vector2(top, 0), Vector2(bot, -h), Vector2(-bot, -h)]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 4]
		var v := [Vector3(-hl, a.y, a.x), Vector3(hl, a.y, a.x), Vector3(-hl, b.y, b.x), Vector3(hl, b.y, b.x)]
		for idx in [0, 2, 1, 1, 2, 3]:
			st.add_vertex(v[idx])
	for sx in [-hl, hl]:
		for idx in [[0, 1, 2], [0, 2, 3]]:
			for j in idx:
				var p: Vector2 = pts[j]
				st.add_vertex(Vector3(sx, p.y, p.x))
	st.generate_normals()
	var body := MeshInstance3D.new()
	body.mesh = st.commit()
	var m := _mat(Color(0.9, 0.9, 0.88), 0.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	body.material_override = m
	body.position = pos
	add_child(body)
	var tube := _cyl(0.013, 0.013, 1.2, pos + Vector3(0, -h - 0.016, 0), _emissive(Color(1.0, 0.95, 0.85), 2.2))
	tube.rotation.z = PI / 2
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 右奥：客席へ抜ける出入り口と、紺の暖簾。暖簾のすきまから客席がのぞく
func _build_doorway() -> void:
	var wood := _mat(Color(0.42, 0.29, 0.17), 0.6)
	var x0 := DOORWAY.position.x
	var x1 := DOORWAY.end.x
	var top := DOORWAY.end.y
	var cx := DOORWAY.get_center().x
	_box(Vector3(0.05, top, 0.08), Vector3(x0 - 0.025, top * 0.5, BACK_Z - 0.02), wood)
	_box(Vector3(0.05, top, 0.08), Vector3(x1 + 0.025, top * 0.5, BACK_Z - 0.02), wood)
	_box(Vector3(x1 - x0 + 0.1, 0.06, 0.08), Vector3(cx, top + 0.03, BACK_Z - 0.02), wood)
	# 暖簾：竹の棒に、紺の無地の布を3枚
	var rod := _cyl(0.01, 0.01, x1 - x0 + 0.06, Vector3(cx, top - 0.04, BACK_Z + 0.03), _mat(Color(0.7, 0.58, 0.36), 0.5))
	rod.rotation.z = PI / 2
	var cloth := ShaderMaterial.new()
	cloth.shader = CLOTH_SHADER
	cloth.set_shader_parameter("cloth_color", Color(0.14, 0.19, 0.36))
	cloth.set_shader_parameter("stripe_color", Color(0.14, 0.19, 0.36))
	var pw := (x1 - x0) / 3.0 - 0.008
	for i in 3:
		var pivot := Node3D.new()
		pivot.position = Vector3(x0 + (x1 - x0) * (float(i) + 0.5) / 3.0, top - 0.04, BACK_Z + 0.035)
		add_child(pivot)
		_box(Vector3(pw, 0.86, 0.004), Vector3(0, -0.43, 0), cloth, pivot)
		_noren.append(pivot)

	# 客席（奥の小部屋）：床・壁・テーブル・赤い丸椅子
	var room_z0 := BACK_Z - 0.06
	var room_z1 := -2.3
	var rcx := cx
	var rw := 1.6
	var rd := room_z0 - room_z1
	var rcz := (room_z0 + room_z1) * 0.5
	_box(Vector3(rw, 0.1, rd), Vector3(rcx, -0.05, rcz), _mat(Color(0.42, 0.33, 0.25), 0.7))
	var cream := _mat(Color(0.86, 0.8, 0.66), 0.9)
	var wainscot := _mat(Color(0.5, 0.34, 0.2), 0.6)
	_box(Vector3(rw, CEILING_Y, 0.06), Vector3(rcx, CEILING_Y * 0.5, room_z1), cream)
	_box(Vector3(rw, 0.9, 0.02), Vector3(rcx, 0.45, room_z1 + 0.04), wainscot)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.06, CEILING_Y, rd), Vector3(rcx + s * rw * 0.5, CEILING_Y * 0.5, rcz), cream)
	_box(Vector3(rw, 0.04, rd), Vector3(rcx, CEILING_Y + 0.02, rcz), cream)
	var table_wood := _mat(Color(0.55, 0.4, 0.26), 0.45)
	var tz := room_z1 + 0.55
	_box(Vector3(0.9, 0.035, 0.6), Vector3(rcx, 0.7, tz), table_wood)
	_box(Vector3(0.06, 0.68, 0.06), Vector3(rcx, 0.34, tz), _mat(Color(0.15, 0.15, 0.15), 0.5, 0.6))
	_lathe_prop([Vector2(0, 0), Vector2(0.025, 0), Vector2(0.025, 0.08), Vector2(0.01, 0.11), Vector2(0, 0.11)],
			_mat(Color(0.25, 0.12, 0.05), 0.1), Vector3(rcx + 0.2, 0.7175, tz))
	var vinyl := _mat(Color(0.72, 0.12, 0.1), 0.35)
	var chrome := _mat(Color(0.8, 0.8, 0.8), 0.25, 0.9)
	for sx in [-0.3, 0.3]:
		var p := Vector3(rcx + sx, 0.0, tz + 0.5)
		_cyl(0.16, 0.16, 0.07, p + Vector3(0, 0.47, 0), vinyl)
		_cyl(0.02, 0.02, 0.44, p + Vector3(0, 0.22, 0), chrome)
		_cyl(0.14, 0.15, 0.015, p + Vector3(0, 0.008, 0), chrome)


## 床に置いてあるもの：漁師さんからの発泡スチロール箱、白い長靴、青いポリバケツ、玉ねぎのネット
func _build_floor_things() -> void:
	# 発泡スチロールの箱。マジックで「さば」
	var foam := _mat(Color(0.95, 0.95, 0.93), 0.95)
	var box := _box(Vector3(0.52, 0.24, 0.34), Vector3(2.4, 0.12, -0.2), foam)
	var lid := _box(Vector3(0.54, 0.04, 0.36), Vector3(2.39, 0.26, -0.19), foam)
	lid.rotation.y = 0.05
	_label("さば", Vector3(-0.08, 0.02, 0.171), 0.09, Color(0.08, 0.08, 0.1), box, 0.95)
	_label("港", Vector3(0.15, 0.02, 0.171), 0.06, Color(0.08, 0.08, 0.1), box, 0.95)
	# 白い長靴
	var rubber := _mat(Color(0.93, 0.93, 0.9), 0.4)
	for i in 2:
		var boot := Node3D.new()
		boot.position = Vector3(2.35 + i * 0.16, 0, 0.45 + i * 0.03)
		boot.rotation.y = -0.2 + i * 0.15
		add_child(boot)
		_cyl(0.06, 0.065, 0.36, Vector3(0, 0.18, 0), rubber, boot)
		_box(Vector3(0.1, 0.07, 0.24), Vector3(0, 0.035, 0.06), rubber, boot)
	# 青いポリバケツ（ふた付き）
	var poly := _mat(Color(0.15, 0.38, 0.72), 0.45)
	_lathe_prop([
		Vector2(0, 0), Vector2(0.17, 0), Vector2(0.2, 0.46), Vector2(0, 0.46),
	], poly, Vector3(-2.2, 0, 0.75))
	_lathe_prop([
		Vector2(0, 0.46), Vector2(0.215, 0.46), Vector2(0.215, 0.49), Vector2(0.05, 0.5),
		Vector2(0.05, 0.53), Vector2(0, 0.53),
	], poly, Vector3(-2.2, 0, 0.75))
	# 赤いネット袋に入った玉ねぎ（作業台の右下）
	var bag := Node3D.new()
	bag.position = Vector3(1.3, 0, 0.62)
	bag.rotation.y = 0.4
	add_child(bag)
	for i in 9:
		var o := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.045
		sphere.height = 0.075
		o.mesh = sphere
		var m := ShaderMaterial.new()
		m.shader = ONION_SHADER
		m.set_shader_parameter("base_color", Color(0.8, 0.53, 0.24).lightened(rng.randf_range(-0.1, 0.1)))
		m.set_shader_parameter("seed", rng.randf_range(0.0, 20.0))
		o.material_override = m
		var layer := floorf(i / 4.0)
		o.position = Vector3(rng.randf_range(-0.07, 0.07), 0.04 + layer * 0.065, rng.randf_range(-0.05, 0.05))
		o.rotation = Vector3(rng.randf_range(-0.8, 0.8), rng.randf(), rng.randf_range(-0.8, 0.8))
		bag.add_child(o)
	var net := MeshInstance3D.new()
	var nm := SphereMesh.new()
	nm.radius = 0.14
	nm.height = 0.3
	net.mesh = nm
	var net_mat := ShaderMaterial.new()
	net_mat.shader = NET_SHADER
	net.material_override = net_mat
	net.position.y = 0.13
	net.scale = Vector3(0.95, 0.85, 0.75)
	bag.add_child(net)
	_cyl(0.012, 0.03, 0.06, Vector3(0, 0.28, 0), _mat(Color(0.8, 0.16, 0.08), 0.7), bag)


## 作業台の脚と下の棚（天板は main.gd 側）。業務用のステンレス作業台で、
## 下の棚にはザルの重ね置き、予備の寸胴、玉ねぎの段ボールのストック
func _build_work_table() -> void:
	var steel := _steel(Color(0.5, 0.5, 0.5))
	var w := 2.2
	var d := 0.9
	var top_under := COUNTER_Y - 0.05
	_box(Vector3(w, 0.08, 0.02), Vector3(0, top_under - 0.04, d * 0.5 - 0.01), steel)
	for lx in [-1.0, 0.0, 1.0]:
		for lz in [-1.0, 1.0]:
			_box(Vector3(0.04, top_under, 0.04), Vector3(lx * (w * 0.5 - 0.03), top_under * 0.5, lz * (d * 0.5 - 0.03)), steel)
			_cyl(0.022, 0.026, 0.02, Vector3(lx * (w * 0.5 - 0.03), 0.01, lz * (d * 0.5 - 0.03)), _mat(Color(0.15, 0.15, 0.15), 0.6))
	_box(Vector3(w - 0.04, 0.02, d - 0.06), Vector3(0, 0.2, 0), steel)
	# ステンレスのザル（重ねて伏せてある）
	var mesh_steel := _mat(Color(0.7, 0.71, 0.72), 0.4, 0.8)
	for i in 3:
		_lathe_prop([
			Vector2(0, 0.09), Vector2(0.06, 0.088), Vector2(0.13, 0.04), Vector2(0.145, 0.0),
			Vector2(0.14, 0.0), Vector2(0.125, 0.038), Vector2(0.058, 0.082), Vector2(0, 0.084),
		], mesh_steel, Vector3(-0.72, 0.21 + i * 0.022, 0.05))
	# 予備の寸胴
	_lathe_prop([
		Vector2(0, 0), Vector2(0.14, 0), Vector2(0.14, 0.26), Vector2(0.145, 0.264),
		Vector2(0.136, 0.26), Vector2(0.136, 0.006), Vector2(0, 0.006),
	], _mat(Color(0.66, 0.67, 0.69), 0.3, 0.85), Vector3(-0.25, 0.21, -0.05))
	# 玉ねぎの段ボールのストック（閉じたまま2箱）
	var kraft := _mat(Color(0.55, 0.4, 0.24), 0.95)
	for i in 2:
		var b := _box(Vector3(0.42, 0.2, 0.4), Vector3(0.55 + i * 0.03, 0.31 + i * 0.2, 0.0), kraft)
		b.rotation.y = 0.04 - i * 0.07
		_box(Vector3(0.43, 0.004, 0.06), Vector3(0, 0.1, 0), _mat(Color(0.75, 0.65, 0.45), 0.6), b)
		_label("北海道産 たまねぎ", Vector3(-0.04, 0.0, 0.201), 0.03, Color(0.16, 0.42, 0.22), b, 0.9)


## 作業台の奥（プレイ中の画面の上の方に映るところ）：菜箸立て、醤油の一升瓶、
## 手書きのテープを貼った調味料の容器、保存容器、布巾、玉ねぎの薄皮のくず
func _build_counter_back() -> void:
	var z := BACK_Z + 0.12
	var y := COUNTER_Y
	var steel := _mat(Color(0.72, 0.73, 0.74), 0.3, 0.8)
	var bamboo := _mat(Color(0.8, 0.68, 0.45), 0.6)

	# 左：ステンレスの菜箸立てに、菜箸・おたま・木べら
	var holder := _lathe_prop([
		Vector2(0, 0), Vector2(0.048, 0), Vector2(0.05, 0.15), Vector2(0.046, 0.15),
		Vector2(0.044, 0.006), Vector2(0, 0.006),
	], steel, Vector3(-0.95, y, z))
	for spec in [[-0.1, 0.06, 0.34], [-0.06, 0.1, 0.34], [0.12, -0.04, 0.33], [0.15, 0.0, 0.33]]:
		var stick := _cyl(0.0022, 0.0035, spec[2], Vector3(0, spec[2] * 0.5, 0), bamboo)
		remove_child(stick)
		var pivot := Node3D.new()
		pivot.position = Vector3(spec[0] * 0.15, 0.01, spec[1] * 0.15)
		pivot.rotation = Vector3(spec[1], 0, spec[0])
		holder.add_child(pivot)
		pivot.add_child(stick)
	var ladle := Node3D.new()
	ladle.position = Vector3(0.01, 0.01, -0.01)
	ladle.rotation = Vector3(-0.12, 0, -0.22)
	holder.add_child(ladle)
	_cyl(0.004, 0.004, 0.3, Vector3(0, 0.15, 0), steel, ladle)
	var bowl := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.035
	bm.height = 0.035
	bm.is_hemisphere = true
	bowl.mesh = bm
	bowl.material_override = steel
	bowl.position = Vector3(0, 0.31, 0.03)
	bowl.rotation.x = PI * 0.5
	ladle.add_child(bowl)
	var spatula := Node3D.new()
	spatula.position = Vector3(-0.012, 0.01, 0.012)
	spatula.rotation = Vector3(0.18, 0, 0.12)
	holder.add_child(spatula)
	var spoon_wood := _mat(Color(0.66, 0.5, 0.32), 0.6)
	_cyl(0.006, 0.007, 0.24, Vector3(0, 0.12, 0), spoon_wood, spatula)
	_box(Vector3(0.05, 0.075, 0.007), Vector3(0, 0.27, 0), spoon_wood, spatula)

	# 醤油の一升瓶
	var bottle_glass := _mat(Color(0.16, 0.08, 0.03), 0.06)
	bottle_glass.metallic_specular = 0.9
	var bottle := _lathe_prop([
		Vector2(0, 0), Vector2(0.05, 0), Vector2(0.053, 0.006), Vector2(0.053, 0.27),
		Vector2(0.045, 0.3), Vector2(0.02, 0.34), Vector2(0.016, 0.38), Vector2(0.018, 0.39),
		Vector2(0.016, 0.4), Vector2(0, 0.4),
	], bottle_glass, Vector3(-0.8, y, z - 0.02))
	var label_paper := _box(Vector3(0.07, 0.11, 0.002), Vector3(0, 0.1, 0.0535), _mat(Color(0.95, 0.92, 0.8), 0.8), bottle)
	_box(Vector3(0.07, 0.014, 0.0025), Vector3(0, 0.048, 0.0002), _mat(Color(0.7, 0.12, 0.08), 0.6), label_paper)
	_label("濃口\n醤油", Vector3(0, -0.006, 0.0016), 0.024, Color(0.1, 0.08, 0.06), label_paper, 0.8)
	_cyl(0.019, 0.019, 0.022, Vector3(0, 0.401, 0), _mat(Color(0.85, 0.75, 0.3), 0.4, 0.6), bottle)

	# マスキングテープに手書きの調味料入れ
	var white_pot := _mat(Color(0.94, 0.93, 0.9), 0.35)
	var lid_white := _mat(Color(0.9, 0.9, 0.88), 0.4)
	var salt := _jar(Vector3(-0.66, y, z + 0.01), 0.04, 0.085, white_pot, lid_white)
	_tape_label("塩", Vector3(0, 0.05, 0.041), 0.02, salt)
	var sugar := _jar(Vector3(0.42, y, z), 0.04, 0.1, white_pot, lid_white)
	_tape_label("砂糖", Vector3(0, 0.06, 0.041), 0.018, sugar)
	var tin := _jar(Vector3(0.52, y, z + 0.015), 0.027, 0.08, _mat(Color(0.75, 0.76, 0.77), 0.3, 0.8), _mat(Color(0.7, 0.71, 0.72), 0.3, 0.8))
	_tape_label("こしょう", Vector3(0, 0.045, 0.028), 0.011, tin)
	# 四角い保存容器（青いふた）を2段重ね。だしと、刻みねぎ
	var tub := _mat(Color(0.92, 0.92, 0.9, 0.85), 0.25)
	tub.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var blue_lid := _mat(Color(0.2, 0.42, 0.75), 0.4)
	for i in 2:
		var by := y + i * 0.075
		var b := _box(Vector3(0.15, 0.062, 0.11), Vector3(0.94, by + 0.031, z), tub)
		_box(Vector3(0.156, 0.012, 0.116), Vector3(0.94, by + 0.068, z), blue_lid)
		_tape_label("だし" if i == 0 else "ねぎ", Vector3(0, 0.0, 0.056), 0.016, b)

	# 手前左：たたんだ布巾（白に、紺の縁取り）
	var towel := ShaderMaterial.new()
	towel.shader = CLOTH_SHADER
	towel.set_shader_parameter("cloth_color", Color(0.9, 0.89, 0.85))
	towel.set_shader_parameter("stripe_color", Color(0.2, 0.28, 0.5))
	var cloth := _box(Vector3(0.2, 0.014, 0.13), Vector3(-0.58, y + 0.007, 0.33), towel)
	cloth.rotation.y = 0.18

	# 段ボールのまわりに落ちた、玉ねぎの薄皮のくず
	var skin_mat := _mat(Color(0.5, 0.3, 0.14), 0.9)
	skin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 9:
		var flake := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(rng.randf_range(0.01, 0.022), rng.randf_range(0.006, 0.014))
		flake.mesh = q
		flake.material_override = skin_mat
		flake.position = Vector3(rng.randf_range(0.3, 0.9), y + 0.002, rng.randf_range(-0.38, 0.24))
		flake.rotation = Vector3(-PI / 2 + rng.randf_range(-0.25, 0.25), rng.randf_range(-PI, PI), rng.randf_range(-0.2, 0.2))
		add_child(flake)


## 玉ねぎの段ボール箱（産地の印刷入り）。手前と左のふたは切り取ってあり、奥と右のふたが外に開いている
func _build_onion_box(pos: Vector3) -> void:
	var kraft := _mat(Color(0.55, 0.4, 0.24), 0.95)
	var size := Vector3(0.42, 0.14, 0.4)
	var t := 0.006
	var c := Vector3(pos.x, COUNTER_Y + size.y * 0.5, pos.z)
	_box(Vector3(size.x, t, size.z), c + Vector3(0, -size.y * 0.5 + t * 0.5, 0), kraft)
	var front := _box(Vector3(size.x, size.y, t), c + Vector3(0, 0, size.z * 0.5), kraft)
	_box(Vector3(size.x, size.y, t), c + Vector3(0, 0, -size.z * 0.5), kraft)
	_box(Vector3(t, size.y, size.z), c + Vector3(size.x * 0.5, 0, 0), kraft)
	_box(Vector3(t, size.y, size.z), c + Vector3(-size.x * 0.5, 0, 0), kraft)
	var top := c.y + size.y * 0.5
	var back_flap := Node3D.new()
	back_flap.position = Vector3(c.x, top, c.z - size.z * 0.5)
	back_flap.rotation.x = -1.95
	add_child(back_flap)
	_box(Vector3(size.x - 0.01, 0.12, t), Vector3(0, 0.06, 0), kraft, back_flap)
	var right_flap := Node3D.new()
	right_flap.position = Vector3(c.x + size.x * 0.5, top, c.z)
	right_flap.rotation.z = -2.0
	add_child(right_flap)
	_box(Vector3(t, 0.2, size.z - 0.01), Vector3(0, 0.1, 0), kraft, right_flap)
	# 印刷：緑の文字で産地と品名、赤い枠に規格
	var green := Color(0.16, 0.42, 0.22)
	_label("北海道産 たまねぎ", Vector3(-0.04, 0.012, t * 0.5 + 0.001), 0.032, green, front, 0.9)
	_label("10kg", Vector3(-0.04, -0.035, t * 0.5 + 0.001), 0.022, green, front, 0.9)
	var mark := _box(Vector3(0.05, 0.05, 0.001), Vector3(0.155, 0.0, t * 0.5 + 0.0005), _mat(Color(0.75, 0.15, 0.1), 0.9), front)
	_box(Vector3(0.04, 0.04, 0.001), Vector3(0, 0, 0.0004), kraft, mark)
	_label("L", Vector3(0, 0, 0.0012), 0.03, Color(0.75, 0.15, 0.1), mark, 0.9)


## 部屋の明かり：窓から入る朝の光、客席からもれる電球色、奥の蛍光灯
func _build_lights() -> void:
	var sun := SpotLight3D.new()
	add_child(sun)
	sun.look_at_from_position(Vector3(-0.1, 2.2, BACK_Z - 1.1), Vector3(0.0, 0.6, 1.4))
	sun.spot_angle = 32.0
	sun.spot_range = 5.0
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	var dining := OmniLight3D.new()
	dining.position = Vector3(DOORWAY.get_center().x, 1.9, -1.5)
	dining.omni_range = 3.0
	dining.light_color = Color(1.0, 0.75, 0.45)
	dining.light_energy = 1.2
	add_child(dining)
	for p in [Vector3(-1.75, 2.25, 0.4), Vector3(1.6, 2.25, 1.2)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 2.6
		l.omni_attenuation = 1.4
		l.light_color = Color(1.0, 0.94, 0.84)
		l.light_energy = 0.55
		add_child(l)


# ================================================================ 湯気

func _add_steam(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 14
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.06
	p.initial_velocity_max = 0.12
	p.gravity = Vector3(0.01, 0.03, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.2))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.25, Color(1, 1, 1, 0.22))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	m.albedo_texture = soft
	quad.material = m
	p.mesh = quad
	add_child(p)


# ================================================================ ヘルパー

func _mat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _steel(base: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STEEL_SHADER
	m.set_shader_parameter("base_color", base)
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _box(size: Vector3, pos: Vector3, material: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


func _cyl(top_r: float, bottom_r: float, height: float, pos: Vector3, material: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = 24
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


## 文字（印刷・手書き・表示など）。height は1文字ぶんの高さ（m）
func _label(text: String, pos: Vector3, height: float, color: Color, parent: Node, alpha_strength := 1.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = 64
	l.pixel_size = height / 64.0
	l.modulate = Color(color, alpha_strength)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.line_spacing = -18.0
	l.position = pos
	parent.add_child(l)
	return l


## マスキングテープに油性ペンで書いたラベル
func _tape_label(text: String, pos: Vector3, height: float, parent: Node) -> void:
	var w := height * (text.length() + 0.8)
	var tape := _box(Vector3(w, height * 1.5, 0.0008), pos, _mat(Color(0.93, 0.87, 0.68), 0.85), parent)
	_label(text, Vector3(0, 0, 0.0006), height, Color(0.08, 0.08, 0.1), tape, 0.95)


func _lathe_prop(path: Array, material: Material, pos: Vector3, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _lathe(path, 32)
	mi.material_override = material
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


## ふた付きの容器
func _jar(pos: Vector3, radius: float, height: float, body: Material, lid: Material) -> MeshInstance3D:
	var jar := _lathe_prop([
		Vector2(0, 0), Vector2(radius * 0.92, 0), Vector2(radius, radius * 0.15),
		Vector2(radius, height * 0.9), Vector2(radius * 0.86, height), Vector2(0, height),
	], body, pos)
	_lathe_prop([
		Vector2(0, height - 0.002), Vector2(radius * 0.92, height - 0.002), Vector2(radius * 0.92, height + 0.016),
		Vector2(radius * 0.8, height + 0.02), Vector2(0, height + 0.02),
	], lid, Vector3.ZERO, jar)
	return jar


## 断面の輪郭（半径, 高さ）を軸のまわりに回転させたメッシュ
func _lathe(path: Array, segments: int) -> ArrayMesh:
	var normals: Array[Vector2] = []
	for i in path.size():
		var a: Vector2 = path[maxi(i - 1, 0)]
		var b: Vector2 = path[mini(i + 1, path.size() - 1)]
		var tangent := (b - a).normalized()
		normals.append(Vector2(tangent.y, -tangent.x))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in path.size() - 1:
		for k in segments:
			var a0 := TAU * float(k) / segments
			var a1 := TAU * float(k + 1) / segments
			var v := [[i, a0], [i, a1], [i + 1, a0], [i + 1, a1]]
			var pos: Array[Vector3] = []
			var nrm: Array[Vector3] = []
			for e in v:
				var p: Vector2 = path[e[0]]
				var n: Vector2 = normals[e[0]]
				var ang: float = e[1]
				pos.append(Vector3(p.x * cos(ang), p.y, p.x * sin(ang)))
				nrm.append(Vector3(n.x * cos(ang), n.y, n.x * sin(ang)))
			for tri in [[0, 1, 2], [1, 3, 2]]:
				for idx in tri:
					st.set_normal(nrm[idx])
					st.add_vertex(pos[idx])
	return st.commit()
