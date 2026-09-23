# 日本語・英語のテキスト表。
# 翻訳を増やすときは STRINGS に言語コードを足し、LOCALES にも追加する。
class_name I18n
extends RefCounted

const LOCALES := ["ja", "en"]

const STRINGS := {
	"TITLE_NAME": {"ja": "涙のみじん切り", "en": "Onion Tears"},
	"TITLE_SUB": {"ja": "泣いても刻め。開店まであと少し。", "en": "Chop through the tears. The diner opens soon."},
	"BTN_CONTINUE": {"ja": "つづきから（%d日目）", "en": "Continue (Day %d)"},
	"BTN_NEW_GAME": {"ja": "はじめから", "en": "New Game"},
	"BTN_LANGUAGE": {"ja": "Language: 日本語", "en": "言語: English"},
	"BTN_QUIT": {"ja": "終了", "en": "Quit"},

	"HUD_DAY": {"ja": "%d日目の仕込み", "en": "Day %d prep"},
	"HUD_TIME": {"ja": "開店まで %d:%02d", "en": "Opening in %d:%02d"},
	"HUD_QUOTA": {"ja": "ノルマ %d / %d g", "en": "Quota %d / %d g"},
	"HUD_MONEY": {"ja": "所持金 %d 円", "en": "Funds $%d"},
	"HUD_TEARS": {"ja": "涙", "en": "Tears"},
	"STEP_LENGTHWISE": {"ja": "1/3 縦に切り込みを入れる", "en": "1/3 Slice lengthwise"},
	"STEP_CROSSWISE": {"ja": "2/3 横に刻む", "en": "2/3 Cut crosswise"},
	"STEP_MINCE": {"ja": "3/3 トントン細かく", "en": "3/3 Mince it fine"},
	"STEP_DONE": {"ja": "できあがり！", "en": "Done!"},
	"HUD_HINT": {
		"ja": "マウス左右: 包丁の位置　左クリック / スペース（長押しOK）: 切る　Esc: メニュー",
		"en": "Move mouse: knife position   LMB / Space (hold OK): chop   Esc: menu",
	},
	"HUD_GAP_HINT": {"ja": "赤い印のところの間隔が広すぎます", "en": "Cuts too far apart at the red marks"},
	"HUD_END_SHIFT": {"ja": "早めに切り上げる", "en": "Finish early"},
	"POP_ONION": {"ja": "+%d g　+%d 円", "en": "+%d g  +$%d"},
	"POP_PROCESSOR": {"ja": "プロセッサー +%d g", "en": "Processor +%d g"},
	"POP_TEARS": {"ja": "目が、目がぁ…！", "en": "My eyes...!"},

	"END_OK": {"ja": "ノルマ達成！", "en": "Quota met!"},
	"END_FAIL": {"ja": "ノルマ未達…", "en": "Quota missed..."},
	"END_BODY": {
		"ja": "刻んだ量: %d g（ノルマ %d g）\n今日の稼ぎ: %d 円",
		"en": "Minced: %d g (quota %d g)\nEarned today: $%d",
	},
	"END_BONUS": {"ja": "達成ボーナス: +%d 円", "en": "Quota bonus: +$%d"},
	"END_RETRY_NOTE": {
		"ja": "明日は同じノルマに再挑戦です。",
		"en": "You will retry the same quota tomorrow.",
	},

	"SHOP_TITLE": {"ja": "厨房道具屋", "en": "Kitchen Supply"},
	"SHOP_LEVEL": {"ja": "Lv %d / %d", "en": "Lv %d / %d"},
	"SHOP_BUY": {"ja": "%d 円で購入", "en": "Buy $%d"},
	"SHOP_MAX": {"ja": "最大", "en": "MAX"},
	"UPG_KNIFE": {"ja": "よく切れる包丁", "en": "Sharper Knife"},
	"UPG_KNIFE_DESC": {"ja": "みじん切りで一度に刻める幅が広がる", "en": "Mince a wider strip per chop"},
	"UPG_GOGGLES": {"ja": "玉ねぎゴーグル", "en": "Onion Goggles"},
	"UPG_GOGGLES_DESC": {"ja": "涙が出にくくなる", "en": "Fewer tears"},
	"UPG_PROCESSOR": {"ja": "フードプロセッサー", "en": "Food Processor"},
	"UPG_PROCESSOR_DESC": {"ja": "一定時間ごとに自動で100g刻んでくれる", "en": "Minces 100 g automatically every few seconds"},
	"UPG_CONTRACT": {"ja": "仕入れ先と値段交渉", "en": "Better Deal"},
	"UPG_CONTRACT_DESC": {"ja": "100gあたりの報酬アップ", "en": "More pay per 100 g"},

	"BTN_START_DAY": {"ja": "仕込み開始", "en": "Start prep"},
	"PAUSE_TITLE": {"ja": "一時停止", "en": "Paused"},
	"BTN_RESUME": {"ja": "再開", "en": "Resume"},
	"BTN_TO_TITLE": {"ja": "タイトルへ（自動保存）", "en": "Back to title (autosave)"},
}


static func register() -> void:
	for locale in LOCALES:
		var t := Translation.new()
		t.locale = locale
		for key in STRINGS:
			t.add_message(key, STRINGS[key][locale])
		TranslationServer.add_translation(t)


static func next_locale(current: String) -> String:
	var i := LOCALES.find(current.substr(0, 2))
	return LOCALES[(i + 1) % LOCALES.size()]
