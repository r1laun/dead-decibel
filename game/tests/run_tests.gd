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
	var shot_dir := OS.get_environment("CAPTURE_V4_SHOTS_DIR")
	if shot_dir.is_empty():
		shot_dir = OS.get_environment("CAPTURE_V3_SHOTS_DIR")
	if not shot_dir.is_empty():
		await _capture_visual_qa_shots(shot_dir)
		get_tree().quit(0)
		return
	await _run_all_tests()


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

	# 1. Live 3D Main Menu + Solo Clearance Drawer
	session.hud._switch_menu_card("solo")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await _settle_ui(0.35)
	await _save_shot(shot_dir, "v4_menu_solo.png")

	# 2. Live 3D Main Menu + Co-op Relay Uplink Console
	session.hud._switch_menu_card("coop")
	await _settle_ui(0.35)
	await _save_shot(shot_dir, "v4_menu_coop.png")

	# 3. Gameplay in Ward B-04 + Co-op Friend Transponders + Pinned Dossier + CRT Sonar & Oscilloscope
	SaveState.tutorial_completed = true
	session.start_match(77707, SaveState.DIFF_NORMAL)
	session.hud.dismiss_tutorial()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	session.player.add_item_to_inventory("flare")
	session.player.add_item_to_inventory("screwdriver")
	session.player.add_item_to_inventory("medkit")
	session.player.select_slot(0)
	session.player.known_safe_code = "4829"
	session.hud.refresh_inventory_bar()
	session.hud.update_objectives(false, false, false, false)
	if not session.hud._dossier_pinned:
		session.hud._toggle_dossier_pinned()

	session.player.global_position = Vector3(-24.8, 0.08, 22.8)
	session.player.rotation.y = -0.15
	session.player.head.rotation.x = -0.02

	NetRelay._handle_packet({"t": "peer_joined", "player_id": "P2", "callsign": "MAKS"})
	NetRelay._handle_packet({
		"t": "player_state",
		"player_id": "P2",
		"state": {"callsign": "MAKS", "pos": [-25.6, 0.08, 19.3], "yaw": 3.05, "downed": false, "flash": true}
	})
	NetRelay._handle_packet({"t": "peer_joined", "player_id": "P3", "callsign": "ARTEM"})
	NetRelay._handle_packet({
		"t": "player_state",
		"player_id": "P3",
		"state": {"callsign": "ARTEM", "pos": [-11.0, 0.08, 21.5], "yaw": 0.0, "downed": true, "flash": true}
	})
	for _pulse_i in range(6):
		AcousticBus.emit_noise(session.player.global_position, 8.0, 0.62, "step")
		await get_tree().create_timer(0.05).timeout
		await _wait_frames(2)
	await _save_shot(shot_dir, "v4_gameplay_ward.png")

	# 4. Central Bio-Lab Pursuit + Glowing Specimen Cylinders + Sculpted Listener-07 + Threat HUD
	NetRelay._handle_packet({"t": "peer_left", "player_id": "P2"})
	NetRelay._handle_packet({"t": "peer_left", "player_id": "P3"})
	session.hud._dossier_pinned = false
	session.hud._dossier_peek_timer = 0.0
	session.hud._dossier_card.visible = false
	session.hud._style_button(session.hud._btn_dossier, false, false)
	session.player.global_position = Vector3(-4.2, 0.08, 3.2)
	session.player.rotation.y = 0.30
	session.player.head.rotation.x = -0.02
	session.player.select_slot(0)
	var orig_chase_spd := session.monster_director.chase_speed
	var orig_patrol_spd := session.monster_director.patrol_speed
	if session.monster_director.stalker_node != null:
		session.monster_director.chase_speed = 0.0
		session.monster_director.stalker_node.global_position = Vector3(-5.2, 0.0, -1.6)
		session.monster_director.stalker_node.rotation.y = PI - 0.25
		session.monster_director.state = MonsterDirector.STATE_CHASE
	await get_tree().create_timer(0.22).timeout
	await _wait_frames(4)
	await _save_shot(shot_dir, "v4_biolab_chase.png")
	session.monster_director.chase_speed = orig_chase_spd

	# 5. Inside Surgical Holding Cage looking out into Operating Theater + Interaction Prompt
	session._set_holding_cage_locked(true)
	session.player.wounds = 1
	session.player.is_caged = true
	session.player.global_position = Vector3(-30.5, 0.08, 11.8)
	session.player.rotation.y = -PI * 0.5
	session.player.head.rotation.x = -0.03
	session.player.select_slot(2)
	session.monster_director.patrol_speed = 0.0
	session.monster_director.state = MonsterDirector.STATE_PATROL
	if session.monster_director.stalker_node != null:
		session.monster_director.stalker_node.global_position = Vector3(-24.2, 0.0, 11.0)
		session.monster_director.stalker_node.rotation.y = -PI * 0.65
	await get_tree().create_timer(0.22).timeout
	await _wait_frames(4)
	await _save_shot(shot_dir, "v4_holding_cage.png")
	session.monster_director.patrol_speed = orig_patrol_spd

	# 6. Security Command Room with Safe Keypad Modal Open
	session._set_holding_cage_locked(false)
	session.player.wounds = 0
	session.player.is_caged = false
	session.player.global_position = Vector3(27.5, 0.08, -6.4)
	session.player.rotation.y = -PI * 0.5 + 0.44
	session.player.head.rotation.x = -0.04
	if session.monster_director.stalker_node != null:
		session.monster_director.stalker_node.global_position = Vector3(-25.0, 0.0, 22.0)
		session.monster_director.state = MonsterDirector.STATE_PATROL
	await _wait_frames(4)
	session.hud.open_safe_modal("4829")
	await _settle_ui(0.35)
	await _save_shot(shot_dir, "v4_safe_keypad.png")

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
