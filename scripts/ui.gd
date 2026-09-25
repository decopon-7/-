# 画面上のUI（HUD・タイトル・終業画面＋購買・一時停止）。
# 見た目はコードで組み立てているので、後でエディタのシーンに置き換えてもよい。
class_name GameUI
extends CanvasLayer

signal continue_pressed
signal new_game_pressed
signal start_day_pressed
signal resume_pressed
signal to_title_pressed
signal end_shift_pressed
signal upgrade_bought(id: String)

const COL_PANEL := Color(0.08, 0.08, 0.07, 0.86)
const COL_ACCENT := Color(0.93, 0.78, 0.36)
const COL_TEXT := Color(0.93, 0.91, 0.86)
const COL_DIM := Color(0.65, 0.63, 0.58)
const COL_GOOD := Color(0.55, 0.85, 0.45)
const COL_BAD := Color(0.95, 0.45, 0.35)

var hud: Control
var title_screen: Control
var day_end_screen: Control
var pause_screen: Control

var _day_label: Label
var _today_label: Label
var _money_label: Label
var _money_shown := -1
var _step_label: Label
var _step_bar: ProgressBar
var _gap_hint: Label
var _tears_bar: ProgressBar
var _tears_label: Label
var _hint_label: Label
var _end_shift_button: Button
var _ticket_title: Label
var _ticket_dish: Label
var _ticket_style: Label
var _ticket_pay: Label
var _ticket_next: Label

var _title_name: Label
var _title_sub: Label
var _continue_button: Button
var _new_game_button: Button
var _language_button: Button
var _quit_button: Button

var _end_title: Label
var _end_body: Label
var _shop_title: Label
var _shop_rows := {}
var _start_day_button: Button

var _pause_title: Label
var _resume_button: Button
var _sound_button: Button
var _music_button: Button
var _to_title_button: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	hud = _build_hud()
	root.add_child(hud)
	day_end_screen = _build_day_end()
	root.add_child(day_end_screen)
	pause_screen = _build_pause()
	root.add_child(pause_screen)
	title_screen = _build_title()
	root.add_child(title_screen)
	refresh_texts()
	_money_shown = GameState.money  # 起動時は0から数え上げず、いきなり現在値で表示


# ---------------------------------------------------------------- 表示切替

func show_only(screen: Control) -> void:
	for s in [title_screen, day_end_screen, pause_screen]:
		s.visible = s == screen
	hud.visible = screen == null or screen == pause_screen


func refresh_texts() -> void:
	_title_name.text = tr("TITLE_NAME")
	_title_sub.text = tr("TITLE_SUB")
	_continue_button.visible = GameState.has_save()
	_continue_button.text = tr("BTN_CONTINUE") % GameState.day
	_new_game_button.text = tr("BTN_NEW_GAME")
	_language_button.text = tr("BTN_LANGUAGE")
	_quit_button.text = tr("BTN_QUIT")
	_hint_label.text = tr("HUD_HINT")
	_gap_hint.text = tr("HUD_GAP_HINT")
	_tears_label.text = tr("HUD_TEARS")
	_end_shift_button.text = tr("HUD_END_SHIFT")
	_shop_title.text = tr("SHOP_TITLE")
	_start_day_button.text = tr("BTN_START_DAY")
	_pause_title.text = tr("PAUSE_TITLE")
	_resume_button.text = tr("BTN_RESUME")
	_to_title_button.text = tr("BTN_TO_TITLE")
	_sound_button.text = tr("BTN_SOUND_OFF") if GameState.muted else tr("BTN_SOUND_ON")
	_music_button.text = tr("BTN_MUSIC_ON") if GameState.music_on else tr("BTN_MUSIC_OFF")
	refresh_shop()


func _process(delta: float) -> void:
	# 所持金はいきなり切り替わらず、数字がパラパラと数え上がる/下がる演出
	if _money_shown != GameState.money and _money_label:
		var diff := GameState.money - _money_shown
		var step := maxi(1, roundi(absf(diff) * delta * 12.0))
		step = mini(step, absi(diff))
		_money_shown += step if diff > 0 else -step
		_money_label.text = tr("HUD_MONEY") % _money_shown


func update_hud(grams_today: int, step_text: String, step_progress: float,
		tears: float, wide_gaps: bool) -> void:
	_day_label.text = tr("HUD_DAY") % GameState.day
	_today_label.text = tr("HUD_TODAY") % grams_today
	_step_label.text = step_text
	_step_bar.value = step_progress * 100.0
	_gap_hint.visible = wide_gaps
	_tears_bar.value = tears * 100.0
	_tears_bar.modulate = COL_BAD if tears > 0.8 else Color.WHITE


func show_day_end(grams: int, earned: int) -> void:
	_end_title.text = tr("END_TITLE")
	_end_title.modulate = COL_ACCENT
	_end_body.text = tr("END_BODY") % [grams, earned]
	refresh_shop()
	show_only(day_end_screen)


func refresh_shop() -> void:
	for id in _shop_rows:
		var row: Dictionary = _shop_rows[id]
		var u: Dictionary = GameState.UPGRADES[id]
		row["name"].text = tr(u["name"])
		row["desc"].text = tr(u["desc"])
		row["level"].text = tr("SHOP_LEVEL") % [GameState.levels[id], u["max"]]
		var button: Button = row["buy"]
		if GameState.is_maxed(id):
			button.text = tr("SHOP_MAX")
			button.disabled = true
		else:
			button.text = tr("SHOP_BUY") % GameState.upgrade_cost(id)
			button.disabled = not GameState.can_buy(id)

## 画面上の位置に「+100 g」などを、弾みをつけてポップアップさせる
func popup(text: String, screen_pos: Vector2, color: Color = COL_ACCENT) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.position = screen_pos - Vector2(60, 20)
	label.pivot_offset = Vector2(60, 20)
	label.scale = Vector2.ZERO
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(label)
	# 飛び出すように少し大きく弾んでから落ち着く（バックイージングでオーバーシュート）
	var pop := label.create_tween()
	pop.tween_property(label, "scale", Vector2.ONE * 1.15, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 90.0, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.15).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(label.queue_free)


# ---------------------------------------------------------------- 組み立て

func _build_hud() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := _panel()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(300, 0)
	c.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_day_label = _label(30, COL_ACCENT)
	_today_label = _label(24)
	_money_label = _label(22)
	for n in [_day_label, _today_label, _money_label]:
		box.add_child(n)

	var step_box := VBoxContainer.new()
	step_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	step_box.offset_left = -260
	step_box.offset_right = 260
	step_box.offset_top = -140
	step_box.offset_bottom = -40
	step_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(step_box)
	_gap_hint = _label(18, COL_BAD)
	_step_label = _label(24)
	_step_bar = _bar()
	_step_bar.custom_minimum_size.y = 18
	for l in [_gap_hint, _step_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step_box.add_child(l)
	step_box.add_child(_step_bar)

	# 涙ゲージ（右下）
	var tears_box := HBoxContainer.new()
	tears_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tears_box.offset_left = -300
	tears_box.offset_right = -24
	tears_box.offset_top = -64
	tears_box.offset_bottom = -34
	tears_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tears_box.add_theme_constant_override("separation", 10)
	c.add_child(tears_box)
	_tears_label = _label(22, Color(0.6, 0.8, 1.0))
	_tears_bar = _bar()
	_tears_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tears_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.7, 1.0)
	fill.set_corner_radius_all(4)
	_tears_bar.add_theme_stylebox_override("fill", fill)
	tears_box.add_child(_tears_label)
	tears_box.add_child(_tears_bar)

	_hint_label = _label(18, COL_DIM)
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_left = 24
	_hint_label.offset_top = -40
	c.add_child(_hint_label)

	# 右上：注文票と「早めに切り上げる」ボタン
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -340
	right.offset_right = -24
	right.offset_top = 24
	right.add_theme_constant_override("separation", 12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(right)
	right.add_child(_build_ticket())
	_end_shift_button = Button.new()
	_end_shift_button.custom_minimum_size.y = 52
	_end_shift_button.pressed.connect(end_shift_pressed.emit)
	_end_shift_button.pressed.connect(_click)
	right.add_child(_end_shift_button)
	return c


## 厨房の伝票のような紙の見た目
func _build_ticket() -> Control:
	var ticket := PanelContainer.new()
	ticket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := _style(Color(0.96, 0.93, 0.84), 3, 16)
	paper.border_color = Color(0.75, 0.3, 0.25)
	paper.border_width_top = 6
	paper.shadow_color = Color(0, 0, 0, 0.5)
	paper.shadow_size = 6
	paper.shadow_offset = Vector2(3, 4)
	ticket.add_theme_stylebox_override("panel", paper)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	ticket.add_child(box)
	var ink := Color(0.18, 0.15, 0.12)
	_ticket_title = _ticket_label(16, Color(0.55, 0.25, 0.2))
	_ticket_dish = _ticket_label(32, ink)
	_ticket_style = _ticket_label(20, ink)
	_ticket_style.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticket_pay = _ticket_label(18, Color(0.35, 0.3, 0.25))
	_ticket_next = _ticket_label(16, Color(0.45, 0.4, 0.35))
	for l in [_ticket_title, _ticket_dish, _ticket_style, _ticket_pay]:
		box.add_child(l)
	var line := HSeparator.new()
	line.add_theme_color_override("separator", Color(0.7, 0.65, 0.55))
	box.add_child(line)
	box.add_child(_ticket_next)
	return ticket


func _ticket_label(size: int, color: Color) -> Label:
	var l := _label(size, color)
	# 紙の上の文字なので黒い縁取りは消す
	l.add_theme_constant_override("outline_size", 0)
	return l


func update_ticket(order_id: String, next_ids: Array, number: int) -> void:
	var o: Dictionary = GameState.ORDERS[order_id]
	_ticket_title.text = tr("TICKET_TITLE") % number
	_ticket_dish.text = tr(o["name"])
	_ticket_style.text = tr(o["style"])
	_ticket_pay.text = tr("TICKET_PAY") % o["pay"]
	var names := next_ids.map(func(id): return tr(GameState.ORDERS[id]["name"]))
	_ticket_next.text = tr("TICKET_NEXT") % " / ".join(names)


func _build_title() -> Control:
	var c := _overlay(0.55)
	var box := _center_box(c)
	_title_name = _label(84, COL_ACCENT)
	_title_sub = _label(26, COL_DIM)
	for l in [_title_name, _title_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	box.add_child(_spacer(30))
	_continue_button = _button(box, continue_pressed.emit)
	_new_game_button = _button(box, new_game_pressed.emit)
	_language_button = _button(box, func():
		GameState.set_locale(I18n.next_locale(TranslationServer.get_locale()))
		refresh_texts())
	_quit_button = _button(box, func(): get_tree().quit())
	return c


func _build_day_end() -> Control:
	var c := _overlay(0.45)
	var panel := _panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(760, 0)
	c.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_end_title = _label(48)
	_end_body = _label(24)
	_shop_title = _label(30, COL_ACCENT)
	box.add_child(_end_title)
	box.add_child(_end_body)
	box.add_child(HSeparator.new())
	box.add_child(_shop_title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for id in GameState.UPGRADE_IDS:
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.add_theme_constant_override("separation", 0)
		var name_label := _label(24)
		var desc_label := _label(17, COL_DIM)
		text_box.add_child(name_label)
		text_box.add_child(desc_label)
		var level_label := _label(20, COL_DIM)
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(190, 48)
		buy.pressed.connect(func(): upgrade_bought.emit(id))
		grid.add_child(text_box)
		grid.add_child(level_label)
		grid.add_child(buy)
		_shop_rows[id] = {"name": name_label, "desc": desc_label, "level": level_label, "buy": buy}

	box.add_child(_spacer(8))
	_start_day_button = _button(box, start_day_pressed.emit)
	return c


func _build_pause() -> Control:
	var c := _overlay(0.6)
	var box := _center_box(c)
	_pause_title = _label(56, COL_ACCENT)
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_pause_title)
	box.add_child(_spacer(20))
	_resume_button = _button(box, resume_pressed.emit)
	_sound_button = _button(box, func():
		GameState.set_muted(not GameState.muted)
		refresh_texts())
	_music_button = _button(box, func():
		GameState.set_music_on(not GameState.music_on)
		Sfx.set_music_enabled(GameState.music_on)
		refresh_texts())
	_to_title_button = _button(box, to_title_pressed.emit)
	return c


# ---------------------------------------------------------------- 部品

func _click() -> void:
	Sfx.play("click", -6.0)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 6)

	var normal := _style(Color(0.2, 0.19, 0.16), 8)
	normal.border_color = Color(0.45, 0.4, 0.3)
	normal.set_border_width_all(2)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.3, 0.27, 0.2)
	hover.border_color = COL_ACCENT
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.14, 0.13, 0.11)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.13, 0.13, 0.12)
	disabled.border_color = Color(0.25, 0.24, 0.22)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", COL_ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.44, 0.4))

	t.set_stylebox("panel", "PanelContainer", _style(COL_PANEL, 12, 20))
	t.set_stylebox("background", "ProgressBar", _style(Color(0.15, 0.15, 0.13), 4))
	t.set_stylebox("fill", "ProgressBar", _style(COL_ACCENT, 4))
	return t


func _style(color: Color, radius: int, margin: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(size: int, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar() -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 14)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _button(parent: Control, callback: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(360, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_click)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = height
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _overlay(alpha: float) -> Control:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, alpha)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.visible = false
	return c


func _center_box(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	return box
