# セーブデータと成長要素（アップグレード）を管理するシングルトン。
# project.godot の [autoload] で "GameState" として登録している。
extends Node

const I18nTable := preload("res://scripts/i18n.gd")
const SAVE_PATH := "user://save.json"

## 1日の仕込み時間（秒）
const DAY_LENGTH := 150.0
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

var day := 1
var money := 0
var total_grams := 0
var levels := {}
var locale := ""
var muted := false
var music_on := true


func _ready() -> void:
	I18nTable.register()
	reset()
	load_game()
	if locale == "":
		locale = "ja" if OS.get_locale_language() == "ja" else "en"
	TranslationServer.set_locale(locale)
	AudioServer.set_bus_mute(0, muted)


func reset() -> void:
	day = 1
	money = 0
	total_grams = 0
	levels = {}
	for id in UPGRADE_IDS:
		levels[id] = 0


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# ---- バランス調整用の数式はここに集約 ----

## その日のノルマ（グラム）
func quota_for_day(d: int = day) -> int:
	return 200 + d * 100


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


func quota_bonus() -> int:
	return int(quota_for_day() / 10.0)


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
	return true


func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, muted)
	save_game()


func set_music_on(value: bool) -> void:
	music_on = value
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
		"version": 2,
		"day": day,
		"money": money,
		"total_grams": total_grams,
		"levels": levels,
		"locale": locale,
		"muted": muted,
		"music_on": music_on,
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
	locale = str(data.get("locale", ""))
	muted = bool(data.get("muted", false))
	music_on = bool(data.get("music_on", true))
	var saved_levels: Dictionary = data.get("levels", {})
	for id in UPGRADE_IDS:
		levels[id] = clampi(int(saved_levels.get(id, 0)), 0, UPGRADES[id]["max"])


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var keep_locale := locale
	reset()
	locale = keep_locale
