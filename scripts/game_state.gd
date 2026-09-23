# セーブデータと成長要素（アップグレード）を管理するシングルトン。
# project.godot の [autoload] で "GameState" として登録している。
extends Node

const I18nTable := preload("res://scripts/i18n.gd")
const SAVE_PATH := "user://save.json"

## 1日の勤務時間（秒）
const DAY_LENGTH := 150.0
## むき終わりとみなす割合
const PEEL_DONE_RATIO := 0.93

const UPGRADE_IDS := ["peeler", "turntable", "machine", "contract"]
const UPGRADES := {
	"peeler": {"name": "UPG_PEELER", "desc": "UPG_PEELER_DESC", "base_cost": 40, "growth": 1.7, "max": 5},
	"turntable": {"name": "UPG_TURNTABLE", "desc": "UPG_TURNTABLE_DESC", "base_cost": 120, "growth": 2.0, "max": 3},
	"machine": {"name": "UPG_MACHINE", "desc": "UPG_MACHINE_DESC", "base_cost": 250, "growth": 1.8, "max": 5},
	"contract": {"name": "UPG_CONTRACT", "desc": "UPG_CONTRACT_DESC", "base_cost": 80, "growth": 1.75, "max": 5},
}

var day := 1
var money := 0
var total_peeled := 0
var levels := {}
var locale := ""


func _ready() -> void:
	I18nTable.register()
	reset()
	load_game()
	if locale == "":
		locale = "ja" if OS.get_locale_language() == "ja" else "en"
	TranslationServer.set_locale(locale)


func reset() -> void:
	day = 1
	money = 0
	total_peeled = 0
	levels = {}
	for id in UPGRADE_IDS:
		levels[id] = 0


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# ---- バランス調整用の数式はここに集約 ----

func quota_for_day(d: int = day) -> int:
	return 3 + d * 2


func price_per_potato() -> int:
	return 10 + levels["contract"] * 5


func quota_bonus() -> int:
	return quota_for_day() * 5


## ピーラーの刃の幅（単位球上の角度・ラジアン）
func peel_radius() -> float:
	return 0.16 + levels["peeler"] * 0.035


## 自動回転台の速度（ラジアン/秒）
func turntable_speed() -> float:
	return levels["turntable"] * 0.9


## 皮むき機が1個むくのにかかる秒数。0 なら未所持。
func machine_interval() -> float:
	var lv: int = levels["machine"]
	return 0.0 if lv == 0 else 18.0 / lv


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
		"version": 1,
		"day": day,
		"money": money,
		"total_peeled": total_peeled,
		"levels": levels,
		"locale": locale,
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
	total_peeled = int(data.get("total_peeled", 0))
	locale = str(data.get("locale", ""))
	var saved_levels: Dictionary = data.get("levels", {})
	for id in UPGRADE_IDS:
		levels[id] = clampi(int(saved_levels.get(id, 0)), 0, UPGRADES[id]["max"])


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var keep_locale := locale
	reset()
	locale = keep_locale
