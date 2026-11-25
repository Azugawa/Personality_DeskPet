extends Node
## Keeps a single DeskPet process alive at a time.
##
## The first launch listens on a loopback port. A later launch finds the live
## listener, asks it to surface the pet, and exits before the main scene is
## built. No files or PIDs are involved, so a crash cannot leave a stale lock.
##
## Editor and headless runs are exempt so previews and tests can run side by
## side. Set DESKPET_FORCE_SINGLE_INSTANCE=1 to exercise the guard in those runs.

const HOST := "127.0.0.1"
const PORT := 47620
const GREETING := "DESKPET-HELLO"
const SHOW_REQUEST := "DESKPET-SHOW"
const ACK := "DESKPET-OK"
const CONNECT_TIMEOUT_MS := 400
const GREETING_TIMEOUT_MS := 600
const ACK_TIMEOUT_MS := 600
const PEER_TIMEOUT_MS := 2000
const POLL_DELAY_MS := 4

var _server: TCPServer = null
var _peers: Array = []
var _secondary := false
var _parked := false
var _saved_position := Vector2i.ZERO


func _ready() -> void:
	if not _guard_enabled():
		return
	_park_window()
	var server := TCPServer.new()
	if server.listen(PORT, HOST) == OK:
		_server = server
		set_process(true)
		_restore_window()
		print("[SingleInstance] Guard listening on %s:%d" % [HOST, PORT])
		return
	if _probe_existing():
		_secondary = true
		print("[SingleInstance] DeskPet is already running; asking it to show and exiting.")
		get_tree().quit()
		return
	_restore_window()
	push_warning("[SingleInstance] Port %d is in use by another program; running without the single-instance guard." % PORT)


func is_secondary() -> bool:
	return _secondary


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			continue
		peer.put_data(GREETING.to_utf8_buffer())
		_peers.append({
			"peer": peer,
			"buffer": "",
			"deadline": Time.get_ticks_msec() + PEER_TIMEOUT_MS,
		})
	_poll_peers()


func _poll_peers() -> void:
	var index := _peers.size() - 1
	while index >= 0:
		var entry: Dictionary = _peers[index]
		var peer: StreamPeerTCP = entry.get("peer")
		if peer == null:
			_peers.remove_at(index)
			index -= 1
			continue
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			entry["buffer"] = str(entry.get("buffer", "")) + peer.get_utf8_string(available)
			_peers[index] = entry
			if str(entry["buffer"]).contains(SHOW_REQUEST):
				_surface_pet()
				peer.put_data((ACK + "\n").to_utf8_buffer())
				peer.disconnect_from_host()
				_peers.remove_at(index)
				index -= 1
				continue
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.remove_at(index)
			index -= 1
			continue
		if Time.get_ticks_msec() > int(entry.get("deadline", 0)):
			peer.disconnect_from_host()
			_peers.remove_at(index)
		index -= 1


## Synchronous on purpose: a second instance must not build the main scene
## before it knows an existing pet is already running.
func _probe_existing() -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host(HOST, PORT) != OK:
		return false
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			peer.disconnect_from_host()
			return false
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		OS.delay_msec(POLL_DELAY_MS)
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()
		return false

	deadline = Time.get_ticks_msec() + GREETING_TIMEOUT_MS
	var buffer := ""
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			buffer += peer.get_utf8_string(available)
			if buffer.contains(GREETING):
				peer.put_data(SHOW_REQUEST.to_utf8_buffer())
				_wait_for_ack(peer)
				return true
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		OS.delay_msec(POLL_DELAY_MS)
	peer.disconnect_from_host()
	return false


func _wait_for_ack(peer: StreamPeerTCP) -> void:
	var deadline := Time.get_ticks_msec() + ACK_TIMEOUT_MS
	var buffer := ""
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			buffer += peer.get_utf8_string(available)
			if buffer.contains(ACK):
				break
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		OS.delay_msec(POLL_DELAY_MS)
	peer.disconnect_from_host()


## The main window cannot be made invisible directly; park it off-screen while
## the guard checks the port. The owner is repositioned by WindowController when
## the main scene starts.
func _park_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window == null:
		return
	_saved_position = window.position
	_parked = true
	window.position = Vector2i(-32000, -32000)


func _restore_window() -> void:
	if not _parked:
		return
	_parked = false
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window != null:
		window.position = _saved_position


func _surface_pet() -> void:
	var tray := get_node_or_null("/root/TrayService")
	if tray != null and tray.has_method("show_pet"):
		tray.show_pet()
	var main := get_tree().current_scene
	if main != null:
		var world := main.get_node_or_null("PetWorld")
		if world != null:
			world.visible = true
	var window := get_window()
	if window != null and DisplayServer.get_name() != "headless":
		DisplayServer.window_move_to_foreground(window.get_window_id())
	print("[SingleInstance] Existing pet surfaced.")


func _guard_enabled() -> bool:
	if _has_argument("--allow-multiple"):
		return false
	if OS.get_environment("DESKPET_FORCE_SINGLE_INSTANCE") == "1":
		return true
	# Editor builds run the preview and the headless smoke suites; blocking
	# those would make local development depend on whether the pet is open.
	if OS.has_feature("editor"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return true


func _has_argument(argument: String) -> bool:
	for arg in OS.get_cmdline_args():
		if arg == argument:
			return true
	for arg in OS.get_cmdline_user_args():
		if arg == argument:
			return true
	return false


func _exit_tree() -> void:
	if _server != null:
		_server.stop()
		_server = null
	for entry in _peers:
		var peer: StreamPeerTCP = entry.get("peer")
		if peer != null:
			peer.disconnect_from_host()
	_peers.clear()
