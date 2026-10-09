# コントローラー（ゲームパッド）操作の自動テスト。スティックで包丁が動く／Aで切る／Startで一時停止／Bで戻る／Yで終業。
#   godot --headless --path . -s tools/test_controller.gd
# 成功なら "PAD TEST OK" を出して終了コード 0。
extends SceneTree

func _pad_button(button: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	var ui = main.get("ui")
	var gs := root.get_node("GameState")

	# タイトル：最初のボタンにフォーカスが乗っている（十字キー/Aですぐ操作できる）
	var owner = root.gui_get_focus_owner()
	assert(owner != null, "title should focus a button")
	print("title focus: ", owner.text)

	# ゲーム開始（ボタンの pressed を直接発火）
	main.call("_start_day")
	await process_frame
	assert(int(main.get("state")) == 1)

	# スティック右へ：包丁がマウスではなくスティックに従って動く
	var x0: float = main.get("_knife_x")
	Input.action_press("knife_right", 1.0)
	for i in 30:
		await process_frame
	Input.action_release("knife_right")
	var x1: float = main.get("_knife_x")
	print("knife x: ", x0, " -> ", x1, " axis_mode=", main.get("_axis_mode"))
	assert(main.get("_axis_mode") == true)
	assert(x1 > x0 + 0.01, "knife should move right with the stick")

	# 左へ戻すと、上限（まな板の端）で止まる
	Input.action_press("knife_left", 1.0)
	for i in 120:
		await process_frame
	Input.action_release("knife_left")
	assert(absf(float(main.get("_knife_x")) + float(main.get("KNIFE_X_LIMIT"))) < 0.0001, "should clamp at the left edge")

	# Aボタンで切る
	var chops_before := 0
	var o = main.get("onion")
	var cuts_before: int = o.cuts_x.size()
	main.set("_knife_x", 0.05)
	Input.action_press("knife_left", 0.0)
	Input.action_release("knife_left")
	_pad_button(JOY_BUTTON_A, true)
	await process_frame
	_pad_button(JOY_BUTTON_A, false)
	await process_frame
	print("cuts: ", cuts_before, " -> ", o.cuts_x.size())
	assert(o.cuts_x.size() > cuts_before, "A button should chop")

	# Startで一時停止 → ポーズ画面の再開にフォーカス
	_pad_button(JOY_BUTTON_START, true)
	await process_frame
	_pad_button(JOY_BUTTON_START, false)
	await process_frame
	assert(int(main.get("state")) == 3, "Start should pause")
	await process_frame
	owner = root.gui_get_focus_owner()
	assert(owner != null)
	print("pause focus: ", owner.text)

	# 実績画面を開いて、Bで戻る（ゲームは再開しない）
	ui.get("_achievements_button").pressed.emit()
	await process_frame
	assert(ui.get("achievements_screen").visible)
	_pad_button(JOY_BUTTON_B, true)
	await process_frame
	_pad_button(JOY_BUTTON_B, false)
	await process_frame
	assert(ui.get("pause_screen").visible, "B should close achievements and return to pause")
	assert(int(main.get("state")) == 3)

	# もう一度Bで再開
	_pad_button(JOY_BUTTON_B, true)
	await process_frame
	_pad_button(JOY_BUTTON_B, false)
	await process_frame
	assert(int(main.get("state")) == 1, "B on the pause menu should resume")

	# Yで終業を試みる：最低量未満なので終わらない
	var day0: int = gs.day
	_pad_button(JOY_BUTTON_Y, true)
	await process_frame
	_pad_button(JOY_BUTTON_Y, false)
	await process_frame
	assert(gs.day == day0 and int(main.get("state")) == 1, "Y below the minimum must not end the day")
	main.set("grams_today", 200)
	_pad_button(JOY_BUTTON_Y, true)
	await process_frame
	_pad_button(JOY_BUTTON_Y, false)
	await process_frame
	assert(gs.day == day0 + 1 and int(main.get("state")) == 2, "Y after the minimum should end the day")

	print("PAD TEST OK")
	quit(0)
