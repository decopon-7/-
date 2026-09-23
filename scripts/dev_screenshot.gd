# 開発用：コマンドラインから画面写真を撮って終了する。
#   godot --path . -- --shot=mince --out=/tmp/mince.png --lang=ja
# shot の種類: title / cut / mince / shop
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
	if shot in ["cut", "mince"]:
		var o: Onion = main.onion
		if _frame == 30:
			# 工程1: 縦の切り込みを等間隔に
			var n := int(ceil(o.rx * 2.0 / 0.02))
			for i in range(1, n):
				main.chop_at(o.global_position.x - o.rx + i * o.rx * 2.0 / n)
		if _frame == 90:
			# 工程2: 横に刻む（cut では途中まで）
			var n := int(ceil(o.rz * 2.0 / 0.02))
			var upto := n if shot == "mince" else n / 2
			for i in range(1, upto):
				main.chop_at(o.global_position.x - o.rz + i * o.rz * 2.0 / n)
		if _frame == 150 and shot == "mince":
			for k in 3:
				for i in 14:
					main.chop_at(o.global_position.x - 0.07 + i * 0.01 + k * 0.003)
			main.tears = 0.85
		if _frame == 150 and shot == "cut":
			main._knife_x = o.global_position.x + 0.012
	if _frame == 12 and shot == "shop":
		main.grams_today = GameState.quota_for_day()
		main.earned_today = 45
		main._end_day()
	if _frame == 220:
		var img := get_viewport().get_texture().get_image()
		var out: String = _args.get("out", "user://shot.png")
		img.save_png(out)
		print("saved screenshot: ", out, "  progress=", main.onion.get_progress() if main.onion else -1.0)
		get_tree().quit()
