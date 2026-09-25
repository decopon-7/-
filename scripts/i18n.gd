# 日本語・英語のテキスト表。
# 翻訳を増やすときは STRINGS に言語コードを足し、LOCALES にも追加する。
class_name I18n
extends RefCounted

const LOCALES := ["ja", "en"]

const STRINGS := {
	"TITLE_NAME": {"ja": "涙のみじん切り", "en": "Onion Tears"},
	"TITLE_SUB": {"ja": "涙をふきながら、今日も玉ねぎと向き合う。", "en": "Wipe your tears, and face the onions again today."},
	"BTN_CONTINUE": {"ja": "つづきから（%d日目）", "en": "Continue (Day %d)"},
	"BTN_NEW_GAME": {"ja": "はじめから", "en": "New Game"},
	"BTN_LANGUAGE": {"ja": "Language: 日本語", "en": "言語: English"},
	"BTN_QUIT": {"ja": "終了", "en": "Quit"},

	"HUD_DAY": {"ja": "%d日目の仕込み", "en": "Day %d prep"},
	"HUD_TODAY": {"ja": "本日 %d g", "en": "%d g today"},
	"HUD_MONEY": {"ja": "所持金 %d 円", "en": "Funds $%d"},
	"HUD_TEARS": {"ja": "涙", "en": "Tears"},
	"STEP_LENGTHWISE": {"ja": "縦に切り込みを入れる", "en": "Slice lengthwise"},
	"STEP_CROSSWISE": {"ja": "横に刻む", "en": "Cut crosswise"},
	"STEP_MINCE": {"ja": "トントン細かく", "en": "Mince it fine"},
	"STEP_DONE": {"ja": "できあがり！", "en": "Done!"},
	"HUD_HINT": {
		"ja": "マウス左右: 包丁の位置　左クリック / スペース（長押しOK）: 切る　Esc: メニュー",
		"en": "Move mouse: knife position   LMB / Space (hold OK): chop   Esc: menu",
	},
	"HUD_GAP_HINT": {"ja": "赤い印のところの間隔が広すぎます", "en": "Cuts too far apart at the red marks"},
	"HUD_END_SHIFT": {"ja": "今日はここまで", "en": "Finish for today"},
	"POP_ONION": {"ja": "+%d g　+%d 円", "en": "+%d g  +$%d"},
	"POP_PROCESSOR": {"ja": "プロセッサー +%d g", "en": "Processor +%d g"},
	"POP_TEARS": {"ja": "目が、目がぁ…！", "en": "My eyes...!"},

	"TICKET_TITLE": {"ja": "注文票 No.%d", "en": "Order No.%d"},
	"TICKET_NEXT": {"ja": "次: %s", "en": "Next: %s"},
	"TICKET_PAY": {"ja": "報酬 ×%.1f", "en": "Pay ×%.1f"},
	"POP_NEW_ORDER": {"ja": "新しい注文: %s", "en": "New order: %s"},
	"ORDER_HAMBURG": {"ja": "ハンバーグ", "en": "Hamburg Steak"},
	"ORDER_CURRY": {"ja": "カレー", "en": "Curry"},
	"ORDER_SOUP": {"ja": "オニオンスープ", "en": "Onion Soup"},
	"ORDER_DRESSING": {"ja": "ドレッシング", "en": "Dressing"},
	"STYLE_MINCE": {"ja": "みじん切り", "en": "Minced"},
	"STYLE_COARSE": {"ja": "粗みじん（大きめでOK）", "en": "Coarse chop (bigger is OK)"},
	"STYLE_SLICE": {"ja": "薄切り（横に細かく刻むだけ）", "en": "Thin slices (crosswise only)"},
	"STYLE_FINE": {"ja": "極みじん（とても細かく）", "en": "Extra-fine mince"},
	"STEP_SLICE": {"ja": "薄く切る", "en": "Slice thinly"},

	"END_TITLE": {"ja": "本日の仕込み、お疲れさまでした", "en": "That's a wrap for today"},
	"END_BODY": {
		"ja": "刻んだ量: %d g\n今日の稼ぎ: %d 円",
		"en": "Minced: %d g\nEarned today: $%d",
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
	"BTN_SOUND_ON": {"ja": "音: オン", "en": "Sound: On"},
	"BTN_SOUND_OFF": {"ja": "音: オフ", "en": "Sound: Off"},
	"BTN_MUSIC_ON": {"ja": "BGM: オン", "en": "Music: On"},
	"BTN_MUSIC_OFF": {"ja": "BGM: オフ", "en": "Music: Off"},
	"BTN_TO_TITLE": {"ja": "タイトルへ（自動保存）", "en": "Back to title (autosave)"},

	# ---- 主人公の日記（多くを語らない性格なので、断片的にしてある） ----
	"DIARY_TITLE": {"ja": "日記", "en": "Diary"},
	"DIARY_1": {
		"ja": "財布も、行くあてもほとんど残っていなかった。大将に「涙もろいやつほど、いい仕事をする」と言われ、住み込みで働くことになった。",
		"en": "My wallet was nearly empty, and I had nowhere to go. The owner said, \"The ones who cry easily make the best cooks,\" and took me in.",
	},
	"DIARY_2": {
		"ja": "慣れない手つきで玉ねぎを刻む。目にしみるのは、玉ねぎのせいだけではない気がした。",
		"en": "My hands are still clumsy with the knife. The sting in my eyes isn't only from the onions, I think.",
	},
	"DIARY_3": {
		"ja": "大将は多くを聞いてこない。それがありがたい。",
		"en": "The owner doesn't ask many questions. I'm grateful for that.",
	},
	"DIARY_5": {
		"ja": "常連の漁師が「新顔か」とだけ言って、いつもの席に座った。名前も聞かれなかった。",
		"en": "A regular fisherman just said \"new face\" and sat in his usual seat. He didn't ask my name.",
	},
	"DIARY_7": {
		"ja": "一週間経った。まだこの町の名前も、ちゃんと覚えていない。",
		"en": "A week has passed. I still don't quite remember the name of this town.",
	},
	"DIARY_10": {
		"ja": "少しだけ、包丁の音が軽くなった気がする。",
		"en": "The sound of the knife feels a little lighter now.",
	},
	"DIARY_13": {
		"ja": "隣町から来たという老婆が、スープを飲んで「懐かしい味だ」と泣いていた。理由は聞かなかった。",
		"en": "An old woman from the next town cried over her soup, saying it tasted like something from long ago. I didn't ask why.",
	},
	"DIARY_16": {
		"ja": "夜、賄いを食べながら大将がぽつりと言った。「うちも昔、誰かを拾ったことがある」",
		"en": "Over the staff meal, the owner said quietly, \"We took someone in once before, too.\"",
	},
	"DIARY_20": {
		"ja": "漁師が魚を分けてくれた。「稼ぎになるかは知らんが」と、ぶっきらぼうに。",
		"en": "The fisherman shared some of his catch. \"Not sure it's worth much,\" he muttered.",
	},
	"DIARY_24": {
		"ja": "玉ねぎの皮をむくとき、もう昔ほど手が震えない。",
		"en": "My hands don't shake as much when I peel an onion anymore.",
	},
	"DIARY_28": {
		"ja": "この町に、少しずつ顔見知りが増えてきた。まだ名乗ってはいないけれど。",
		"en": "I'm starting to recognize more faces in this town. I still haven't told anyone mine.",
	},
	"DIARY_32": {
		"ja": "大将に「ここにいたいだけいていい」と言われた。理由も聞かれなかった。",
		"en": "The owner said, \"Stay as long as you like.\" No questions asked.",
	},
	"DIARY_36": {
		"ja": "涙は、悲しいときだけに出るものじゃないと、最近わかってきた。",
		"en": "I'm starting to understand — tears don't only come from sadness.",
	},
	"DIARY_40": {
		"ja": "今日も玉ねぎを刻む。急ぐ理由は、もうどこにもない。",
		"en": "I cut onions again today. There's no reason to hurry, not anymore.",
	},
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
