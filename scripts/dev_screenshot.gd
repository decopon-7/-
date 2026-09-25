# 開発用：コマンドラインから画面写真を撮って終了する。
#   godot --path . -- --shot=mince --out=/tmp/mince.png --lang=ja
# shot の種類: title / cut / mince / shop / fresh / complete　（--order=soup などで注文を指定できる）
#   fresh: 1回も切っていない、まっさらな玉ねぎ（回転・スケールが落ち着いた状態）
#   complete: 1品を完成させ、ヒットストップ・きらめき演出まで通す
extends Node

var _args := {}
var _frame := 0


static func requested() -> bool:
	return _parse().has("shot")


static func _parse() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1]
	return d


func _ready() -> void:
	_args = _parse()
	if _args.has("lang"):
		GameState.set_locale(_args["lang"])
		get_parent().ui.refresh_texts()


func _process(_delta: float) -> void:
	_frame += 1
	var main := get_parent()
	var shot: String = _args["shot"]
	if _frame == 5 and shot != "title":
		main._start_day()
		GameState.money = 480
		if _args.has("order"):
			# 指定した注文の玉ねぎに入れ替える
			main.onion.queue_free()
			main.onion = null
			main.order_queue.push_front(_args["order"])
			main._spawn_onion(false)
	if shot in ["cut", "mince", "complete"]:
		var o: Onion = main.onion
		if _frame == 30:
			# 工程1: 縦の切り込みを等間隔に
			var n := int(ceil(o.rx * 2.0 / 0.02))
			for i in range(1, n):
				main.chop_at(o.global_position.x - o.rx + i * o.rx * 2.0 / n)
		if _frame == 90:
			# 工程2: 横に刻む（cut では途中まで）
			var n := int(ceil(o.rz * 2.0 / 0.02))
			@warning_ignore("integer_division")
			var upto := n if shot == "mince" else n / 2  # 整数同士の割り算でOK（半分の個数）
			for i in range(1, upto):
				main.chop_at(o.global_position.x - o.rz + i * o.rz * 2.0 / n)
		if _frame == 150 and shot == "mince":
			for k in 3:
				for i in 14:
					main.chop_at(o.global_position.x - 0.07 + i * 0.01 + k * 0.003)
			main.tears = 0.85
		if _frame == 30 and shot == "complete":
			# 工程1: 一気に細かく切り込みを入れる
			for i in range(1, 20):
				main.chop_at(o.global_position.x - o.rx + i * o.rx * 2.0 / 20)
		if _frame == 90 and shot == "complete":
			# 工程2: 一気に細かく刻む
			for i in range(1, 20):
				main.chop_at(o.global_position.x - o.rz + i * o.rz * 2.0 / 20)
		if _frame == 150 and shot == "complete":
			# 目標サイズ以下になるまで徹底的に刻んで、完成（ヒットストップ・きらめき）まで通す
			for pass_i in 30:
				for i in 20:
					main.chop_at(o.global_position.x - 0.08 + i * 0.008)
		if _frame == 150 and shot == "cut":
			main._knife_x = o.global_position.x + 0.012
	if _frame == 90 and shot == "fresh":
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args.get("out", "user://shot.png"))
		print("saved fresh screenshot")
		get_tree().quit()
	if _frame == 12 and shot == "shop":
		main.grams_today = 300
		main.earned_today = 45
		main._end_day()
	if _frame == 220:
		var img := get_viewport().get_texture().get_image()
		var out: String = _args.get("out", "user://shot.png")
		img.save_png(out)
		print("saved screenshot: ", out, "  progress=", main.onion.get_progress() if main.onion else -1.0)
		get_tree().quit()
