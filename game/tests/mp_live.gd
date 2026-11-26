extends Node

# Live two-process co-op integration test. Run two Godot instances against one relay:
#   MP_ROLE=host   MP_HANDSHAKE=<file> MP_RELAY_URL=ws://127.0.0.1:8799 godot --headless --path game res://tests/mp_live.tscn
#   MP_ROLE=client MP_HANDSHAKE=<file> MP_RELAY_URL=ws://127.0.0.1:8799 godot --headless --path game res://tests/mp_live.tscn

var _checks: int = 0
var _fails: int = 0
var _session: GameSession = null
var _role: String = ""
var _handshake: String = ""
var _hs_code: String = ""
var _acks: Dictionary = {}
var _client_id: String = ""


func _assert(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("[PASS] ", msg)
	else:
		_fails += 1
		print("[FAIL] ", msg)


func _ready() -> void:
	_role = OS.get_environment("MP_ROLE")
	_handshake = OS.get_environment("MP_HANDSHAKE")
	var url := OS.get_environment("MP_RELAY_URL")
	if not url.is_empty():
		SaveState.relay_url = url
	SaveState.mic_mode = SaveState.MIC_OFF
	call_deferred("_run")


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _wait_for(pred: Callable, max_frames: int = 900) -> bool:
	for _i in range(max_frames):
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return bool(pred.call())


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_session = packed.instantiate() as GameSession
	get_tree().root.add_child(_session)
	await _frames(5)
	NetRelay.remote_event_received.connect(_on_remote_event)
	if _role == "host":
		await _host_flow()
	else:
		await _client_flow()
	print("=== MP_%s SUMMARY: %d / %d CHECKS PASSED ===" % [_role.to_upper(), _checks - _fails, _checks])
	await _frames(5)
	get_tree().quit(0 if _fails == 0 else 1)


func _on_remote_event(from_id: String, ev: String, data: Dictionary) -> void:
	if ev == "mp_ack":
		_acks[str(data.get("step", ""))] = true
		_client_id = from_id


func _host_flow() -> void:
	NetRelay.create_room(true, 1)
	var ok := await _wait_for(func(): return not NetRelay.room_code.is_empty())
	_assert(ok, "Host created co-op room " + NetRelay.room_code)

	_session.start_match(424242, SaveState.DIFF_NORMAL)
	await _frames(3)
	_session._toggle_door("door_ward", true)
	_session._remove_world_pickup("init_1")
	NetRelay.send_game_event("pickup_taken", {"pid": "init_1", "iid": "bottle"})

	# Publish the code only once the world state above exists, so the late-join
	# snapshot must already contain the open door & the taken pickup.
	var f := FileAccess.open(_handshake, FileAccess.WRITE)
	if f != null:
		f.store_string(NetRelay.room_code)
		f.close()

	ok = await _wait_for(func(): return NetRelay.peers.size() >= 1)
	_assert(ok, "Friend joined the room over WebSocket")
	ok = await _wait_for(func(): return _acks.has("snapshot"))
	_assert(ok, "Late-join friend received & applied live match snapshot")
	await _frames(40)

	var canteen_open := false
	for d in _session._doors:
		if str(d["id"]) == "door_canteen":
			canteen_open = bool(d["is_open"])
	_assert(canteen_open, "Friend's door toggle replicated to host world")
	_assert(not _session._world_pickups.has("init_2"), "Friend's pickup taken replicated to host world")

	NetRelay.send_game_event("stalker_caught_peer", {"target_id": _client_id})
	ok = await _wait_for(func(): return _acks.has("downed"))
	_assert(ok, "Host catch downed the friend (SOS crawl state)")
	NetRelay.send_game_event("revive_peer", {"target_id": _client_id, "heal": true})
	ok = await _wait_for(func(): return _acks.has("revived"))
	_assert(ok, "Host revive restored friend to standing health")

	ok = await _wait_for(func(): return _session.planks_removed)
	_assert(ok, "Friend's crowbar lock clear replicated to host")
	_session._trigger_victory(true)
	ok = await _wait_for(func(): return _acks.has("victory"))
	_assert(ok, "Friend reached shared evacuation victory screen")


func _client_flow() -> void:
	var ok := await _wait_for(func():
		if _hs_code.is_empty() and FileAccess.file_exists(_handshake):
			var ff := FileAccess.open(_handshake, FileAccess.READ)
			if ff != null:
				_hs_code = ff.get_as_text().strip_edges()
				ff.close()
		return not _hs_code.is_empty())
	_assert(ok, "Client read room code handshake")
	NetRelay.join_room(_hs_code)
	ok = await _wait_for(func(): return not NetRelay.room_code.is_empty() and not NetRelay.is_host)
	_assert(ok, "Client joined room as operative (not host)")
	ok = await _wait_for(func(): return _session.phase == GameSession.Phase.PLAYING and _session.current_seed == 424242)
	_assert(ok, "Mid-match snapshot dropped client into host's live descent")
	_assert(not _session._world_pickups.has("init_1"), "Snapshot excluded pickup already taken by host")
	var ward_open := false
	for d in _session._doors:
		if str(d["id"]) == "door_ward":
			ward_open = bool(d["is_open"])
	_assert(ward_open, "Snapshot replicated host's open door")
	NetRelay.send_game_event("mp_ack", {"step": "snapshot"})

	_session._toggle_door("door_canteen", true)
	_session._remove_world_pickup("init_2")
	NetRelay.send_game_event("pickup_taken", {"pid": "init_2", "iid": "screwdriver"})

	ok = await _wait_for(func(): return _session.player.is_downed)
	_assert(ok, "Host stalker catch downed client")
	NetRelay.send_game_event("mp_ack", {"step": "downed"})
	ok = await _wait_for(func(): return not _session.player.is_downed and _session.player.wounds == 0)
	_assert(ok, "Host revive stood client back up with full health")
	NetRelay.send_game_event("mp_ack", {"step": "revived"})

	_session.player.add_item_to_inventory("crowbar")
	_session._interact_exit_gate("crowbar")
	_assert(_session.planks_removed, "Client pried exit planks locally & broadcast")
	ok = await _wait_for(func(): return _session.phase == GameSession.Phase.ENDED)
	_assert(ok, "Host victory ended client match together")
	NetRelay.send_game_event("mp_ack", {"step": "victory"})
	await _frames(10)
