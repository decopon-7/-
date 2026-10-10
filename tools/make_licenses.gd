# 配布物に同梱する、第三者のライセンス表記（THIRD_PARTY_LICENSES.txt）を書き出す。
#   godot --headless --path . -s tools/make_licenses.gd -- build/windows/THIRD_PARTY_LICENSES.txt
# Godot エンジン本体（MIT と、エンジンに含まれる各ライブラリ）の表記はエンジン自身が持っているので、
# それをそのまま出力し、あわせて同梱しているフォントの OFL を付ける。
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "THIRD_PARTY_LICENSES.txt"
	var text := "Onion Tears — Third-party licenses\n\n"
	text += "==================== Godot Engine ====================\n\n"
	text += Engine.get_license_text() + "\n\n"
	text += "---- Third-party components of Godot Engine ----\n\n"
	for part in Engine.get_copyright_info():
		text += "## %s\n" % part["name"]
		for item in part["parts"]:
			text += "Files: %s\n" % ", ".join(item["files"])
			text += "Copyright: %s\n" % "\n           ".join(item["copyright"])
			text += "License: %s\n\n" % item["license"]
	text += "\n"
	var licenses := Engine.get_license_info()
	for name in licenses:
		text += "---- %s ----\n%s\n\n" % [name, licenses[name]]
	text += "==================== Noto Sans JP (font) ====================\n\n"
	text += FileAccess.get_file_as_string("res://fonts/OFL.txt") + "\n"
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("書き出せません: " + out_path)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("wrote ", out_path, " (", text.length(), " chars)")
	quit(0)
