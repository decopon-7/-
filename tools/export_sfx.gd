# 開発用：合成した効果音を WAV ファイルに書き出す（試聴・確認用）。
#   godot --headless --path . -s tools/export_sfx.gd -- --out=/tmp/sfx
extends SceneTree


func _initialize() -> void:
	var out := "user://sfx"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var sfx: Node = load("res://scripts/sfx.gd").new()
	root.add_child(sfx)


func _process(_delta: float) -> bool:
	var out := "user://sfx"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var sfx: Node = root.get_child(root.get_child_count() - 1)
	for name in sfx._streams:
		var path := "%s/%s.wav" % [out, name]
		sfx.get_stream(name).save_to_wav(path)
		print("wrote ", path)
	return true
