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
	"HUD_END_SHIFT_LOCKED": {"ja": "あと %d g で終業できます", "en": "%d g more to finish for today"},
	"POP_ONION": {"ja": "+%d g　+%d 円", "en": "+%d g  +$%d"},
	"POP_PROCESSOR": {"ja": "プロセッサー +%d g", "en": "Processor +%d g"},
	"POP_TEARS": {"ja": "目が、目がぁ…！", "en": "My eyes...!"},

	"TICKET_TITLE": {"ja": "注文票 No.%d", "en": "Order No.%d"},
	"TICKET_NEXT": {"ja": "次: %s", "en": "Next: %s"},
	"TICKET_PAY": {"ja": "報酬 ×%.1f", "en": "Pay ×%.1f"},
	"POP_NEW_ORDER": {"ja": "新しい注文: %s", "en": "New order: %s"},
	"POP_GOLDEN": {"ja": "✨ 幸運の玉ねぎだ！", "en": "✨ A lucky golden onion!"},
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
	"OPT_SOUND": {"ja": "効果音 %d%%", "en": "Sound %d%%"},
	"OPT_MUSIC": {"ja": "BGM %d%%", "en": "Music %d%%"},
	"BTN_FULLSCREEN_ON": {"ja": "画面表示: フルスクリーン", "en": "Display: Fullscreen"},
	"BTN_FULLSCREEN_OFF": {"ja": "画面表示: ウィンドウ", "en": "Display: Windowed"},
	"BTN_TO_TITLE": {"ja": "タイトルへ（自動保存）", "en": "Back to title (autosave)"},
	"BTN_ACHIEVEMENTS": {"ja": "実績", "en": "Achievements"},
	"BTN_BACK": {"ja": "戻る", "en": "Back"},

	# ---- 実績・見た目の称号 ----
	"ACHIEVEMENTS_TITLE": {"ja": "実績（%d / %d）", "en": "Achievements (%d / %d)"},
	"ACH_DONE": {"ja": "達成", "en": "Done"},
	"ACH_LOCKED": {"ja": "未達成", "en": "Locked"},
	"SKIN_LABEL": {"ja": "道具の称号: %s", "en": "Gear rank: %s"},
	"SKIN_NONE": {"ja": "なし", "en": "None"},
	"SKIN_GOLD": {"ja": "ゴールド", "en": "Gold"},
	"SKIN_PLATINUM": {"ja": "プラチナ", "en": "Platinum"},
	"SKIN_DIAMOND": {"ja": "ダイヤ", "en": "Diamond"},
	"ACH_KNIFE_MAX": {"ja": "研ぎ澄まされた一振り", "en": "A Finely Honed Edge"},
	"ACH_KNIFE_MAX_DESC": {"ja": "包丁を最大Lvまで鍛える", "en": "Upgrade the knife to max level"},
	"ACH_GOGGLES_MAX": {"ja": "涙知らず", "en": "No More Tears"},
	"ACH_GOGGLES_MAX_DESC": {"ja": "玉ねぎゴーグルを最大Lvまで鍛える", "en": "Upgrade the onion goggles to max level"},
	"ACH_PROCESSOR_MAX": {"ja": "厨房の相棒", "en": "Kitchen's Best Friend"},
	"ACH_PROCESSOR_MAX_DESC": {"ja": "フードプロセッサーを最大Lvまで鍛える", "en": "Upgrade the food processor to max level"},
	"ACH_CONTRACT_MAX": {"ja": "やり手の交渉人", "en": "Master Negotiator"},
	"ACH_CONTRACT_MAX_DESC": {"ja": "仕入れ先との値段交渉を最大Lvまで進める", "en": "Max out the supplier price negotiation"},
	"ACH_DAY10": {"ja": "十日目の朝", "en": "Ten Mornings In"},
	"ACH_DAY10_DESC": {"ja": "10日目を迎える", "en": "Reach day 10"},
	"ACH_MONEY1000": {"ja": "ひと財産", "en": "A Tidy Sum"},
	"ACH_MONEY1000_DESC": {"ja": "所持金が1000円に達する", "en": "Have $1000 or more"},
	"ACH_GOLDEN1": {"ja": "幸運を掴む", "en": "Stroke of Luck"},
	"ACH_GOLDEN1_DESC": {"ja": "幸運の玉ねぎを仕上げる", "en": "Finish a lucky golden onion"},
	"ACH_GRAMS3000": {"ja": "積み重ねた腕前", "en": "Building Up Skill"},
	"ACH_GRAMS3000_DESC": {"ja": "累計3000g刻む", "en": "Mince 3000 g in total"},
	"ACH_DAY40": {"ja": "この町で見つけたもの", "en": "What I Found in This Town"},
	"ACH_DAY40_DESC": {"ja": "40日目を迎える（特別な実績：ゴールド→プラチナ）", "en": "Reach day 40 (special: Gold → Platinum)"},
	"ACH_GRAMS20000": {"ja": "玉ねぎの達人", "en": "Onion Virtuoso"},
	"ACH_GRAMS20000_DESC": {"ja": "累計20000g刻む（特別な実績：プラチナ→ダイヤ）", "en": "Mince 20000 g in total (special: Platinum → Diamond)"},

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
	# 40日目（ENDING_DAY）だけは特別で、それまでの遊び方によって3つに分岐する（複数エンド）
	"ENDING_MASTER": {
		"ja": "気づけば、包丁もゴーグルもプロセッサーも、店の誰よりも手に馴染んでいた。大将は何も言わずに、厨房の合鍵をそっと渡してくれた。",
		"en": "Without quite noticing, every tool in this kitchen had become an extension of my hand. The owner said nothing — just quietly handed me a spare key to the kitchen.",
	},
	"ENDING_BONDS": {
		"ja": "幸運の玉ねぎに、何度も出くわした気がする。漁師も、隣町の老婆も、いつのまにか顔なじみになっていた。誰も理由を聞かないこの町で、初めて「ただいま」と言いたくなった。",
		"en": "I seem to have crossed paths with the lucky onion more than once. The fisherman, the old woman from the next town — somehow, they'd all become familiar faces. In this town where no one asks why, for the first time, I wanted to say \"I'm home.\"",
	},
	"ENDING_QUIET": {
		"ja": "今日も玉ねぎを刻む。急ぐ理由は、もうどこにもない。",
		"en": "I cut onions again today. There's no reason to hurry, not anymore.",
	},

	"BTN_DIARY": {"ja": "日記を読み返す", "en": "Reread the Diary"},
	"DIARY_RECAP_TITLE": {"ja": "日記（%d / %d）", "en": "Diary (%d / %d)"},
	"DIARY_DAY_LABEL": {"ja": "%d日目", "en": "Day %d"},
	"DIARY_LOCKED": {"ja": "……（まだ読んでいない）", "en": "…… (not read yet)"},
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
