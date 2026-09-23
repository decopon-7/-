# 日本語・英語のテキスト表。
# 翻訳を増やすときは STRINGS に言語コードを足し、LOCALES にも追加する。
class_name I18n
extends RefCounted

const LOCALES := ["ja", "en"]

const STRINGS := {
	"TITLE_NAME": {"ja": "芋むき兵站部", "en": "Spud Duty"},
	"TITLE_SUB": {"ja": "今日も前線は腹ぺこだ。", "en": "The front line is hungry. Again."},
	"BTN_CONTINUE": {"ja": "つづきから（%d日目）", "en": "Continue (Day %d)"},
	"BTN_NEW_GAME": {"ja": "はじめから", "en": "New Game"},
	"BTN_LANGUAGE": {"ja": "Language: 日本語", "en": "言語: English"},
	"BTN_QUIT": {"ja": "終了", "en": "Quit"},

	"HUD_DAY": {"ja": "%d日目", "en": "Day %d"},
	"HUD_TIME": {"ja": "残り %d:%02d", "en": "Time %d:%02d"},
	"HUD_QUOTA": {"ja": "ノルマ %d / %d 個", "en": "Quota %d / %d"},
	"HUD_MONEY": {"ja": "所持金 %d 円", "en": "Funds $%d"},
	"HUD_PEEL": {"ja": "皮むき %d%%", "en": "Peeled %d%%"},
	"HUD_HINT": {
		"ja": "左ドラッグ: むく　右ドラッグ / WASD: 回す　Esc: メニュー",
		"en": "LMB drag: peel   RMB drag / WASD: rotate   Esc: menu",
	},
	"HUD_END_SHIFT": {"ja": "早めに上がる", "en": "End shift early"},
	"POP_POTATO": {"ja": "+%d 円", "en": "+$%d"},
	"POP_MACHINE": {"ja": "皮むき機 +1個", "en": "Machine +1"},

	"END_OK": {"ja": "ノルマ達成！", "en": "Quota met!"},
	"END_FAIL": {"ja": "ノルマ未達…", "en": "Quota missed..."},
	"END_BODY": {
		"ja": "むいた数: %d 個（ノルマ %d 個）\n今日の稼ぎ: %d 円",
		"en": "Peeled: %d (quota %d)\nEarned today: $%d",
	},
	"END_BONUS": {"ja": "達成ボーナス: +%d 円", "en": "Quota bonus: +$%d"},
	"END_RETRY_NOTE": {
		"ja": "明日は同じノルマに再挑戦です。",
		"en": "You will retry the same quota tomorrow.",
	},

	"SHOP_TITLE": {"ja": "補給部の購買", "en": "Quartermaster's Shop"},
	"SHOP_LEVEL": {"ja": "Lv %d / %d", "en": "Lv %d / %d"},
	"SHOP_BUY": {"ja": "%d 円で購入", "en": "Buy $%d"},
	"SHOP_MAX": {"ja": "最大", "en": "MAX"},
	"UPG_PEELER": {"ja": "上等なピーラー", "en": "Better Peeler"},
	"UPG_PEELER_DESC": {"ja": "一度にむける幅が広がる", "en": "Peel a wider strip at once"},
	"UPG_TURNTABLE": {"ja": "自動回転台", "en": "Turntable"},
	"UPG_TURNTABLE_DESC": {"ja": "芋が勝手に回ってくれる", "en": "Spins the potato for you"},
	"UPG_MACHINE": {"ja": "皮むき機", "en": "Peeling Machine"},
	"UPG_MACHINE_DESC": {"ja": "一定時間ごとに自動で1個むく", "en": "Peels a potato automatically every few seconds"},
	"UPG_CONTRACT": {"ja": "補給契約の見直し", "en": "Better Contract"},
	"UPG_CONTRACT_DESC": {"ja": "1個あたりの報酬アップ", "en": "More pay per potato"},

	"BTN_START_DAY": {"ja": "勤務開始", "en": "Start shift"},
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
