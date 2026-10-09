# セーブデータと成長要素（アップグレード）を管理するシングルトン。
# project.godot の [autoload] で "GameState" として登録している。
extends Node

const I18nTable := preload("res://scripts/i18n.gd")
const SAVE_PATH := "user://save.json"

## 包丁を振り下ろせる間隔（秒）
const CHOP_COOLDOWN := 0.11

const UPGRADE_IDS := ["knife", "goggles", "processor", "contract"]
const UPGRADES := {
	"knife": {"name": "UPG_KNIFE", "desc": "UPG_KNIFE_DESC", "base_cost": 50, "growth": 1.7, "max": 5},
	"goggles": {"name": "UPG_GOGGLES", "desc": "UPG_GOGGLES_DESC", "base_cost": 60, "growth": 1.8, "max": 4},
	"processor": {"name": "UPG_PROCESSOR", "desc": "UPG_PROCESSOR_DESC", "base_cost": 250, "growth": 1.8, "max": 5},
	"contract": {"name": "UPG_CONTRACT", "desc": "UPG_CONTRACT_DESC", "base_cost": 80, "growth": 1.75, "max": 5},
}

## 注文の種類。day 日目から出てくる。
##   steps: 工程（L=縦に切り込み, C=横に刻む, M=トントン細かく）
##   gap:   切れ目の間隔の上限（メートル）
##   size:  みじん切りの目標サイズ（メートル）
##   pay:   報酬の倍率
## 実績。base はすべて揃うとゴールドの見た目（skin_tier=1）を解禁する。
## day40 / grams20000 はその上の特別な実績で、順にプラチナ（2）・ダイヤ（3）へ格上げする。
## bowl_* は称号には関わらない、1日の仕込み量に対するおまけの実績（3段階）。
## knife_only も同様に称号には関わらない：フードプロセッサーを一度も稼働させないまま
## （買うだけは買ってもよい）累計3000g刻んだら解除する、包丁一本の職人向けの実績。
const BASE_ACHIEVEMENT_IDS := ["knife_max", "goggles_max", "processor_max", "contract_max",
		"day10", "money1000", "golden1", "grams3000"]
const TIER_ACHIEVEMENT_IDS := ["day40", "grams20000"]
const BOWL_ACHIEVEMENT_IDS := ["bowl1000", "bowl2500", "bowl5000"]
const KNIFE_ONLY_ACHIEVEMENT_IDS := ["knife_only"]
const ALL_ACHIEVEMENT_IDS := BASE_ACHIEVEMENT_IDS + TIER_ACHIEVEMENT_IDS \
		+ BOWL_ACHIEVEMENT_IDS + KNIFE_ONLY_ACHIEVEMENT_IDS
## "hint" がある実績は、解除するまで説明の一部を「???」で隠す（何を目指すかだけ分かる、ちょっとした秘密）
const ACHIEVEMENTS := {
	"knife_max": {"name": "ACH_KNIFE_MAX", "desc": "ACH_KNIFE_MAX_DESC"},
	"goggles_max": {"name": "ACH_GOGGLES_MAX", "desc": "ACH_GOGGLES_MAX_DESC"},
	"processor_max": {"name": "ACH_PROCESSOR_MAX", "desc": "ACH_PROCESSOR_MAX_DESC"},
	"contract_max": {"name": "ACH_CONTRACT_MAX", "desc": "ACH_CONTRACT_MAX_DESC"},
	"day10": {"name": "ACH_DAY10", "desc": "ACH_DAY10_DESC"},
	"money1000": {"name": "ACH_MONEY1000", "desc": "ACH_MONEY1000_DESC"},
	"golden1": {"name": "ACH_GOLDEN1", "desc": "ACH_GOLDEN1_DESC"},
	"grams3000": {"name": "ACH_GRAMS3000", "desc": "ACH_GRAMS3000_DESC"},
	"day40": {"name": "ACH_DAY40", "desc": "ACH_DAY40_DESC"},
	"grams20000": {"name": "ACH_GRAMS20000", "desc": "ACH_GRAMS20000_DESC", "hint": "ACH_GRAMS20000_HINT"},
	"bowl1000": {"name": "ACH_BOWL1000", "desc": "ACH_BOWL1000_DESC"},
	"bowl2500": {"name": "ACH_BOWL2500", "desc": "ACH_BOWL2500_DESC", "hint": "ACH_BOWL_HINT"},
	"bowl5000": {"name": "ACH_BOWL5000", "desc": "ACH_BOWL5000_DESC", "hint": "ACH_BOWL_HINT"},
	"knife_only": {"name": "ACH_KNIFE_ONLY", "desc": "ACH_KNIFE_ONLY_DESC", "hint": "ACH_KNIFE_ONLY_HINT"},
}
## 見た目の称号。0=なし 1=ゴールド 2=プラチナ 3=ダイヤ
const SKIN_NAMES := ["", "SKIN_GOLD", "SKIN_PLATINUM", "SKIN_DIAMOND"]

## 主人公の日記が出てくる日。40日目だけは特別で、遊び方によって内容が分岐する（複数エンド）
const DIARY_DAYS := [1, 2, 3, 5, 7, 10, 13, 16, 20, 24, 28, 32, 36, 40]
const ENDING_DAY := 40

const ORDER_IDS := ["hamburg", "curry", "soup", "dressing"]
const ORDERS := {
	"hamburg": {"name": "ORDER_HAMBURG", "style": "STYLE_MINCE", "day": 1, "pay": 1.0,
			"steps": ["L", "C", "M"], "gap": 0.024, "size": 0.006},
	"curry": {"name": "ORDER_CURRY", "style": "STYLE_COARSE", "day": 2, "pay": 0.8,
			"steps": ["L", "C", "M"], "gap": 0.03, "size": 0.011},
	"soup": {"name": "ORDER_SOUP", "style": "STYLE_SLICE", "day": 3, "pay": 1.1,
			"steps": ["C"], "gap": 0.009},
	"dressing": {"name": "ORDER_DRESSING", "style": "STYLE_FINE", "day": 4, "pay": 1.6,
			"steps": ["L", "C", "M"], "gap": 0.02, "size": 0.0045},
}

signal achievement_unlocked(id: String)
signal skin_tier_changed(tier: int)

var day := 1
var money := 0
var total_grams := 0
var golden_onions := 0
var levels := {}
var achievements := {}
var skin_tier := 0
## フードプロセッサーが一度でも自動で刻んだら true（knife_only 実績の判定用。買うだけなら影響しない）
var processor_used := false
## 読んだ日記の日付（回想機能で「まだ読んでいない」ものを伏せるため）
var diary_seen := {}
## 最終日（ENDING_DAY）に決まる分岐エンド。一度決まったら固定（"master" / "bonds" / "quiet"）
var ending_id := ""
var locale := ""
## 音量は 0.0〜1.0。実際にバスへ反映するのは Sfx 側
## （オートロードの順番上、Sfx のバスがまだ無い時点でここから触れないため）
var sound_volume := 1.0
var music_volume := 1.0
var fullscreen := false
## 厨房の掛け時計と窓の外を、遊んでいる人の実際の時刻に合わせるか。
## 配信で自分の時刻を見せたくない人のために、オフにすると時刻は決まった値で固定される
var clock_sync := true


func _ready() -> void:
	I18nTable.register()
	reset()
	load_game()
	if locale == "":
		locale = "ja" if OS.get_locale_language() == "ja" else "en"
	TranslationServer.set_locale(locale)
	_apply_window_settings()


func _apply_window_settings() -> void:
	get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED


func reset() -> void:
	day = 1
	money = 0
	total_grams = 0
	golden_onions = 0
	levels = {}
	for id in UPGRADE_IDS:
		levels[id] = 0
	achievements = {}
	skin_tier = 0
	processor_used = false
	diary_seen = {}
	ending_id = ""


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# ---- バランス調整用の数式はここに集約 ----

## 100gあたりの報酬
func price_per_100g() -> int:
	return 15 + levels["contract"] * 6


func pay_for(grams: int, multiplier: float = 1.0) -> int:
	return int(round(grams * price_per_100g() / 100.0 * multiplier))


## 今日までに解禁された注文
func orders_for_day(d: int = day) -> Array:
	return ORDER_IDS.filter(func(id): return ORDERS[id]["day"] <= d)


## 今日はじめて出てくる注文（なければ空）
func new_orders_today() -> Array:
	return ORDER_IDS.filter(func(id): return ORDERS[id]["day"] == day)


## みじん切り工程で包丁が届く幅（片側・メートル）
func chop_reach() -> float:
	return 0.004 + levels["knife"] * 0.0025


## 涙のたまりやすさ（1 が素の状態）
func tear_multiplier() -> float:
	return 1.0 - levels["goggles"] * 0.2


## フードプロセッサーが100g刻むのにかかる秒数。0 なら未所持。
func processor_interval() -> float:
	var lv: int = levels["processor"]
	return 0.0 if lv == 0 else 20.0 / lv


func upgrade_cost(id: String) -> int:
	var u: Dictionary = UPGRADES[id]
	return int(u["base_cost"] * pow(u["growth"], levels[id]))


func is_maxed(id: String) -> bool:
	return levels[id] >= UPGRADES[id]["max"]


func can_buy(id: String) -> bool:
	return not is_maxed(id) and money >= upgrade_cost(id)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	money -= upgrade_cost(id)
	levels[id] += 1
	save_game()
	check_achievements()
	return true


## 最終日（ENDING_DAY）に、それまでの遊び方から進む道を決める（複数エンド）。
## 道具を鍛え上げた「職人」／幸運を何度も引き当てた「絆」／どちらでもない「静かな日々」の3択。
## 優先度は職人 > 絆 > 静かな日々（両方の条件を満たしても職人を優先）
func determine_ending() -> String:
	var maxed_count := 0
	for id in UPGRADE_IDS:
		if is_maxed(id):
			maxed_count += 1
	if maxed_count >= 3:
		return "master"
	if golden_onions >= 3:
		return "bonds"
	return "quiet"


# ---- 実績・見た目の称号 ----

## grams_today は main.gd 側でその日ボウルに刻んだ量（呼び出し元が持っている値をそのまま渡す）
func _achievement_condition(id: String, grams_today: int) -> bool:
	match id:
		"knife_max": return is_maxed("knife")
		"goggles_max": return is_maxed("goggles")
		"processor_max": return is_maxed("processor")
		"contract_max": return is_maxed("contract")
		"day10": return day >= 10
		"money1000": return money >= 1000
		"golden1": return golden_onions >= 1
		"grams3000": return total_grams >= 3000
		"day40": return day >= 40
		"grams20000": return total_grams >= 20000
		"bowl1000": return grams_today >= 1000
		"bowl2500": return grams_today >= 2500
		"bowl5000": return grams_today >= 5000
		"knife_only": return total_grams >= 3000 and not processor_used
		_: return false


func base_achievements_complete() -> bool:
	return BASE_ACHIEVEMENT_IDS.all(func(id): return achievements.get(id, false))


func _recompute_skin_tier() -> void:
	var tier := 0
	if base_achievements_complete():
		tier = 1
		if achievements.get("day40", false):
			tier = 2
			if achievements.get("grams20000", false):
				tier = 3
	if tier != skin_tier:
		skin_tier = tier
		skin_tier_changed.emit(skin_tier)


## 実績条件をまとめて確認し、新しく解除したものがあれば通知する。
## アップグレード購入・報酬受け取り・幸運の玉ねぎ・日の開始など、状況が変わるたびに呼ぶ。
## grams_today は省略可（省略時は0。ボウル関連の実績はそのぶん判定を持ち越す）
func check_achievements(grams_today: int = 0) -> void:
	var unlocked_any := false
	for id in ALL_ACHIEVEMENT_IDS:
		if achievements.get(id, false):
			continue
		if _achievement_condition(id, grams_today):
			achievements[id] = true
			unlocked_any = true
			achievement_unlocked.emit(id)
	_recompute_skin_tier()
	if unlocked_any:
		save_game()


## live: 値を反映するだけ（スライダーを動かしている最中など）。false ならセーブまで行う。
func set_sound_volume(value: float, live: bool = false) -> void:
	sound_volume = clampf(value, 0.0, 1.0)
	Sfx.set_sound_volume(sound_volume)
	if not live:
		save_game()


func set_music_volume(value: float, live: bool = false) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	Sfx.set_music_volume(music_volume)
	if not live:
		save_game()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_window_settings()
	save_game()


func set_clock_sync(value: bool) -> void:
	clock_sync = value
	save_game()


func set_locale(value: String) -> void:
	locale = value
	TranslationServer.set_locale(locale)
	save_game()


# ---- セーブ / ロード ----

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("セーブに失敗しました: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify({
		"version": 5,
		"day": day,
		"money": money,
		"total_grams": total_grams,
		"golden_onions": golden_onions,
		"processor_used": processor_used,
		"levels": levels,
		"achievements": achievements,
		"diary_seen": diary_seen,
		"ending_id": ending_id,
		"locale": locale,
		"sound_volume": sound_volume,
		"music_volume": music_volume,
		"fullscreen": fullscreen,
		"clock_sync": clock_sync,
	}, "\t"))


func load_game() -> void:
	if not has_save():
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("セーブデータが壊れています。新規で開始します。")
		return
	day = int(data.get("day", 1))
	money = int(data.get("money", 0))
	total_grams = int(data.get("total_grams", 0))
	golden_onions = int(data.get("golden_onions", 0))
	processor_used = bool(data.get("processor_used", false))
	locale = str(data.get("locale", ""))
	# version 2 以前（オン/オフの2択）からの引き継ぎ。新しい保存にはもう出てこない
	sound_volume = float(data.get("sound_volume", 0.0 if data.get("muted", false) else 1.0))
	music_volume = float(data.get("music_volume", 1.0 if data.get("music_on", true) else 0.0))
	fullscreen = bool(data.get("fullscreen", false))
	clock_sync = bool(data.get("clock_sync", true))
	var saved_levels: Dictionary = data.get("levels", {})
	for id in UPGRADE_IDS:
		levels[id] = clampi(int(saved_levels.get(id, 0)), 0, UPGRADES[id]["max"])
	var saved_achievements: Dictionary = data.get("achievements", {})
	achievements = {}
	for id in ALL_ACHIEVEMENT_IDS:
		if saved_achievements.get(id, false):
			achievements[id] = true
	_recompute_skin_tier()
	var saved_diary: Dictionary = data.get("diary_seen", {})
	diary_seen = {}
	for d in DIARY_DAYS:
		# JSONの辞書キーは文字列になるため、日付(int)を文字列にして引く
		if saved_diary.get(str(d), false):
			diary_seen[d] = true
	ending_id = str(data.get("ending_id", ""))
	# version 4 以前のセーブデータで、既に最終日を過ぎている場合は、現在の状態からさかのぼって決める
	if ending_id == "" and day > ENDING_DAY:
		ending_id = determine_ending()
		diary_seen[ENDING_DAY] = true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var keep_locale := locale
	reset()
	locale = keep_locale
