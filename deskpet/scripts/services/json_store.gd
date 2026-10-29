class_name JsonStore
extends RefCounted
## Small atomic JSON file helper used for all local assistant data.
##
## Writes go to "<path>.tmp" first, the previous file is kept as "<path>.bak",
## and the temp file is renamed over the target. A crash between the two renames
## leaves the backup readable, which load_dict() falls back to.

static func absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func load_dict(path: String, fallback: Dictionary = {}) -> Dictionary:
	var abs := absolute_path(path)
	for candidate in [abs, abs + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(text.trim_prefix("\ufeff"))
		if parsed is Dictionary:
			return parsed
	return fallback.duplicate(true)


static func save_dict(path: String, data: Dictionary) -> bool:
	var abs := absolute_path(path)
	var directory := abs.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			return false
	var temp := abs + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	var backup := abs + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(abs):
		if DirAccess.rename_absolute(abs, backup) != OK:
			return false
	if DirAccess.rename_absolute(temp, abs) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, abs)
		return false
	return true


static func remove_file(path: String) -> void:
	var abs := absolute_path(path)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)


static func ensure_directory(path: String) -> bool:
	var abs := absolute_path(path)
	if DirAccess.dir_exists_absolute(abs):
		return true
	return DirAccess.make_dir_recursive_absolute(abs) == OK


static func remove_tree(path: String) -> void:
	var abs := absolute_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	var dir := DirAccess.open(abs)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for name in names:
		var child := abs.path_join(name)
		if DirAccess.dir_exists_absolute(child):
			remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	DirAccess.remove_absolute(abs)
