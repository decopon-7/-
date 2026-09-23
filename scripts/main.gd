# ゲーム本体。調理場の3D空間を組み立て、1日の勤務ループを回す。
extends Node3D

enum State { TITLE, PLAYING, DAY_END, PAUSED }

const POTATO_SCALE := 0.1
const WORK_POS := Vector3(0.0, 1.04, 0.05)
const BIN_POS := Vector3(0.72, 1.0, 0.02)
const POT_POS := Vector3(-0.72, 0.94, 0.02)
const MACHINE_POS := Vector3(-0.5, 0.94, -0.34)
const MAX_POT_PILE := 36

var state := State.TITLE
var time_left := 0.0
var peeled_today := 0
var earned_today := 0
var machine_timer := 0.0

var rng := RandomNumberGenerator.new()
var camera: Camera3D
var ui: GameUI
var potato: Potato
var peeler: Node3D
var chips: CPUParticles3D
var machine: Node3D
var machine_drum: Node3D
var machine_lamp: StandardMaterial3D
var pot_pile: Array[Node3D] = []

var _peeling := false
var _rotating := false
var _last_dir = null  # Vector3 または null
var _peeler_rest: Transform3D


func _ready() -> void:
	rng.randomize()
	_build_environment()
	_build_kitchen()
	_build_peeler()
	_build_machine()

	ui = GameUI.new()
	add_child(ui)
	ui.continue_pressed.connect(_on_continue)
	ui.new_game_pressed.connect(_on_new_game)
	ui.start_day_pressed.connect(_start_day)
	ui.resume_pressed.connect(func(): _set_state(State.PLAYING))
	ui.to_title_pressed.connect(_on_to_title)
	ui.end_shift_pressed.connect(_end_day)
	ui.upgrade_bought.connect(_on_upgrade_bought)

	_spawn_potato(false)
	_set_state(State.TITLE)

	var dev := preload("res://scripts/dev_screenshot.gd")
	if dev.requested():
		add_child(dev.new())


# ================================================================ 勤務ループ

func _set_state(s: State) -> void:
	state = s
	_peeling = false
	_rotating = false
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
	time_left = GameState.DAY_LENGTH
	peeled_today = 0
	earned_today = 0
	machine_timer = 0.0
	_update_machine_visibility()
	if potato == null:
		_spawn_potato(true)
	_set_state(State.PLAYING)


func _end_day() -> void:
	if state != State.PLAYING:
		return
	var quota := GameState.quota_for_day()
	var success := peeled_today >= quota
	var bonus := 0
	if success:
		bonus = GameState.quota_bonus()
		GameState.money += bonus
	ui.show_day_end(success, peeled_today, quota, earned_today, bonus)
	if success:
		GameState.day += 1
	GameState.save_game()
	_set_state(State.DAY_END)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		time_left -= delta
		_rotate_potato_by_keys(delta)
		if potato and GameState.turntable_speed() > 0.0:
			potato.rotate_object_local(Vector3.RIGHT, GameState.turntable_speed() * delta)
		_update_machine(delta)
		_update_peeling()
		ui.update_hud(time_left, peeled_today, potato.get_peel_ratio() if potato else 0.0)
		if time_left <= 0.0:
			_end_day()
	elif state == State.TITLE and potato:
		potato.rotate_y(delta * 0.3)  # タイトル画面ではゆっくり回して飾る
	_update_peeler_pose(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if state == State.PLAYING:
			_set_state(State.PAUSED)
		elif state == State.PAUSED:
			_set_state(State.PLAYING)
		return
	if state != State.PLAYING:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_peeling = event.pressed
			_last_dir = null
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = event.pressed
	elif event is InputEventMouseMotion and _rotating and potato:
		_rotate_potato(event.relative * 0.008)


# ================================================================ 皮むき

func _mouse_hit() -> Dictionary:
	if potato == null:
		return {}
	var mouse := get_viewport().get_mouse_position()
	return potato.intersect_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))


func _update_peeling() -> void:
	chips.emitting = false
	if not _peeling or potato == null:
		return
	var hit := _mouse_hit()
	if hit.is_empty():
		_last_dir = null
		return
	var from: Vector3 = hit["dir"] if _last_dir == null else _last_dir
	var gained := potato.peel_stroke(from, hit["dir"], GameState.peel_radius())
	_last_dir = hit["dir"]
	if gained > 0.0:
		chips.global_position = hit["position"]
		chips.emitting = true
	if potato.get_peel_ratio() >= GameState.PEEL_DONE_RATIO:
		_complete_potato()


func _complete_potato() -> void:
	var done := potato
	potato = null
	_last_dir = null
	done.peel_all()
	var pay := GameState.price_per_potato()
	_award(pay)
	ui.popup(tr("POP_POTATO") % pay, camera.unproject_position(done.global_position))
	_send_to_pot(done)
	_spawn_potato(true)


func _award(pay: int) -> void:
	peeled_today += 1
	earned_today += pay
	GameState.money += pay
	GameState.total_peeled += 1


func _spawn_potato(animated: bool) -> void:
	potato = Potato.new()
	potato.randomize_shape(rng)
	add_child(potato)
	potato.scale = Vector3.ONE * POTATO_SCALE
	potato.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-PI, PI), 0.0)
	if animated:
		potato.position = BIN_POS + Vector3(0, 0.05, 0)
		var tw := potato.create_tween()
		tw.tween_property(potato, "position", WORK_POS, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		potato.position = WORK_POS


## むけた芋を鍋へ放り込む
func _send_to_pot(p: Node3D) -> void:
	var slot := pot_pile.size()
	var ring := rng.randf_range(0.0, 0.12)
	var ang := rng.randf_range(0.0, TAU)
	var target := POT_POS + Vector3(cos(ang) * ring, 0.05 + minf(slot, MAX_POT_PILE) * 0.004, sin(ang) * ring)
	var mid := (p.position + target) * 0.5 + Vector3(0, 0.25, 0)
	var tw := p.create_tween()
	tw.tween_property(p, "position", mid, 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "scale", Vector3.ONE * POTATO_SCALE * 0.8, 0.4)
	tw.parallel().tween_property(p, "rotation", p.rotation + Vector3(rng.randf_range(2, 5), 0, rng.randf_range(1, 3)), 0.4)
	tw.tween_property(p, "position", target, 0.2).set_ease(Tween.EASE_IN)
	pot_pile.append(p)
	if pot_pile.size() > MAX_POT_PILE:
		pot_pile.pop_front().queue_free()


# ================================================================ 回転

func _rotate_potato(amount: Vector2) -> void:
	potato.rotate(camera.global_basis.y, amount.x)
	potato.rotate(camera.global_basis.x, amount.y)


func _rotate_potato_by_keys(delta: float) -> void:
	if potato == null:
		return
	var v := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if v != Vector2.ZERO:
		_rotate_potato(v * 2.5 * delta)


# ================================================================ 皮むき機（自動化）

func _update_machine_visibility() -> void:
	machine.visible = GameState.machine_interval() > 0.0


func _update_machine(delta: float) -> void:
	var interval := GameState.machine_interval()
	if interval <= 0.0:
		return
	machine_drum.rotate_z(delta * 6.0)
	machine_timer += delta
	machine_lamp.emission_energy_multiplier = 0.4 + 2.5 * pow(machine_timer / interval, 4.0)
	if machine_timer < interval:
		return
	machine_timer -= interval
	_award(GameState.price_per_potato())
	var p := Potato.new()
	p.randomize_shape(rng)
	add_child(p)
	p.peel_all()
	p.scale = Vector3.ONE * POTATO_SCALE * 0.8
	p.position = MACHINE_POS + Vector3(0, 0.4, 0)
	_send_to_pot(p)
	ui.popup(tr("POP_MACHINE"), camera.unproject_position(MACHINE_POS + Vector3(0, 0.45, 0)), GameUI.COL_GOOD)


# ================================================================ UIイベント

func _on_continue() -> void:
	_start_day()


func _on_new_game() -> void:
	GameState.delete_save()
	GameState.save_game()
	for p in pot_pile:
		p.queue_free()
	pot_pile.clear()
	_start_day()


func _on_to_title() -> void:
	GameState.save_game()
	_set_state(State.TITLE)


func _on_upgrade_bought(id: String) -> void:
	if GameState.buy(id):
		ui.refresh_shop()
		_update_machine_visibility()


# ================================================================ ピーラー

func _update_peeler_pose(delta: float) -> void:
	var target := _peeler_rest
	if state == State.PLAYING:
		var hit := _mouse_hit()
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			var cb := camera.global_basis
			var y := (n * 0.6 + cb.y * 0.7 + cb.z * 0.4 + cb.x * 0.3).normalized()
			var x := (cb.x - y * y.dot(cb.x)).normalized()
			var b := Basis(x, y, x.cross(y))
			if _peeling:
				b = b.rotated(n, sin(Time.get_ticks_msec() * 0.03) * 0.08)
			target = Transform3D(b, hit["position"] + n * 0.004)
	peeler.global_transform = peeler.global_transform.interpolate_with(target, minf(1.0, delta * 20.0))


func _build_peeler() -> void:
	var metal := _mat(Color(0.72, 0.72, 0.74), 0.35, 0.9)
	var wood := _mat(Color(0.42, 0.26, 0.14), 0.7)
	peeler = Node3D.new()
	add_child(peeler)
	_box(peeler, Vector3(0.075, 0.004, 0.014), Vector3.ZERO, metal)  # 刃
	for side in [-1.0, 1.0]:
		var arm := _box(peeler, Vector3(0.005, 0.05, 0.005), Vector3(side * 0.036, 0.025, 0), metal)
		arm.rotation.z = side * 0.35
	_box(peeler, Vector3(0.04, 0.006, 0.008), Vector3(0, 0.05, 0), metal)
	var handle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.011
	cyl.bottom_radius = 0.013
	cyl.height = 0.11
	handle.mesh = cyl
	handle.material_override = wood
	handle.position = Vector3(0, 0.108, 0)
	peeler.add_child(handle)

	_peeler_rest = Transform3D(Basis.from_euler(Vector3(-PI / 2, 0.4, 0)), Vector3(0.26, 0.975, 0.2))
	peeler.global_transform = _peeler_rest

	chips = CPUParticles3D.new()
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.012, 0.0015, 0.02)
	chip_mesh.material = _mat(Color(0.5, 0.34, 0.17), 0.9)
	chips.mesh = chip_mesh
	chips.amount = 80
	chips.lifetime = 0.8
	chips.local_coords = false
	chips.emitting = false
	chips.direction = Vector3(0, 1, 0)
	chips.spread = 70.0
	chips.initial_velocity_min = 0.25
	chips.initial_velocity_max = 0.6
	chips.gravity = Vector3(0, -3.5, 0)
	chips.angular_velocity_min = -720.0
	chips.angular_velocity_max = 720.0
	chips.particle_flag_rotate_y = true
	add_child(chips)


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
	camera.look_at_from_position(Vector3(0, 1.52, 0.78), Vector3(0, 0.98, -0.04))

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
	var concrete := _mat(Color(0.2, 0.2, 0.19), 0.95)
	var wall := _mat(Color(0.23, 0.25, 0.21), 0.9)
	var steel := _mat(Color(0.28, 0.29, 0.29), 0.45, 0.7)
	var dark_steel := _mat(Color(0.16, 0.17, 0.17), 0.5, 0.6)
	var board := _mat(Color(0.4, 0.27, 0.16), 0.75)
	var pipe := _mat(Color(0.3, 0.2, 0.14), 0.5, 0.8)

	# 床と壁
	_box(self, Vector3(8, 0.1, 8), Vector3(0, -0.05, 0), concrete)
	_box(self, Vector3(8, 3.2, 0.1), Vector3(0, 1.6, -2.4), wall)
	_box(self, Vector3(0.1, 3.2, 8), Vector3(-3.2, 1.6, 0), wall)
	_box(self, Vector3(0.1, 3.2, 8), Vector3(3.2, 1.6, 0), wall)
	# 壁の腰板
	_box(self, Vector3(8, 1.1, 0.02), Vector3(0, 0.55, -2.34), _mat(Color(0.17, 0.19, 0.16), 0.8))

	# 作業台
	_box(self, Vector3(2.2, 0.88, 0.9), Vector3(0, 0.44, 0), dark_steel)
	_box(self, Vector3(2.3, 0.05, 1.0), Vector3(0, 0.915, 0), steel)
	_box(self, Vector3(0.44, 0.025, 0.34), Vector3(0, 0.9525, 0.05), board)

	# 未処理の芋ケース（右）
	_crate(BIN_POS + Vector3(0, -0.06, 0), Vector3(0.5, 0.14, 0.46), steel)
	for i in 22:
		var p := Potato.new()
		p.randomize_shape(rng)
		add_child(p)
		p.scale = Vector3.ONE * rng.randf_range(0.075, 0.09)
		p.position = BIN_POS + Vector3(rng.randf_range(-0.19, 0.19), rng.randf_range(-0.04, 0.02), rng.randf_range(-0.17, 0.17))
		p.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-PI, PI), rng.randf_range(-0.4, 0.4))

	# むいた芋の鍋（左）
	var pot := MeshInstance3D.new()
	var pot_mesh := CylinderMesh.new()
	pot_mesh.top_radius = 0.2
	pot_mesh.bottom_radius = 0.19
	pot_mesh.height = 0.2
	pot_mesh.cap_top = false
	pot.mesh = pot_mesh
	var pot_mat := _mat(Color(0.55, 0.56, 0.57), 0.3, 0.9)
	pot_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pot.material_override = pot_mat
	pot.position = POT_POS + Vector3(0, 0.1, 0)
	add_child(pot)
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 0.185
	water_mesh.bottom_radius = 0.185
	water_mesh.height = 0.01
	water.mesh = water_mesh
	water.material_override = _mat(Color(0.25, 0.3, 0.3), 0.05, 0.2)
	water.position = POT_POS + Vector3(0, 0.12, 0)
	add_child(water)

	# 奥のシンク台と棚
	_box(self, Vector3(3.6, 0.9, 0.6), Vector3(0, 0.45, -2.05), dark_steel)
	for x in [-1.1, 0.0, 1.1]:
		_crate(Vector3(x, 0.84, -2.05), Vector3(0.9, 0.12, 0.45), steel)
		_box(self, Vector3(0.03, 0.3, 0.03), Vector3(x, 1.05, -2.3), steel)
		_box(self, Vector3(0.03, 0.03, 0.2), Vector3(x, 1.2, -2.2), steel)
	_box(self, Vector3(3.0, 0.04, 0.35), Vector3(0, 1.75, -2.2), steel)
	for i in 7:
		var jar := MeshInstance3D.new()
		var jar_mesh := CylinderMesh.new()
		jar_mesh.top_radius = 0.07
		jar_mesh.bottom_radius = 0.08
		jar_mesh.height = rng.randf_range(0.12, 0.25)
		jar.mesh = jar_mesh
		jar.material_override = _mat(Color(0.3, 0.3, 0.26).lerp(Color(0.5, 0.35, 0.2), rng.randf()), 0.6, 0.4)
		jar.position = Vector3(-1.3 + i * 0.42, 1.77 + jar_mesh.height / 2, -2.2)
		add_child(jar)

	# 配管
	for h in [2.3, 2.45]:
		var p := MeshInstance3D.new()
		var p_mesh := CylinderMesh.new()
		p_mesh.top_radius = 0.035
		p_mesh.bottom_radius = 0.035
		p_mesh.height = 6.4
		p.mesh = p_mesh
		p.material_override = pipe
		p.rotation.z = PI / 2
		p.position = Vector3(0, h, -2.3)
		add_child(p)
	var valve := MeshInstance3D.new()
	var valve_mesh := TorusMesh.new()
	valve_mesh.inner_radius = 0.1
	valve_mesh.outer_radius = 0.13
	valve.mesh = valve_mesh
	valve.material_override = _mat(Color(0.5, 0.1, 0.08), 0.5, 0.5)
	valve.rotation.x = PI / 2
	valve.position = Vector3(1.6, 1.4, -2.3)
	add_child(valve)


func _build_machine() -> void:
	var green := _mat(Color(0.24, 0.29, 0.18), 0.6, 0.4)
	var steel := _mat(Color(0.5, 0.5, 0.5), 0.35, 0.9)
	machine = Node3D.new()
	machine.position = MACHINE_POS
	add_child(machine)
	_box(machine, Vector3(0.34, 0.26, 0.26), Vector3(0, 0.13, 0), green)
	_box(machine, Vector3(0.02, 0.12, 0.2), Vector3(-0.16, 0.34, 0), steel)
	_box(machine, Vector3(0.02, 0.12, 0.2), Vector3(0.16, 0.34, 0), steel)
	machine_drum = Node3D.new()
	machine_drum.position = Vector3(0, 0.36, 0)
	machine.add_child(machine_drum)
	var drum := MeshInstance3D.new()
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = 0.09
	drum_mesh.bottom_radius = 0.09
	drum_mesh.height = 0.28
	drum_mesh.radial_segments = 10
	drum.mesh = drum_mesh
	drum.material_override = steel
	drum.rotation.z = PI / 2
	machine_drum.add_child(drum)
	machine_lamp = _mat(Color(0.8, 0.15, 0.1), 0.4)
	machine_lamp.emission_enabled = true
	machine_lamp.emission = Color(1.0, 0.2, 0.1)
	_box(machine, Vector3(0.04, 0.04, 0.02), Vector3(0.11, 0.2, 0.135), machine_lamp)
	machine.visible = false


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
