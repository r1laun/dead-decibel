extends Node

signal room_joined(code: String, is_room_host: bool)
signal room_left(reason: String)
signal open_lobbies_received(lobbies: Array)
signal peer_updated(peer_id: String, state: Dictionary)
signal peer_removed(peer_id: String)
signal peer_voice_received(peer_id: String, pcm8: PackedByteArray, level: float)
signal remote_event_received(from_id: String, event_type: String, payload: Dictionary)
signal host_migrated(new_host_id: String, new_host_name: String)
signal relay_error(reason: String)
signal connection_status_changed(status: String)

var ws: WebSocketPeer = null
var connected_to_relay: bool = false
var room_code: String = ""
var is_host: bool = true
var is_public_room: bool = true
var peers: Dictionary = {} # peer_id -> {callsign, pos, yaw, pitch, crouch, suit, device, has_tick, grabbed, dead, frozen}

var _pending_action: Dictionary = {}
var _reconnect_timer: float = 0.0
var _was_in_room_before_drop: bool = false
var _heartbeat_timer: float = 0.0
var _connected_url: String = ""
var _connect_timeout: float = 0.0


static func normalize_relay_url(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	var low := s.to_lower()
	if low.begins_with("https://"):
		s = "wss://" + s.substr(8)
	elif low.begins_with("http://"):
		s = "ws://" + s.substr(7)
	elif not (low.begins_with("ws://") or low.begins_with("wss://")):
		s = "ws://" + s
	return s


func _ready() -> void:
	AcousticBus.voice_chunk_captured.connect(_on_local_voice_chunk)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if not room_code.is_empty():
			send_game_event("call_freeze", {"frozen": true})
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if not room_code.is_empty():
			send_game_event("call_freeze", {"frozen": false})


func get_squad_size() -> int:
	return 1 + peers.size()


func start_solo_mode() -> void:
	_pending_action.clear()
	_was_in_room_before_drop = false
	_connect_timeout = 0.0
	_reconnect_timer = 0.0
	if not room_code.is_empty() or not peers.is_empty():
		leave_room()
	else:
		room_code = ""
		is_host = true
		peers.clear()
	if ws != null:
		ws.close()
		ws = null
	_connected_url = ""
	if connected_to_relay:
		connected_to_relay = false
		connection_status_changed.emit("disconnected")


func ensure_socket(url: String = "") -> void:
	var raw_target := SaveState.relay_url if url.is_empty() else url
	var target := normalize_relay_url(raw_target)
	if target.is_empty():
		connected_to_relay = false
		_connected_url = ""
		connection_status_changed.emit("error")
		if not _pending_action.is_empty():
			_pending_action.clear()
			relay_error.emit("RELAY_UNREACHABLE")
		return

	if ws != null:
		if _connected_url != target:
			if not room_code.is_empty():
				if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
					_send_json({"t": "leave_room", "player_id": SaveState.player_id})
				room_code = ""
				is_host = true
				peers.clear()
				room_left.emit("url_changed")
			ws.close()
			ws = null
			connected_to_relay = false
			_connected_url = ""
			_connect_timeout = 0.0
		else:
			var st := ws.get_ready_state()
			if st == WebSocketPeer.STATE_OPEN or st == WebSocketPeer.STATE_CONNECTING:
				return

	ws = WebSocketPeer.new()
	ws.outbound_buffer_size = 262144
	ws.inbound_buffer_size = 262144
	_connected_url = target
	_connect_timeout = 0.0
	connected_to_relay = false
	var err := ws.connect_to_url(target)
	if err != OK:
		ws = null
		_connected_url = ""
		connected_to_relay = false
		connection_status_changed.emit("error")
		if not _pending_action.is_empty():
			_pending_action.clear()
			relay_error.emit("RELAY_UNREACHABLE")
	else:
		connection_status_changed.emit("connecting")


func create_room(public_lobby: bool = true, biome: int = 1) -> void:
	is_public_room = public_lobby
	_pending_action = {
		"t": "create_room",
		"player_id": SaveState.player_id,
		"callsign": SaveState.callsign,
		"public": public_lobby,
		"biome": biome
	}
	ensure_socket()
	_try_flush_pending()


func join_room(code: String) -> void:
	var clean := code.strip_edges().to_upper()
	if clean.is_empty():
		return
	_pending_action = {
		"t": "join_room",
		"code": clean,
		"player_id": SaveState.player_id,
		"callsign": SaveState.callsign
	}
	ensure_socket()
	_try_flush_pending()


func request_open_lobbies() -> void:
	_pending_action = {
		"t": "list_rooms",
		"player_id": SaveState.player_id
	}
	ensure_socket()
	_try_flush_pending()


func leave_room() -> void:
	_pending_action.clear()
	_was_in_room_before_drop = false
	_connect_timeout = 0.0
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not room_code.is_empty():
		_send_json({"t": "leave_room", "player_id": SaveState.player_id})
	room_code = ""
	is_host = true
	peers.clear()
	room_left.emit("manual")


func copy_invite_to_clipboard() -> String:
	if room_code.is_empty():
		return ""
	var text_ru := "Заходи в МЁРТВЫЙ ДЕЦИБЕЛ! Код нашей комнаты: %s" % room_code
	var text_en := "Join my squad in DEAD DECIBEL! Room code: %s" % room_code
	var msg := text_ru if Loc.current_lang == "ru" else text_en
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(msg)
	return room_code


func broadcast_local_player_state(state: Dictionary) -> void:
	if room_code.is_empty() or ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_send_json({
		"t": "player_state",
		"player_id": SaveState.player_id,
		"state": state
	})


func send_game_event(event_type: String, payload: Dictionary = {}) -> void:
	if room_code.is_empty() or ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_send_json({
		"t": "game_event",
		"player_id": SaveState.player_id,
		"ev": event_type,
		"data": payload
	})


func _on_local_voice_chunk(pcm8: PackedByteArray, level: float) -> void:
	if room_code.is_empty() or ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_send_json({
		"t": "voice",
		"player_id": SaveState.player_id,
		"lvl": snappedf(level, 0.01),
		"b64": Marshalls.raw_to_base64(pcm8)
	})


func _send_json(dict: Dictionary) -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(dict))


func _try_flush_pending() -> void:
	if not _pending_action.is_empty() and ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_json(_pending_action)
		_pending_action.clear()


func _process(delta: float) -> void:
	if ws == null:
		if not _pending_action.is_empty():
			# Retry queued create/join/list actions while socket is down (tunnel warm-up, LTE handoff)
			_reconnect_timer -= delta
			if _reconnect_timer <= 0.0:
				_reconnect_timer = 1.5
				ensure_socket()
		elif _was_in_room_before_drop and not room_code.is_empty():
			_reconnect_timer -= delta
			if _reconnect_timer <= 0.0:
				_reconnect_timer = 2.0
				_pending_action = {
					"t": "rejoin_room",
					"code": room_code,
					"player_id": SaveState.player_id,
					"callsign": SaveState.callsign
				}
				ensure_socket()
		return

	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_CONNECTING or st == WebSocketPeer.STATE_CLOSING:
		_connect_timeout += delta
		if _connect_timeout >= 6.0:
			_connect_timeout = 0.0
			ws.close()
			ws = null
			_connected_url = ""
			connected_to_relay = false
			connection_status_changed.emit("error")
			if not _pending_action.is_empty():
				_pending_action.clear()
				relay_error.emit("RELAY_UNREACHABLE")
	elif st == WebSocketPeer.STATE_OPEN:
		_connect_timeout = 0.0
		if not connected_to_relay:
			connected_to_relay = true
			connection_status_changed.emit("connected")
		_try_flush_pending()
		_heartbeat_timer += delta
		if _heartbeat_timer >= 3.0:
			_heartbeat_timer = 0.0
			_send_json({"t": "ping", "player_id": SaveState.player_id})

		while ws.get_available_packet_count() > 0:
			var raw := ws.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(raw)
			if typeof(parsed) == TYPE_DICTIONARY:
				_handle_packet(parsed)
	elif st == WebSocketPeer.STATE_CLOSED:
		var was_connected := connected_to_relay
		connected_to_relay = false
		ws = null
		_connected_url = ""
		_connect_timeout = 0.0
		if not room_code.is_empty():
			# Enter 25-second auto-reconnect grace window for phone calls / LTE handoff
			_was_in_room_before_drop = true
			_reconnect_timer = 1.2
			if was_connected:
				connection_status_changed.emit("disconnected")
		elif not _pending_action.is_empty():
			_pending_action.clear()
			connection_status_changed.emit("error")
			relay_error.emit("RELAY_UNREACHABLE")
		elif was_connected:
			connection_status_changed.emit("disconnected")


func _handle_packet(msg: Dictionary) -> void:
	var mtype := str(msg.get("t", ""))
	match mtype:
		"error":
			var reason := str(msg.get("reason", "UNKNOWN"))
			_pending_action.clear()
			if not room_code.is_empty() and _was_in_room_before_drop and reason == "ROOM_NOT_FOUND":
				_was_in_room_before_drop = false
				room_code = ""
				is_host = true
				peers.clear()
				room_left.emit(reason)
			relay_error.emit(reason)
		"room_joined":
			room_code = str(msg.get("code", ""))
			is_host = str(msg.get("host_id", "")) == SaveState.player_id
			_was_in_room_before_drop = true
			peers.clear()
			if typeof(msg.get("members")) == TYPE_ARRAY:
				for m in msg["members"]:
					if typeof(m) == TYPE_DICTIONARY:
						var pid := str(m.get("player_id", ""))
						if pid != "" and pid != SaveState.player_id:
							peers[pid] = {
								"callsign": str(m.get("callsign", "LISTENER")),
								"frozen": bool(m.get("frozen", false))
							}
							peer_updated.emit(pid, peers[pid])
			room_joined.emit(room_code, is_host)

		"rooms_list":
			var arr: Array = msg.get("rooms", []) if typeof(msg.get("rooms")) == TYPE_ARRAY else []
			open_lobbies_received.emit(arr)

		"peer_joined":
			var pid := str(msg.get("player_id", ""))
			if pid != "" and pid != SaveState.player_id:
				peers[pid] = {
					"callsign": str(msg.get("callsign", "LISTENER")),
					"frozen": false
				}
				peer_updated.emit(pid, peers[pid])

		"peer_left":
			var pid := str(msg.get("player_id", ""))
			if peers.has(pid):
				peers.erase(pid)
				peer_removed.emit(pid)

		"peer_frozen":
			var pid := str(msg.get("player_id", ""))
			var frz := bool(msg.get("frozen", false))
			if peers.has(pid):
				peers[pid]["frozen"] = frz
				peer_updated.emit(pid, peers[pid])

		"host_migrated":
			var new_host := str(msg.get("host_id", ""))
			var new_name := str(msg.get("host_callsign", "LISTENER"))
			is_host = (new_host == SaveState.player_id)
			host_migrated.emit(new_host, new_name)

		"player_state":
			var pid := str(msg.get("player_id", ""))
			if pid != "" and pid != SaveState.player_id and typeof(msg.get("state")) == TYPE_DICTIONARY:
				var incoming: Dictionary = msg["state"]
				if not peers.has(pid):
					peers[pid] = {}
				for k in incoming.keys():
					peers[pid][k] = incoming[k]
				peer_updated.emit(pid, peers[pid])

		"voice":
			var pid := str(msg.get("player_id", ""))
			if pid != "" and pid != SaveState.player_id:
				var b64 := str(msg.get("b64", ""))
				if not b64.is_empty():
					var raw := Marshalls.base64_to_raw(b64)
					peer_voice_received.emit(pid, raw, float(msg.get("lvl", 0.5)))

		"game_event":
			var pid := str(msg.get("player_id", ""))
			if pid != SaveState.player_id:
				var ev := str(msg.get("ev", ""))
				var data: Dictionary = msg.get("data", {}) if typeof(msg.get("data")) == TYPE_DICTIONARY else {}
				if ev == "call_freeze" and peers.has(pid):
					peers[pid]["frozen"] = bool(data.get("frozen", false))
					peer_updated.emit(pid, peers[pid])
				else:
					remote_event_received.emit(pid, ev, data)
