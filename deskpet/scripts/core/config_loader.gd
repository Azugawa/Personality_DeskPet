class_name ConfigLoader
extends RefCounted
## Loads and validates JSON configuration.
##
## All configuration is read from res:// so the running pet never needs Python
## or any file outside the Godot project. Errors are printed and exposed through
## the static last_error property so callers/tests can report actionable details.

static var last_error: String = ""


static func load_json(path: String) -> Dictionary:
	last_error = ""
	if path.is_empty():
		_fail("Config path is empty.")
		return {}
	if not FileAccess.file_exists(path):
		_fail("Config file not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Cannot open config file: %s (FileAccess error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		_fail("Invalid JSON in %s (line %d): %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		_fail("Config root must be a JSON object: %s" % path)
		return {}

	return parser.data as Dictionary


static func validate_scene_config(config: Dictionary, expected_id: String = "") -> PackedStringArray:
	var errors := PackedStringArray()
	if config.is_empty():
		errors.append("scene config is empty")
		return errors

	var scene_id := str(config.get("scene_id", ""))
	if scene_id.is_empty():
		errors.append("scene_id must be a non-empty string")
	if not expected_id.is_empty() and scene_id != expected_id:
		errors.append("scene_id '%s' does not match expected '%s'" % [scene_id, expected_id])

	if typeof(config.get("background")) != TYPE_DICTIONARY:
		errors.append("background must be an object")
	else:
		var background: Dictionary = config.get("background")
		var background_type := str(background.get("type", ""))
		if background_type.is_empty():
			errors.append("background.type must be set (transparent, color or texture)")
		elif background_type == "texture" and str(background.get("texture", "")).is_empty():
			errors.append("background.texture is required when background.type is 'texture'")

	if typeof(config.get("character")) != TYPE_DICTIONARY:
		errors.append("character must be an object")
	else:
		var character: Dictionary = config.get("character")
		if str(character.get("profile", "")).is_empty():
			errors.append("character.profile must be set")
		if not _is_vec2(character.get("position")) and not _is_vec2(character.get("ground_position")):
			errors.append("character needs position [x, y] or ground_position [x, depth]")
		if not _is_number(character.get("scale")):
			errors.append("character.scale must be a number")
		elif float(character.get("scale")) <= 0.0:
			errors.append("character.scale must be greater than 0")

	if typeof(config.get("props")) != TYPE_ARRAY:
		errors.append("props must be an array")
	else:
		var props: Array = config.get("props")
		var seen_ids := {}
		for i in props.size():
			if typeof(props[i]) != TYPE_DICTIONARY:
				errors.append("props[%d] must be an object" % i)
				continue
			var prop: Dictionary = props[i]
			var prop_id := str(prop.get("id", ""))
			if prop_id.is_empty():
				errors.append("props[%d].id must be a non-empty string" % i)
			elif seen_ids.has(prop_id):
				errors.append("duplicate prop id '%s'" % prop_id)
			else:
				seen_ids[prop_id] = true
			if str(prop.get("type", "")).is_empty():
				errors.append("props[%d].type must be a non-empty string" % i)
			var has_screen_position := _is_vec2(prop.get("position"))
			var has_ground_position := _is_vec2(prop.get("ground_position"))
			if not has_screen_position and not has_ground_position:
				errors.append("props[%d] needs position [x, y] or ground_position [x, depth]" % i)
			if prop.has("scale") and not _is_scale(prop.get("scale")):
				errors.append("props[%d].scale must be a number or [x, y]" % i)
			if prop.has("visible") and typeof(prop.get("visible")) != TYPE_BOOL:
				errors.append("props[%d].visible must be a boolean" % i)
			if prop.has("z_index") and not _is_number(prop.get("z_index")):
				errors.append("props[%d].z_index must be a number" % i)
			var prop_type := str(prop.get("type", ""))
			if prop_type == "debug_placeholder":
				if not _is_vec2(prop.get("size")):
					errors.append("props[%d].size must be [width, height] for debug_placeholder" % i)
			elif prop_type == "pseudo3d_debug":
				if str(prop.get("profile", "")).is_empty():
					errors.append("props[%d].profile is required for pseudo3d_debug" % i)
				if not has_ground_position:
					errors.append("props[%d].ground_position [x, depth] is required for pseudo3d_debug" % i)

	if typeof(config.get("allowed_events")) != TYPE_ARRAY:
		errors.append("allowed_events must be an array")
	else:
		var allowed_events: Array = config.get("allowed_events")
		for i in allowed_events.size():
			if typeof(allowed_events[i]) != TYPE_STRING or str(allowed_events[i]).is_empty():
				errors.append("allowed_events[%d] must be a non-empty string" % i)

	if typeof(config.get("transitions")) != TYPE_DICTIONARY:
		errors.append("transitions must be an object")
	else:
		var transitions: Dictionary = config.get("transitions")
		for event_name in transitions.keys():
			var rule: Variant = transitions[event_name]
			if typeof(rule) != TYPE_DICTIONARY:
				errors.append("transitions.%s must be an object" % event_name)
				continue
			var target := str(rule.get("target_scene", ""))
			if target.is_empty():
				errors.append("transitions.%s.target_scene must be set" % event_name)
			var allowed_for_transition: Variant = config.get("allowed_events")
			if typeof(allowed_for_transition) != TYPE_ARRAY or not (allowed_for_transition as Array).has(event_name):
				errors.append("transitions.%s is not listed in allowed_events" % event_name)

	if config.has("lifecycle") and typeof(config.get("lifecycle")) != TYPE_DICTIONARY:
		errors.append("lifecycle must be an object")

	return errors


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_vec2(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var arr: Array = value
	if arr.size() != 2:
		return false
	return _is_number(arr[0]) and _is_number(arr[1])


static func _is_scale(value: Variant) -> bool:
	if _is_number(value):
		return true
	return _is_vec2(value)


static func _fail(message: String) -> void:
	last_error = message
	push_error("[ConfigLoader] " + message)
