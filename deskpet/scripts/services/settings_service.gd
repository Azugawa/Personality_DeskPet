extends Node
## Local settings for the assistant features.
##
## Defaults come from res://config/assistant/defaults.json; user overrides and
## secrets live under user:// so they survive updates and never enter the pck.
## Secrets are kept in a separate file and are never printed by this service.

signal changed(key: String, value: Variant)

const DEFAULTS_PATH := "res://config/assistant/defaults.json"
const USER_PATH := "user://config/settings.json"
const SECRETS_PATH := "user://config/secrets.json"

var _defaults: Dictionary = {}
var _user: Dictionary = {}
var _secrets: Dictionary = {}
var _path := USER_PATH
var _secrets_path := SECRETS_PATH
var _configured := false


func setup(path: String = USER_PATH, secrets_path: String = SECRETS_PATH) -> void:
	_path = path
	_secrets_path = secrets_path
	_defaults = ConfigLoader.load_json(DEFAULTS_PATH)
	if _defaults.is_empty():
		push_error("[Settings] defaults could not be loaded: %s" % ConfigLoader.last_error)
	_user = JsonStore.load_dict(_path, {})
	_secrets = JsonStore.load_dict(_secrets_path, {})
	_configured = true


func get_value(key: String, fallback: Variant = null) -> Variant:
	var user_value := _lookup(_user, key)
	if bool(user_value.get("found", false)):
		return user_value.get("value")
	var default_value := _lookup(_defaults, key)
	if bool(default_value.get("found", false)):
		return default_value.get("value")
	return fallback


func get_bool(key: String, fallback: bool = false) -> bool:
	var value: Variant = get_value(key, fallback)
	if typeof(value) == TYPE_BOOL:
		return value
	return fallback


func get_int(key: String, fallback: int = 0) -> int:
	var value: Variant = get_value(key, fallback)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


func get_float(key: String, fallback: float = 0.0) -> float:
	var value: Variant = get_value(key, fallback)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return fallback


func get_string(key: String, fallback: String = "") -> String:
	var value: Variant = get_value(key, fallback)
	if typeof(value) == TYPE_STRING:
		return str(value)
	return fallback


func get_array(key: String, fallback: Array = []) -> Array:
	var value: Variant = get_value(key, fallback)
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).duplicate(true)
	return fallback.duplicate(true)


func get_dict(key: String, fallback: Dictionary = {}) -> Dictionary:
	var value: Variant = get_value(key, fallback)
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	return fallback.duplicate(true)


func set_value(key: String, value: Variant) -> void:
	_assign(_user, key, value)
	JsonStore.save_dict(_path, _user)
	changed.emit(key, value)


func get_secret(key: String, fallback: String = "") -> String:
	var value := _lookup(_secrets, key)
	if bool(value.get("found", false)) and typeof(value.get("value")) == TYPE_STRING:
		return str(value.get("value"))
	return fallback


func set_secret(key: String, value: String) -> void:
	_assign(_secrets, key, value)
	JsonStore.save_dict(_secrets_path, _secrets)
	changed.emit("secrets." + key, "***")


func has_secret(key: String) -> bool:
	return not get_secret(key, "").is_empty()


## Deep-merged view of defaults and user overrides, safe to show in a settings UI.
func snapshot() -> Dictionary:
	var merged: Dictionary = _defaults.duplicate(true)
	_merge_into(merged, _user)
	return merged


func user_snapshot() -> Dictionary:
	return _user.duplicate(true)


func reload() -> void:
	_user = JsonStore.load_dict(_path, {})
	_secrets = JsonStore.load_dict(_secrets_path, {})
	changed.emit("", null)


func _lookup(tree: Dictionary, key: String) -> Dictionary:
	if key.is_empty():
		return {"found": true, "value": tree}
	var cursor: Variant = tree
	for part in key.split("."):
		if typeof(cursor) != TYPE_DICTIONARY:
			return {"found": false}
		var dict := cursor as Dictionary
		if not dict.has(part):
			return {"found": false}
		cursor = dict[part]
	return {"found": true, "value": cursor}


func _assign(tree: Dictionary, key: String, value: Variant) -> void:
	var parts := key.split(".")
	var cursor := tree
	for index in parts.size() - 1:
		var part := parts[index]
		if typeof(cursor.get(part)) != TYPE_DICTIONARY:
			cursor[part] = {}
		cursor = cursor[part]
	cursor[parts[parts.size() - 1]] = value


func _merge_into(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		var value: Variant = source[key]
		if typeof(value) == TYPE_DICTIONARY and typeof(target.get(key)) == TYPE_DICTIONARY:
			_merge_into(target[key], value)
		else:
			target[key] = value.duplicate(true) if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value
