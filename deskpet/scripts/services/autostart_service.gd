extends Node
## Per-user autostart through HKCU Run (no administrator required).
##
## Registry access happens in DeskPetSentinel.exe (Microsoft.Win32.Registry) so
## paths containing spaces need no shell quoting. The installer writes the same
## value on first install; the settings UI toggles it later.

const RUN_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const VALUE_NAME := "Hezhuazhua"


func is_enabled() -> bool:
	var helper := _helper_path()
	if helper.is_empty():
		return false
	var output: Array = []
	return OS.execute(helper, PackedStringArray(["--autostart", "status"]), output, true) == 0


func set_enabled(enabled: bool) -> bool:
	if OS.has_feature("editor"):
		push_warning("[Autostart] refusing to change autostart from the editor")
		return false
	var helper := _helper_path()
	if helper.is_empty():
		return false
	var executable := OS.get_executable_path()
	if executable.is_empty():
		return false
	var arguments: Array[String] = ["--autostart", "on" if enabled else "off"]
	if enabled:
		arguments.append_array(["--app", executable])
	var output: Array = []
	return OS.execute(helper, PackedStringArray(arguments), output, true) == 0


func status() -> String:
	if OS.has_feature("editor"):
		return "编辑器环境下不修改自启"
	return "已开启" if is_enabled() else "未开启"


func _helper_path() -> String:
	var parent := get_parent()
	if parent != null and parent.has_method("get_provider"):
		var sentinel: Node = parent.get_provider("sentinel")
		if sentinel != null and sentinel.has_method("helper_executable"):
			var extracted: String = sentinel.helper_executable()
			if not extracted.is_empty():
				return extracted
	if FileAccess.file_exists("res://bin/DeskPetSentinel.exe"):
		return ProjectSettings.globalize_path("res://bin/DeskPetSentinel.exe")
	var installed := OS.get_executable_path().get_base_dir().path_join("DeskPetSentinel.exe")
	if FileAccess.file_exists(installed):
		return installed
	return ""
