# 開発用：コマンドラインから画面写真を撮って終了する。
#   godot --path . -- --shot=mince --out=/tmp/mince.png --lang=ja
# shot の種類: title / cut / mince / shop / fresh / complete / golden / knife
#   （--order=soup などで注文を指定できる）
#   fresh: 1回も切っていない、まっさらな玉ねぎ（回転・スケールが落ち着いた状態）
#   complete: 1品を完成させ、ヒットストップ・きらめき演出まで通す
#   golden: 「幸運の玉ねぎ」の見た目を確認する（本番は確率抽選、ここでは強制的に出す）
#   knife: 包丁のLv別の見た目を確認する（--knife_lv=0〜5 で指定、省略時は5＝最大Lv。--close=1 で横から寄る）
#   gear: ゴーグル・フードプロセッサー・包丁をまとめて確認する
#         （--gear_lv=0〜5 で全道具のLv、--skin=0〜3 で称号スキンを指定。省略時はLv5・称号なし）
#   achievements: 実績一覧画面を確認する（--skin=0〜3 で称号、--scroll=1 で一覧の下の方）
#   diary: 日記の回想画面を確認する（--diary_days=1,2,40 のように読んだことにする日を指定可能）
#   （cut / mince / complete に --golden=1 を付けると、幸運の玉ねぎで工程を通す）
#   （どのショットでも --pad=1 を付けると、ゲームパッド用の操作ヒントになる）
#   bowl: ボウルの中身の見た目を確認する（--bowl_grams=750 のように溜まった量を指定可能。省略時750）
#   title_withsave: セーブがある状態のタイトル画面（つづきから／はじめからの見分けやすさを確認）
#   newgame_confirm: 「はじめから」を押したときの確認ダイアログを確認する
#   room: タイトル画面の引きの画から、UIを消して厨房全体を見る（--day=12 で日めくりの日付、
#         --hour=21.5 で時計と窓の外の時刻を指定可能。--hour はどのショットでも使える）
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
	if _args.has("hour"):
		# 掛け時計と窓の外の明るさを、実際の時刻ではなく指定の時刻で確認する（例 --hour=21.5）
		get_parent().kitchen.debug_hour = float(_args["hour"])
		get_parent().kitchen._update_sky()
	if _args.get("pad", "0") == "1":
		# ゲームパッド用の操作ヒント表示を確認する
		get_parent().ui.set_hint_pad(true)


func _process(_delta: float) -> void:
	_frame += 1
	var main := get_parent()
	var shot: String = _args["shot"]
	if _frame == 5 and not shot in ["title", "title_withsave", "newgame_confirm", "room"]:
		main._start_day()
		GameState.money = 480
		if _args.has("order"):
			# 指定した注文の玉ねぎに入れ替える
			main.onion.queue_free()
			main.onion = null
			main.order_queue.push_front(_args["order"])
			main._spawn_onion(false)
	if _frame == 10 and _args.get("golden", "0") == "1" and main.onion:
		# 幸運の玉ねぎで工程を通す（みじん切りでも金色のままか確認）
		main.onion.set_golden(true)
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
	if _frame == 20 and shot == "knife":
		var lv := int(_args.get("knife_lv", 5))
		GameState.levels["knife"] = lv
		main._rebuild_knife_visual()
		main._knife_x = main.onion.global_position.x
		if _args.get("close", "0") == "1":
			# 包丁の形をよく見るため、確認用にカメラを横から寄せる
			main.onion.visible = false
			main._knife_x = 0.0
			main.camera.look_at_from_position(Vector3(0.32, 1.12, 0.18), Vector3(0.0, 1.0, 0.03))
			main.set_camera_now(main.camera.global_transform)
			main.ui.hud.visible = false
	if _frame == 20 and shot == "gear":
		var lv := int(_args.get("gear_lv", 5))
		_unlock_for_skin(int(_args.get("skin", 0)))
		GameState.levels["knife"] = clampi(lv, 0, GameState.UPGRADES["knife"]["max"])
		GameState.levels["goggles"] = clampi(lv, 0, GameState.UPGRADES["goggles"]["max"])
		GameState.levels["processor"] = clampi(lv, 0, GameState.UPGRADES["processor"]["max"])
		main._rebuild_knife_visual()
		main._rebuild_goggles_visual()
		main._rebuild_processor_visual()
		main.goggles.visible = true
		main.processor.visible = true
		main._knife_x = main.onion.global_position.x
	if _frame == 20 and shot == "achievements":
		GameState.skin_tier = int(_args.get("skin", 0))
		if _args.get("unlock", "0") == "1":
			GameState.achievements["knife_max"] = true
			GameState.achievements["day10"] = true
		main._set_state(main.State.PAUSED)
		main.ui.refresh_achievements()
		main.ui.show_only(main.ui.achievements_screen)
	if _frame == 40 and shot == "achievements" and _args.get("scroll", "0") == "1":
		# 一覧の下の方（秘密の実績など）を確認する
		main.ui._ach_scroll.scroll_vertical = 100000
	if _frame == 20 and shot == "diary":
		if _args.has("force_ending"):
			GameState.ending_id = _args["force_ending"]
		if _args.has("diary_days"):
			for tok in _args["diary_days"].split(","):
				var d := int(tok)
				GameState.diary_seen[d] = true
				if d == GameState.ENDING_DAY and GameState.ending_id == "":
					GameState.ending_id = GameState.determine_ending()
		main.ui.refresh_diary_recap()
		main.ui.show_only(main.ui.diary_screen)
	if _frame == 20 and shot == "bowl":
		main.grams_today = int(_args.get("bowl_grams", 750))
		main._update_bowl()
		# ボウルの中身がよく見えるように、確認用にカメラだけ寄せる
		# （_camera_base_transform も更新しないと、揺れ演出の復帰処理で毎フレーム元に戻ってしまう）
		main.camera.look_at_from_position(Vector3(-0.56, 1.25, 0.28), main.BOWL_POS)
		main.set_camera_now(main.camera.global_transform)
	if _frame == 20 and shot == "room":
		main.ui.title_screen.visible = false
		main.kitchen.set_day(int(_args.get("day", 1)))
	if _frame == 20 and shot == "title_withsave":
		GameState.day = 5
		GameState.save_game()
		main.ui.refresh_texts()
		main.kitchen.set_day(GameState.day)
	if _frame == 20 and shot == "newgame_confirm":
		GameState.day = 5
		GameState.save_game()
		main.ui.refresh_texts()
		main.ui.show_only(main.ui.confirm_new_game_screen)
	if _frame == 20 and shot == "pause":
		main._set_state(main.State.PAUSED)
		GameState.set_fullscreen(true)
		main.ui.refresh_texts()
	if _frame == 20 and shot == "golden":
		main.onion.set_golden(true)
		main._clean_view = true  # Hキーによる「UIを隠す」の見た目を一緒に確認
		main.ui.hud.visible = false
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


## 称号スキンは実績から毎回計算し直されるので（フードプロセッサーの稼働時など）、
## skin_tier を直接書き換えるのではなく、その称号に必要な実績を解除しておく
func _unlock_for_skin(tier: int) -> void:
	if tier >= 1:
		for id in GameState.BASE_ACHIEVEMENT_IDS:
			GameState.achievements[id] = true
	if tier >= 2:
		GameState.achievements["day40"] = true
	if tier >= 3:
		GameState.achievements["grams20000"] = true
	GameState._recompute_skin_tier()
