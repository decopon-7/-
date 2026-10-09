# 掛け時計の「実際の時刻に合わせる／合わせない」設定の自動テスト。
#   godot --headless --path . -s tools/test_clock.gd
# 成功なら "CLOCK TEST OK" を出して終了コード 0。
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var gs := root.get_node("GameState")
	var kitchen = main.get("kitchen")
	var ui = main.get("ui")

	# オン：実際の時刻（システム時計）と一致する
	gs.set_clock_sync(true)
	var t := Time.get_time_dict_from_system()
	var real: float = t["hour"] + t["minute"] / 60.0
	var h: float = kitchen.call("_now_hour")
	print("sync on: ", h, " real=", real)
	assert(absf(h - real) < 0.05 or absf(absf(h - real) - 24.0) < 0.05, "should follow the system clock")

	# オフ：固定の時刻（見る人の実際の時刻は出ない）
	gs.set_clock_sync(false)
	await process_frame
	h = kitchen.call("_now_hour")
	print("sync off: ", h)
	assert(absf(h - float(kitchen.FIXED_HOUR)) < 0.0001, "should show the fixed time")
	# 針も固定（短針は10時台、長針は10分）
	assert(absf(kitchen.get("_hour_hand").rotation.z + TAU * fmod(kitchen.FIXED_HOUR, 12.0) / 12.0) < 0.01, "hour hand should point at 10")
	assert(absf(kitchen.get("_minute_hand").rotation.z + TAU * 10.0 / 60.0) < 0.01, "minute hand should point at 10 min")

	# ボタン：タイトルと一時停止の両方にあり、押すと切り替わり、保存される
	ui.get("_title_clock_button").pressed.emit()
	assert(gs.clock_sync == true)
	ui.get("_clock_button").pressed.emit()
	assert(gs.clock_sync == false)
	print("title button text: ", ui.get("_title_clock_button").text)
	var cfg = JSON.parse_string(FileAccess.get_file_as_string(gs.SAVE_PATH))
	assert(cfg["clock_sync"] == false, "setting should be saved")
	print("CLOCK TEST OK")
	quit(0)
