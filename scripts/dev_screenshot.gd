# 開発用：コマンドラインから画面写真を撮って終了する。
#   godot --path . -- --shot=play --out=/tmp/play.png --lang=ja
# shot の種類: title / play / shop
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
	if _frame == 10 and shot == "play":
		# 自動で帯状にむいて途中経過を見せる
		var p: Potato = main.potato
		for i in 5:
			var a := Vector3(-0.8, 0.9 - i * 0.35, 0.6).normalized()
			var b := Vector3(0.8, 0.9 - i * 0.35, 0.6).normalized()
			p.peel_stroke(a, b, GameState.peel_radius())
		main._peeling = true
	if _frame == 12 and shot == "shop":
		main.peeled_today = GameState.quota_for_day()
		main.earned_today = 50
		main._end_day()
	if _frame == 40:
		var img := get_viewport().get_texture().get_image()
		var out: String = _args.get("out", "user://shot.png")
		img.save_png(out)
		print("saved screenshot: ", out)
		get_tree().quit()
