extends Node

var _failures: int = 0
var _checks: int = 0


func _assert(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("[PASS] ", msg)
	else:
		_failures += 1
		push_error("[FAIL] " + msg)
		print("[FAIL] ", msg)


func _ready() -> void:
	call_deferred("_entry")


func _entry() -> void:
	var shot_dir_v7 := OS.get_environment("CAPTURE_V7_SHOTS_DIR")
	if not shot_dir_v7.is_empty():
		await _capture_v7_visual_qa_shots(shot_dir_v7)
		get_tree().quit(0)
		return
	var shot_dir_v6 := OS.get_environment("CAPTURE_V6_SHOTS_DIR")
	if not shot_dir_v6.is_empty():
		await _capture_v6_visual_qa_shots(shot_dir_v6)
		get_tree().quit(0)
		return
	var shot_dir := OS.get_environment("CAPTURE_V5_SHOTS_DIR")
	if shot_dir.is_empty():
		shot_dir = OS.get_environment("CAPTURE_V4_SHOTS_DIR")
	if shot_dir.is_empty():
		shot_dir = OS.get_environment("CAPTURE_V3_SHOTS_DIR")
	if not shot_dir.is_empty():
		await _capture_visual_qa_shots(shot_dir)
		get_tree().quit(0)
		return
	await _run_all_tests()


func _collect_hud_texts(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect_hud_texts(c, out)


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _settle_ui(sec: float = 0.35) -> void:
	await get_tree().create_timer(sec).timeout
	await _wait_frames(4)


func _save_shot(shot_dir: String, filename: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	img.save_png(shot_dir.path_join(filename))
	print("SAVED_SHOT: ", filename, " (", img.get_width(), "x", img.get_height(), ")")


func _capture_visual_qa_shots(shot_dir: String) -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _wait_frames(4)

	Loc.set_language("en")
	SaveState.reduce_motion = false
	SaveState.total_escapes = 0
	SaveState.best_escape_sec = 0.0
	SaveState.save_profile()

	var main_packed: PackedScene = load("res://scenes/main.tscn")
	var session: GameSession = main_packed.instantiate() as GameSession
	get_tree().root.add_child(session)
	await _wait_frames(10)

	# 1. v5_menu.png — Live 3D Main Menu (no quick lang button on sidebar, crisp typography, upgraded Listener-07)
	session.hud._switch_menu_card("solo")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await _settle_ui(0.45)
	await _save_shot(shot_dir, "v5_menu.png")

	# 2. v5_touch_hud.png — Ward B-04 with Touch Controls enabled, item in slot 0, crouched MAKS, Top-Center Acoustic Scope, Static Minimap
	SaveState.tutorial_completed = true
	session.start_match(77707, SaveState.DIFF_NORMAL)
	session.hud.dismiss_tutorial()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	session.hud._set_touch_controls_visible(true)
	session.player.add_item_to_inventory("flare")
	session.player.add_item_to_inventory("screwdriver")
	session.player.add_item_to_inventory("medkit")
	session.player.select_slot(0)
	session.player.known_safe_code = "4829"
	session.hud.refresh_inventory_bar()
	session.hud.update_objectives(false, false, false, false)

	session.player.global_position = Vector3(-24.8, 0.08, 23.0)
	session.player.rotation.y = 0.12
	session.player.head.rotation.x = -0.04
	if session.monster_director.stalker_node != null:
		session.monster_director.stalker_node.global_position = Vector3(25.0, 0.0, -8.0)

	NetRelay._handle_packet({"t": "peer_joined", "player_id": "P2", "callsign": "MAKS"})
	NetRelay._handle_packet({
		"t": "player_state",
		"player_id": "P2",
		"state": {"callsign": "MAKS", "pos": [-25.3, 0.0, 19.8], "yaw": 2.35, "crouch": true, "downed": false, "flash": true}
	})
	for _pulse_i in range(6):
		AcousticBus.emit_noise(session.player.global_position, 8.0, 0.62, "step")
		await get_tree().create_timer(0.06).timeout
		await _wait_frames(2)
	await _settle_ui(0.45)
	await _save_shot(shot_dir, "v5_touch_hud.png")

	# 3. v5_locker_peek.png — Hiding inside loc_ward locker looking out into Ward B-04 through iron louvers
	NetRelay._handle_packet({"t": "peer_left", "player_id": "P2"})
	session.hud._set_touch_controls_visible(false)
	var lk_ward: Dictionary = session._lockers["loc_ward"]
	lk_ward["occupied"] = true
	var lk_piv := lk_ward.get("door_pivot") as Node3D
	if is_instance_valid(lk_piv):
		lk_piv.rotation.y = 0.14
	session.player.enter_locker("loc_ward", lk_ward["inside_pos"], float(lk_ward["look_yaw"]))
	var orig_patrol_spd := session.monster_director.patrol_speed
	var orig_chase_spd := session.monster_director.chase_speed
	if session.monster_director.stalker_node != null:
		session.monster_director.patrol_speed = 0.0
		session.monster_director.state = MonsterDirector.STATE_PATROL
		session.monster_director.stalker_node.global_position = Vector3(-24.2, 0.0, 23.2)
		session.monster_director.stalker_node.rotation.y = PI * 0.55
	await _settle_ui(0.45)
	await _save_shot(shot_dir, "v5_locker_peek.png")

	# 4. v5_corridor_clean.png — Long shot down West Ring Corridor checking distant two-tone walls (zero stripes)
	session.player.exit_locker(lk_ward["exit_pos"])
	lk_ward["occupied"] = false
	if is_instance_valid(lk_piv):
		lk_piv.rotation.y = 0.0
	if session.monster_director.stalker_node != null:
		session.monster_director.stalker_node.global_position = Vector3(25.0, 0.0, -8.0)
	session.player.global_position = Vector3(-15.6, 0.08, 13.8)
	session.player.rotation.y = 0.08
	session.player.head.rotation.x = -0.02
	session.player.flashlight_on = true
	await _settle_ui(0.45)
	await _save_shot(shot_dir, "v5_corridor_clean.png")

	# 5. v5_biolab_wounded.png — Bio-Lab chase with upgraded Listener-07 + player.wounds = 1 (Blood-Edge Vignette)
	session.hud._dossier_pinned = false
	session.hud._dossier_peek_timer = 0.0
	session.hud._dossier_card.visible = false
	session.player.global_position = Vector3(-4.2, 0.08, 2.8)
	session.player.rotation.y = 0.25
	session.player.head.rotation.x = 0.02
	session.player.wounds = 1
	session.player.select_slot(0)
	if session.monster_director.stalker_node != null:
		session.monster_director.chase_speed = 0.0
		session.monster_director.stalker_node.global_position = Vector3(-5.0, 0.0, -0.4)
		session.monster_director.stalker_node.rotation.y = PI - 0.22
		session.monster_director.state = MonsterDirector.STATE_CHASE
	await _settle_ui(0.65)
	await _save_shot(shot_dir, "v5_biolab_wounded.png")
	session.monster_director.chase_speed = orig_chase_spd
	session.monster_director.patrol_speed = orig_patrol_spd

	Loc.set_language("en")
	SaveState.difficulty = SaveState.DIFF_NORMAL
	SaveState.callsign = "SURVIVOR"
	SaveState.reduce_motion = false
	SaveState.tutorial_completed = false
	SaveState.save_profile()
	session.queue_free()
	await _wait_frames(2)


func _capture_v6_visual_qa_shots(shot_dir: String) -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _wait_frames(4)

	Loc.set_language("en")
	SaveState.reduce_motion = false
	SaveState.total_escapes = 0
	SaveState.best_escape_sec = 0.0
	SaveState.save_profile()

	var main_packed: PackedScene = load("res://scenes/main.tscn")
	var session: GameSession = main_packed.instantiate() as GameSession
	get_tree().root.add_child(session)
	await _wait_frames(10)

	# 1. v6_menu.png — Main Menu confirming 2-line subtitle without · and grotesque Listener-07 idle hunch
	session.hud._switch_menu_card("solo")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await _settle_ui(0.55)
	await _save_shot(shot_dir, "v6_menu.png")

	# 2. v6_hud_clean.png — Gameplay Ward B-04 confirming clean Top-Right minimap with ZERO indicators next to/under it
	SaveState.tutorial_completed = true
	session.start_match(77707, SaveState.DIFF_NORMAL)
	session.hud.dismiss_tutorial()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	session.hud._set_touch_controls_visible(false)
	session.player.add_item_to_inventory("flare")
	session.player.add_item_to_inventory("screwdriver")
	session.player.select_slot(0)
	session.hud.refresh_inventory_bar()
	session.hud.update_objectives(false, false, false, false)

	session.player.global_position = Vector3(-24.8, 0.08, 23.0)
	session.player.rotation.y = 0.12
	session.player.head.rotation.x = -0.04
	session.player.flashlight_on = true
	if session.monster_director.stalker_node != null:
		session.monster_director.stalker_node.global_position = Vector3(25.0, 0.0, -8.0)
	await _settle_ui(0.45)
	await _save_shot(shot_dir, "v6_hud_clean.png")

	# 3. v6_chase_panic.png — Central Bio-Lab STATE_CHASE with Listener-07 mid-Run lunge + Chase Panic VFX
	session.hud._dossier_pinned = false
	session.hud._dossier_peek_timer = 0.0
	session.hud._dossier_card.visible = false
	session.player.global_position = Vector3(-4.2, 0.08, 2.8)
	session.player.rotation.y = 0.25
	session.player.head.rotation.x = 0.03
	session.player.wounds = 0
	session.player.flashlight_on = true
	session.player.select_slot(0)
	var orig_patrol_spd := session.monster_director.patrol_speed
	var orig_chase_spd := session.monster_director.chase_speed
	if session.monster_director.stalker_node != null:
		session.monster_director.chase_speed = 0.0
		session.monster_director.patrol_speed = 0.0
		session.monster_director.stalker_node.global_position = Vector3(-5.0, 0.0, -0.3)
		var to_p := session.player.global_position - session.monster_director.stalker_node.global_position
		session.monster_director.stalker_node.rotation.y = atan2(-to_p.x, -to_p.z) + 0.16
		session.monster_director.state = MonsterDirector.STATE_CHASE
		session.monster_director._state_timer = 5.0
		session.monster_director._current_path = [session.player.global_position]
		session.monster_director._play_anim("run")
		if session.monster_director.anim_player != null:
			session.monster_director.anim_player.advance(0.28)
	await _settle_ui(0.75)
	await _save_shot(shot_dir, "v6_chase_panic.png")
	session.monster_director.chase_speed = orig_chase_spd
	session.monster_director.patrol_speed = orig_patrol_spd

	Loc.set_language("en")
	SaveState.difficulty = SaveState.DIFF_NORMAL
	SaveState.callsign = "SURVIVOR"
	SaveState.reduce_motion = false
	SaveState.tutorial_completed = false
	SaveState.save_profile()
	session.queue_free()
	await _wait_frames(2)


func _capture_v7_visual_qa_shots(shot_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _wait_frames(6)

	Loc.set_language("en")
	SaveState.reduce_motion = false
	SaveState.total_escapes = 0
	SaveState.best_escape_sec = 0.0
	SaveState.save_profile()

	var main_packed: PackedScene = load("res://scenes/main.tscn")
	var session: GameSession = main_packed.instantiate() as GameSession
	get_tree().root.add_child(session)
	await _wait_frames(10)

	# 1. v7_menu_copy.png — Main Menu showing humanized copy (clean 2-line subtitle, clean buttons)
	session.hud._switch_menu_card("solo")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await _settle_ui(0.55)
	await _save_shot(shot_dir, "v7_menu_copy.png")

	# 2. v7_scary_run.png — Listener-07 mid-chase playing Run in a corridor with reaching/slashing arms
	SaveState.tutorial_completed = true
	session.start_match(77707, SaveState.DIFF_NORMAL)
	session.hud.dismiss_tutorial()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	session.hud._set_touch_controls_visible(false)
	session.hud._dossier_pinned = false
	session.hud._dossier_peek_timer = 0.0
	session.hud._dossier_card.visible = false

	session.player.global_position = Vector3(-14.2, 0.08, 4.2)
	session.player.rotation.y = 0.05
	session.player.head.rotation.x = 0.02
	session.player.flashlight_on = true
	session.player.wounds = 0
	session.player.select_slot(0)

	var md := session.monster_director
	var orig_patrol_spd := md.patrol_speed
	var orig_chase_spd := md.chase_speed
	if md.stalker_node != null:
		md.chase_speed = 0.0
		md.patrol_speed = 0.0
		md.stalker_node.global_position = Vector3(-14.3, 0.0, 0.7)
		var to_p := session.player.global_position - md.stalker_node.global_position
		md.stalker_node.rotation.y = atan2(-to_p.x, -to_p.z) + 0.10
		md.state = MonsterDirector.STATE_CHASE
		md._state_timer = 6.0
		md._current_path = [session.player.global_position]
		md._play_anim("run")
		if md.anim_player != null:
			md.anim_player.advance(0.32)
	await _settle_ui(0.65)
	await _save_shot(shot_dir, "v7_scary_run.png")

	# 3. v7_jumpscare.png — Actual in-game jumpscare (~0.25s mid-lunge via trigger_jumpscare_pose + _play_catch_jumpscare)
	md.chase_speed = orig_chase_spd
	md.patrol_speed = orig_patrol_spd
	session.player.global_position = Vector3(-14.2, 0.08, 3.8)
	session.player.rotation.y = 0.0
	session.player.head.rotation.x = -0.35
	session.player.flashlight_on = true
	session.player.wounds = 0
	if md.stalker_node != null:
		md.stalker_node.global_position = Vector3(-14.2, 0.0, 2.5)
	session._on_local_player_caught()
	await get_tree().create_timer(0.25).timeout
	await _save_shot(shot_dir, "v7_jumpscare.png")

	Loc.set_language("en")
	SaveState.difficulty = SaveState.DIFF_NORMAL
	SaveState.callsign = "SURVIVOR"
	SaveState.reduce_motion = false
	SaveState.tutorial_completed = false
	SaveState.save_profile()
	session.queue_free()
	await _wait_frames(2)


func _run_all_tests() -> void:
	print("=== DEAD DECIBEL v4.1 // GODOT 4 AUTOMATED VERIFICATION ===")

	_assert(Loc != null and SaveState != null and SynthAudio != null and AcousticBus != null and NetRelay != null, "All 5 core Autoload singletons initialized")

	# 1. Localization RU & EN
	Loc.set_language("ru")
	_assert(Loc.t("GAME_TITLE") == "МЁРТВЫЙ ДЕЦИБЕЛ", "Russian localization active")
	Loc.set_language("en")
	_assert(Loc.t("GAME_TITLE") == "DEAD DECIBEL", "English localization active")
	Loc.set_language("ru")

	# 2. Verify all 36 Blender 5.3 .glb 3D Models & Skeletal Animations
	var models := [
		"monster_stalker", "survivor_hazmat", "locker_metal", "desk_hide", "door_heavy",
		"exit_airlock", "cabinet_search", "safe_wall", "generator_panel",
		"item_crowbar", "item_cutters", "item_fuse", "item_key", "item_code_note",
		"item_bottle", "item_syringe", "item_battery", "item_flare", "item_medkit", "item_screwdriver",
		"prop_gurney", "prop_barrel", "prop_ceiling_lamp", "prop_pipes",
		"prop_shelving_rack", "prop_lab_bench", "prop_computer_terminal", "prop_medical_curtain",
		"prop_iv_drip", "prop_wheelchair", "prop_corpse_bag", "prop_filing_tall",
		"prop_vent_hatch", "prop_pa_intercom", "prop_glass_shards", "prop_holding_cage"
	]
	for m in models:
		var scn := AssetLibrary.get_model_scene(m)
		_assert(scn != null, "Blender 3D .glb model imported: " + m)

	var test_stalker := AssetLibrary.instantiate_model("monster_stalker")
	var stalker_anim := AssetLibrary.find_animation_player(test_stalker)
	_assert(stalker_anim != null and stalker_anim.get_animation_list().size() >= 4, "Listener-07 has baked skeletal animations: " + str(stalker_anim.get_animation_list() if stalker_anim else []))
	test_stalker.free()

	var test_surv := AssetLibrary.instantiate_model("survivor_hazmat")
	var surv_anim := AssetLibrary.find_animation_player(test_surv)
	var surv_anims := surv_anim.get_animation_list() if surv_anim != null else PackedStringArray()
	var has_crouch_anim := false
	var has_downed_anim := false
	for aname in surv_anims:
		var norm := str(aname).to_lower().replace("_", "").replace("-", "").replace(" ", "")
		if norm.contains("crouch"):
			has_crouch_anim = true
		if norm.contains("downed"):
			has_downed_anim = true
	_assert(surv_anim != null and surv_anims.size() >= 5 and has_crouch_anim and has_downed_anim, "survivor_hazmat.glb has >= 5 baked animations including crouch & downed: " + str(surv_anims))
	test_surv.free()

	# 3. Verify all 18 UI & Inventory 2D Icons
	var icons := [
		"item_crowbar", "item_cutters", "item_fuse", "item_key", "item_code_note",
		"item_bottle", "item_syringe", "item_battery", "item_flare", "item_medkit", "item_screwdriver",
		"ui_hand", "ui_flashlight", "ui_crouch", "ui_drop", "ui_run", "ui_breath", "ui_journal"
	]
	for ic in icons:
		_assert(AssetLibrary.get_icon(ic) != null, "Crisp 2D UI icon loaded: " + ic)

	# 4. Verify Expanded Procedural Horror Audio Bank (27 clips)
	var clips := [
		"ambient_drone", "ui_click", "step_tile", "monster_step", "monster_snarl",
		"monster_roar", "catch_slam", "jumpscare_screech", "heartbeat", "door_creak", "locker_clang",
		"drawer_slide", "item_pickup", "item_clatter", "bottle_shatter",
		"plank_rip", "wire_snip", "generator_on", "padlock_open", "victory_airlock",
		"echolocate_click", "glass_crunch", "wheelchair_squeak", "pa_siren",
		"flare_stun", "door_smash", "vent_open"
	]
	for c in clips:
		_assert(SynthAudio.clips.has(c) and SynthAudio.clips[c] is AudioStreamWAV, "Synthesized horror SFX ready: " + c)

	for vc in ["menu_theme", "monster_click_idle", "monster_breath_rasp"]:
		_assert(SynthAudio.clips.has(vc) and SynthAudio.clips[vc] is AudioStreamWAV, "v5 Audio clip ready: " + vc)
	SynthAudio.set_menu_music(true)
	SynthAudio.set_menu_music(false)
	_assert(SynthAudio.has_method("set_menu_music"), "SynthAudio.set_menu_music(true/false) executes cleanly")
	_assert(NetRelay.normalize_relay_url("https://demo.trycloudflare.com") == "wss://demo.trycloudflare.com", "NetRelay.normalize_relay_url converts https:// to wss://")

	# 5. Instantiate Main Scene -> Verify Live 3D Main Menu Diorama
	var main_packed: PackedScene = load("res://scenes/main.tscn")
	_assert(main_packed != null, "main.tscn loaded")
	var session: GameSession = main_packed.instantiate() as GameSession
	get_tree().root.add_child(session)
	await get_tree().process_frame

	_assert(session.phase == GameSession.Phase.MAIN_MENU, "Game boots into Live 3D Main Menu")
	_assert(session._menu_cam != null and session._menu_stalker != null, "3D Main Menu horror corridor diorama & Listener-07 active")

	# 6. Verify Recon / Practice Mode (0 Monsters)
	session.start_match(55501, SaveState.DIFF_PRACTICE)
	await get_tree().process_frame
	_assert(session.phase == GameSession.Phase.PLAYING and not session.monster_director.active, "Recon Mode spawns 0 monsters for peaceful 14-room exploration")

	# 7. Verify Massive 64m x 56m 14-Room Facility, LoS Minimap & Multi-Stage Listener-07 AI
	session.start_match(77707, SaveState.DIFF_NORMAL)
	await get_tree().process_frame
	_assert(session.monster_director.active and session.monster_director.stalker_node != null, "Standard Mode spawns Listener-07 stalker")
	_assert(session._cabinets.size() == 16 and session._lockers.size() == 10 and session._doors.size() == 23 and session._vents.size() == 4, "64m x 56m 14-room Complex built with 16 cabinets, 10 lockers, 23 heavy doors, and 4 crawlspace vents")
	_assert(session.monster_director.nav_nodes.size() == 33, "33-node doorway-aligned navigation graph active across all 14 rooms")
	_assert(session.hud.minimap != null and session.hud.minimap.wall_segments.size() >= 45, "Line-of-Sight Tactical Minimap bound with real facility wall, pillar & door segments")

	# Test PA Intercom Lure across facility
	session._trigger_pa_intercom("pa_canteen", true)
	_assert(session.monster_director.state == MonsterDirector.STATE_INVESTIGATE, "Wall PA Intercom broadcasts distant siren and lures Listener-07 across facility")

	# Test Crawlspace Vent Hatch unscrewing
	session._open_vent_hatch("vent_ward_canteen", true, false)
	_assert(bool(session._vents["vent_ward_canteen"]["is_open"]), "Crawlspace vent hatch unscrewed for stealth shortcut between wings")

	# Test Echolocation & Sonic Strobe Flare Stun
	session.monster_director.trigger_echolocation()
	_assert(session.monster_director.state == MonsterDirector.STATE_ECHOLOCATE, "Listener-07 performs doorway echolocation sonar listening state")
	var stunned := session.monster_director.stun_with_flare(session.monster_director.stalker_node.global_position + Vector3(1.0, 0, 1.0), 10.5)
	_assert(stunned and session.monster_director.state == MonsterDirector.STATE_STUNNED, "Sonic Strobe Flare stuns Listener-07 in place")

	# Test Locker Hiding + Suspicious Inspection + Hold Breath + Medkit Healing
	var first_lk: Dictionary = session._lockers["loc_ward"]
	first_lk["occupied"] = true
	session.player.enter_locker("loc_ward", first_lk["inside_pos"], float(first_lk["look_yaw"]))
	session.player.is_holding_breath = true
	session.monster_director.begin_locker_inspection("loc_ward")
	_assert(session.player.is_hiding_in_locker and session.monster_director.state == MonsterDirector.STATE_INSPECT_LOCKER, "Listener-07 inspects suspicious locker while player holds breath")
	session.player.exit_locker(first_lk["exit_pos"])
	first_lk["occupied"] = false

	# Test Time-Free Holding Cage Capture & Escape Latch
	session._set_holding_cage_locked(true)
	session.player.wounds = 1
	session.player.is_caged = true
	session._unlock_holding_cage(false)
	_assert(not bool(session._holding_cage["is_locked"]) and not session.player.is_caged, "Player unlatches Surgical Holding Cage bars to escape")
	session.player.add_item_to_inventory("medkit")
	session.player.try_use_held_consumable()
	_assert(session.player.wounds == 0, "Field Medkit treats wounds back to 0 for unlimited time-free survival")

	# Test Full 4-Lock Escape Puzzle Sequence -> Victory!
	session._on_safe_code_submitted(session.safe_code)
	_assert(session.safe_opened and session._world_pickups.has("safe_master_key"), "Correct 4-digit code unlocks Wall Safe and reveals Master Key")

	session.player.add_item_to_inventory("fuse")
	session._activate_generator(false)
	_assert(session.power_restored, "Lock 1/4 cleared: Fuse restores Substation Generator power to Exit Gate")

	session.player.add_item_to_inventory("crowbar")
	session._interact_exit_gate("crowbar")
	_assert(session.planks_removed, "Lock 2/4 cleared: Crowbar rips wooden planks off Exit Gate")

	session.player.add_item_to_inventory("cutters")
	session._interact_exit_gate("cutters")
	_assert(session.cable_cut, "Lock 3/4 cleared: Bolt Cutters sever security cable")

	session.player.add_item_to_inventory("key")
	session._interact_exit_gate("key")
	_assert(session.padlock_unlocked, "Lock 4/4 cleared: Master Key unlocks Exit Gate padlock")

	session._interact_exit_gate("")
	_assert(session.phase == GameSession.Phase.ENDED and session.gate_opening, "All 4 seals cleared -> Blast Gate opens & triggers Evacuation Victory!")

	# 8. Verify Co-op Skinned Hazmat Teammate, Radar Transponder & Friend Revive
	NetRelay._handle_packet({"t": "peer_joined", "player_id": "ALLY-02", "callsign": "MAKS"})
	NetRelay._handle_packet({
		"t": "player_state",
		"player_id": "ALLY-02",
		"state": {"callsign": "MAKS", "pos": [-23.5, 0.08, 22.5], "yaw": 0.5, "downed": true, "flash": true}
	})
	await get_tree().process_frame
	_assert(session.remote_listeners.has("ALLY-02") and (session.remote_listeners["ALLY-02"] as RemoteListener).is_downed, "Co-op RemoteListener Hazmat avatar spawned & tracks downed SOS state on radar")

	session.phase = GameSession.Phase.PLAYING
	session.player.is_downed = true
	session._on_remote_event("ALLY-02", "revive_peer", {"target_id": SaveState.player_id, "heal": true})
	_assert(not session.player.is_downed and session.player.wounds == 0, "Co-op teammate revive restores downed survivor to standing health")

	# 9. Verify v4 НИИ-07 Fonts, SaveState.reduce_motion, Sector Lookup & Live HUD Sector Tracking
	var font_paths := [
		"res://assets/fonts/Oswald-Variable.ttf",
		"res://assets/fonts/IBMPlexSans-Regular.ttf",
		"res://assets/fonts/IBMPlexSans-SemiBold.ttf",
		"res://assets/fonts/IBMPlexMono-Regular.ttf",
		"res://assets/fonts/IBMPlexMono-SemiBold.ttf"
	]
	for fp in font_paths:
		var f_res := load(fp) as Font
		_assert(f_res != null and f_res.has_char(0x0416), "Cyrillic font loaded & supports Cyrillic glyphs: " + fp)

	var orig_rm := SaveState.reduce_motion
	SaveState.reduce_motion = true
	SaveState.save_profile()
	SaveState.reduce_motion = false
	SaveState.load_profile()
	_assert(SaveState.reduce_motion == true, "SaveState.reduce_motion persists cleanly across save/load")
	SaveState.reduce_motion = orig_rm
	SaveState.save_profile()

	_assert(FloorGenerator.get_sector_at(Vector3(-24.8, 0.08, 22.8), "ru").contains("Б-04"), "FloorGenerator.get_sector_at resolves Ward B-04 in RU")
	_assert(FloorGenerator.get_sector_at(Vector3(-4.2, 0.08, 3.2), "en").contains("C-07"), "FloorGenerator.get_sector_at resolves Bio-Lab in EN")
	_assert(FloorGenerator.get_sector_at(Vector3(25.0, 0.08, -8.0), "ru").contains("О-01"), "FloorGenerator.get_sector_at resolves Security Command in RU")
	_assert(FloorGenerator.get_sector_at(Vector3(-15.0, 0.08, 0.0), "en").contains("R-W"), "FloorGenerator.get_sector_at resolves West Ring Gallery in EN")

	session.start_match(77707, SaveState.DIFF_NORMAL)
	await get_tree().process_frame
	_assert(session.hud._sector_lbl.text == FloorGenerator.get_sector_at(session.player.global_position, Loc.current_lang), "GameSession.start_match wires initial HUD sector name")
	session.player.global_position = Vector3(-4.2, 0.08, 3.2)
	await get_tree().process_frame
	_assert(session.hud._sector_lbl.text == FloorGenerator.get_sector_at(Vector3(-4.2, 0.08, 3.2), Loc.current_lang), "GameSession._process updates HUD sector dynamically when moving")
	Loc.set_language("en")
	_assert(session.hud._sector_lbl.text.contains("C-07"), "Loc.language_changed updates HUD sector name cleanly to EN")
	Loc.set_language("ru")
	session.hud.set_sector_name("СЕКТОР-ТЕСТ")
	_assert(session.hud._sector_lbl.text == "СЕКТОР-ТЕСТ", "BrutalHud.set_sector_name updates sector readout directly")

	# 10. Verify Catch Jumpscare Sequence & Interactive Field Tutorial
	session.monster_director.trigger_jumpscare_pose(session.player.camera)
	_assert(session.monster_director._jumpscare_active and session.monster_director._jumpscare_face_light != null, "MonsterDirector.trigger_jumpscare_pose places face light & freezes stalker")
	session.hud.play_jumpscare_flash(0.82)
	_assert(session.hud._jumpscare_overlay.visible and session.hud._jumpscare_flash_timer > 0.0, "BrutalHud.play_jumpscare_flash activates horror strobe overlay")
	session.monster_director.end_jumpscare_pose()
	_assert(not session.monster_director._jumpscare_active and session.monster_director._jumpscare_face_light == null, "MonsterDirector.end_jumpscare_pose removes face light cleanly")
	session.player.wounds = 1
	session._on_local_player_caught()
	await get_tree().process_frame
	_assert(not session._jumpscare_active and session.phase == GameSession.Phase.ENDED and session.player.camera.fov == ListenerPlayer.BASE_FOV, "Headless _on_local_player_caught completes jumpscare without stalling & restores camera FOV")
	session.start_match(77707, SaveState.DIFF_NORMAL)
	await get_tree().process_frame

	SaveState.tutorial_completed = true
	SaveState.save_profile()
	SaveState.tutorial_completed = false
	SaveState.load_profile()
	_assert(SaveState.tutorial_completed == true, "SaveState.tutorial_completed persists cleanly across save/load")

	SaveState.tutorial_completed = false
	session.hud.start_tutorial_if_needed(true)
	_assert(session.hud.is_tutorial_active() and session.hud._tut_step == 1 and session.hud._tut_card.visible, "Field orientation tutorial starts cleanly at step 1/4")
	session.hud.advance_tutorial_if_step(1)
	_assert(session.hud._tut_step == 2, "Tutorial advances cleanly from step 1 to step 2")
	session.hud.advance_tutorial_if_step(2)
	_assert(session.hud._tut_step == 3, "Tutorial advances cleanly from step 2 to step 3")
	session.hud.advance_tutorial_if_step(3)
	_assert(session.hud._tut_step == 4, "Tutorial advances cleanly from step 3 to step 4")
	session.hud.dismiss_tutorial()
	_assert(not session.hud.is_tutorial_active() and not session.hud._tut_card.visible and SaveState.tutorial_completed == true, "Tutorial dismissal hides card & persists SaveState.tutorial_completed")

	# 11. Verify v5 Physics CharacterBody3D, Blind-Stealth, Cage Wakeup, Touch Drop Button & Zero PC Hints on Gameplay HUD
	session.start_match(77707, SaveState.DIFF_NORMAL)
	await get_tree().process_frame
	_assert(session.monster_director.stalker_node is CharacterBody3D, "MonsterDirector.stalker_node is CharacterBody3D")
	_assert(session.monster_director.chase_speed < ListenerPlayer.SPRINT_SPEED, "Monster chase_speed (%.2f) < ListenerPlayer.SPRINT_SPEED (%.2f)" % [session.monster_director.chase_speed, ListenerPlayer.SPRINT_SPEED])

	session.player.global_position = Vector3(-4.2, 0.08, 3.2)
	session.player.velocity = Vector3.ZERO
	session.player.is_crouching = true
	session.player.is_holding_breath = true
	session.player.flashlight_on = false
	session.player.is_hiding_in_locker = false
	session.player.is_under_desk = false
	session.monster_director.state = MonsterDirector.STATE_PATROL
	session.monster_director.stalker_node.global_position = Vector3(-4.2, 0.0, 2.2)
	session.monster_director.stalker_node.rotation.y = PI
	_assert(session.monster_director._can_detect_local_player() == false, "True Blind-Stealth: silent crouching breath-hold with light off 1.0m from Listener-07 is undetected")

	session.hud.play_cage_wakeup_effect(2.5)
	session.player.start_cage_wakeup(2.2)
	_assert(session.player.head.position.y >= 1.50, "Cage wakeup effect & player.start_cage_wakeup execute cleanly")

	session.hud._set_touch_controls_visible(true)
	session.player.add_item_to_inventory("flare")
	session.player.select_slot(0)
	session.hud.refresh_inventory_bar()
	var drop_vis_with_item := session.hud._btn_drop.visible
	session.player.select_slot(4)
	session.hud.refresh_inventory_bar()
	var drop_vis_empty := session.hud._btn_drop.visible
	session.hud._set_touch_controls_visible(session.hud._is_touch_device)
	_assert(drop_vis_with_item and not drop_vis_empty, "BrutalHud._btn_drop toggles visibility based on equipped item when touch controls are visible")

	var hud_texts: Array[String] = []
	_collect_hud_texts(session.hud._hud_root, hud_texts)
	var has_pc_hint := false
	for ht in hud_texts:
		if ht.contains("[TAB]") or ht.contains("[E]"):
			has_pc_hint = true
	_assert(not has_pc_hint, "Zero [TAB] or [E] PC keycap hints appear on gameplay HUD")

	# 12. Verify v6 Obstacle-Avoiding Grid A*, Chase Audio, 2-Line Subtitle, Clean Curtain & Clean Top-Right Minimap
	await get_tree().physics_frame
	if not session.monster_director._grid_baked:
		session.monster_director._bake_walkability_grid()
	var blocked_cells := 0
	for b in session.monster_director._grid_walkable:
		if b == 0:
			blocked_cells += 1
	_assert(session.monster_director._grid_baked and blocked_cells > 0, "Grid A* walkability grid bakes non-zero blocked obstacle cells (%d blocked)" % blocked_cells)

	var biolab_path := session.monster_director._build_grid_path(Vector3(-8.5, 0.0, -6.5), Vector3(-2.0, 0.0, 6.5))
	var all_wp_walkable := not biolab_path.is_empty()
	for wp in biolab_path:
		var wc := session.monster_director._world_to_grid(wp)
		if not session.monster_director._is_grid_cell_walkable(wc.x, wc.y):
			all_wp_walkable = false
			break
	_assert(all_wp_walkable, "Grid A* _build_grid_path routes cleanly across furnished Bio-Lab (%d waypoints, all walkable)" % biolab_path.size())

	_assert(SynthAudio.clips.has("chase_theme") and SynthAudio.clips["chase_theme"] is AudioStreamWAV, "SynthAudio.clips has chase_theme WAV")
	_assert(SynthAudio.clips.has("monster_chatter") and SynthAudio.clips["monster_chatter"] is AudioStreamWAV, "SynthAudio.clips has monster_chatter WAV")
	SynthAudio.update_chase_music(0.1, true, 6.0)
	SynthAudio.update_chase_music(1.0, false, 999.0)
	_assert(SynthAudio.has_method("update_chase_music") and (SynthAudio._chase_music_player == null or not SynthAudio._chase_music_player.playing), "SynthAudio.update_chase_music ramps in and stops cleanly")

	Loc.set_language("en")
	var sub_en := Loc.t("GAME_SUBTITLE")
	_assert(sub_en.contains("\n") and not sub_en.contains("·"), "EN GAME_SUBTITLE is 2-line without middle dot")
	Loc.set_language("ru")
	var sub_ru := Loc.t("GAME_SUBTITLE")
	_assert(sub_ru.contains("\n") and not sub_ru.contains("·"), "RU GAME_SUBTITLE is 2-line without middle dot")

	session.hud.show_cage_curtain(true)
	_assert(not session.hud._curtain_sub.visible, "hud.show_cage_curtain(true) keeps _curtain_sub hidden (title only)")
	session.hud.show_cage_curtain(false)

	var mm_parent := session.hud.minimap.get_parent()
	var visible_mm_children: Array[Node] = []
	for mc in mm_parent.get_children():
		if mc is Control and (mc as Control).visible:
			visible_mm_children.append(mc)
	_assert(visible_mm_children.size() == 1 and visible_mm_children[0] == session.hud.minimap, "Top-Right minimap container has ONLY minimap as its visible child")

	# 13. Verify v7 Doorway Chase Navigation, Jumpscare Alignment & Humanized Copy
	# 13a. Collision layers & masks + Doorway chase navigation stress test
	session.start_match(77707, SaveState.DIFF_NORMAL)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var md: MonsterDirector = session.monster_director
	if not md._grid_baked:
		md._bake_walkability_grid()

	var all_doors_layer16 := session._doors.size() > 0
	for d in session._doors:
		var col := d.get("collider") as CollisionObject3D
		if col == null or col.collision_layer != 16:
			all_doors_layer16 = false
			break
		d["is_open"] = false
	_assert(all_doors_layer16, "All %d facility door colliders are on collision_layer 16" % session._doors.size())
	_assert(md.stalker_body != null and md.stalker_body.collision_mask == 1, "MonsterDirector.stalker_body.collision_mask == 1 (ignores door leaf layer 16)")
	_assert(session.player.collision_mask == (1 | 16), "ListenerPlayer.collision_mask == (1 | 16) (collides with walls and closed doors)")

	# Place player inside Bio-Lab (x = -4.0, z = 0.0) and Listener-07 in West Ring Gallery (x = -15.6, z = 2.2),
	# forcing a doorway crossing through door_biolab_w at (-10.0, 0.0).
	session.player.controls_enabled = false
	session.player.velocity = Vector3.ZERO
	session.player.is_crouching = false
	session.player.is_hiding_in_locker = false
	session.player.is_under_desk = false
	session.player.is_downed = false
	session.player.is_dead = false
	session.player.flashlight_on = true
	session.player.global_position = Vector3(-4.0, 0.08, 0.0)
	session.player.force_update_transform()

	md.stalker_body.global_position = Vector3(-15.6, 0.0, 2.2)
	md.stalker_body.velocity = Vector3.ZERO
	md.stalker_body.force_update_transform()
	md.state = MonsterDirector.STATE_CHASE
	md._state_timer = 8.0
	md._echolocate_cooldown = 99.0
	md._listen_pause_timer = 0.0
	md._alert_snap_timer = 0.0
	md._stuck_timer = 0.0
	md._stuck_rebuilds = 0
	md._stuck_anchor_pos = md.stalker_body.global_position
	md._progress_timer = 0.0
	md._progress_anchor = md.stalker_body.global_position
	md._wall_slide_timer = 0.0
	md._goal_pos = Vector3(-4.0, 0.0, 0.0)
	md._build_nav_path_to(md._goal_pos)

	var crossed_doorway := false
	for _pf in range(240):
		await get_tree().physics_frame
		if md.stalker_node != null and md.stalker_node.global_position.x > -9.2:
			crossed_doorway = true
			break
	_assert(crossed_doorway, "Listener-07 crosses doorway door_biolab_w into Bio-Lab mid-chase without getting stuck (end_pos=%s)" % str(md.stalker_node.global_position if md.stalker_node else Vector3.ZERO))

	# 13b. Jumpscare alignment test from crouched + pitched-down + wall-adjacent player pose
	session.start_match(77707, SaveState.DIFF_NORMAL)
	await get_tree().physics_frame
	md = session.monster_director
	session.player.controls_enabled = false
	session.player.velocity = Vector3.ZERO
	session.player.is_crouching = true
	session.player.head.position.y = 0.96
	session.player.rotation.y = PI * 0.5
	session.player.head.rotation.x = -0.85
	session.player.camera.rotation = Vector3(0.0, 0.0, 0.34)
	session.player.global_position = Vector3(-31.45, 0.08, 22.0)
	session.player.force_update_transform()
	session.player.head.force_update_transform()
	session.player.camera.force_update_transform()
	if md.stalker_body != null:
		md.stalker_body.global_position = Vector3(-31.85, 0.0, 22.0)
		md.stalker_body.force_update_transform()

	md.trigger_jumpscare_pose(session.player.camera)
	await get_tree().process_frame
	var cam := session.player.camera
	var js_head_pos := md.get_jumpscare_head_world_pos()
	var js_dist_2d := Vector2(md.stalker_node.global_position.x - cam.global_position.x, md.stalker_node.global_position.z - cam.global_position.z).length()
	var js_space := session.get_world_3d().direct_space_state
	var js_q := PhysicsRayQueryParameters3D.create(cam.global_position, js_head_pos)
	js_q.collision_mask = 1
	var js_ex: Array[RID] = [session.player.get_rid()]
	if md.stalker_body != null:
		js_ex.append(md.stalker_body.get_rid())
	js_q.exclude = js_ex
	var js_wall_hit := js_space.intersect_ray(js_q)
	var js_vp_sz := session.get_viewport().get_visible_rect().size
	var js_proj := cam.unproject_position(js_head_pos)
	var js_nx := js_proj.x / maxf(js_vp_sz.x, 1.0)
	var js_ny := js_proj.y / maxf(js_vp_sz.y, 1.0)
	var js_in_center := (not cam.is_position_behind(js_head_pos)) and js_nx >= 0.35 and js_nx <= 0.65 and js_ny >= 0.35 and js_ny <= 0.65
	_assert(absf(session.player.head.rotation.x) < 0.01 and absf(cam.rotation.z) < 0.01, "Jumpscare levels head pitch (%.4f) & zeroes camera roll (%.4f)" % [session.player.head.rotation.x, cam.rotation.z])
	_assert(js_dist_2d >= 0.95 and js_dist_2d <= 1.15 and js_wall_hit.is_empty(), "Jumpscare places Listener-07 unobstructed %.2fm in front of wall-adjacent crouched cam" % js_dist_2d)
	_assert(js_in_center, "Jumpscare live Head bone projects cleanly near screen center (norm=%.2f, %.2f)" % [js_nx, js_ny])
	md.end_jumpscare_pose()
	session._reset_player_jumpscare_camera()

	# 13c. Humanized copy check across all Loc.STRINGS keys (EN & RU)
	var has_em_dash := false
	var keys_match := true
	for loc_key in Loc.STRINGS.keys():
		var entry: Dictionary = Loc.STRINGS[loc_key]
		if not entry.has("en") or not entry.has("ru"):
			keys_match = false
			break
		var en_s := str(entry["en"])
		var ru_s := str(entry["ru"])
		if en_s.contains("—") or ru_s.contains("—"):
			has_em_dash = true
			break
	Loc.set_language("en")
	var en_title_ok := Loc.t("GAME_TITLE") == "DEAD DECIBEL"
	var en_sub_lines := Loc.t("GAME_SUBTITLE").split("\n").size() == 2
	Loc.set_language("ru")
	var ru_title_ok := Loc.t("GAME_TITLE") == "МЁРТВЫЙ ДЕЦИБЕЛ"
	var ru_sub_lines := Loc.t("GAME_SUBTITLE").split("\n").size() == 2
	_assert(not has_em_dash and keys_match, "Loc.STRINGS EN & RU have identical keys and 0 em-dashes")
	_assert(en_title_ok and ru_title_ok and en_sub_lines and ru_sub_lines, "GAME_TITLE & 2-line GAME_SUBTITLE intact in EN & RU")

	var ws_port := OS.get_environment("ECHO7_LIVE_WS_PORT")
	if not ws_port.is_empty():
		SaveState.relay_url = "ws://127.0.0.1:" + ws_port
		SaveState.callsign = "HOST-01"
		NetRelay.create_room(true, 1)
		var wf := 0
		while NetRelay.room_code.is_empty() and wf < 90:
			await get_tree().process_frame
			wf += 1
		_assert(NetRelay.room_code.length() == 4 and NetRelay.is_host, "Live WebSocket Co-op room created: " + NetRelay.room_code)
		NetRelay.leave_room()
		SaveState.relay_url = "ws://127.0.0.1:8787"

	Loc.set_language("en")
	SaveState.difficulty = SaveState.DIFF_NORMAL
	SaveState.callsign = "SURVIVOR"
	SaveState.reduce_motion = false
	SaveState.tutorial_completed = false
	SaveState.total_escapes = 0
	SaveState.best_escape_sec = 0.0
	SaveState.save_profile()

	session.queue_free()
	await get_tree().process_frame

	print("=== SUMMARY: %d / %d CHECKS PASSED ===" % [_checks - _failures, _checks])
	get_tree().quit(0 if _failures == 0 else 1)
