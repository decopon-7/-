# 開発用の自動テスト：全種類の注文で、玉ねぎを最後（DONE）まで切れるか確かめる。
#   godot --headless --path . -s tools/selftest.gd
# 成功なら "ALL OK" を出して終了コード 0、失敗なら 1。
extends SceneTree

const GameStateScript := preload("res://scripts/game_state.gd")
const OnionScript := preload("res://scripts/onion.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed := false
	for id in GameStateScript.ORDER_IDS:
		var order: Dictionary = GameStateScript.ORDERS[id]
		var onion: Node3D = OnionScript.new()
		onion.configure(id, order)
		root.add_child(onion)
		var chops := 0
		while onion.phase != OnionScript.Phase.DONE and chops < 2000:
			if onion.is_busy():
				await process_frame
				continue
			if onion.phase == OnionScript.Phase.MINCE:
				# 左右に往復しながらトントン
				var sweep := chops % 60
				var x := -0.08 + (sweep if sweep < 30 else 60 - sweep) * 0.0055
				onion.chop(x, 0.004)
				chops += 1
				if chops % 20 == 0:
					await process_frame
			else:
				# 許容間隔より少し狭い間隔で端から切っていく
				var r: float = onion.rx if onion.phase == OnionScript.Phase.LENGTHWISE else onion.rz
				var step: float = onion.gap_max * 0.8
				var x := -r + step
				while x < r and not onion.is_busy() and onion.phase != OnionScript.Phase.DONE:
					onion.chop(x, 0.004)
					chops += 1
					x += step
				await process_frame
		var ok: bool = onion.phase == OnionScript.Phase.DONE
		failed = failed or not ok
		print("%-9s %s  chops=%d" % [id, "OK  " if ok else "FAIL", chops])
		onion.queue_free()
		await process_frame
	print("ALL OK" if not failed else "SOME FAILED")
	quit(1 if failed else 0)
