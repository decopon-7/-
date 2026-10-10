# 累計の量による実績（total10000 / total50000 / total100000）と、ボウル実績との独立性の自動テスト。
#   godot --headless --path . -s tools/test_achievements.gd
# 成功なら "ACHIEVEMENT TEST OK" を出して終了コード 0。
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var gs := root.get_node("GameState")
	gs.reset()

	var unlocked: Array = []
	gs.achievement_unlocked.connect(func(id): unlocked.append(id))

	# 手前の段階では解除されない
	gs.total_grams = 9999
	gs.check_achievements(0)
	assert(not gs.achievements.get("total10000", false), "9999 g should not unlock total10000")

	# 10000g ちょうどで1段階目だけ
	gs.total_grams = 10000
	gs.check_achievements(0)
	assert(gs.achievements.get("total10000", false))
	assert(not gs.achievements.get("total50000", false))

	# 1日の量のボウル実績とは独立（累計が増えても、その日の量が足りなければ bowl は解除されない）
	assert(not gs.achievements.get("bowl1000", false), "bowl1000 depends on grams_today")

	# 既に大量に刻んだセーブを読み込んだ場合は、残りがまとめて解除される
	gs.total_grams = 120000
	gs.check_achievements(0)
	assert(gs.achievements.get("total50000", false) and gs.achievements.get("total100000", false))
	print("unlocked order: ", unlocked)
	assert(unlocked.count("total10000") == 1, "must not unlock twice")

	# 称号（ゴールド等）には関わらない
	assert(not gs.TOTAL_ACHIEVEMENT_IDS.any(func(id): return id in gs.BASE_ACHIEVEMENT_IDS))
	assert(gs.skin_tier == 0)

	# 全体の数・ACHIEVEMENTS の定義が揃っている（解除済みの説明が隠れない／未解除のヒントが定義されている）
	for id in gs.ALL_ACHIEVEMENT_IDS:
		assert(gs.ACHIEVEMENTS.has(id), "missing definition: " + id)
	print("achievements: ", gs.ALL_ACHIEVEMENT_IDS.size())
	assert(gs.ALL_ACHIEVEMENT_IDS.size() == 17)

	# 保存して読み直しても残る
	gs.save_game()
	gs.reset()
	gs.load_game()
	assert(gs.achievements.get("total100000", false), "should persist")
	print("ACHIEVEMENT TEST OK")
	quit(0)
