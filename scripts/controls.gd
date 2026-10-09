# 入力の割り当て（キーボード・マウス・ゲームパッド）。
# Steam Deck などコントローラーだけでも最後まで遊べるように、
# 操作は InputMap のアクション経由にしておく。
#   chop        … 包丁を下ろす（スペース / 左クリック / A・X・RB）
#   knife_left  … 包丁を左へ（A・←キー / 左スティック・十字キー・右スティック）
#   knife_right … 包丁を右へ
#   end_day     … 「今日はここまで」（Eキー / Yボタン）
#   pause       … 一時停止（Esc / Startボタン）
#   back        … 戻る（Bボタン / Backspace）。Godot標準の ui_cancel にはBボタンが入っていないため自前で用意する
# メニューの操作は Godot 標準の ui_* アクション（十字キー・Aボタンなど）をそのまま使う。
extends RefCounted

const AXIS_DEADZONE := 0.18


static func register() -> void:
	_add("chop", 0.5, [
		_key(KEY_SPACE),
		_mouse(MOUSE_BUTTON_LEFT),
		_pad_button(JOY_BUTTON_A),
		_pad_button(JOY_BUTTON_X),
		_pad_button(JOY_BUTTON_RIGHT_SHOULDER),
	])
	_add("knife_left", AXIS_DEADZONE, [
		_key(KEY_A),
		_key(KEY_LEFT),
		_pad_button(JOY_BUTTON_DPAD_LEFT),
		_pad_axis(JOY_AXIS_LEFT_X, -1.0),
		_pad_axis(JOY_AXIS_RIGHT_X, -1.0),
	])
	_add("knife_right", AXIS_DEADZONE, [
		_key(KEY_D),
		_key(KEY_RIGHT),
		_pad_button(JOY_BUTTON_DPAD_RIGHT),
		_pad_axis(JOY_AXIS_LEFT_X, 1.0),
		_pad_axis(JOY_AXIS_RIGHT_X, 1.0),
	])
	_add("end_day", 0.5, [
		_key(KEY_E),
		_pad_button(JOY_BUTTON_Y),
	])
	_add("pause", 0.5, [
		_key(KEY_ESCAPE),
		_pad_button(JOY_BUTTON_START),
	])
	_add("back", 0.5, [
		_key(KEY_BACKSPACE),
		_pad_button(JOY_BUTTON_B),
	])


static func _add(action: String, deadzone: float, events: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, deadzone)
	for e in events:
		InputMap.action_add_event(action, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


static func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


static func _pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
