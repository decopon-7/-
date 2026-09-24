# ゲーム本体。洋食屋の仕込み場の3D空間を組み立て、1日の仕込みループを回す。
extends Node3D

enum State { TITLE, PLAYING, DAY_END, PAUSED }

const BOARD_TOP := 0.965
const WORK_POS := Vector3(0.0, BOARD_TOP, 0.04)
const CRATE_POS := Vector3(0.6, 1.0, -0.12)
const BOWL_POS := Vector3(-0.56, 0.94, -0.16)
const PROCESSOR_POS := Vector3(-0.3, 0.94, -0.38)
const KNIFE_LIFT := 0.09
const KNIFE_X_LIMIT := 0.26

## 涙：1回切るごとに増える量（工程1・2 / 工程3）と、1秒あたりに引く量
const TEARS_PER_CUT := 0.05
const TEARS_PER_CHOP := 0.012
const TEARS_DECAY := 0.045
const TEARS_STUN_TIME := 2.2

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
var processor_blade: Node3D
var bowl_fill: MeshInstance3D
var gap_markers: Array[MeshInstance3D] = []
var tear_overlay: ColorRect
## これから来る注文（先頭が次の玉ねぎ）
var order_queue: Array[String] = []
var ticket_number := 0

var _knife_x := 0.0
var _chop_t := 1.0
var _cooldown := 0.0
var _holding := false
var _chips_time := 0.0
var _gap_mat: StandardMaterial3D


func _ready() -> void:
	rng.randomize()
	_build_environment()
	_build_kitchen()
	_build_knife()
	_build_processor()
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

	_refill_orders()
	_spawn_onion(false)
	_set_state(State.TITLE)

	var dev := preload("res://scripts/dev_screenshot.gd")
	if dev.requested():
		add_child(dev.new())


# ================================================================ 仕込みループ

func _set_state(s: State) -> void:
	state = s
	_holding = false
	Sfx.set_music_muffled(s != State.PLAYING)
	if s != State.PLAYING:
		Sfx.set_music_tempo(1.0)
	match s:
		State.TITLE:
			ui.refresh_texts()
			ui.show_only(ui.title_screen)
		State.PLAYING:
			ui.show_only(null)
		State.PAUSED:
			ui.show_only(ui.pause_screen)
		State.DAY_END:
			pass  # ui.show_day_end() が表示する


func _start_day() -> void:
	grams_today = 0
	earned_today = 0
	processor_timer = 0.0
	tears = 0.0
	stun = 0.0
	_update_bowl()
	processor.visible = GameState.processor_interval() > 0.0
	if onion == null:
		_spawn_onion(true)
	Sfx.play("bell", -8.0, 0.0, 1.2)
	_prepare_orders()
	_set_state(State.PLAYING)


func _end_day() -> void:
	if state != State.PLAYING:
		return
	ui.show_day_end(grams_today, earned_today)
	Sfx.play("bell", -2.0, 0.0)
	Sfx.set_loop("processor", false)
	GameState.day += 1
	GameState.save_game()
	_set_state(State.DAY_END)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		_update_tears(delta)
		_update_processor(delta)
		Sfx.set_loop("processor", processor.visible, -16.0)
		_update_chopping(delta)
		_update_gap_markers()
		ui.update_hud(grams_today, _step_text(), onion.get_progress() if onion else 1.0,
				tears, not gap_markers.is_empty() and gap_markers[0].visible)
	else:
		for m in gap_markers:
			m.visible = false
		Sfx.set_loop("processor", false)
	_update_knife_pose(delta)
	_update_tear_overlay(delta)
	_chips_time -= delta
	chips.emitting = _chips_time > 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if state == State.PLAYING:
			_set_state(State.PAUSED)
		elif state == State.PAUSED:
			_set_state(State.PLAYING)
		return
	if state != State.PLAYING:
		return
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_holding = event.pressed
		pressed = event.pressed
	elif event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		_holding = event.pressed
		pressed = event.pressed
	if pressed and _cooldown <= 0.0:
		_chop()


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


func _update_chopping(delta: float) -> void:
	_cooldown -= delta
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
	chips.global_position = Vector3(x, BOARD_TOP + 0.03, WORK_POS.z)
	_chips_time = 0.06
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
	var done := onion
	onion = null
	var pay := GameState.pay_for(done.grams, GameState.ORDERS[done.order_id]["pay"])
	_award(done.grams, pay)
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


func _update_bowl() -> void:
	var level := clampf(float(grams_today) / 1500.0, 0.0, 1.0)
	bowl_fill.visible = level > 0.0
	bowl_fill.scale = Vector3(1.0, maxf(level, 0.01), 1.0)
	bowl_fill.position = BOWL_POS + Vector3(0, 0.01 + 0.15 * level * 0.5, 0)


func _update_gap_markers() -> void:
	var gaps := onion.get_wide_gaps_world() if onion else []
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
		tears = 0.75
		_holding = false
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
	_award(100, GameState.pay_for(100))
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


# ================================================================ 包丁・機械の組み立て

func _build_knife() -> void:
	var steel := _mat(Color(0.8, 0.81, 0.83), 0.2, 0.95)
	var wood := _mat(Color(0.2, 0.13, 0.08), 0.6)
	knife = Node3D.new()
	add_child(knife)
	# 刃は Z 方向（奥〜手前）に伸びる。原点が刃先の線。
	_box(knife, Vector3(0.003, 0.05, 0.22), Vector3(0, 0.025, -0.04), steel)
	_box(knife, Vector3(0.008, 0.03, 0.015), Vector3(0, 0.035, 0.075), steel)
	_box(knife, Vector3(0.018, 0.024, 0.12), Vector3(0, 0.037, 0.14), wood)

	chips = CPUParticles3D.new()
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.004, 0.004, 0.004)
	chip_mesh.material = _mat(Color(0.95, 0.94, 0.85), 0.3)
	chips.mesh = chip_mesh
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

	_gap_mat = StandardMaterial3D.new()
	_gap_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gap_mat.albedo_color = Color(1.0, 0.3, 0.25)


func _build_processor() -> void:
	var body_mat := _mat(Color(0.85, 0.83, 0.78), 0.4)
	var glass := _mat(Color(0.8, 0.9, 0.95, 0.25), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	processor = Node3D.new()
	processor.position = PROCESSOR_POS
	add_child(processor)
	_box(processor, Vector3(0.2, 0.1, 0.2), Vector3(0, 0.05, 0), body_mat)
	var jar := MeshInstance3D.new()
	var jar_mesh := CylinderMesh.new()
	jar_mesh.top_radius = 0.08
	jar_mesh.bottom_radius = 0.075
	jar_mesh.height = 0.16
	jar.mesh = jar_mesh
	jar.material_override = glass
	jar.position = Vector3(0, 0.18, 0)
	processor.add_child(jar)
	processor_blade = Node3D.new()
	processor_blade.position = Vector3(0, 0.125, 0)
	processor.add_child(processor_blade)
	_box(processor_blade, Vector3(0.12, 0.004, 0.015), Vector3.ZERO, _mat(Color(0.7, 0.7, 0.72), 0.2, 0.9))
	var lid := _box(processor, Vector3(0.17, 0.015, 0.17), Vector3(0, 0.265, 0), body_mat)
	lid.rotation.y = PI / 4
	processor.visible = false


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
	camera.look_at_from_position(Vector3(0, 1.5, 0.52), Vector3(0, 0.965, -0.01))

	# 吊り下げランプ
	var lamp_root := Node3D.new()
	lamp_root.position = Vector3(0, 2.05, 0.0)
	add_child(lamp_root)
	var shade := MeshInstance3D.new()
	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = 0.04
	shade_mesh.bottom_radius = 0.22
	shade_mesh.height = 0.16
	shade_mesh.cap_bottom = false
	shade.mesh = shade_mesh
	var shade_mat := _mat(Color(0.18, 0.22, 0.17), 0.5, 0.6)
	shade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade.material_override = shade_mat
	lamp_root.add_child(shade)
	var bulb := MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.04
	bulb_mesh.height = 0.08
	bulb.mesh = bulb_mesh
	var bulb_mat := _mat(Color(1, 0.9, 0.7), 0.5)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.8, 0.5)
	bulb_mat.emission_energy_multiplier = 6.0
	bulb.material_override = bulb_mat
	bulb.position.y = -0.07
	lamp_root.add_child(bulb)
	_box(lamp_root, Vector3(0.01, 1.0, 0.01), Vector3(0, 0.55, 0), _mat(Color(0.1, 0.1, 0.1), 0.6))

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
	var concrete := _mat(Color(0.22, 0.2, 0.18), 0.95)
	var wall := _mat(Color(0.78, 0.76, 0.7), 0.9)
	var tile := _mat(Color(0.55, 0.6, 0.58), 0.4)
	var steel := _mat(Color(0.32, 0.33, 0.33), 0.45, 0.7)
	var dark_steel := _mat(Color(0.18, 0.19, 0.19), 0.5, 0.6)
	var board := _mat(Color(0.52, 0.42, 0.3), 0.8)

	# 床と壁（壁の下半分はタイル）
	_box(self, Vector3(8, 0.1, 8), Vector3(0, -0.05, 0), concrete)
	_box(self, Vector3(8, 3.2, 0.1), Vector3(0, 1.6, -2.4), wall)
	_box(self, Vector3(0.1, 3.2, 8), Vector3(-3.2, 1.6, 0), wall)
	_box(self, Vector3(0.1, 3.2, 8), Vector3(3.2, 1.6, 0), wall)
	_box(self, Vector3(8, 1.5, 0.02), Vector3(0, 0.75, -2.34), tile)

	# 作業台とまな板
	_box(self, Vector3(2.2, 0.88, 0.9), Vector3(0, 0.44, 0), dark_steel)
	_box(self, Vector3(2.3, 0.05, 1.0), Vector3(0, 0.915, 0), steel)
	_box(self, Vector3(0.6, 0.025, 0.36), Vector3(0, BOARD_TOP - 0.0125, 0.05), board)

	# 玉ねぎのケース（右）
	_crate(CRATE_POS + Vector3(0, -0.06, 0), Vector3(0.42, 0.14, 0.4), _mat(Color(0.45, 0.3, 0.18), 0.8))
	var onion_skin := _mat(Color(0.55, 0.33, 0.15), 0.6)
	for i in 16:
		var o := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.045
		sphere.height = 0.08
		o.mesh = sphere
		o.material_override = onion_skin
		o.position = CRATE_POS + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.03, 0.02), rng.randf_range(-0.14, 0.14))
		o.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-PI, PI), rng.randf_range(-0.6, 0.6))
		o.scale = Vector3.ONE * rng.randf_range(0.85, 1.1)
		add_child(o)
		var tip := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.001
		cone.bottom_radius = 0.012
		cone.height = 0.025
		tip.mesh = cone
		tip.material_override = onion_skin
		tip.position = Vector3(0, 0.045, 0)
		o.add_child(tip)

	# みじん切りをためるボウル（左）
	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.19
	bowl_mesh.bottom_radius = 0.11
	bowl_mesh.height = 0.15
	bowl_mesh.cap_top = false
	bowl.mesh = bowl_mesh
	var bowl_mat := _mat(Color(0.75, 0.76, 0.78), 0.35, 0.3)
	bowl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bowl.material_override = bowl_mat
	bowl.position = BOWL_POS + Vector3(0, 0.075, 0)
	add_child(bowl)
	bowl_fill = MeshInstance3D.new()
	var fill_mesh := CylinderMesh.new()
	fill_mesh.top_radius = 0.17
	fill_mesh.bottom_radius = 0.11
	fill_mesh.height = 0.15
	bowl_fill.mesh = fill_mesh
	bowl_fill.material_override = _mat(Color(0.93, 0.91, 0.8), 0.3)
	add_child(bowl_fill)

	# 奥のシンク台・棚・鍋
	_box(self, Vector3(3.6, 0.9, 0.6), Vector3(0, 0.45, -2.05), dark_steel)
	for x in [-1.1, 0.0, 1.1]:
		_crate(Vector3(x, 0.84, -2.05), Vector3(0.9, 0.12, 0.45), steel)
		_box(self, Vector3(0.03, 0.3, 0.03), Vector3(x, 1.05, -2.3), steel)
		_box(self, Vector3(0.03, 0.03, 0.2), Vector3(x, 1.2, -2.2), steel)
	_box(self, Vector3(3.0, 0.04, 0.35), Vector3(0, 1.75, -2.2), steel)
	for i in 6:
		var pot := MeshInstance3D.new()
		var pot_mesh := CylinderMesh.new()
		pot_mesh.top_radius = rng.randf_range(0.08, 0.13)
		pot_mesh.bottom_radius = pot_mesh.top_radius
		pot_mesh.height = rng.randf_range(0.1, 0.2)
		pot.mesh = pot_mesh
		pot.material_override = _mat(Color(0.6, 0.6, 0.62).lerp(Color(0.55, 0.35, 0.22), rng.randf() * 0.5), 0.3, 0.8)
		pot.position = Vector3(-1.25 + i * 0.5, 1.77 + pot_mesh.height / 2, -2.2)
		add_child(pot)
	# 吊るしたおたまやフライパン
	_box(self, Vector3(2.4, 0.02, 0.02), Vector3(0, 2.1, -2.3), steel)
	for i in 5:
		var hx := -0.9 + i * 0.45
		_box(self, Vector3(0.012, 0.3, 0.012), Vector3(hx, 1.93, -2.28), steel)
		var pan := MeshInstance3D.new()
		var pan_mesh := CylinderMesh.new()
		pan_mesh.top_radius = 0.1
		pan_mesh.bottom_radius = 0.09
		pan_mesh.height = 0.02
		pan.mesh = pan_mesh
		pan.material_override = dark_steel
		pan.rotation.x = PI / 2
		pan.position = Vector3(hx, 1.72, -2.27)
		add_child(pan)


# ================================================================ ヘルパー

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


## 上が開いた箱（ケースやシンク）
func _crate(center: Vector3, size: Vector3, material: Material) -> void:
	var t := 0.015
	_box(self, Vector3(size.x, t, size.z), center + Vector3(0, -size.y / 2, 0), material)
	_box(self, Vector3(size.x, size.y, t), center + Vector3(0, 0, size.z / 2), material)
	_box(self, Vector3(size.x, size.y, t), center + Vector3(0, 0, -size.z / 2), material)
	_box(self, Vector3(t, size.y, size.z), center + Vector3(size.x / 2, 0, 0), material)
	_box(self, Vector3(t, size.y, size.z), center + Vector3(-size.x / 2, 0, 0), material)
