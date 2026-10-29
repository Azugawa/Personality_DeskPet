extends SceneTree
class MockUpdate:
	extends "res://scripts/services/update_service.gd"
	var calls: Array[String] = []
	func _ready() -> void: pass
	func _fetch_once(url: String, _file: String = "") -> Array:
		calls.append(url)
		if calls.size() == 1: return [HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray()]
		if calls.size() == 2: return [0, 200, [], "<html>gateway error</html>".to_utf8_buffer()]
		var body := JSON.stringify({"version":"0.2.2","url":PREFIX+"v0.2.2/DeskPet.exe","sha256":"a".repeat(64)})
		return [0,200,[],body.to_utf8_buffer()]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var updater := MockUpdate.new()
	root.add_child(updater)
	updater.update_config = ConfigLoader.load_json("res://config/updates.json")
	var result := await updater._fetch(updater.FEED)
	assert(not result.is_empty())
	assert(updater.calls.size()==3)
	assert(updater.calls[0]==updater.FEED)
	assert(updater.calls[1]=="https://gh-proxy.com/"+updater.FEED)
	assert(updater.calls[2]=="https://ghproxy.net/"+updater.FEED)
	assert(updater._download_candidates("https://example.com/update.json").size()==1)
	print("PASS: direct failure, invalid gateway response, next gateway success, non-GitHub untouched")
	quit()
