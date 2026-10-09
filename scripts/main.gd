# ゲーム本体。洋食屋の仕込み場の3D空間を組み立て、1日の仕込みループを回す。
extends Node3D

enum State { TITLE, PLAYING, DAY_END, PAUSED }

const BOARD_TOP := 0.965
const WORK_POS := Vector3(0.0, BOARD_TOP, 0.04)
const CRATE_POS := Vector3(0.6, 1.0, -0.12)
const BOWL_POS := Vector3(-0.56, 0.94, -0.16)
const PROCESSOR_POS := Vector3(-0.3, 0.94, -0.38)
const GOGGLES_POS := Vector3(0.22, 0.941, -0.3)
const KNIFE_LIFT := 0.09
const KNIFE_X_LIMIT := 0.26
const ControlsScript := preload("res://scripts/controls.gd")
const CRATE_ONION_SHADER := preload("res://shaders/onion_whole.gdshader")
const WOOD_SHADER := preload("res://shaders/wood.gdshader")
const STEEL_SHADER := preload("res://shaders/brushed_steel.gdshader")
const KitchenScript := preload("res://scripts/kitchen.gd")
# カメラ：プレイ中は作業台を見下ろす。タイトル画面では一歩引いて、厨房全体を見せる
const WORK_CAM_POS := Vector3(0, 1.5, 0.52)
const WORK_CAM_LOOK := Vector3(0, 0.965, -0.01)
const TITLE_CAM_POS := Vector3(0.15, 1.6, 2.35)
const TITLE_CAM_LOOK := Vector3(-0.15, 1.18, -0.54)
const CAM_MOVE_TIME := 1.4
## ボウルに溜まる、みじん切りのかけら（見た目用）の最大個数と、満タン時の散らばり半径
const BOWL_CHUNK_COUNT := 70
const BOWL_CHUNK_RADIUS := 0.16
## ボウルの寸法（高さ・壁の厚み・内側の底の高さ）
const BOWL_HEIGHT := 0.15
const BOWL_WALL := 0.007
const BOWL_FLOOR_Y := 0.01

## 1日の最低量。これを刻むまでは「今日はここまで」で終われない
## （時間制限やノルマの罰則ではなく、1日を早送りしすぎてストーリーを消費し尽くさないための下限）
const MIN_GRAMS_PER_DAY := 200

## 涙：1回切るごとに増える量（工程1・2 / 工程3）と、1秒あたりに引く量
const TEARS_PER_CUT := 0.05
const TEARS_PER_CHOP := 0.012
const TEARS_DECAY := 0.045
const TEARS_STUN_TIME := 2.2

## 手応え：カメラの揺れ量（trauma。0〜1で蓄積し、揺れ幅は trauma^2）
const SHAKE_CHOP := 0.13
const SHAKE_MINCE := 0.05
const SHAKE_TEARS_MAX := 0.22
const SHAKE_ORDER_DONE := 0.3
## 1品完成した瞬間、ごく短く時間の流れを遅くする「間」
const HIT_STOP_DURATION := 0.07
const HIT_STOP_SCALE := 0.15

## ごくたまに出てくる「幸運の玉ねぎ」（見た目が金色になり、報酬が増える驚きの演出）
const GOLDEN_CHANCE := 0.04
const GOLDEN_BONUS := 5.0
const CHIP_COLOR := Color(0.95, 0.94, 0.85)
const CHIP_COLOR_GOLDEN := Color(1.0, 0.82, 0.2)

var state := State.TITLE
var grams_today := 0
var earned_today := 0
var processor_timer := 0.0
var tears := 0.0
var stun := 0.0

var rng := RandomNumberGenerator.new()
var camera: Camera3D
var ui: GameUI
var onion: Onion
var knife: Node3D
var chips: CPUParticles3D
var processor: Node3D
var processor_visual: Node3D
var processor_blade: Node3D
var goggles: Node3D
var goggles_visual: Node3D
var bowl_fill: MeshInstance3D
var bowl_chunks: MultiMeshInstance3D
var gap_markers: Array[MeshInstance3D] = []
var tear_overlay: ColorRect
## これから来る注文（先頭が次の玉ねぎ）
var order_queue: Array[String] = []
var ticket_number := 0

var _knife_x := 0.0
## true なら包丁はスティック・十字キー・A/Dキーで動かす（false ならマウス）
var _axis_mode := false
var _goal_notified := false
var _chop_t := 1.0
var _cooldown := 0.0
var _holding := false
var _chips_time := 0.0
var _gap_mat: StandardMaterial3D
var _clean_view := false

## 手応え（カメラの微振動・包丁のスクワッシュ・きらめき演出）
var knife_visual: Node3D
var sparkle: CPUParticles3D
var camera_trauma := 0.0
var _camera_base_transform: Transform3D
var kitchen: Node3D
# カメラの移動（タイトルの引きの画 ⇔ 作業台）。_cam_t が 1 になったら移動完了
var _cam_from: Transform3D
var _cam_goal: Transform3D
var _cam_t := 1.0
var _cam_time := 0.0
var _hitstop_id := 0


func _ready() -> void:
	ControlsScript.register()
	rng.randomize()
	_build_environment()
	_build_kitchen()
	_build_knife()
	_build_processor()
	_build_goggles()
	_build_tear_overlay()

	ui = GameUI.new()
	ui.layer = 2
	add_child(ui)
	ui.continue_pressed.connect(_on_continue)
	ui.new_game_pressed.connect(_on_new_game)
	ui.start_day_pressed.connect(_start_day)
	ui.resume_pressed.connect(func(): _set_state(State.PLAYING))
	ui.to_title_pressed.connect(_on_to_title)
	ui.end_shift_pressed.connect(_end_day)
	ui.upgrade_bought.connect(_on_upgrade_bought)
	GameState.achievement_unlocked.connect(_on_achievement_unlocked)
	GameState.skin_tier_changed.connect(_on_skin_tier_changed)

	_refill_orders()
	_spawn_onion(false)
	_set_state(State.TITLE)
	set_camera_now(_title_camera())  # 起動時は動かさず、最初から引きの画で

	var dev := preload("res://scripts/dev_screenshot.gd")
	if dev.requested():
		add_child(dev.new())


# ================================================================ 仕込みループ

func _set_state(s: State) -> void:
	state = s
	_holding = false
	_update_cursor()
	Sfx.set_music_muffled(s != State.PLAYING)
	if s != State.PLAYING:
		Sfx.set_music_tempo(1.0)
	match s:
		State.TITLE:
			ui.refresh_texts()
			ui.show_only(ui.title_screen)
			kitchen.set_day(GameState.day)
			_move_camera(_title_camera())
		State.PLAYING:
			ui.show_only(null)
			_move_camera(_work_camera())
		State.PAUSED:
			ui.show_only(ui.pause_screen)
		State.DAY_END:
			pass  # ui.show_day_end() が表示する


func _start_day() -> void:
	grams_today = 0
	earned_today = 0
	_goal_notified = false
	processor_timer = 0.0
	tears = 0.0
	stun = 0.0
	_update_bowl()
	processor.visible = GameState.processor_interval() > 0.0
	goggles.visible = GameState.levels["goggles"] > 0
	if onion == null:
		_spawn_onion(true)
	Sfx.play("bell", -8.0, 0.0, 1.2)
	_prepare_orders()
	kitchen.set_day(GameState.day)
	_set_state(State.PLAYING)
	GameState.check_achievements(grams_today)


func _end_day() -> void:
	if state != State.PLAYING:
		return
	if grams_today < MIN_GRAMS_PER_DAY:
		return
	ui.show_day_end(grams_today, earned_today, _diary_text_for(GameState.day))
	Sfx.play("bell", -2.0, 0.0)
	Sfx.set_loop("processor", false)
	GameState.day += 1
	GameState.save_game()
	_set_state(State.DAY_END)


## 主人公の小さな日記。多くを語らない性格なので、決まった日にだけぽつりと出てくる。
## 最終日（ENDING_DAY）だけは、それまでの遊び方によって内容が分岐する（複数エンド）
func _diary_text_for(day: int) -> String:
	if not day in GameState.DIARY_DAYS:
		return ""
	GameState.diary_seen[day] = true
	if day == GameState.ENDING_DAY:
		if GameState.ending_id == "":
			GameState.ending_id = GameState.determine_ending()
		return tr("ENDING_" + GameState.ending_id.to_upper())
	return tr("DIARY_%d" % day)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		_update_tears(delta)
		_update_processor(delta)
		Sfx.set_loop("processor", processor.visible, -16.0)
		_update_chopping(delta)
		_update_gap_markers()
		ui.update_hud(grams_today, _step_text(), onion.get_progress() if onion else 1.0,
				tears, not gap_markers.is_empty() and gap_markers[0].visible,
				maxi(0, MIN_GRAMS_PER_DAY - grams_today))
	else:
		for m in gap_markers:
			m.visible = false
		Sfx.set_loop("processor", false)
	_update_knife_pose(delta)
	_update_tear_overlay(delta)
	_update_camera_move(delta)
	_update_camera_shake(delta)
	_chips_time -= delta
	chips.emitting = _chips_time > 0.0


func _unhandled_input(event: InputEvent) -> void:
	# 包丁の位置は、マウスを動かしたらマウス、スティック・十字キー・A/Dキーを使ったらそちらに切り替わる
	if event is InputEventMouseMotion:
		_set_axis_mode(false)
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		_set_pad_hint(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		_set_pad_hint(false)
	# Esc / Startボタン：一時停止。サブ画面（実績・日記・確認）を開いているときは、まずそれを閉じる
	if event.is_action_pressed("pause"):
		if ui.go_back():
			return
		if state == State.PLAYING:
			_set_state(State.PAUSED)
		elif state == State.PAUSED:
			_set_state(State.PLAYING)
		return
	# Bボタン：戻る。一時停止中に押したら再開する
	if event.is_action_pressed("back"):
		if ui.go_back():
			return
		if state == State.PAUSED:
			_set_state(State.PLAYING)
			return
	if event.is_action_pressed("end_day") and state == State.PLAYING:
		if grams_today < MIN_GRAMS_PER_DAY:
			# ボタンが押せない理由を、メニューを開かなくても分かるように知らせる
			ui.popup(tr("HUD_END_SHIFT_LOCKED") % (MIN_GRAMS_PER_DAY - grams_today),
					get_viewport().get_visible_rect().size * Vector2(0.5, 0.4), GameUI.COL_DIM)
		_end_day()
		return
	# 実況・配信用：文字要素を消して、映像だけのきれいな画を撮れるようにする
	if event is InputEventKey and event.pressed and event.keycode == KEY_H and not event.echo:
		_clean_view = not _clean_view
		ui.hud.visible = not _clean_view
		return
	# 地味だが実用的なQoL：F11でいつでもフルスクリーン切り替え
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11 and not event.echo:
		GameState.set_fullscreen(not GameState.fullscreen)
		if ui.pause_screen.visible:
			ui.refresh_texts()
		return
	if state != State.PLAYING:
		return
	# 包丁を下ろす：スペース / 左クリック / A・X・RBボタン（長押しでみじん切りを連打）
	if event.is_action("chop") and not event.is_echo():
		_holding = event.is_pressed()
		if _holding and _cooldown <= 0.0:
			_chop()
	# A/Dキーやスティックで動かし始めたら、包丁はマウスではなくそちらに従う
	if event.is_action("knife_left") or event.is_action("knife_right"):
		if event.is_pressed():
			_set_axis_mode(true)


# ================================================================ 包丁

func _step_text() -> String:
	if onion == null or onion.phase == Onion.Phase.DONE:
		return tr("STEP_DONE")
	var key := "STEP_LENGTHWISE"
	match onion.phase:
		Onion.Phase.CROSSWISE:
			key = "STEP_SLICE" if onion.steps.size() == 1 else "STEP_CROSSWISE"
		Onion.Phase.MINCE:
			key = "STEP_MINCE"
	return "%d/%d %s" % [onion.steps.find(onion.phase) + 1, onion.steps.size(), tr(key)]


## スティックの倒し具合で速さが変わる（まな板の端から端まで、フルに倒して約1秒）
const KNIFE_AXIS_SPEED := 0.5


func _set_axis_mode(on: bool) -> void:
	if _axis_mode == on:
		return
	_axis_mode = on
	_update_cursor()


## 画面下の操作ヒントを、使っている入力（マウス/キーボード or ゲームパッド）に合わせる
func _set_pad_hint(pad: bool) -> void:
	if ui:
		ui.set_hint_pad(pad)


## スティックで遊んでいる間は、動かないマウスカーソルが画面に残らないよう隠す
func _update_cursor() -> void:
	var hide := _axis_mode and state == State.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if hide else Input.MOUSE_MODE_VISIBLE


func _update_chopping(delta: float) -> void:
	_cooldown -= delta
	var axis := Input.get_axis("knife_left", "knife_right")
	if absf(axis) > 0.25:
		_set_axis_mode(true)
	if _axis_mode:
		_knife_x = clampf(_knife_x + axis * KNIFE_AXIS_SPEED * delta, -KNIFE_X_LIMIT, KNIFE_X_LIMIT)
	else:
		_knife_x = _mouse_board_x()
	# みじん切り工程だけは押しっぱなしでトントン連打できる
	var repeat := onion != null and onion.phase == Onion.Phase.MINCE
	if _holding and repeat and _cooldown <= 0.0:
		_chop()


func _chop() -> void:
	if stun > 0.0:
		return
	_cooldown = GameState.CHOP_COOLDOWN
	_chop_t = 0.0
	if not chop_at(_knife_x):
		# 何も切れなかった（まな板を叩いただけ）
		Sfx.play("knock", -8.0, 0.1)


## ワールド座標 x の位置で包丁を下ろす（テスト・デモからも呼ぶ）
func chop_at(x: float) -> bool:
	if onion == null:
		return false
	var mincing := onion.phase == Onion.Phase.MINCE
	if not onion.chop(x, GameState.chop_reach()):
		return false
	if mincing:
		Sfx.play("mince", -2.0, 0.12)
	else:
		Sfx.play("cut", 0.0, 0.1)
	tears += (TEARS_PER_CHOP if mincing else TEARS_PER_CUT) * GameState.tear_multiplier()
	chips.color = CHIP_COLOR_GOLDEN if onion.is_golden else CHIP_COLOR
	chips.global_position = Vector3(x, BOARD_TOP + 0.03, WORK_POS.z)
	_chips_time = 0.06
	_shake(SHAKE_MINCE if mincing else SHAKE_CHOP)
	_squash_knife()
	return true


func _mouse_board_x() -> float:
	var mouse := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mouse)
	var d := camera.project_ray_normal(mouse)
	if absf(d.y) < 0.0001:
		return _knife_x
	var t := (BOARD_TOP + 0.04 - o.y) / d.y
	return clampf(o.x + d.x * t, -KNIFE_X_LIMIT, KNIFE_X_LIMIT)


func _update_knife_pose(delta: float) -> void:
	_chop_t = minf(1.0, _chop_t + delta / 0.12)
	var target: Vector3
	# 刃の面がカメラから見えるよう少し傾ける
	var rot := Basis(Vector3.BACK, 0.35)
	if state == State.PLAYING:
		var lift := KNIFE_LIFT * (1.0 - sin(_chop_t * PI) * 0.97)
		target = Vector3(_knife_x, BOARD_TOP + lift, WORK_POS.z)
		if stun > 0.0:
			target.y += 0.05
			rot = Basis(Vector3.BACK, 0.35 + sin(Time.get_ticks_msec() * 0.02) * 0.15)
	else:
		# 待機中はまな板の手前に寝かせておく
		target = Vector3(0.3, BOARD_TOP + 0.004, 0.14)
		rot = Basis(Vector3.BACK, PI / 2).rotated(Vector3.UP, 0.3)
	var k := 1.0 if _chop_t < 1.0 and state == State.PLAYING else minf(1.0, delta * 18.0)
	knife.global_transform = knife.global_transform.interpolate_with(Transform3D(rot, target), k)


# ================================================================ 玉ねぎ

func _spawn_onion(animated: bool) -> void:
	var id: String = order_queue.pop_front()
	_refill_orders()
	ticket_number += 1
	onion = Onion.new()
	onion.randomize_shape(rng)
	onion.configure(id, GameState.ORDERS[id])
	ui.update_ticket(id, order_queue.slice(0, 2), ticket_number)
	add_child(onion)
	onion.phase_changed.connect(_on_onion_phase)
	if rng.randf() < GOLDEN_CHANCE:
		onion.set_golden(true)
		if sparkle:
			sparkle.global_position = onion.global_position + Vector3(0, 0.04, 0)
			sparkle.restart()
			sparkle.emitting = true
		Sfx.play("bell", -4.0, 0.0, 1.7)
		ui.popup(tr("POP_GOLDEN"), get_viewport().get_visible_rect().size * Vector2(0.5, 0.3), Color(1.0, 0.85, 0.3))
	if animated:
		onion.position = CRATE_POS + Vector3(0, 0.06, 0)
		var tw := onion.create_tween()
		tw.tween_property(onion, "position", WORK_POS, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		Sfx.play_later(0.25, "knock", -10.0)
	else:
		onion.position = WORK_POS


func _on_onion_phase(p: int) -> void:
	if p == Onion.Phase.CROSSWISE or p == Onion.Phase.MINCE:
		# 玉ねぎを回す / かき集める
		Sfx.play_later(0.1, "whoosh", -4.0)
	if p != Onion.Phase.DONE:
		return
	Sfx.play("coin", -6.0, 0.0)
	Sfx.play_later(0.65, "plop", -2.0)
	_shake(SHAKE_ORDER_DONE)
	_hit_stop(HIT_STOP_DURATION, HIT_STOP_SCALE)
	if sparkle:
		sparkle.global_position = onion.global_position + Vector3(0, 0.04, 0)
		sparkle.restart()
		sparkle.emitting = true
	var done := onion
	onion = null
	if done.is_golden:
		GameState.golden_onions += 1
	var multiplier: float = GameState.ORDERS[done.order_id]["pay"] * (GOLDEN_BONUS if done.is_golden else 1.0)
	var pay := GameState.pay_for(done.grams, multiplier)
	_award(done.grams, pay)
	GameState.check_achievements(grams_today)
	ui.popup(tr("POP_ONION") % [done.grams, pay], camera.unproject_position(done.global_position + Vector3(0, 0.05, 0)))
	# まな板からボウルへ移す
	var tw := done.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(done, "position", BOWL_POS + Vector3(0, 0.2, 0), 0.25).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(done, "scale", Vector3.ONE * 0.6, 0.4)
	tw.tween_property(done, "position", BOWL_POS + Vector3(0, 0.08, 0), 0.15).set_ease(Tween.EASE_IN)
	tw.tween_callback(done.queue_free)
	get_tree().create_timer(0.45).timeout.connect(func():
		if state == State.PLAYING and onion == null:
			_spawn_onion(true))


# ================================================================ 注文

func _refill_orders() -> void:
	var available := GameState.orders_for_day()
	while order_queue.size() < 3:
		order_queue.append(available[rng.randi() % available.size()])


## 仕込み開始時：今日の注文を並べ直し、新しい注文があれば先頭に入れて知らせる
func _prepare_orders() -> void:
	order_queue.clear()
	var fresh := GameState.new_orders_today()
	for id in fresh:
		order_queue.append(id)
	_refill_orders()
	if onion:
		ui.update_ticket(onion.order_id, order_queue.slice(0, 2), ticket_number)
	for i in fresh.size():
		var text := tr("POP_NEW_ORDER") % tr(GameState.ORDERS[fresh[i]]["name"])
		get_tree().create_timer(0.6 + i * 1.2).timeout.connect(func():
			ui.popup(text, get_viewport().get_visible_rect().size * Vector2(0.5, 0.35), GameUI.COL_ACCENT))


func _award(grams: int, pay: int) -> void:
	grams_today += grams
	earned_today += pay
	GameState.money += pay
	GameState.total_grams += grams
	_update_bowl()
	if not _goal_notified and grams_today >= MIN_GRAMS_PER_DAY:
		# 今日の目安に届いた瞬間に一度だけ知らせる（ここから先はいつでも終われる）
		_goal_notified = true
		Sfx.play("bell", -10.0, 0.0, 1.4)
		ui.popup(tr("POP_GOAL_REACHED"), get_viewport().get_visible_rect().size * Vector2(0.5, 0.22), GameUI.COL_GOOD)


func _update_bowl() -> void:
	var level := clampf(float(grams_today) / 1500.0, 0.0, 1.0)
	bowl_fill.visible = level > 0.0
	# 中身は、ボウルの内側の形に沿った高さ・太さの筒にする（縦に潰すだけだと、少ないときに壁からはみ出す）
	var top_y := BOWL_FLOOR_Y + (BOWL_HEIGHT - BOWL_FLOOR_Y - 0.012) * level
	var fill := bowl_fill.mesh as CylinderMesh
	fill.height = maxf(top_y - BOWL_FLOOR_Y, 0.001)
	fill.bottom_radius = _bowl_inner_radius(BOWL_FLOOR_Y) - 0.002
	fill.top_radius = _bowl_inner_radius(top_y) - 0.002
	bowl_fill.position = BOWL_POS + Vector3(0, BOWL_FLOOR_Y + fill.height * 0.5, 0)
	# みじん切りのかけらは、その中身の表面に乗せる（散らばる半径も、そこの内径に合わせる）
	bowl_chunks.position = BOWL_POS + Vector3(0, top_y, 0)
	bowl_chunks.scale = Vector3.ONE * ((_bowl_inner_radius(top_y) - 0.018) / BOWL_CHUNK_RADIUS)
	bowl_chunks.multimesh.visible_instance_count = roundi(level * BOWL_CHUNK_COUNT)


## ボウルの外側の半径（高さ y のとき）。底はすぼまり、口に向かってゆるやかに広がる
func _bowl_outer_radius(y: float) -> float:
	return 0.085 + 0.105 * pow(clampf(y / BOWL_HEIGHT, 0.0, 1.0), 0.6)


func _bowl_inner_radius(y: float) -> float:
	return _bowl_outer_radius(y) - BOWL_WALL


## ボウル本体のメッシュ：外側の壁 → 口の縁（丸み） → 内側の壁 → 内側の底、の輪郭を回転させる
func _bowl_mesh() -> ArrayMesh:
	var path: Array[Vector2] = []
	var steps := 14
	for i in steps + 1:
		var y := BOWL_HEIGHT * float(i) / steps
		path.append(Vector2(_bowl_outer_radius(y), y))
	# 口の縁は半円で丸める
	var rim_c := Vector2(_bowl_outer_radius(BOWL_HEIGHT) - BOWL_WALL * 0.5, BOWL_HEIGHT)
	for i in range(1, 6):
		var a := PI * float(i) / 6.0
		path.append(rim_c + Vector2(cos(a), sin(a)) * BOWL_WALL * 0.5)
	for i in range(steps, -1, -1):
		var y := BOWL_FLOOR_Y + (BOWL_HEIGHT - BOWL_FLOOR_Y) * float(i) / steps
		path.append(Vector2(_bowl_inner_radius(y), y))
	path.append(Vector2(0.0, BOWL_FLOOR_Y))
	# 外側の底の中心から始める
	path.push_front(Vector2(0.0, 0.0))
	return _lathe(path, 56)


## 断面の輪郭（半径, 高さ）を軸のまわりに回転させたメッシュ。法線は輪郭の向きからなめらかに求める
func _lathe(path: Array[Vector2], segments: int) -> ArrayMesh:
	var normals: Array[Vector2] = []
	for i in path.size():
		var a := path[maxi(i - 1, 0)]
		var b := path[mini(i + 1, path.size() - 1)]
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


func _update_gap_markers() -> void:
	# 実況・配信用にUIを隠しているときは、赤い目印も一緒に隠して画面をきれいにする
	var gaps := onion.get_wide_gaps_world() if onion and not _clean_view else []
	while gap_markers.size() < gaps.size():
		var m := MeshInstance3D.new()
		m.mesh = BoxMesh.new()
		m.material_override = _gap_mat
		add_child(m)
		gap_markers.append(m)
	for i in gap_markers.size():
		var m := gap_markers[i]
		m.visible = i < gaps.size()
		if m.visible:
			var a: float = gaps[i][0]
			var b: float = gaps[i][1]
			(m.mesh as BoxMesh).size = Vector3(maxf(0.002, b - a - 0.004), 0.002, 0.012)
			m.position = Vector3((a + b) * 0.5, BOARD_TOP + 0.001, WORK_POS.z + 0.11)


# ================================================================ 涙

func _update_tears(delta: float) -> void:
	if stun > 0.0:
		stun -= delta
		return
	tears = maxf(0.0, tears - TEARS_DECAY * delta)
	if tears >= 1.0:
		stun = TEARS_STUN_TIME
		Sfx.play("sniff", 0.0, 0.05)
		Sfx.play_later(0.2, "voice", -6.0)
		tears = 0.75
		_holding = false
		_shake(SHAKE_TEARS_MAX)
		ui.popup(tr("POP_TEARS"), get_viewport().get_visible_rect().size * 0.5, Color(0.6, 0.8, 1.0))


func _update_tear_overlay(delta: float) -> void:
	var goal := 0.0
	if state == State.PLAYING or state == State.PAUSED:
		goal = 1.0 if stun > 0.0 else smoothstep(0.3, 1.0, tears) * 0.8
	var mat := tear_overlay.material as ShaderMaterial
	var amount: float = lerpf(mat.get_shader_parameter("amount"), goal, minf(1.0, delta * 4.0))
	mat.set_shader_parameter("amount", amount)
	tear_overlay.visible = amount > 0.01


func _build_tear_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	tear_overlay = ColorRect.new()
	tear_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	tear_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/tears.gdshader")
	mat.set_shader_parameter("amount", 0.0)
	tear_overlay.material = mat
	tear_overlay.visible = false
	layer.add_child(tear_overlay)


# ================================================================ フードプロセッサー（自動化）

func _update_processor(delta: float) -> void:
	var interval := GameState.processor_interval()
	if interval <= 0.0:
		return
	processor_blade.rotate_y(delta * 25.0)
	processor_timer += delta
	if processor_timer < interval:
		return
	processor_timer -= interval
	GameState.processor_used = true
	_award(100, GameState.pay_for(100))
	GameState.check_achievements(grams_today)
	Sfx.play("plop", -10.0, 0.1, 0.8)
	ui.popup(tr("POP_PROCESSOR") % 100, camera.unproject_position(PROCESSOR_POS + Vector3(0, 0.3, 0)), GameUI.COL_GOOD)


# ================================================================ UIイベント

func _on_continue() -> void:
	_start_day()


func _on_new_game() -> void:
	GameState.delete_save()
	GameState.save_game()
	# タイトル画面に置いていた玉ねぎは前のセーブの注文なので入れ替える
	if onion:
		onion.queue_free()
		onion = null
	order_queue.clear()
	_refill_orders()
	_start_day()


func _on_to_title() -> void:
	GameState.save_game()
	_set_state(State.TITLE)


func _on_upgrade_bought(id: String) -> void:
	if GameState.buy(id):
		Sfx.play("coin", -4.0, 0.0, 0.8)
		ui.refresh_shop()
		match id:
			"knife": _rebuild_knife_visual()
			"goggles": _rebuild_goggles_visual()
			"processor": _rebuild_processor_visual()


## 実績を解除した瞬間に一言お知らせする（地味な実績も、見た目の称号に繋がる特別なものも同じ扱い）
func _on_achievement_unlocked(id: String) -> void:
	Sfx.play("bell", -2.0, 0.0, 1.5)
	Sfx.play_later(0.12, "coin", -4.0)
	var text := "🏆 " + tr(GameState.ACHIEVEMENTS[id]["name"])
	ui.popup(text, get_viewport().get_visible_rect().size * Vector2(0.5, 0.4), Color(1.0, 0.85, 0.3))


## ゴールド／プラチナ／ダイヤの称号を得た瞬間、道具の見た目を丸ごと塗り替える
func _on_skin_tier_changed(tier: int) -> void:
	_rebuild_knife_visual()
	_rebuild_goggles_visual()
	_rebuild_processor_visual()
	if tier <= 0:
		return
	Sfx.play("bell", 0.0, 0.0, 1.2)
	Sfx.play_later(0.18, "bell", -2.0)
	var text := "✨ " + tr(GameState.SKIN_NAMES[tier])
	ui.popup(text, get_viewport().get_visible_rect().size * Vector2(0.5, 0.3), Color(1.0, 0.85, 0.3))


# ================================================================ 手応え（カメラ・スクワッシュ・きらめき）

func _work_camera() -> Transform3D:
	return Transform3D.IDENTITY.translated(WORK_CAM_POS).looking_at(WORK_CAM_LOOK)


func _title_camera() -> Transform3D:
	return Transform3D.IDENTITY.translated(TITLE_CAM_POS).looking_at(TITLE_CAM_LOOK)


## カメラをすぐにその位置へ置く（起動時・確認用のスクショなど）
func set_camera_now(xf: Transform3D) -> void:
	_cam_goal = xf
	_cam_t = 1.0
	_camera_base_transform = xf
	if camera:
		camera.global_transform = xf


## カメラをゆっくりその位置へ動かす。同じ場所にいるなら何もしない
func _move_camera(xf: Transform3D) -> void:
	if _cam_goal.is_equal_approx(xf):
		return
	_cam_from = _camera_base_transform
	_cam_goal = xf
	_cam_t = 0.0


func _update_camera_move(delta: float) -> void:
	_cam_time += delta
	if _cam_t < 1.0:
		_cam_t = minf(1.0, _cam_t + delta / CAM_MOVE_TIME)
		_camera_base_transform = _cam_from.interpolate_with(_cam_goal, smoothstep(0.0, 1.0, _cam_t))
	elif state == State.TITLE:
		# タイトル画面では、ほんの少しだけゆらゆらと視点が漂う（止まった写真に見えないように）
		var drift := Vector3(sin(_cam_time * 0.21) * 0.05, sin(_cam_time * 0.33) * 0.02, 0.0)
		_camera_base_transform = _cam_goal.translated_local(drift)


## trauma（0〜1）をためる。1フレームで指数的に減衰し、揺れ幅は trauma^2 でなめらかに立ち上がる
func _shake(amount: float) -> void:
	camera_trauma = clampf(camera_trauma + amount, 0.0, 1.0)


func _update_camera_shake(delta: float) -> void:
	camera_trauma = maxf(0.0, camera_trauma - delta * 2.4)
	var shake := camera_trauma * camera_trauma
	if shake < 0.0004:
		camera.global_transform = _camera_base_transform
		return
	var offset := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), 0.0) * 0.012 * shake
	var roll := rng.randf_range(-1.0, 1.0) * deg_to_rad(1.6) * shake
	var t := _camera_base_transform.translated_local(offset)
	t.basis = t.basis.rotated(t.basis.z.normalized(), roll)
	camera.global_transform = t


## 包丁が当たった瞬間、ぺしゃっと潰れてすぐ弾んで戻る（スクワッシュ＆ストレッチ）
func _squash_knife() -> void:
	if knife_visual == null:
		return
	knife_visual.scale = Vector3(1.15, 0.72, 1.1)
	var tw := knife_visual.create_tween()
	tw.tween_property(knife_visual, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## ごく短く時間の流れを遅くして、決まった瞬間に一拍の「間」を作る
func _hit_stop(duration: float, scale: float) -> void:
	_hitstop_id += 1
	var id := _hitstop_id
	Engine.time_scale = scale
	var timer := get_tree().create_timer(duration, true, false, true)  # ignore_time_scale
	timer.timeout.connect(func():
		if id == _hitstop_id:
			Engine.time_scale = 1.0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 地味だが実用的なQoL：他のウィンドウに切り替えたら自動で一時停止する
## （離席中に涙が限界を超えたり、うっかり刻みすぎたりしないように）
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING:
		_set_state(State.PAUSED)


# ================================================================ 包丁・機械の組み立て

func _build_knife() -> void:
	knife = Node3D.new()
	add_child(knife)
	# 見た目だけを入れ子にしておき、当たった瞬間のスクワッシュはここだけを動かす
	# （knife 自身の位置・傾きは _update_knife_pose が管理しているため）
	knife_visual = Node3D.new()
	knife.add_child(knife_visual)
	_rebuild_knife_visual()

	chips = CPUParticles3D.new()
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.004, 0.004, 0.004)
	var chip_mat := _mat(Color.WHITE, 0.3)
	chip_mat.vertex_color_use_as_albedo = true  # 色は chips.color で決める（幸運の玉ねぎは金色）
	chip_mesh.material = chip_mat
	chips.mesh = chip_mesh
	chips.color = CHIP_COLOR
	chips.amount = 40
	chips.lifetime = 0.5
	chips.local_coords = false
	chips.emitting = false
	chips.direction = Vector3(0, 1, 0)
	chips.spread = 80.0
	chips.initial_velocity_min = 0.2
	chips.initial_velocity_max = 0.45
	chips.gravity = Vector3(0, -4.0, 0)
	add_child(chips)

	# 1品完成したときの、ぱっと散るきらめき演出
	sparkle = CPUParticles3D.new()
	var sparkle_mesh := QuadMesh.new()
	sparkle_mesh.size = Vector2(0.012, 0.012)
	var sparkle_mat := StandardMaterial3D.new()
	sparkle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sparkle_mat.albedo_color = Color(1.0, 0.92, 0.55)
	sparkle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sparkle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sparkle_mesh.material = sparkle_mat
	sparkle.mesh = sparkle_mesh
	sparkle.amount = 22
	sparkle.lifetime = 0.5
	sparkle.one_shot = true
	sparkle.explosiveness = 1.0
	sparkle.local_coords = false
	sparkle.emitting = false
	sparkle.direction = Vector3(0, 1, 0)
	sparkle.spread = 180.0
	sparkle.initial_velocity_min = 0.3
	sparkle.initial_velocity_max = 0.9
	sparkle.gravity = Vector3(0, -1.6, 0)
	sparkle.scale_amount_min = 0.5
	sparkle.scale_amount_max = 1.4
	sparkle.color_ramp = _fade_out_gradient()
	add_child(sparkle)

	_gap_mat = StandardMaterial3D.new()
	_gap_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gap_mat.albedo_color = Color(1.0, 0.3, 0.25)


## 実績で解禁する見た目の称号（0=なし/1=ゴールド/2=プラチナ/3=ダイヤ）に応じた、
## 道具の主要パーツを丸ごと塗り替えるための素材。称号がなければ null。
func _current_skin_mat() -> StandardMaterial3D:
	var m: StandardMaterial3D
	match GameState.skin_tier:
		1:
			m = _mat(Color(0.85, 0.7, 0.25), 0.12, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.6, 0.45, 0.1)
			m.emission_energy_multiplier = 0.35
		2:
			m = _mat(Color(0.86, 0.88, 0.92), 0.05, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.5, 0.55, 0.6)
			m.emission_energy_multiplier = 0.3
		3:
			m = _mat(Color(0.82, 0.93, 0.98), 0.03, 0.9)
			m.emission_enabled = true
			m.emission = Color(0.35, 0.7, 0.95)
			m.emission_energy_multiplier = 0.55
	return m


## 包丁のアップグレードLvに応じて見た目を変える（地味だが、育てた実感が出るように）
## Lv0: ふつうの包丁 → Lv上がるごとに刃が長く・輝きが増し → 最大Lvで柄口に金の縁飾り
## さらに実績で称号（ゴールド/プラチナ/ダイヤ）を得ていれば、そちらの色を丸ごと優先する
func _rebuild_knife_visual() -> void:
	if knife_visual == null:
		return
	for c in knife_visual.get_children():
		c.queue_free()
	var lv: int = GameState.levels["knife"]
	var max_lv: int = GameState.UPGRADES["knife"]["max"]
	var t: float = float(lv) / float(max_lv)  # 0.0〜1.0
	var skin := _current_skin_mat()

	var blade_len: float = lerpf(0.22, 0.285, t)
	var steel := skin if skin else _mat(Color(0.8, 0.81, 0.83).lerp(Color(0.88, 0.9, 0.94), t), lerpf(0.24, 0.1, t), 0.72)
	# 柄：Lv0は明るい朴（ほお）の木 → Lvが上がるほど濃い色、最大Lvは黒檀のような黒
	var wood := skin if skin else _mat(Color(0.46, 0.33, 0.2).lerp(Color(0.07, 0.05, 0.05), t), lerpf(0.65, 0.3, t))
	# 口金：Lv0〜2は水牛の角のような黒、Lv3以降は真鍮
	var ferrule := skin if skin else (_mat(Color(0.8, 0.65, 0.25), 0.25, 0.9) if lv >= 3 else _mat(Color(0.08, 0.07, 0.07), 0.35))
	for m in [steel, wood, ferrule]:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 刃は Z 方向（奥〜手前）に伸びる。原点が刃先の線。かかと（柄側）は z=0.07 で固定し、Lvで前へ伸びる
	var blade := MeshInstance3D.new()
	blade.mesh = _knife_blade_mesh(blade_len, 0.05)
	blade.material_override = steel
	knife_visual.add_child(blade)
	# 口金（柄の付け根の輪）と、八角形の和包丁の柄
	var handle_y := 0.036
	_loft(knife_visual, [
		[0.072, 0.0105, 0.0125], [0.076, 0.0115, 0.0135], [0.088, 0.0115, 0.0135], [0.091, 0.0108, 0.0128],
	], handle_y, 16, ferrule)
	_loft(knife_visual, [
		[0.09, 0.0098, 0.0118], [0.15, 0.0108, 0.0128], [0.205, 0.0112, 0.0132], [0.208, 0.0102, 0.0122],
	], handle_y, 8, wood)
	if lv >= max_lv:
		# 最大Lv：柄尻に金のキャップ、刃の背のまっすぐな部分に金の細いライン
		var gold := skin if skin else _mat(Color(0.95, 0.78, 0.35), 0.15, 1.0)
		_loft(knife_visual, [
			[0.206, 0.0104, 0.0124], [0.212, 0.0104, 0.0124], [0.214, 0.008, 0.01],
		], handle_y, 8, gold)
		var straight := blade_len * 0.55
		_box(knife_visual, Vector3(0.0028, 0.0025, straight), Vector3(0, 0.0505, 0.07 - straight * 0.5), gold)


## 牛刀の刃のメッシュ。刃線（下）はかかとからまっすぐ伸び、先の3割で反り上がって切っ先へ。
## 峰（上）は先の4割で下がって切っ先で合流する。厚みは峰から刃先へ薄くなり、
## 刃先の手前に角度の違う「切刃」の帯があるので、光が当たると刃先に沿って細い反射が出る。
func _knife_blade_mesh(length: float, height: float) -> ArrayMesh:
	var heel_z := 0.07
	var stations := 28
	var rows := 9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid := []  # [station][row] -> [y, half_thickness]
	for i in stations + 1:
		var u := float(i) / stations          # 0 = かかと, 1 = 切っ先
		var belly := smoothstep(0.62, 1.0, u)
		var edge_y := 0.009 * belly * belly
		var spine_drop := smoothstep(0.55, 1.0, u)
		var spine_y := lerpf(height, 0.0095, spine_drop * spine_drop)
		var taper := lerpf(1.0, 0.25, smoothstep(0.5, 1.0, u))
		var col := []
		for j in rows + 1:
			var v := float(j) / rows        # 0 = 刃先, 1 = 峰
			var half := 0.0
			if v < 0.16:
				half = lerpf(0.00006, 0.0008, v / 0.16)
			else:
				half = lerpf(0.0008, 0.0013, (v - 0.16) / 0.84)
			col.append([lerpf(edge_y, spine_y, v), half * taper])
		grid.append(col)
	var zat := func(i: int) -> float: return heel_z - length * float(i) / stations
	for side in [-1.0, 1.0]:
		for i in stations:
			for j in rows:
				var q := []
				for c in [[i, j], [i + 1, j], [i, j + 1], [i + 1, j + 1]]:
					var g: Array = grid[c[0]][c[1]]
					q.append(Vector3(side * g[1], g[0], zat.call(c[0])))
				_quad(st, q[0], q[1], q[2], q[3], side > 0.0)
	# 峰（上面の細い帯）と、かかと（柄側の断面）
	for i in stations:
		var a: Array = grid[i][rows]
		var b: Array = grid[i + 1][rows]
		_quad(st, Vector3(-a[1], a[0], zat.call(i)), Vector3(-b[1], b[0], zat.call(i + 1)),
				Vector3(a[1], a[0], zat.call(i)), Vector3(b[1], b[0], zat.call(i + 1)), true)
	for j in rows:
		var a: Array = grid[0][j]
		var b: Array = grid[0][j + 1]
		_quad(st, Vector3(-a[1], a[0], heel_z), Vector3(a[1], a[0], heel_z),
				Vector3(-b[1], b[0], heel_z), Vector3(b[1], b[0], heel_z), true)
	st.generate_normals()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flip: bool) -> void:
	var tris := [[a, b, c], [b, d, c]] if not flip else [[a, c, b], [b, c, d]]
	for tri in tris:
		for v in tri:
			st.add_vertex(v)


## 断面（楕円に近い多角形）を z 方向に並べてつないだ筒。rings は [z, 横の半径, 縦の半径] の並び。
## 柄や口金に使う。sides=8 にすると和包丁らしい八角の柄になる
func _loft(parent: Node, rings: Array, center_y: float, sides: int, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for r in rings:
		var ring := []
		for k in sides:
			var ang := TAU * (float(k) + 0.5) / sides
			ring.append(Vector3(cos(ang) * r[1], center_y + sin(ang) * r[2], r[0]))
		pts.append(ring)
	for i in pts.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			_quad(st, pts[i][k], pts[i][k2], pts[i + 1][k], pts[i + 1][k2], false)
	# 両端のふた
	for end in [0, pts.size() - 1]:
		var c := Vector3(0, center_y, rings[end][0])
		for k in sides:
			var tri := [c, pts[end][k], pts[end][(k + 1) % sides]]
			if end == 0:
				tri = [c, pts[end][(k + 1) % sides], pts[end][k]]
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	parent.add_child(mi)
	return mi


func _build_processor() -> void:
	processor = Node3D.new()
	processor.position = PROCESSOR_POS
	add_child(processor)
	processor_visual = Node3D.new()
	processor.add_child(processor_visual)
	processor.visible = false
	_rebuild_processor_visual()


## フードプロセッサーのLvに応じて見た目を変える：本体が大きく艶やかに、
## Lv3以降は刃が十字（2枚）になり、最大Lvで電源ランプ（赤いつまみ）が付く。
## 称号（ゴールド/プラチナ/ダイヤ）があれば本体と刃をそちらの色で丸ごと塗り替える。
func _rebuild_processor_visual() -> void:
	if processor_visual == null:
		return
	for c in processor_visual.get_children():
		c.queue_free()
	var lv: int = GameState.levels["processor"]
	var max_lv: int = GameState.UPGRADES["processor"]["max"]
	var t: float = float(lv) / float(max_lv)
	var skin := _current_skin_mat()

	var body_mat := skin if skin else _mat(Color(0.85, 0.83, 0.78).lerp(Color(0.78, 0.8, 0.84), t), lerpf(0.4, 0.15, t), lerpf(0.0, 0.55, t))
	var glass := _mat(Color(0.8, 0.9, 0.95, 0.25), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

	var base_size: float = lerpf(0.2, 0.24, t)
	_box(processor_visual, Vector3(base_size, 0.1, base_size), Vector3(0, 0.05, 0), body_mat)

	var jar := MeshInstance3D.new()
	var jar_mesh := CylinderMesh.new()
	jar_mesh.top_radius = lerpf(0.08, 0.095, t)
	jar_mesh.bottom_radius = lerpf(0.075, 0.09, t)
	jar_mesh.height = lerpf(0.16, 0.19, t)
	jar.mesh = jar_mesh
	jar.material_override = glass
	jar.position = Vector3(0, 0.18, 0)
	processor_visual.add_child(jar)

	processor_blade = Node3D.new()
	processor_blade.position = Vector3(0, 0.125, 0)
	processor_visual.add_child(processor_blade)
	var blade_mat := skin if skin else _mat(Color(0.7, 0.7, 0.72), 0.2, 0.9)
	_box(processor_blade, Vector3(0.12, 0.004, 0.015), Vector3.ZERO, blade_mat)
	if lv >= 3:
		# 中間Lv以降：刃がもう1枚、十字に増える（よりパワフルな印象に）
		_box(processor_blade, Vector3(0.015, 0.004, 0.12), Vector3.ZERO, blade_mat)

	var lid := _box(processor_visual, Vector3(lerpf(0.17, 0.2, t), 0.015, lerpf(0.17, 0.2, t)),
			Vector3(0, jar.position.y + jar_mesh.height * 0.5 + 0.005, 0), body_mat)
	lid.rotation.y = PI / 4

	if lv >= max_lv:
		# 最大Lv：電源ランプ（プロ機っぽい赤いつまみ）
		var knob_mat := skin if skin else _mat(Color(0.9, 0.2, 0.2), 0.3, 0.2)
		var knob := MeshInstance3D.new()
		var knob_mesh := CylinderMesh.new()
		knob_mesh.top_radius = 0.014
		knob_mesh.bottom_radius = 0.014
		knob_mesh.height = 0.02
		knob.mesh = knob_mesh
		knob.material_override = knob_mat
		knob.position = Vector3(base_size * 0.5 - 0.025, 0.06, base_size * 0.5 - 0.025)
		processor_visual.add_child(knob)


func _build_goggles() -> void:
	goggles = Node3D.new()
	goggles.position = GOGGLES_POS
	goggles.rotation.y = deg_to_rad(18.0)
	add_child(goggles)
	goggles_visual = Node3D.new()
	goggles.add_child(goggles_visual)
	goggles.visible = false
	_rebuild_goggles_visual()


## 玉ねぎゴーグルのLvに応じて見た目を変える：透明な安全メガネ→琥珀色のレンズ→
## 金属フレームの鏡面レンズへ。最大Lvでフレームに金の縁飾り。
## 称号があればフレームをそちらの色で丸ごと塗り替える（レンズの色味は残す）。
func _rebuild_goggles_visual() -> void:
	if goggles_visual == null:
		return
	for c in goggles_visual.get_children():
		c.queue_free()
	var lv: int = GameState.levels["goggles"]
	if lv <= 0:
		return
	var max_lv: int = GameState.UPGRADES["goggles"]["max"]
	var t: float = float(lv) / float(max_lv)
	var skin := _current_skin_mat()

	var lens_color := Color(0.75, 0.85, 0.9, 0.55).lerp(Color(0.35, 0.55, 0.75, 0.85), t)
	var lens_mat := _mat(lens_color, 0.1, lerpf(0.1, 0.6, t))
	lens_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var frame_mat := skin if skin else _mat(Color(0.15, 0.15, 0.16).lerp(Color(0.3, 0.3, 0.32), t), lerpf(0.6, 0.25, t), lerpf(0.1, 0.6, t))

	for side in [-1.0, 1.0]:
		_box(goggles_visual, Vector3(0.058, 0.006, 0.052), Vector3(side * 0.032, 0.0, 0), frame_mat)
		_box(goggles_visual, Vector3(0.05, 0.012, 0.045), Vector3(side * 0.032, 0.006, 0), lens_mat)
	_box(goggles_visual, Vector3(0.02, 0.008, 0.018), Vector3(0, 0.006, 0), frame_mat)
	_box(goggles_visual, Vector3(0.13, 0.006, 0.006), Vector3(0, 0.006, -0.03), frame_mat)

	if lv >= max_lv:
		# 最大Lv：フレームの縁に金の飾り（称号があればそちらの色のまま）
		var gold := skin if skin else _mat(Color(0.95, 0.78, 0.35), 0.15, 1.0)
		for side in [-1.0, 1.0]:
			_box(goggles_visual, Vector3(0.062, 0.004, 0.056), Vector3(side * 0.032, 0.009, 0), gold)


# ================================================================ 空間の組み立て

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.45)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.09, 0.08)
	env.fog_density = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	set_camera_now(_work_camera())

	# 作業台の真上の蛍光灯の明かり（器具は kitchen.gd 側にある）
	var light := SpotLight3D.new()
	light.position = Vector3(0, 2.0, 0.0)
	light.rotation.x = -PI / 2
	light.spot_angle = 55.0
	light.spot_range = 4.0
	light.light_color = Color(1.0, 0.82, 0.58)
	light.light_energy = 2.2
	light.shadow_enabled = true
	add_child(light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(1.2, 1.8, 1.5)
	fill.omni_range = 5.0
	fill.light_color = Color(0.55, 0.65, 0.8)
	fill.light_energy = 0.5
	add_child(fill)


func _build_kitchen() -> void:
	# まな板は檜（ひのき）。白っぽい黄色で、木目は控えめ
	var board := _wood_mat(Color(0.62, 0.48, 0.31), Color(0.46, 0.32, 0.19), 1.7)

	# 部屋まわり（壁・窓・コンロ・冷蔵庫・暖簾・小物など）は kitchen.gd でまとめて組み立てる
	kitchen = KitchenScript.new()
	add_child(kitchen)
	kitchen.build(CRATE_POS, rng)

	# 作業台の天板とまな板（脚・下の棚は kitchen.gd）
	var counter_top := ShaderMaterial.new()
	counter_top.shader = STEEL_SHADER
	counter_top.set_shader_parameter("base_color", Color(0.44, 0.44, 0.44))
	_box(self, Vector3(2.3, 0.05, 1.0), Vector3(0, 0.915, 0), counter_top)
	_box(self, Vector3(0.6, 0.025, 0.36), Vector3(0, BOARD_TOP - 0.0125, 0.05), board)

	# 段ボール箱（kitchen.gd）の中の玉ねぎ。1個ずつ別のマテリアルにして、色味・筋の位相をばらつかせる
	var stem_mat := _mat(Color(0.32, 0.2, 0.1), 0.7)
	for i in 16:
		var o := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		# 完全な球ではなく、少しつぶれた（現実の玉ねぎに近い）比率に
		sphere.radius = 0.048
		sphere.height = 0.078
		o.mesh = sphere
		var skin_mat := ShaderMaterial.new()
		skin_mat.shader = CRATE_ONION_SHADER
		skin_mat.set_shader_parameter("base_color",
				Color(0.82, 0.55, 0.25).lightened(rng.randf_range(-0.12, 0.14)))
		skin_mat.set_shader_parameter("seed", rng.randf_range(0.0, 20.0))
		skin_mat.set_shader_parameter("streak_count", rng.randf_range(12.0, 20.0))
		o.material_override = skin_mat
		o.position = CRATE_POS + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.03, 0.02), rng.randf_range(-0.14, 0.14))
		o.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-PI, PI), rng.randf_range(-0.6, 0.6))
		o.scale = Vector3.ONE * rng.randf_range(0.85, 1.1)
		add_child(o)
		# 枯れた芽の跡（細く短い茶色の突起）
		var tip := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0015
		cone.bottom_radius = 0.009
		cone.height = 0.018
		tip.mesh = cone
		tip.material_override = stem_mat
		tip.position = Vector3(0, 0.042, 0)
		o.add_child(tip)

	# みじん切りをためるボウル（左）：断面の輪郭を回転させて作る、厚みのあるステンレスのボウル
	var bowl := MeshInstance3D.new()
	bowl.mesh = _bowl_mesh()
	var bowl_mat := _mat(Color(0.78, 0.8, 0.83), 0.28, 0.85)
	bowl.material_override = bowl_mat
	bowl.position = BOWL_POS
	add_child(bowl)
	bowl_fill = MeshInstance3D.new()
	bowl_fill.mesh = CylinderMesh.new()
	bowl_fill.material_override = _mat(Color(0.93, 0.91, 0.8), 0.3)
	add_child(bowl_fill)
	_build_bowl_chunks()
	# 作った直後は CylinderMesh の初期サイズ（半径0.5m）のままなので、
	# 仕込みが始まる前（タイトル画面）でも空のボウルの状態にそろえておく
	_update_bowl()


## ボウルの中身を、なめらかな1色の山ではなく、小さなかけらが積もった表面に見せる。
## かけら（小さな箱）を中身の一番上の面にだけ薄く散らし、_update_bowl 側で
## 「今の中身の高さ・広さ」に合わせてこのノードごと上下・拡縮する
func _build_bowl_chunks() -> void:
	bowl_chunks = MultiMeshInstance3D.new()
	bowl_chunks.position = BOWL_POS
	var chunk_mesh := BoxMesh.new()
	chunk_mesh.size = Vector3(0.016, 0.011, 0.016)
	var chunk_mat := StandardMaterial3D.new()
	chunk_mat.vertex_color_use_as_albedo = true
	chunk_mat.roughness = 0.4
	chunk_mesh.material = chunk_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = chunk_mesh
	mm.instance_count = BOWL_CHUNK_COUNT
	mm.visible_instance_count = 0
	bowl_chunks.multimesh = mm
	add_child(bowl_chunks)

	for i in BOWL_CHUNK_COUNT:
		var ang := rng.randf_range(0.0, TAU)
		var r := BOWL_CHUNK_RADIUS * sqrt(rng.randf_range(0.0, 0.92))
		var y := rng.randf_range(-0.004, 0.012)
		var pos := Vector3(cos(ang) * r, y, sin(ang) * r)
		var rot := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		rot = rot.rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
		var sc := rng.randf_range(0.7, 1.2)
		mm.set_instance_transform(i, Transform3D(rot.scaled(Vector3.ONE * sc), pos))
		var shade := rng.randf_range(0.88, 1.05)
		mm.set_instance_color(i, Color(0.95, 0.93, 0.8) * shade)


## 透明にフェードアウトするグラデーション（パーティクルの寿命後半で消えるように）
func _fade_out_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.6, Color(1, 1, 1, 1))
	return g


# ================================================================ ヘルパー

## 木目つきの素材。seed を変えると木目の位置がずれて、板ごとの違いになる
func _wood_mat(base: Color, dark: Color, seed_value: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WOOD_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("dark_color", dark)
	m.set_shader_parameter("seed", seed_value)
	return m


func _mat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _box(parent: Node, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi
