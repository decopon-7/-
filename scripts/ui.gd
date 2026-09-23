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
var _time_label: Label
var _quota_label: Label
var _quota_bar: ProgressBar
var _money_label: Label
var _peel_label: Label
var _peel_bar: ProgressBar
var _hint_label: Label
var _end_shift_button: Button

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
	_end_shift_button.text = tr("HUD_END_SHIFT")
	_shop_title.text = tr("SHOP_TITLE")
	_start_day_button.text = tr("BTN_START_DAY")
	_pause_title.text = tr("PAUSE_TITLE")
	_resume_button.text = tr("BTN_RESUME")
	_to_title_button.text = tr("BTN_TO_TITLE")
	refresh_shop()


func update_hud(time_left: float, peeled_today: int, peel_ratio: float) -> void:
	var quota := GameState.quota_for_day()
	var secs := int(ceil(maxf(time_left, 0.0)))
	_day_label.text = tr("HUD_DAY") % GameState.day
	_time_label.text = tr("HUD_TIME") % [secs / 60, secs % 60]
	_time_label.modulate = COL_BAD if time_left < 20.0 else COL_TEXT
	_quota_label.text = tr("HUD_QUOTA") % [peeled_today, quota]
	_quota_bar.max_value = quota
	_quota_bar.value = peeled_today
	_quota_bar.modulate = COL_GOOD if peeled_today >= quota else Color.WHITE
	_money_label.text = tr("HUD_MONEY") % GameState.money
	_peel_label.text = tr("HUD_PEEL") % int(peel_ratio * 100.0)
	_peel_bar.value = peel_ratio / GameState.PEEL_DONE_RATIO * 100.0
	_end_shift_button.visible = peeled_today >= quota


func show_day_end(success: bool, peeled: int, quota: int, earned: int, bonus: int) -> void:
	_end_title.text = tr("END_OK") if success else tr("END_FAIL")
	_end_title.modulate = COL_GOOD if success else COL_BAD
	var body := tr("END_BODY") % [peeled, quota, earned]
	if success:
		body += "\n" + tr("END_BONUS") % bonus
	else:
		body += "\n" + tr("END_RETRY_NOTE")
	_end_body.text = body
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
	if _money_label:
		_money_label.text = tr("HUD_MONEY") % GameState.money


## 画面上の位置に「+10円」などを浮かび上がらせる
func popup(text: String, screen_pos: Vector2, color: Color = COL_ACCENT) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.position = screen_pos - Vector2(60, 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(label)
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 90.0, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 1.1).set_ease(Tween.EASE_IN)
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
	_time_label = _label(24)
	_quota_label = _label(22)
	_quota_bar = _bar()
	_money_label = _label(22)
	for n in [_day_label, _time_label, _quota_label, _quota_bar, _money_label]:
		box.add_child(n)

	var peel_box := VBoxContainer.new()
	peel_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	peel_box.offset_left = -220
	peel_box.offset_right = 220
	peel_box.offset_top = -110
	peel_box.offset_bottom = -40
	peel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(peel_box)
	_peel_label = _label(22)
	_peel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_peel_bar = _bar()
	_peel_bar.custom_minimum_size.y = 18
	peel_box.add_child(_peel_label)
	peel_box.add_child(_peel_bar)

	_hint_label = _label(18, COL_DIM)
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_left = 24
	_hint_label.offset_top = -40
	c.add_child(_hint_label)

	_end_shift_button = Button.new()
	_end_shift_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_end_shift_button.offset_left = -260
	_end_shift_button.offset_right = -24
	_end_shift_button.offset_top = 24
	_end_shift_button.offset_bottom = 80
	_end_shift_button.pressed.connect(end_shift_pressed.emit)
	c.add_child(_end_shift_button)
	return c


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
	_to_title_button = _button(box, to_title_pressed.emit)
	return c


# ---------------------------------------------------------------- 部品

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
