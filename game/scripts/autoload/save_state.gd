extends Node

signal profile_updated

const SAVE_PATH := "user://dead_decibel_profile.json"

const DIFF_PRACTICE := 0
const DIFF_NORMAL := 1
const DIFF_NIGHTMARE := 2

const MIC_AUTO := 0
const MIC_PTT := 1
const MIC_OFF := 2

var player_id: String = ""
var callsign: String = "SURVIVOR"
var language_override: String = "en"
var difficulty: int = DIFF_NORMAL
var look_sensitivity: float = 1.0
var master_volume: float = 0.88
var mic_mode: int = MIC_AUTO
var gyro_enabled: bool = false
var haptics_enabled: bool = true
var reduce_motion: bool = false
var tutorial_completed: bool = false
var relay_url: String = "ws://127.0.0.1:8787"

var total_escapes: int = 0
var best_escape_sec: float = 0.0

# Per-instance session overrides (second co-op window on one Mac / tunnel launchers).
# Never persisted back into the shared profile file.
var _env_player_id: String = ""
var _env_callsign: String = ""
var _env_relay_url: String = ""
var _env_mic_mode: String = ""
var _profile_player_id: String = ""
var _profile_callsign: String = "SURVIVOR"
var _profile_relay_url: String = "ws://127.0.0.1:8787"
var _profile_mic_mode: int = 0

# Legacy compatibility getters if referenced by relay
var ptt_mode: bool:
	get:
		return mic_mode == MIC_PTT


func _ready() -> void:
	load_profile()
	_profile_player_id = player_id
	_profile_callsign = callsign
	_profile_relay_url = relay_url
	_profile_mic_mode = mic_mode
	_env_player_id = OS.get_environment("ECHO7_PLAYER_ID").strip_edges()
	_env_callsign = OS.get_environment("ECHO7_CALLSIGN").strip_edges()
	_env_relay_url = OS.get_environment("ECHO7_RELAY_URL").strip_edges()
	if not _env_player_id.is_empty():
		player_id = _env_player_id.left(24)
	if not _env_callsign.is_empty():
		callsign = _env_callsign.left(14)
	if not _env_relay_url.is_empty() and (_env_relay_url.begins_with("ws://") or _env_relay_url.begins_with("wss://")):
		relay_url = _env_relay_url
	var env_mic := OS.get_environment("ECHO7_MIC_MODE").strip_edges()
	if env_mic in ["0", "1", "2"]:
		_env_mic_mode = env_mic
		mic_mode = int(env_mic)
	apply_audio_settings()


func _generate_id() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var suffix := ""
	for _i in range(5):
		suffix += chars[rng.randi_range(0, chars.length() - 1)]
	return "SRV-" + suffix


func apply_audio_settings() -> void:
	var db := linear_to_db(clampf(master_volume, 0.02, 1.5))
	AudioServer.set_bus_volume_db(0, db)


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		player_id = _generate_id()
		language_override = "en"
		Loc.set_language("en")
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		player_id = _generate_id()
		language_override = "en"
		Loc.set_language("en")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		player_id = _generate_id()
		language_override = "en"
		Loc.set_language("en")
		return
	var d: Dictionary = parsed
	player_id = str(d.get("player_id", _generate_id()))
	callsign = str(d.get("callsign", "SURVIVOR"))
	if callsign.strip_edges().is_empty():
		callsign = "SURVIVOR"
	language_override = str(d.get("language_override", "en"))
	if language_override in ["ru", "en"]:
		Loc.set_language(language_override)
	else:
		language_override = "en"
		Loc.set_language("en")
	difficulty = clampi(int(d.get("difficulty", DIFF_NORMAL)), 0, 2)
	look_sensitivity = clampf(float(d.get("look_sensitivity", 1.0)), 0.25, 3.0)
	master_volume = clampf(float(d.get("master_volume", 0.88)), 0.05, 1.2)
	mic_mode = clampi(int(d.get("mic_mode", MIC_AUTO)), 0, 2)
	gyro_enabled = bool(d.get("gyro_enabled", false))
	haptics_enabled = bool(d.get("haptics_enabled", true))
	reduce_motion = bool(d.get("reduce_motion", false))
	tutorial_completed = bool(d.get("tutorial_completed", false))
	relay_url = str(d.get("relay_url", "ws://127.0.0.1:8787"))
	total_escapes = maxi(0, int(d.get("total_escapes", 0)))
	best_escape_sec = maxf(0.0, float(d.get("best_escape_sec", 0.0)))


func save_profile() -> void:
	var data := {
		"player_id": _profile_player_id if not _env_player_id.is_empty() else player_id,
		"callsign": _profile_callsign if not _env_callsign.is_empty() else callsign,
		"language_override": Loc.current_lang,
		"difficulty": difficulty,
		"look_sensitivity": look_sensitivity,
		"master_volume": master_volume,
		"mic_mode": _profile_mic_mode if not _env_mic_mode.is_empty() else mic_mode,
		"gyro_enabled": gyro_enabled,
		"haptics_enabled": haptics_enabled,
		"reduce_motion": reduce_motion,
		"tutorial_completed": tutorial_completed,
		"relay_url": _profile_relay_url if not _env_relay_url.is_empty() else relay_url,
		"total_escapes": total_escapes,
		"best_escape_sec": best_escape_sec,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
	apply_audio_settings()
	profile_updated.emit()


func record_escape(elapsed_sec: float) -> void:
	total_escapes += 1
	if best_escape_sec <= 0.0 or elapsed_sec < best_escape_sec:
		best_escape_sec = elapsed_sec
	save_profile()
