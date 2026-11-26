class_name BrutalHud
extends CanvasLayer

signal start_solo_requested(difficulty: int)
signal start_coop_match_requested(difficulty: int)
signal resume_requested
signal restart_match_requested
signal return_to_menu_requested
signal safe_code_submitted(entered_code: String)

# НИИ-07 / Soviet Field Instrument Design Tokens (DESIGN.md)
const COL_INK := Color(0.039, 0.047, 0.043, 0.96)       # #0A0C0B
const COL_PANEL := Color(0.067, 0.082, 0.075, 0.92)     # #111513
const COL_PANEL_HI := Color(0.102, 0.125, 0.114, 0.96)  # #1A201D
const COL_RULE := Color(0.851, 0.824, 0.757, 0.14)      # #D9D2C1 @ 14%
const COL_RULE_STRONG := Color(0.851, 0.824, 0.757, 0.30)
const COL_PAPER := Color(0.867, 0.839, 0.769, 1.0)      # #DDD6C4
const COL_PAPER_DIM := Color(0.612, 0.592, 0.541, 1.0)  # #9C978A
const COL_PAPER_MUTE := Color(0.384, 0.373, 0.341, 1.0) # #625F57
const COL_SODIUM := Color(0.890, 0.635, 0.231, 1.0)     # #E3A23B
const COL_SIGNAL := Color(0.800, 0.227, 0.180, 1.0)     # #CC3A2E
const COL_PHOSPHOR := Color(0.557, 0.863, 0.620, 1.0)   # #8EDC9E
const COL_COLD := Color(0.498, 0.722, 0.784, 1.0)       # #7FB8C8

# Compatibility aliases
const COL_BG := COL_PANEL
const COL_SURFACE := COL_PANEL
const COL_SURFACE_HI := COL_PANEL_HI
const COL_HAIRLINE := COL_RULE
const COL_TEXT_PRI := COL_PAPER
const COL_TEXT_SEC := COL_PAPER_DIM
const COL_TEXT_MUTED := COL_PAPER_MUTE
const COL_ACCENT := COL_SODIUM
const COL_DANGER := COL_SIGNAL
const COL_OK := COL_PHOSPHOR

const JOY_SIZE := 168.0
const JOY_KNOB_SIZE := 66.0
const JOY_REST_POS := Vector2(51.0, 51.0)
const JOY_MAX_R := 66.0
const JOY_SPRINT_RATIO := 0.75


class AcousticScopeControl extends Control:
	var mono_font: Font = null
	var mono_bold: Font = null
	var is_holding_breath: bool = false
	var chase_flare: float = 0.0
	var _wave_history: PackedFloat32Array = PackedFloat32Array()
	var _wave_accum: float = 0.0
	var _pulse_time: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(188, 38)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wave_history.resize(44)
		_wave_history.fill(0.0)

	func tick(delta: float, holding_breath: bool) -> void:
		is_holding_breath = holding_breath
		_pulse_time += delta
		_wave_accum += delta
		if _wave_accum >= 0.04:
			_wave_accum = 0.0
			var nl := AcousticBus.current_noise_level
			for i in range(_wave_history.size() - 1):
				_wave_history[i] = _wave_history[i + 1]
			var jitter := sin(_pulse_time * 37.0) * cos(_pulse_time * 19.0)
			var sample := jitter * (0.03 + nl * 0.92)
			if is_holding_breath:
				sample *= 0.22
			_wave_history[_wave_history.size() - 1] = clampf(sample, -1.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var sz := size
		if sz.x < 24.0 or sz.y < 16.0:
			return
		var rect := Rect2(Vector2.ZERO, sz)
		var bg_col := COL_INK.lerp(Color(0.18, 0.03, 0.03, 0.98), chase_flare * 0.45)
		var brd_col := COL_RULE.lerp(COL_SIGNAL, chase_flare)
		draw_rect(rect, bg_col, true)
		draw_rect(rect, brd_col, false, lerpf(1.0, 2.2, chase_flare))

		for gx_i in range(1, 6):
			var gx := lerpf(2.0, sz.x - 2.0, float(gx_i) / 6.0)
			draw_line(Vector2(gx, 2.0), Vector2(gx, sz.y - 2.0), Color(COL_PHOSPHOR, 0.07), 1.0)

		var mid_y := sz.y * 0.62
		draw_line(Vector2(3.0, mid_y), Vector2(sz.x - 3.0, mid_y), Color(COL_PHOSPHOR, 0.14), 1.0)

		var nl_cur := AcousticBus.current_noise_level
		var trace_col := COL_SIGNAL if (nl_cur >= 0.45 or chase_flare > 0.35) else (
			COL_SODIUM if nl_cur >= 0.18 else COL_PHOSPHOR
		)
		if is_holding_breath:
			trace_col = COL_COLD

		if mono_font != null:
			var tag_left := Loc.t("ACOUSTIC_HOLD") if is_holding_breath else Loc.t("ACOUSTIC_TAG")
			draw_string(mono_font, Vector2(6.0, 12.0), tag_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(trace_col, 0.85))
			var db_val := clampi(int(round(nl_cur * 96.0)), 0, 99)
			var db_str := "%02d dB" % db_val
			var f_bold := mono_bold if mono_bold != null else mono_font
			draw_string(f_bold, Vector2(sz.x - 46.0, 12.0), db_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, trace_col)

		var poly := PackedVector2Array()
		var n_pts := _wave_history.size()
		for i in range(n_pts):
			var px := lerpf(5.0, sz.x - 5.0, float(i) / float(max(1, n_pts - 1)))
			var py := mid_y - _wave_history[i] * (sz.y * 0.30)
			poly.append(Vector2(px, py))
		if poly.size() >= 2:
			draw_polyline(poly, Color(trace_col, 0.25), 3.2, true)
			draw_polyline(poly, trace_col, 1.5, true)


class ChaseInterferenceOverlay extends Control:
	var intensity: float = 0.0
	var proximity: float = 0.0
	var pulse_time: float = 0.0
	var reduce_motion: bool = false

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func update_state(p_intensity: float, p_proximity: float, p_pulse_time: float, p_reduce_motion: bool) -> void:
		intensity = clampf(p_intensity, 0.0, 1.0)
		proximity = clampf(p_proximity, 0.0, 1.0)
		pulse_time = p_pulse_time
		reduce_motion = p_reduce_motion
		visible = intensity > 0.005 and not reduce_motion
		if visible:
			queue_redraw()

	func _draw() -> void:
		if intensity <= 0.005 or reduce_motion:
			return
		var sz := size
		if sz.x < 16.0 or sz.y < 16.0:
			return

		var pulse := 0.5 + 0.5 * sin(pulse_time * 9.5)
		var fast_flick := 0.5 + 0.5 * sin(pulse_time * 31.0 + cos(pulse_time * 17.0))

		# Dynamic tunnel-vision tightening borders synced to stalker proximity (< 16m)
		var squeeze := lerpf(0.035, 0.135, proximity) * intensity
		var band_w := sz.x * squeeze * (0.94 + 0.10 * pulse)
		var band_h := sz.y * squeeze * (0.94 + 0.10 * pulse)
		for b_i in range(3):
			var frac := float(3 - b_i) / 3.0
			var bw := band_w * frac
			var bh := band_h * frac
			var edge_a := intensity * (0.14 + 0.16 * proximity) * (1.15 - frac * 0.45)
			var edge_col := Color(0.055, 0.012, 0.014, clampf(edge_a, 0.0, 0.62))
			draw_rect(Rect2(0.0, 0.0, sz.x, bh), edge_col, true)
			draw_rect(Rect2(0.0, sz.y - bh, sz.x, bh), edge_col, true)
			draw_rect(Rect2(0.0, bh, bw, maxf(0.0, sz.y - bh * 2.0)), edge_col, true)
			draw_rect(Rect2(sz.x - bw, bh, bw, maxf(0.0, sz.y - bh * 2.0)), edge_col, true)

		# Erratic horizontal signal-interference panic bars & dark/crimson tears
		var phase := int(floor(pulse_time * 24.0))
		var tear_count := int(round(lerpf(4.0, 12.0, proximity)))
		for i in range(tear_count):
			var seed_v := (i * 53 + phase * 29) % 101
			var y_norm := float(seed_v) / 101.0
			if y_norm > 0.36 and y_norm < 0.64:
				y_norm = y_norm * 0.45 if (i % 2 == 0) else 1.0 - (1.0 - y_norm) * 0.45
			var bar_y := y_norm * sz.y
			var bar_h := 1.5 + float((i + phase) % 3) * 1.4
			var bar_w := sz.x * lerpf(0.28, 0.96, float((seed_v * 7) % 19) / 18.0)
			var x_off := float(((i * 19 + phase * 11) % 31) - 15) * 3.5
			if (i + phase) % 3 == 0:
				var dark_a := intensity * (0.18 + 0.22 * proximity) * (0.6 + 0.4 * fast_flick)
				draw_rect(Rect2(clampf(x_off, 0.0, sz.x * 0.4), bar_y, bar_w, bar_h), Color(COL_INK.r, COL_INK.g, COL_INK.b, dark_a), true)
			else:
				var sig_a := intensity * (0.10 + 0.22 * proximity) * (0.55 + 0.45 * fast_flick)
				draw_rect(Rect2(clampf(x_off, 0.0, sz.x * 0.4), bar_y, bar_w, bar_h), Color(COL_SIGNAL.r, COL_SIGNAL.g, COL_SIGNAL.b, sig_a), true)

		# Pulsing red corner panic brackets synced to proximity
		var inset := lerpf(28.0, 14.0, proximity)
		var br_len := lerpf(22.0, 42.0, proximity)
		var br_a := intensity * (0.35 + 0.45 * pulse) * lerpf(0.65, 1.0, proximity)
		var br_col := Color(COL_SIGNAL.r, COL_SIGNAL.g, COL_SIGNAL.b, clampf(br_a, 0.0, 0.92))
		var br_w := lerpf(1.6, 2.8, proximity)
		var x0 := inset
		var y0 := inset
		var x1 := sz.x - inset
		var y1 := sz.y - inset
		draw_line(Vector2(x0, y0 + br_len), Vector2(x0, y0), br_col, br_w)
		draw_line(Vector2(x0, y0), Vector2(x0 + br_len, y0), br_col, br_w)
		draw_line(Vector2(x1 - br_len, y0), Vector2(x1, y0), br_col, br_w)
		draw_line(Vector2(x1, y0), Vector2(x1, y0 + br_len), br_col, br_w)
		draw_line(Vector2(x0, y1 - br_len), Vector2(x0, y1), br_col, br_w)
		draw_line(Vector2(x0, y1), Vector2(x0 + br_len, y1), br_col, br_w)
		draw_line(Vector2(x1 - br_len, y1), Vector2(x1, y1), br_col, br_w)
		draw_line(Vector2(x1, y1 - br_len), Vector2(x1, y1), br_col, br_w)


var player: ListenerPlayer = null
var minimap: LoSMinimapControl = null

# Typography & Theme
var _theme: Theme
var _font_display: Font
var _font_display_md: Font
var _font_sans: Font
var _font_sans_bold: Font
var _font_mono: Font
var _font_mono_bold: Font

# Root layers
var _danger_overlay: ColorRect
var _blood_vignette: TextureRect
var _blood_vig_alpha: float = 0.0
var _blood_pulse_t: float = 0.0
var _chase_panic_overlay: Control
var _chase_vignette: TextureRect
var _chase_interference: ChaseInterferenceOverlay
var _chase_intensity: float = 0.0
var _chase_prox: float = 0.0
var _chase_pulse_t: float = 0.0
var _wakeup_overlay: Control
var _wakeup_timer: float = 0.0
var _wakeup_duration: float = 2.5
var _jumpscare_overlay: Control
var _jumpscare_flash_timer: float = 0.0
var _jumpscare_flash_duration: float = 0.85
var _modal_scrim: ColorRect
var _black_curtain: ColorRect
var _curtain_title: Label
var _curtain_sub: Label

var _menu_root: Control
var _hud_root: Control
var _safe_modal: PanelContainer
var _pause_modal: PanelContainer
var _end_modal: PanelContainer

# --- Main Menu widgets ---
var _menu_title_lbl: Label
var _menu_sub_lbl: Label
var _record_lbl: Label
var _record_plate: PanelContainer
var _btn_nav_solo: Button
var _btn_nav_coop: Button
var _btn_nav_settings: Button
var _btn_nav_how: Button
var _active_menu_tab: String = ""

var _card_solo: PanelContainer
var _diff_title_lbl: Label
var _diff_btns: Array[Button] = []
var _btn_begin_solo: Button

var _card_coop: PanelContainer
var _coop_title_lbl: Label
var _lbl_callsign: Label
var _lbl_relay: Label
var _name_input: LineEdit
var _relay_input: LineEdit
var _code_input: LineEdit
var _coop_status_lbl: Label
var _relay_hint_lbl: Label
var _public_rooms_box: VBoxContainer
var _btn_create_room: Button
var _btn_copy_code: Button
var _btn_join_code: Button
var _btn_refresh_public: Button
var _btn_launch_coop: Button
var _coop_conn_status: String = ""
var _coop_error_msg: String = ""

var _card_settings: PanelContainer
var _set_title_lbl: Label
var _lbl_sens: Label
var _val_sens_lbl: Label
var _slider_sens: HSlider
var _lbl_vol: Label
var _val_vol_lbl: Label
var _slider_vol: HSlider
var _btn_mic_mode: Button
var _btn_gyro: Button
var _btn_haptics: Button
var _btn_reduce_motion: Button
var _btn_lang: Button
var _btn_replay_tutorial: Button

var _card_how: PanelContainer
var _how_title_lbl: Label
var _how_body_lbl: Label
var _manual_key_rows: Array[Dictionary] = []
var _manual_keys_grid: GridContainer

# --- Diegetic In-Game HUD widgets ---
var _btn_pause: Button
var _btn_dossier: Button
var _sector_lbl: Label
var _sector_text: String = ""
var _dossier_card: PanelContainer
var _dossier_pinned: bool = false
var _dossier_peek_timer: float = 0.0
var _seals_done_count: int = 0
var _obj_header_lbl: Label
var _obj_rows: Dictionary = {}
var _obj_boxes: Dictionary = {}
var _dossier_code_lbl: Label

var _top_status_bar: PanelContainer
var _top_bar_style: StyleBoxFlat
var _acoustic_scope: AcousticScopeControl
var _status_pill: PanelContainer
var _status_pill_style: StyleBoxFlat
var _stalker_alert_lbl: Label
var _status_accent: Color = COL_RULE_STRONG
var _status_is_urgent: bool = false

var _breath_bar: ProgressBar

var _reticle_dot: ColorRect
var _reticle_canvas: Control
var _reticle_gap: float = 6.0
var _reticle_target_gap: float = 6.0
var _reticle_active: bool = false

var _prompt_box: PanelContainer
var _prompt_icon: TextureRect
var _prompt_lbl: Label

var _toast_plate: PanelContainer
var _toast_lbl: Label
var _held_item_lbl: Label
var _slot_btns: Array[Button] = []
var _slot_icons: Array[TextureRect] = []
var _slot_nums: Array[Label] = []

# Field Orientation Tutorial Card
var _tut_card: PanelContainer
var _tut_header_lbl: Label
var _tut_step_lbl: Label
var _tut_body_lbl: Label
var _tut_next_btn: Button
var _tut_skip_btn: Button
var _tut_active: bool = false
var _tut_step: int = 0

# Mobile Touch Controls
var _is_touch_device: bool = false
var _touch_controls_visible: bool = false
var _joy_base: Panel
var _joy_knob: Panel
var _joy_sprinting: bool = false
var _btn_breath: Button
var _btn_flashlight: Button
var _btn_crouch: Button
var _btn_drop: Button

# Double-Tap Ripple Indicator
var _tap_ripple_ctrl: Control
var _tap_ripple_pos: Vector2 = Vector2.ZERO
var _tap_ripple_timer: float = 0.0

# Safe Keypad Modal
var _safe_title_lbl: Label
var _safe_display_lbl: Label
var _safe_hint_lbl: Label
var _safe_entered: String = ""

# Pause & End Modals
var _pause_title_lbl: Label
var _btn_resume: Button
var _btn_restart: Button
var _btn_to_menu: Button

var _end_title_lbl: Label
var _end_sub_lbl: Label
var _btn_play_again: Button
var _btn_end_menu: Button

# Runtime state
var _joy_touch_idx: int = -1
var _joy_center: Vector2 = Vector2.ZERO
var _look_touch_idx: int = -1
var _look_touch_start_pos: Vector2 = Vector2.ZERO
var _look_touch_start_time: float = 0.0
var _look_touch_moved: float = 0.0
var _last_tap_time: float = -10.0
var _last_tap_pos: Vector2 = Vector2.ZERO
var _toast_timer: float = 0.0
var _danger_pulse: float = 0.0
var _status_pulse_t: float = 0.0


func _ready() -> void:
	layer = 10
	_load_fonts_and_build_theme()
	_build_all_ui()
	Loc.language_changed.connect(func(_l: String): refresh_texts())
	NetRelay.room_joined.connect(func(_c: String, _h: bool):
		_coop_error_msg = ""
		_coop_conn_status = "connected"
		_refresh_coop_ui()
	)
	NetRelay.room_left.connect(func(_r: String): _refresh_coop_ui())
	NetRelay.peer_updated.connect(func(_id: String, _s: Dictionary): _refresh_coop_ui())
	NetRelay.peer_removed.connect(func(_id: String): _refresh_coop_ui())
	NetRelay.host_migrated.connect(func(_id: String, _n: String): _refresh_coop_ui())
	NetRelay.open_lobbies_received.connect(_on_open_lobbies)
	if NetRelay.has_signal("relay_error"):
		NetRelay.connect("relay_error", _on_relay_error)
	if NetRelay.has_signal("connection_status_changed"):
		NetRelay.connect("connection_status_changed", _on_relay_connection_status)
	refresh_texts()


func _tr_or(key: String, ru_fb: String, en_fb: String) -> String:
	var res := Loc.t(key)
	if res == key:
		return ru_fb if Loc.current_lang == "ru" else en_fb
	return res


func _get_reduce_motion() -> bool:
	return bool(SaveState.get("reduce_motion"))


func _set_reduce_motion(val: bool) -> void:
	SaveState.set("reduce_motion", val)
	SaveState.save_profile()


func _load_font_safe(path: String, fallback: Font) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f != null:
			return f
	return fallback


func _make_slider_grabber_tex(col: Color, sz: Vector2i) -> ImageTexture:
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	img.fill(col)
	for x in range(sz.x):
		img.set_pixel(x, 0, COL_INK)
		img.set_pixel(x, sz.y - 1, COL_INK)
	for y in range(sz.y):
		img.set_pixel(0, y, COL_INK)
		img.set_pixel(sz.x - 1, y, COL_INK)
	return ImageTexture.create_from_image(img)


func _load_fonts_and_build_theme() -> void:
	var sys_fb := ThemeDB.fallback_font
	_font_sans = _load_font_safe("res://assets/fonts/IBMPlexSans-Regular.ttf", sys_fb)
	_font_sans_bold = _load_font_safe("res://assets/fonts/IBMPlexSans-SemiBold.ttf", _font_sans)
	_font_mono = _load_font_safe("res://assets/fonts/IBMPlexMono-Regular.ttf", _font_sans)
	_font_mono_bold = _load_font_safe("res://assets/fonts/IBMPlexMono-SemiBold.ttf", _font_mono)

	var oswald_base := _load_font_safe("res://assets/fonts/Oswald-Variable.ttf", _font_sans_bold)
	var fv_disp := FontVariation.new()
	fv_disp.base_font = oswald_base
	fv_disp.variation_opentype = {"wght": 650}
	fv_disp.spacing_glyph = 2
	_font_display = fv_disp

	var fv_disp_md := FontVariation.new()
	fv_disp_md.base_font = oswald_base
	fv_disp_md.variation_opentype = {"wght": 550}
	fv_disp_md.spacing_glyph = 1
	_font_display_md = fv_disp_md

	_theme = Theme.new()
	_theme.default_font = _font_sans
	_theme.default_font_size = 16

	# LineEdit styling (recessed ink input + sodium focus/caret)
	var le_norm := _make_box(COL_INK, COL_RULE_STRONG, 2, 12, 9, 1)
	var le_focus := _make_box(COL_INK, COL_SODIUM, 2, 12, 9, 1)
	var le_ro := _make_box(COL_PANEL, COL_RULE, 2, 12, 9, 1)
	_theme.set_stylebox("normal", "LineEdit", le_norm)
	_theme.set_stylebox("focus", "LineEdit", le_focus)
	_theme.set_stylebox("read_only", "LineEdit", le_ro)
	_theme.set_color("font_color", "LineEdit", COL_PAPER)
	_theme.set_color("font_placeholder_color", "LineEdit", COL_PAPER_MUTE)
	_theme.set_color("caret_color", "LineEdit", COL_SODIUM)
	_theme.set_color("selection_color", "LineEdit", Color(COL_SODIUM, 0.30))
	_theme.set_font("font", "LineEdit", _font_sans)
	_theme.set_font_size("font_size", "LineEdit", 16)

	# HSlider styling (Soviet hardware fader rail + square metal thumb)
	var sl_bg := _make_box(COL_INK, COL_RULE_STRONG, 1, 0, 0, 1)
	sl_bg.content_margin_top = 5
	sl_bg.content_margin_bottom = 5
	var sl_hi := _make_box(Color(COL_SODIUM, 0.42), COL_SODIUM, 1, 0, 0, 0)
	sl_hi.content_margin_top = 5
	sl_hi.content_margin_bottom = 5
	var sl_area := _make_box(Color(COL_PAPER_DIM, 0.25), Color.TRANSPARENT, 1, 0, 0, 0)
	sl_area.content_margin_top = 5
	sl_area.content_margin_bottom = 5
	_theme.set_stylebox("slider", "HSlider", sl_bg)
	_theme.set_stylebox("grabber_area", "HSlider", sl_area)
	_theme.set_stylebox("grabber_area_highlight", "HSlider", sl_hi)
	_theme.set_icon("grabber", "HSlider", _make_slider_grabber_tex(COL_PAPER, Vector2i(14, 22)))
	_theme.set_icon("grabber_highlight", "HSlider", _make_slider_grabber_tex(COL_SODIUM, Vector2i(16, 24)))

	# Scrollbar styling
	var sb_track := _make_box(COL_INK, COL_RULE, 0, 3, 3, 1)
	var sb_grab := _make_box(COL_PAPER_MUTE, Color.TRANSPARENT, 1, 0, 0, 0)
	var sb_grab_hi := _make_box(COL_SODIUM, Color.TRANSPARENT, 1, 0, 0, 0)
	_theme.set_stylebox("scroll", "VScrollBar", sb_track)
	_theme.set_stylebox("grabber", "VScrollBar", sb_grab)
	_theme.set_stylebox("grabber_highlight", "VScrollBar", sb_grab_hi)
	_theme.set_stylebox("grabber_pressed", "VScrollBar", sb_grab_hi)


func bind_player(p: ListenerPlayer) -> void:
	player = p
	if not player.inventory_changed.is_connected(refresh_inventory_bar):
		player.inventory_changed.connect(refresh_inventory_bar)
	if not player.consumable_used.is_connected(show_toast_key):
		player.consumable_used.connect(show_toast_key)
	if not player.toggle_dossier_requested.is_connected(_toggle_dossier_pinned):
		player.toggle_dossier_requested.connect(_toggle_dossier_pinned)
	refresh_inventory_bar()


func bind_minimap_world(
	p_monster: MonsterDirector,
	p_remotes: Dictionary,
	p_wall_segs: Array[Dictionary],
	p_doors: Array[Dictionary],
	p_vents: Dictionary
) -> void:
	if minimap != null:
		minimap.configure_map(player, p_monster, p_remotes, p_wall_segs, p_doors, p_vents)


func _anchor_box(c: Control, ax0: float, ay0: float, ax1: float, ay1: float, ox0: float, oy0: float, ox1: float, oy1: float) -> void:
	c.anchor_left = ax0
	c.anchor_top = ay0
	c.anchor_right = ax1
	c.anchor_bottom = ay1
	c.offset_left = ox0
	c.offset_top = oy0
	c.offset_right = ox1
	c.offset_bottom = oy1


func _make_box(bg: Color, border: Color, radius: int = 2, pad_x: int = 16, pad_y: int = 11, border_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


func _attach_corner_ticks(ctrl: Control, col: Color = COL_RULE_STRONG, len_px: float = 9.0, inset: float = 1.0) -> void:
	ctrl.set_meta("tick_color", col)
	if not ctrl.has_meta("ticks_connected"):
		ctrl.set_meta("ticks_connected", true)
		ctrl.draw.connect(_on_draw_corner_ticks.bind(ctrl, len_px, inset))
	ctrl.queue_redraw()


func _set_corner_tick_color(ctrl: Control, col: Color) -> void:
	if is_instance_valid(ctrl):
		ctrl.set_meta("tick_color", col)
		ctrl.queue_redraw()


func _on_draw_corner_ticks(ctrl: Control, len_px: float, inset: float) -> void:
	var sz := ctrl.size
	if sz.x < 16.0 or sz.y < 16.0:
		return
	var col: Color = ctrl.get_meta("tick_color", COL_RULE_STRONG)
	if col.a <= 0.01:
		return
	var x0 := inset
	var y0 := inset
	var x1 := sz.x - inset
	var y1 := sz.y - inset
	var l := minf(len_px, minf(sz.x, sz.y) * 0.28)
	var w := 1.5
	ctrl.draw_line(Vector2(x0, y0 + l), Vector2(x0, y0), col, w)
	ctrl.draw_line(Vector2(x0, y0), Vector2(x0 + l, y0), col, w)
	ctrl.draw_line(Vector2(x1 - l, y0), Vector2(x1, y0), col, w)
	ctrl.draw_line(Vector2(x1, y0), Vector2(x1, y0 + l), col, w)
	ctrl.draw_line(Vector2(x0, y1 - l), Vector2(x0, y1), col, w)
	ctrl.draw_line(Vector2(x0, y1), Vector2(x0 + l, y1), col, w)
	ctrl.draw_line(Vector2(x1 - l, y1), Vector2(x1, y1), col, w)
	ctrl.draw_line(Vector2(x1, y1 - l), Vector2(x1, y1), col, w)


func _style_button(btn: Button, primary_cta: bool = false, selected: bool = false) -> void:
	var focus_box := _make_box(Color.TRANSPARENT, COL_SODIUM, 2, 16, 11, 1)
	btn.add_theme_stylebox_override("focus", focus_box)
	if primary_cta:
		var cta_norm := _make_box(COL_SODIUM, COL_SODIUM, 2, 18, 12, 1)
		var cta_hov := _make_box(Color(0.945, 0.698, 0.298, 1.0), Color(0.945, 0.698, 0.298, 1.0), 2, 18, 12, 1)
		var cta_prs := _make_box(Color(0.760, 0.520, 0.165, 1.0), COL_SODIUM, 2, 18, 12, 1)
		var cta_dis := _make_box(COL_PANEL, COL_RULE, 2, 18, 12, 1)
		btn.add_theme_stylebox_override("normal", cta_norm)
		btn.add_theme_stylebox_override("hover", cta_hov)
		btn.add_theme_stylebox_override("pressed", cta_prs)
		btn.add_theme_stylebox_override("disabled", cta_dis)
		btn.add_theme_color_override("font_color", Color(0.039, 0.047, 0.043, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.039, 0.047, 0.043, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.039, 0.047, 0.043, 1.0))
		btn.add_theme_color_override("font_disabled_color", Color(0.51, 0.49, 0.45, 1.0))
		btn.add_theme_font_override("font", _font_sans_bold)
		btn.add_theme_font_size_override("font_size", 17)
	else:
		var bg := COL_PANEL_HI if selected else COL_PANEL
		var brd := Color(COL_SODIUM, 0.85) if selected else COL_RULE_STRONG
		btn.add_theme_stylebox_override("normal", _make_box(bg, brd, 2, 16, 11, 1))
		btn.add_theme_stylebox_override("hover", _make_box(COL_PANEL_HI, Color(COL_PAPER, 0.42), 2, 16, 11, 1))
		btn.add_theme_stylebox_override("pressed", _make_box(Color(0.145, 0.175, 0.160, 0.98), COL_SODIUM, 2, 16, 11, 1))
		btn.add_theme_stylebox_override("disabled", _make_box(COL_INK, COL_RULE, 2, 16, 11, 1))
		btn.add_theme_color_override("font_color", COL_SODIUM if selected else COL_PAPER)
		btn.add_theme_color_override("font_hover_color", COL_PAPER)
		btn.add_theme_color_override("font_pressed_color", COL_SODIUM)
		btn.add_theme_color_override("font_disabled_color", COL_PAPER_MUTE)
		btn.add_theme_font_override("font", _font_sans_bold if selected else _font_sans)
		btn.add_theme_font_size_override("font_size", 17)


func _style_nav_switch(btn: Button, active: bool) -> void:
	_style_button(btn, false, active)
	btn.set_meta("nav_active", active)
	if not btn.has_meta("nav_draw_bound"):
		btn.set_meta("nav_draw_bound", true)
		btn.draw.connect(func():
			var is_on := bool(btn.get_meta("nav_active", false))
			var sz := btn.size
			if sz.x < 24.0:
				return
			var box_r := Rect2(sz.x - 20.0, sz.y * 0.5 - 4.5, 9.0, 9.0)
			if is_on:
				btn.draw_rect(box_r, COL_SODIUM, true)
			else:
				btn.draw_rect(box_r, COL_RULE_STRONG, false, 1.0)
		)
	btn.queue_redraw()


func _make_drawer_header(parent: VBoxContainer, on_close: Callable) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var title_lbl := Label.new()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.uppercase = true
	title_lbl.add_theme_font_override("font", _font_display)
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", COL_PAPER)
	row.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.text = ""
	close_btn.add_theme_stylebox_override("normal", _make_box(COL_INK, COL_RULE_STRONG, 2, 0, 0, 1))
	close_btn.add_theme_stylebox_override("hover", _make_box(COL_PANEL_HI, COL_SODIUM, 2, 0, 0, 1))
	close_btn.add_theme_stylebox_override("pressed", _make_box(COL_PANEL_HI, COL_SIGNAL, 2, 0, 0, 1))
	close_btn.add_theme_stylebox_override("focus", _make_box(Color.TRANSPARENT, COL_SODIUM, 2, 0, 0, 1))
	close_btn.draw.connect(func():
		var c := close_btn.size * 0.5
		var col := COL_SODIUM if close_btn.is_hovered() else COL_PAPER_DIM
		close_btn.draw_line(c + Vector2(-5.5, -5.5), c + Vector2(5.5, 5.5), col, 1.6, true)
		close_btn.draw_line(c + Vector2(5.5, -5.5), c + Vector2(-5.5, 5.5), col, 1.6, true)
	)
	close_btn.pressed.connect(on_close)
	row.add_child(close_btn)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = COL_RULE
	parent.add_child(sep)
	return title_lbl


func _tween_pop_in(ctrl: Control, start_scale: float = 0.97, start_alpha: float = 0.90, dur: float = 0.20) -> void:
	if not is_instance_valid(ctrl):
		return
	if ctrl.has_meta("_pop_tween"):
		var prev_tw: Variant = ctrl.get_meta("_pop_tween")
		if prev_tw is Tween and (prev_tw as Tween).is_valid():
			(prev_tw as Tween).kill()
	var piv := ctrl.size * 0.5
	if piv.x < 4.0 or piv.y < 4.0:
		piv = Vector2(ctrl.offset_right - ctrl.offset_left, ctrl.offset_bottom - ctrl.offset_top) * 0.5
	if piv.x < 4.0 or piv.y < 4.0:
		piv = ctrl.custom_minimum_size * 0.5
	ctrl.pivot_offset = piv
	if _get_reduce_motion():
		ctrl.scale = Vector2.ONE
		ctrl.modulate.a = 1.0
		return
	ctrl.scale = Vector2.ONE * start_scale
	ctrl.modulate.a = start_alpha
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_EXPO)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "scale", Vector2.ONE, dur)
	tw.tween_property(ctrl, "modulate:a", 1.0, dur)
	ctrl.set_meta("_pop_tween", tw)


func _make_blood_vignette_tex() -> ImageTexture:
	var w := 256
	var h := 144
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var ny := (float(y) / float(h - 1)) * 2.0 - 1.0
		for x in range(w):
			var nx := (float(x) / float(w - 1)) * 2.0 - 1.0
			var ell := sqrt(nx * nx * 1.12 + ny * ny * 0.94)
			var box_d := maxf(absf(nx), absf(ny))
			var edge := lerpf(ell, box_d, 0.45)
			# Keep center 52% clear; rich organic blood mottling along screen sides & corners
			var org := 0.5 + 0.5 * (sin(nx * 11.3 + ny * 7.1) * 0.55 + cos(nx * 23.7 - ny * 17.9) * 0.45)
			var vig := clampf((edge - 0.52) / 0.48, 0.0, 1.0)
			var raw_a := clampf(pow(vig, 1.45) * (0.62 + 0.46 * org), 0.0, 0.96)
			var r_col := lerpf(0.28, 0.72, clampf(org * 0.8 + vig * 0.25, 0.0, 1.0))
			var g_col := lerpf(0.02, 0.09, org * (1.0 - vig * 0.4))
			var b_col := 0.03
			img.set_pixel(x, y, Color(r_col, g_col, b_col, raw_a))
	return ImageTexture.create_from_image(img)


func _make_chase_vignette_tex() -> ImageTexture:
	var w := 256
	var h := 144
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var ny := (float(y) / float(h - 1)) * 2.0 - 1.0
		for x in range(w):
			var nx := (float(x) / float(w - 1)) * 2.0 - 1.0
			var ell := sqrt(nx * nx * 1.18 + ny * ny * 1.04)
			var box_d := maxf(absf(nx), absf(ny))
			var edge := lerpf(ell, box_d, 0.35)
			var vig := clampf((edge - 0.38) / 0.62, 0.0, 1.0)
			var tunnel_a := clampf(pow(vig, 1.35) * 0.94, 0.0, 0.96)
			var rim := clampf((edge - 0.72) / 0.28, 0.0, 1.0)
			var r_col := lerpf(0.56, 0.06, rim)
			var g_col := lerpf(0.06, 0.015, rim)
			var b_col := lerpf(0.05, 0.02, rim)
			img.set_pixel(x, y, Color(r_col, g_col, b_col, tunnel_a))
	return ImageTexture.create_from_image(img)


func _build_all_ui() -> void:
	_danger_overlay = ColorRect.new()
	_danger_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_overlay.color = Color(0.55, 0.06, 0.05, 0.0)
	add_child(_danger_overlay)

	_blood_vignette = TextureRect.new()
	_blood_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blood_vignette.texture = _make_blood_vignette_tex()
	_blood_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blood_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_blood_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_vignette.modulate.a = 0.0
	_blood_vignette.visible = false
	add_child(_blood_vignette)

	_chase_panic_overlay = Control.new()
	_chase_panic_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chase_panic_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chase_panic_overlay.visible = false
	add_child(_chase_panic_overlay)

	_chase_vignette = TextureRect.new()
	_chase_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chase_vignette.texture = _make_chase_vignette_tex()
	_chase_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chase_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_chase_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chase_vignette.modulate.a = 0.0
	_chase_panic_overlay.add_child(_chase_vignette)

	_chase_interference = ChaseInterferenceOverlay.new()
	_chase_panic_overlay.add_child(_chase_interference)

	_build_main_menu()
	_build_gameplay_hud()

	_wakeup_overlay = Control.new()
	_wakeup_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wakeup_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wakeup_overlay.visible = false
	_wakeup_overlay.draw.connect(_draw_wakeup_overlay)
	add_child(_wakeup_overlay)

	_jumpscare_overlay = Control.new()
	_jumpscare_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_jumpscare_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jumpscare_overlay.visible = false
	_jumpscare_overlay.draw.connect(_draw_jumpscare_overlay)
	add_child(_jumpscare_overlay)

	_modal_scrim = ColorRect.new()
	_modal_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_scrim.color = Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.72)
	_modal_scrim.visible = false
	add_child(_modal_scrim)

	_build_safe_keypad_modal()
	_build_pause_and_end_modals()

	# Holding Cage Capture Transition Curtain
	_black_curtain = ColorRect.new()
	_black_curtain.theme = _theme
	_black_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black_curtain.color = Color(0.031, 0.037, 0.034, 1.0)
	_black_curtain.visible = false
	add_child(_black_curtain)

	var cv := VBoxContainer.new()
	_anchor_box(cv, 0.5, 0.5, 0.5, 0.5, -300, -90, 300, 90)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 14)
	_black_curtain.add_child(cv)

	_curtain_title = Label.new()
	_curtain_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_curtain_title.uppercase = true
	_curtain_title.add_theme_font_override("font", _font_display)
	_curtain_title.add_theme_font_size_override("font_size", 36)
	_curtain_title.add_theme_color_override("font_color", COL_SIGNAL)
	cv.add_child(_curtain_title)

	_curtain_sub = Label.new()
	_curtain_sub.visible = false
	_curtain_sub.text = ""
	cv.add_child(_curtain_sub)


func _build_main_menu() -> void:
	_menu_root = Control.new()
	_menu_root.theme = _theme
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_root)

	# Soft gradient scrim on left side so right 2/3 showcase live 3D Listener-07 corridor cleanly
	var grad := Gradient.new()
	grad.set_color(0, Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.94))
	grad.set_color(1, Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.0))
	grad.add_point(0.62, Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.80))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 256
	grad_tex.height = 8
	grad_tex.fill_from = Vector2(0.0, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)

	var left_shade := TextureRect.new()
	_anchor_box(left_shade, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 560.0, 0.0)
	left_shade.texture = grad_tex
	left_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(left_shade)

	var hair_div := ColorRect.new()
	_anchor_box(hair_div, 0.0, 0.0, 0.0, 1.0, 386.0, 28.0, 387.0, -28.0)
	hair_div.color = COL_RULE
	hair_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(hair_div)

	var left_col := VBoxContainer.new()
	_anchor_box(left_col, 0.0, 0.0, 0.0, 1.0, 28.0, 34.0, 368.0, -28.0)
	left_col.add_theme_constant_override("separation", 11)
	_menu_root.add_child(left_col)

	_menu_title_lbl = Label.new()
	_menu_title_lbl.uppercase = true
	_menu_title_lbl.add_theme_font_override("font", _font_display)
	_menu_title_lbl.add_theme_font_size_override("font_size", 40)
	_menu_title_lbl.add_theme_color_override("font_color", COL_PAPER)
	_menu_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_col.add_child(_menu_title_lbl)

	_menu_sub_lbl = Label.new()
	_menu_sub_lbl.add_theme_font_override("font", _font_sans)
	_menu_sub_lbl.add_theme_font_size_override("font_size", 16)
	_menu_sub_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
	_menu_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_col.add_child(_menu_sub_lbl)

	_record_plate = PanelContainer.new()
	_record_plate.add_theme_stylebox_override("panel", _make_box(COL_PANEL, COL_RULE_STRONG, 2, 14, 9, 1))
	_attach_corner_ticks(_record_plate, Color(COL_SODIUM, 0.65), 7.0, 1.0)
	left_col.add_child(_record_plate)

	_record_lbl = Label.new()
	_record_lbl.add_theme_font_override("font", _font_mono_bold)
	_record_lbl.add_theme_font_size_override("font_size", 14)
	_record_lbl.add_theme_color_override("font_color", COL_SODIUM)
	_record_plate.add_child(_record_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	left_col.add_child(spacer)

	_btn_nav_solo = Button.new()
	_btn_nav_solo.custom_minimum_size = Vector2(0, 52)
	_btn_nav_solo.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_nav_switch(_btn_nav_solo, false)
	_btn_nav_solo.pressed.connect(func(): _switch_menu_card("solo"))
	left_col.add_child(_btn_nav_solo)

	_btn_nav_coop = Button.new()
	_btn_nav_coop.custom_minimum_size = Vector2(0, 52)
	_btn_nav_coop.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_nav_switch(_btn_nav_coop, false)
	_btn_nav_coop.pressed.connect(func(): _switch_menu_card("coop"))
	left_col.add_child(_btn_nav_coop)

	_btn_nav_settings = Button.new()
	_btn_nav_settings.custom_minimum_size = Vector2(0, 52)
	_btn_nav_settings.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_nav_switch(_btn_nav_settings, false)
	_btn_nav_settings.pressed.connect(func(): _switch_menu_card("settings"))
	left_col.add_child(_btn_nav_settings)

	_btn_nav_how = Button.new()
	_btn_nav_how.custom_minimum_size = Vector2(0, 52)
	_btn_nav_how.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_nav_switch(_btn_nav_how, false)
	_btn_nav_how.pressed.connect(func(): _switch_menu_card("how"))
	left_col.add_child(_btn_nav_how)

	var flex_spacer := Control.new()
	flex_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(flex_spacer)

	var foot_row := HBoxContainer.new()
	foot_row.add_theme_constant_override("separation", 10)
	left_col.add_child(foot_row)

	var inst_id := Label.new()
	inst_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inst_id.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	inst_id.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inst_id.text = "НИИ-07 · КТ-4 · v4.1"
	inst_id.add_theme_font_override("font", _font_mono)
	inst_id.add_theme_font_size_override("font_size", 13)
	inst_id.add_theme_color_override("font_color", COL_PAPER_MUTE)
	foot_row.add_child(inst_id)

	var drawer_style := _make_box(COL_PANEL, COL_RULE_STRONG, 3, 22, 18, 1)

	# A) SOLO CLEARANCE DRAWER (kept within x = 402..850 so Listener-07 stays unobstructed on the right!)
	_card_solo = PanelContainer.new()
	_anchor_box(_card_solo, 0.0, 0.0, 0.0, 0.0, 402.0, 46.0, 850.0, 476.0)
	_card_solo.add_theme_stylebox_override("panel", drawer_style)
	_attach_corner_ticks(_card_solo, COL_SODIUM, 10.0, 1.0)
	_card_solo.visible = false
	_menu_root.add_child(_card_solo)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	_card_solo.add_child(sv)

	_diff_title_lbl = _make_drawer_header(sv, func(): _switch_menu_card(""))

	for d_idx in range(3):
		var db := Button.new()
		db.custom_minimum_size = Vector2(0, 62)
		db.alignment = HORIZONTAL_ALIGNMENT_LEFT
		db.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_button(db, false, d_idx == SaveState.difficulty)
		db.add_theme_font_size_override("font_size", 15)
		var captured := d_idx
		db.draw.connect(func():
			var sel := (captured == SaveState.difficulty)
			var sq := Rect2(14.0, db.size.y * 0.5 - 5.0, 10.0, 10.0)
			if sel:
				db.draw_rect(sq, COL_SODIUM, true)
			else:
				db.draw_rect(sq, COL_RULE_STRONG, false, 1.0)
		)
		db.pressed.connect(func():
			SynthAudio.play_2d("ui_click", -5.0)
			SaveState.difficulty = captured
			SaveState.save_profile()
			_refresh_diff_buttons()
		)
		sv.add_child(db)
		_diff_btns.append(db)

	var sp_s := Control.new()
	sp_s.custom_minimum_size = Vector2(0, 4)
	sv.add_child(sp_s)

	_btn_begin_solo = Button.new()
	_btn_begin_solo.custom_minimum_size = Vector2(0, 52)
	_style_button(_btn_begin_solo, true, false)
	_btn_begin_solo.add_theme_font_override("font", _font_display_md)
	_btn_begin_solo.add_theme_font_size_override("font_size", 20)
	_btn_begin_solo.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -2.0)
		start_solo_requested.emit(SaveState.difficulty)
	)
	sv.add_child(_btn_begin_solo)

	# B) CO-OP RELAY UPLINK CONSOLE
	_card_coop = PanelContainer.new()
	_anchor_box(_card_coop, 0.0, 0.0, 0.0, 0.0, 402.0, 30.0, 902.0, 668.0)
	_card_coop.add_theme_stylebox_override("panel", drawer_style)
	_attach_corner_ticks(_card_coop, COL_PHOSPHOR, 10.0, 1.0)
	_card_coop.visible = false
	_menu_root.add_child(_card_coop)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	_card_coop.add_child(cv)

	_coop_title_lbl = _make_drawer_header(cv, func(): _switch_menu_card(""))

	var row_prof := HBoxContainer.new()
	row_prof.add_theme_constant_override("separation", 10)
	cv.add_child(row_prof)

	var col_name := VBoxContainer.new()
	col_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_name.add_theme_constant_override("separation", 4)
	row_prof.add_child(col_name)

	_lbl_callsign = Label.new()
	_lbl_callsign.add_theme_font_override("font", _font_mono)
	_lbl_callsign.add_theme_font_size_override("font_size", 13)
	_lbl_callsign.add_theme_color_override("font_color", COL_PAPER_DIM)
	col_name.add_child(_lbl_callsign)

	_name_input = LineEdit.new()
	_name_input.text = SaveState.callsign
	_name_input.placeholder_text = "SURVIVOR"
	_name_input.custom_minimum_size = Vector2(0, 44)
	_name_input.text_changed.connect(func(nt: String):
		SaveState.callsign = nt.strip_edges().left(14) if not nt.strip_edges().is_empty() else "SURVIVOR"
		SaveState.save_profile()
	)
	col_name.add_child(_name_input)

	var col_relay := VBoxContainer.new()
	col_relay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_relay.add_theme_constant_override("separation", 4)
	row_prof.add_child(col_relay)

	_lbl_relay = Label.new()
	_lbl_relay.add_theme_font_override("font", _font_mono)
	_lbl_relay.add_theme_font_size_override("font_size", 13)
	_lbl_relay.add_theme_color_override("font_color", COL_PAPER_DIM)
	col_relay.add_child(_lbl_relay)

	_relay_input = LineEdit.new()
	_relay_input.text = SaveState.relay_url
	_relay_input.placeholder_text = "ws://127.0.0.1:8787"
	_relay_input.custom_minimum_size = Vector2(0, 44)
	_relay_input.add_theme_font_override("font", _font_mono)
	_relay_input.add_theme_font_size_override("font_size", 14)
	_relay_input.text_changed.connect(func(nt: String):
		_apply_normalized_relay_url(nt, false)
	)
	_relay_input.text_submitted.connect(func(nt: String):
		_apply_normalized_relay_url(nt, true)
	)
	_relay_input.focus_exited.connect(func():
		_apply_normalized_relay_url(_relay_input.text, true)
	)
	col_relay.add_child(_relay_input)

	_relay_hint_lbl = Label.new()
	_relay_hint_lbl.add_theme_font_override("font", _font_sans)
	_relay_hint_lbl.add_theme_font_size_override("font_size", 13)
	_relay_hint_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
	_relay_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_relay_hint_lbl)

	var row_create := HBoxContainer.new()
	row_create.add_theme_constant_override("separation", 10)
	cv.add_child(row_create)

	_btn_create_room = Button.new()
	_btn_create_room.custom_minimum_size = Vector2(0, 48)
	_btn_create_room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_create_room, true, false)
	_btn_create_room.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		_apply_normalized_relay_url(_relay_input.text, true)
		_coop_error_msg = ""
		_coop_conn_status = "connecting"
		_refresh_coop_ui()
		NetRelay.create_room(true, 1)
	)
	row_create.add_child(_btn_create_room)

	_btn_copy_code = Button.new()
	_btn_copy_code.custom_minimum_size = Vector2(0, 48)
	_btn_copy_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_copy_code, false, false)
	_btn_copy_code.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		NetRelay.copy_invite_to_clipboard()
	)
	row_create.add_child(_btn_copy_code)

	var row_join := HBoxContainer.new()
	row_join.add_theme_constant_override("separation", 10)
	cv.add_child(row_join)

	_code_input = LineEdit.new()
	_code_input.max_length = 6
	_code_input.placeholder_text = "ABCD"
	_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_input.custom_minimum_size = Vector2(104, 48)
	_code_input.add_theme_font_override("font", _font_mono_bold)
	_code_input.add_theme_font_size_override("font_size", 18)
	row_join.add_child(_code_input)

	_btn_join_code = Button.new()
	_btn_join_code.custom_minimum_size = Vector2(0, 48)
	_btn_join_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_join_code, false, false)
	_btn_join_code.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		_apply_normalized_relay_url(_relay_input.text, true)
		_coop_error_msg = ""
		_coop_conn_status = "connecting"
		_refresh_coop_ui()
		NetRelay.join_room(_code_input.text)
	)
	row_join.add_child(_btn_join_code)

	_btn_refresh_public = Button.new()
	_btn_refresh_public.custom_minimum_size = Vector2(0, 48)
	_btn_refresh_public.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_refresh_public, false, false)
	_btn_refresh_public.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		_apply_normalized_relay_url(_relay_input.text, true)
		_coop_error_msg = ""
		_coop_conn_status = "connecting"
		_refresh_coop_ui()
		NetRelay.request_open_lobbies()
	)
	row_join.add_child(_btn_refresh_public)

	_coop_status_lbl = Label.new()
	_coop_status_lbl.add_theme_font_override("font", _font_mono)
	_coop_status_lbl.add_theme_font_size_override("font_size", 14)
	_coop_status_lbl.add_theme_color_override("font_color", COL_SODIUM)
	_coop_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_coop_status_lbl)

	var rooms_scroll := ScrollContainer.new()
	rooms_scroll.custom_minimum_size = Vector2(0, 108)
	rooms_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(rooms_scroll)

	_public_rooms_box = VBoxContainer.new()
	_public_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_public_rooms_box.add_theme_constant_override("separation", 6)
	rooms_scroll.add_child(_public_rooms_box)

	_btn_launch_coop = Button.new()
	_btn_launch_coop.custom_minimum_size = Vector2(0, 52)
	_style_button(_btn_launch_coop, true, false)
	_btn_launch_coop.add_theme_font_override("font", _font_display_md)
	_btn_launch_coop.add_theme_font_size_override("font_size", 19)
	_btn_launch_coop.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -2.0)
		start_coop_match_requested.emit(SaveState.difficulty)
	)
	cv.add_child(_btn_launch_coop)

	# C) SETTINGS CONSOLE (Language Switch lives ONLY here)
	_card_settings = PanelContainer.new()
	_anchor_box(_card_settings, 0.0, 0.0, 0.0, 0.0, 402.0, 40.0, 916.0, 614.0)
	_card_settings.add_theme_stylebox_override("panel", drawer_style)
	_attach_corner_ticks(_card_settings, COL_SODIUM, 10.0, 1.0)
	_card_settings.visible = false
	_menu_root.add_child(_card_settings)

	var stv := VBoxContainer.new()
	stv.add_theme_constant_override("separation", 12)
	_card_settings.add_child(stv)

	_set_title_lbl = _make_drawer_header(stv, func(): _switch_menu_card(""))

	var sens_row := HBoxContainer.new()
	stv.add_child(sens_row)
	_lbl_sens = Label.new()
	_lbl_sens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_sens.add_theme_font_size_override("font_size", 16)
	_lbl_sens.add_theme_color_override("font_color", COL_PAPER)
	sens_row.add_child(_lbl_sens)
	_val_sens_lbl = Label.new()
	_val_sens_lbl.add_theme_font_override("font", _font_mono_bold)
	_val_sens_lbl.add_theme_font_size_override("font_size", 16)
	_val_sens_lbl.add_theme_color_override("font_color", COL_SODIUM)
	sens_row.add_child(_val_sens_lbl)

	_slider_sens = HSlider.new()
	_slider_sens.custom_minimum_size = Vector2(0, 28)
	_slider_sens.min_value = 0.3
	_slider_sens.max_value = 2.5
	_slider_sens.step = 0.05
	_slider_sens.value = SaveState.look_sensitivity
	_slider_sens.value_changed.connect(func(v: float):
		SaveState.look_sensitivity = v
		SaveState.save_profile()
		refresh_texts()
	)
	stv.add_child(_slider_sens)

	var vol_row := HBoxContainer.new()
	stv.add_child(vol_row)
	_lbl_vol = Label.new()
	_lbl_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_vol.add_theme_font_size_override("font_size", 16)
	_lbl_vol.add_theme_color_override("font_color", COL_PAPER)
	vol_row.add_child(_lbl_vol)
	_val_vol_lbl = Label.new()
	_val_vol_lbl.add_theme_font_override("font", _font_mono_bold)
	_val_vol_lbl.add_theme_font_size_override("font_size", 16)
	_val_vol_lbl.add_theme_color_override("font_color", COL_SODIUM)
	vol_row.add_child(_val_vol_lbl)

	_slider_vol = HSlider.new()
	_slider_vol.custom_minimum_size = Vector2(0, 28)
	_slider_vol.min_value = 0.05
	_slider_vol.max_value = 1.2
	_slider_vol.step = 0.05
	_slider_vol.value = SaveState.master_volume
	_slider_vol.value_changed.connect(func(v: float):
		SaveState.master_volume = v
		SaveState.save_profile()
		refresh_texts()
	)
	stv.add_child(_slider_vol)

	_btn_mic_mode = Button.new()
	_btn_mic_mode.custom_minimum_size = Vector2(0, 48)
	_btn_mic_mode.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_button(_btn_mic_mode, false, false)
	_btn_mic_mode.add_theme_font_size_override("font_size", 16)
	_btn_mic_mode.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		SaveState.mic_mode = (SaveState.mic_mode + 1) % 3
		SaveState.save_profile()
		refresh_texts()
	)
	stv.add_child(_btn_mic_mode)

	var toggle_grid := GridContainer.new()
	toggle_grid.columns = 2
	toggle_grid.add_theme_constant_override("h_separation", 10)
	toggle_grid.add_theme_constant_override("v_separation", 10)
	stv.add_child(toggle_grid)

	_btn_gyro = Button.new()
	_btn_gyro.custom_minimum_size = Vector2(0, 58)
	_btn_gyro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_gyro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_button(_btn_gyro, false, SaveState.gyro_enabled)
	_btn_gyro.add_theme_font_size_override("font_size", 15)
	_btn_gyro.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		SaveState.gyro_enabled = not SaveState.gyro_enabled
		SaveState.save_profile()
		refresh_texts()
	)
	toggle_grid.add_child(_btn_gyro)

	_btn_haptics = Button.new()
	_btn_haptics.custom_minimum_size = Vector2(0, 58)
	_btn_haptics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_haptics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_button(_btn_haptics, false, SaveState.haptics_enabled)
	_btn_haptics.add_theme_font_size_override("font_size", 15)
	_btn_haptics.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		SaveState.haptics_enabled = not SaveState.haptics_enabled
		SaveState.save_profile()
		refresh_texts()
	)
	toggle_grid.add_child(_btn_haptics)

	_btn_reduce_motion = Button.new()
	_btn_reduce_motion.custom_minimum_size = Vector2(0, 58)
	_btn_reduce_motion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_reduce_motion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_button(_btn_reduce_motion, false, _get_reduce_motion())
	_btn_reduce_motion.add_theme_font_size_override("font_size", 15)
	_btn_reduce_motion.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		_set_reduce_motion(not _get_reduce_motion())
		refresh_texts()
	)
	toggle_grid.add_child(_btn_reduce_motion)

	_btn_lang = Button.new()
	_btn_lang.custom_minimum_size = Vector2(0, 58)
	_btn_lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_lang.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_button(_btn_lang, false, false)
	_btn_lang.add_theme_font_size_override("font_size", 15)
	_btn_lang.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		Loc.toggle_language()
		SaveState.save_profile()
	)
	toggle_grid.add_child(_btn_lang)

	_btn_replay_tutorial = Button.new()
	_btn_replay_tutorial.custom_minimum_size = Vector2(0, 48)
	_style_button(_btn_replay_tutorial, false, not SaveState.tutorial_completed)
	_btn_replay_tutorial.add_theme_font_size_override("font_size", 15)
	_btn_replay_tutorial.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -5.0)
		SaveState.tutorial_completed = false
		SaveState.save_profile()
		refresh_texts()
	)
	stv.add_child(_btn_replay_tutorial)

	# D) STRUCTURED FIELD MANUAL (Mobile Touch + PC/Gamepad Controls + Survival Protocol)
	_card_how = PanelContainer.new()
	_anchor_box(_card_how, 0.0, 0.0, 0.0, 0.0, 402.0, 32.0, 944.0, 676.0)
	_card_how.add_theme_stylebox_override("panel", drawer_style)
	_attach_corner_ticks(_card_how, COL_COLD, 10.0, 1.0)
	_card_how.visible = false
	_menu_root.add_child(_card_how)

	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 10)
	_card_how.add_child(hv)

	_how_title_lbl = _make_drawer_header(hv, func(): _switch_menu_card(""))

	var how_scroll := ScrollContainer.new()
	how_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hv.add_child(how_scroll)

	var how_scroll_vb := VBoxContainer.new()
	how_scroll_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how_scroll_vb.add_theme_constant_override("separation", 12)
	how_scroll.add_child(how_scroll_vb)

	_how_body_lbl = Label.new()
	_how_body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_how_body_lbl.add_theme_font_override("font", _font_sans)
	_how_body_lbl.add_theme_font_size_override("font_size", 15)
	_how_body_lbl.add_theme_color_override("font_color", COL_PAPER)
	_how_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how_scroll_vb.add_child(_how_body_lbl)

	var sep_how := ColorRect.new()
	sep_how.custom_minimum_size = Vector2(0, 1)
	sep_how.color = COL_RULE
	how_scroll_vb.add_child(sep_how)

	_manual_keys_grid = GridContainer.new()
	_manual_keys_grid.columns = 2
	_manual_keys_grid.add_theme_constant_override("h_separation", 14)
	_manual_keys_grid.add_theme_constant_override("v_separation", 7)
	how_scroll_vb.add_child(_manual_keys_grid)

	var key_specs := [
		["WASD", "KEY_MOVE"],
		["SHIFT", "KEY_SPRINT"],
		["E / LMB", "KEY_INTERACT"],
		["F", "KEY_LIGHT"],
		["R", "KEY_CELL"],
		["C", "KEY_CROUCH"],
		["SPACE", "KEY_BREATH"],
		["G / Q", "KEY_THROW"],
		["RMB", "KEY_USE"],
		["TAB", "KEY_DOSSIER"]
	]
	for ks in key_specs:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		_manual_keys_grid.add_child(row)

		var cap_panel := PanelContainer.new()
		cap_panel.custom_minimum_size = Vector2(82, 28)
		cap_panel.add_theme_stylebox_override("panel", _make_box(COL_INK, COL_RULE_STRONG, 2, 6, 3, 1))
		row.add_child(cap_panel)

		var cap_lbl := Label.new()
		cap_lbl.text = ks[0]
		cap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cap_lbl.add_theme_font_override("font", _font_mono_bold)
		cap_lbl.add_theme_font_size_override("font_size", 12)
		cap_lbl.add_theme_color_override("font_color", COL_SODIUM)
		cap_panel.add_child(cap_lbl)

		var desc_lbl := Label.new()
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_font_override("font", _font_sans)
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
		row.add_child(desc_lbl)

		_manual_key_rows.append({"id": ks[1], "lbl": desc_lbl})


func _build_gameplay_hud() -> void:
	_hud_root = Control.new()
	_hud_root.theme = _theme
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.visible = false
	add_child(_hud_root)

	# 1. TOP-LEFT: Pause + Dossier Toggle (clean label) + Sector Readout + Collapsible Field Dossier
	var tl_col := VBoxContainer.new()
	_anchor_box(tl_col, 0.0, 0.0, 0.0, 0.0, 20.0, 14.0, 388.0, 360.0)
	tl_col.add_theme_constant_override("separation", 6)
	tl_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(tl_col)

	var tl_row := HBoxContainer.new()
	tl_row.add_theme_constant_override("separation", 10)
	tl_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl_col.add_child(tl_row)

	_btn_pause = Button.new()
	_btn_pause.text = ""
	_btn_pause.custom_minimum_size = Vector2(48, 48)
	_style_button(_btn_pause, false, false)
	_btn_pause.draw.connect(func():
		var c := _btn_pause.size * 0.5
		var col := COL_SODIUM if _btn_pause.is_hovered() else COL_PAPER
		_btn_pause.draw_rect(Rect2(c + Vector2(-6.0, -7.0), Vector2(3.5, 14.0)), col, true)
		_btn_pause.draw_rect(Rect2(c + Vector2(2.5, -7.0), Vector2(3.5, 14.0)), col, true)
	)
	_btn_pause.pressed.connect(func(): toggle_pause_modal(true))
	tl_row.add_child(_btn_pause)

	_btn_dossier = Button.new()
	_btn_dossier.custom_minimum_size = Vector2(168, 48)
	_btn_dossier.icon = AssetLibrary.get_icon("ui_journal")
	_btn_dossier.expand_icon = true
	_style_button(_btn_dossier, false, false)
	_btn_dossier.add_theme_font_override("font", _font_sans_bold)
	_btn_dossier.add_theme_font_size_override("font_size", 16)
	_btn_dossier.pressed.connect(_toggle_dossier_pinned)
	tl_row.add_child(_btn_dossier)

	_sector_lbl = Label.new()
	_sector_lbl.uppercase = true
	_sector_lbl.add_theme_font_override("font", _font_display_md)
	_sector_lbl.add_theme_font_size_override("font_size", 16)
	_sector_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
	tl_col.add_child(_sector_lbl)

	_dossier_card = PanelContainer.new()
	_dossier_card.custom_minimum_size = Vector2(360, 0)
	_dossier_card.add_theme_stylebox_override("panel", _make_box(COL_PANEL, COL_RULE_STRONG, 2, 16, 13, 1))
	_attach_corner_ticks(_dossier_card, COL_SODIUM, 8.0, 1.0)
	_dossier_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dossier_card.visible = false
	tl_col.add_child(_dossier_card)

	var d_vb := VBoxContainer.new()
	d_vb.add_theme_constant_override("separation", 7)
	_dossier_card.add_child(d_vb)

	_obj_header_lbl = Label.new()
	_obj_header_lbl.uppercase = true
	_obj_header_lbl.add_theme_font_override("font", _font_display_md)
	_obj_header_lbl.add_theme_font_size_override("font_size", 17)
	_obj_header_lbl.add_theme_color_override("font_color", COL_SODIUM)
	d_vb.add_child(_obj_header_lbl)

	var sep_d := ColorRect.new()
	sep_d.custom_minimum_size = Vector2(0, 1)
	sep_d.color = COL_RULE
	d_vb.add_child(sep_d)

	for key in ["planks", "cable", "power", "padlock"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d_vb.add_child(row)

		var box := Control.new()
		box.custom_minimum_size = Vector2(15, 15)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_meta("done", false)
		box.draw.connect(func():
			var is_done := bool(box.get_meta("done", false))
			var r := Rect2(Vector2(1, 1), Vector2(13, 13))
			if is_done:
				box.draw_rect(r, Color(COL_PHOSPHOR, 0.16), true)
				box.draw_rect(r, COL_PHOSPHOR, false, 1.2)
				box.draw_line(Vector2(3.5, 7.5), Vector2(6.5, 10.5), COL_PHOSPHOR, 1.8, true)
				box.draw_line(Vector2(6.5, 10.5), Vector2(11.5, 4.5), COL_PHOSPHOR, 1.8, true)
			else:
				box.draw_rect(r, COL_RULE_STRONG, false, 1.0)
		)
		row.add_child(box)
		_obj_boxes[key] = box

		var rlbl := Label.new()
		rlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rlbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rlbl.add_theme_font_override("font", _font_sans)
		rlbl.add_theme_font_size_override("font_size", 15)
		rlbl.add_theme_color_override("font_color", COL_PAPER_DIM)
		row.add_child(rlbl)
		_obj_rows[key] = rlbl

	_dossier_code_lbl = Label.new()
	_dossier_code_lbl.add_theme_font_override("font", _font_mono)
	_dossier_code_lbl.add_theme_font_size_override("font_size", 13)
	_dossier_code_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
	d_vb.add_child(_dossier_code_lbl)

	# 1B. MID-LEFT: Compact НИИ-07 Field Orientation Card (below Dossier, above Touch Joystick)
	_tut_card = PanelContainer.new()
	_anchor_box(_tut_card, 0.0, 0.0, 0.0, 0.0, 20.0, 316.0, 376.0, 316.0)
	_tut_card.custom_minimum_size = Vector2(356, 0)
	_tut_card.add_theme_stylebox_override("panel", _make_box(COL_PANEL, COL_RULE_STRONG, 2, 16, 12, 1))
	_attach_corner_ticks(_tut_card, COL_SODIUM, 9.0, 1.0)
	_tut_card.visible = false
	_hud_root.add_child(_tut_card)

	var tut_vb := VBoxContainer.new()
	tut_vb.add_theme_constant_override("separation", 8)
	_tut_card.add_child(tut_vb)

	var tut_hdr := HBoxContainer.new()
	tut_hdr.add_theme_constant_override("separation", 8)
	tut_vb.add_child(tut_hdr)

	_tut_header_lbl = Label.new()
	_tut_header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tut_header_lbl.uppercase = true
	_tut_header_lbl.add_theme_font_override("font", _font_display_md)
	_tut_header_lbl.add_theme_font_size_override("font_size", 17)
	_tut_header_lbl.add_theme_color_override("font_color", COL_SODIUM)
	tut_hdr.add_child(_tut_header_lbl)

	_tut_step_lbl = Label.new()
	_tut_step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tut_step_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tut_step_lbl.text = "1/4"
	_tut_step_lbl.add_theme_font_override("font", _font_mono_bold)
	_tut_step_lbl.add_theme_font_size_override("font_size", 13)
	_tut_step_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
	tut_hdr.add_child(_tut_step_lbl)

	var tut_rule := ColorRect.new()
	tut_rule.custom_minimum_size = Vector2(0, 1)
	tut_rule.color = COL_RULE
	tut_vb.add_child(tut_rule)

	_tut_body_lbl = Label.new()
	_tut_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_body_lbl.add_theme_font_override("font", _font_sans)
	_tut_body_lbl.add_theme_font_size_override("font_size", 15)
	_tut_body_lbl.add_theme_color_override("font_color", COL_PAPER)
	tut_vb.add_child(_tut_body_lbl)

	var tut_btns := HBoxContainer.new()
	tut_btns.add_theme_constant_override("separation", 10)
	tut_vb.add_child(tut_btns)

	_tut_skip_btn = Button.new()
	_tut_skip_btn.custom_minimum_size = Vector2(0, 38)
	_style_button(_tut_skip_btn, false, false)
	_tut_skip_btn.add_theme_font_override("font", _font_mono)
	_tut_skip_btn.add_theme_font_size_override("font_size", 13)
	_tut_skip_btn.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -6.0)
		dismiss_tutorial()
	)
	tut_btns.add_child(_tut_skip_btn)

	var tut_sp := Control.new()
	tut_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut_btns.add_child(tut_sp)

	_tut_next_btn = Button.new()
	_tut_next_btn.custom_minimum_size = Vector2(104, 38)
	_style_button(_tut_next_btn, true, false)
	_tut_next_btn.add_theme_font_override("font", _font_mono_bold)
	_tut_next_btn.add_theme_font_size_override("font_size", 13)
	_tut_next_btn.pressed.connect(func():
		SynthAudio.play_2d("ui_click", -6.0)
		advance_tutorial_if_step(_tut_step)
	)
	tut_btns.add_child(_tut_next_btn)

	# 2. TOP-CENTER: Sleek Acoustic dB Oscilloscope Instrument ONLY (+ thin Breath Bar underneath when active)
	var top_bar_wrap := CenterContainer.new()
	_anchor_box(top_bar_wrap, 0.5, 0.0, 0.5, 0.0, -140.0, 14.0, 140.0, 74.0)
	top_bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(top_bar_wrap)

	_top_status_bar = PanelContainer.new()
	_top_status_bar.custom_minimum_size = Vector2(248, 48)
	_top_bar_style = _make_box(COL_PANEL, COL_RULE_STRONG, 2, 8, 6, 1)
	_top_status_bar.add_theme_stylebox_override("panel", _top_bar_style)
	_attach_corner_ticks(_top_status_bar, COL_RULE_STRONG, 7.0, 1.0)
	_top_status_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar_wrap.add_child(_top_status_bar)

	var top_vb := VBoxContainer.new()
	top_vb.add_theme_constant_override("separation", 4)
	top_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_status_bar.add_child(top_vb)

	_acoustic_scope = AcousticScopeControl.new()
	_acoustic_scope.custom_minimum_size = Vector2(232, 42)
	_acoustic_scope.mono_font = _font_mono
	_acoustic_scope.mono_bold = _font_mono_bold
	top_vb.add_child(_acoustic_scope)

	_breath_bar = ProgressBar.new()
	_breath_bar.max_value = 100.0
	_breath_bar.value = 100.0
	_breath_bar.show_percentage = false
	_breath_bar.custom_minimum_size = Vector2(232, 5)
	_breath_bar.add_theme_stylebox_override("background", _make_box(COL_INK, COL_RULE, 1, 0, 0, 1))
	_breath_bar.add_theme_stylebox_override("fill", _make_box(COL_COLD, Color.TRANSPARENT, 1, 0, 0, 0))
	_breath_bar.visible = false
	top_vb.add_child(_breath_bar)

	# 2B. TOP-CENTER THREAT / STATUS WHISPER (directly below Acoustic Oscilloscope at y = 76)
	var status_wrap := CenterContainer.new()
	_anchor_box(status_wrap, 0.0, 0.0, 1.0, 0.0, 220.0, 76.0, -220.0, 122.0)
	status_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(status_wrap)

	_status_pill = PanelContainer.new()
	_status_pill.custom_minimum_size = Vector2(340, 40)
	_status_pill_style = _make_box(COL_PANEL, COL_RULE_STRONG, 2, 16, 7, 1)
	_status_pill.add_theme_stylebox_override("panel", _status_pill_style)
	_attach_corner_ticks(_status_pill, COL_SODIUM, 7.0, 1.0)
	_status_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_pill.visible = false
	status_wrap.add_child(_status_pill)

	_stalker_alert_lbl = Label.new()
	_stalker_alert_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stalker_alert_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stalker_alert_lbl.add_theme_font_override("font", _font_sans_bold)
	_stalker_alert_lbl.add_theme_font_size_override("font_size", 15)
	_stalker_alert_lbl.add_theme_color_override("font_color", COL_PAPER)
	_status_pill.add_child(_stalker_alert_lbl)

	# 3. TOP-RIGHT: Clean Static Square-Framed LoS Map ONLY
	var tr_col := VBoxContainer.new()
	_anchor_box(tr_col, 1.0, 0.0, 1.0, 0.0, -200.0, 14.0, -20.0, 194.0)
	tr_col.add_theme_constant_override("separation", 0)
	tr_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(tr_col)

	minimap = LoSMinimapControl.new()
	tr_col.add_child(minimap)

	# 4. CENTER RETICLE & CLEAN CONTEXTUAL INTERACTION PROMPT (Tappable on Mobile, NO [E] Keycap)
	_reticle_dot = ColorRect.new()
	_anchor_box(_reticle_dot, 0.5, 0.5, 0.5, 0.5, -1.0, -1.0, 1.0, 1.0)
	_reticle_dot.color = Color(COL_PAPER, 0.85)
	_reticle_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_reticle_dot)

	_reticle_canvas = Control.new()
	_anchor_box(_reticle_canvas, 0.5, 0.5, 0.5, 0.5, -24.0, -24.0, 24.0, 24.0)
	_reticle_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle_canvas.draw.connect(func():
		var c := _reticle_canvas.size * 0.5
		var g := _reticle_gap
		var l := 5.5 if _reticle_active else 4.0
		var col := COL_SODIUM if _reticle_active else Color(COL_PAPER, 0.62)
		var w := 1.8 if _reticle_active else 1.2
		_reticle_canvas.draw_line(c + Vector2(-g - l, 0), c + Vector2(-g, 0), col, w)
		_reticle_canvas.draw_line(c + Vector2(g, 0), c + Vector2(g + l, 0), col, w)
		_reticle_canvas.draw_line(c + Vector2(0, -g - l), c + Vector2(0, -g), col, w)
		_reticle_canvas.draw_line(c + Vector2(0, g), c + Vector2(0, g + l), col, w)
	)
	_hud_root.add_child(_reticle_canvas)

	var prompt_wrap := CenterContainer.new()
	_anchor_box(prompt_wrap, 0.0, 0.5, 1.0, 0.5, 0.0, 28.0, 0.0, 80.0)
	prompt_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(prompt_wrap)

	_prompt_box = PanelContainer.new()
	_prompt_box.custom_minimum_size = Vector2(240, 46)
	_prompt_box.add_theme_stylebox_override("panel", _make_box(COL_PANEL, Color(COL_SODIUM, 0.72), 2, 16, 9, 1))
	_attach_corner_ticks(_prompt_box, COL_SODIUM, 6.0, 1.0)
	_prompt_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_prompt_box.visible = false
	_prompt_box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and player != null:
				player.trigger_interact()
	)
	prompt_wrap.add_child(_prompt_box)

	var phb := HBoxContainer.new()
	phb.alignment = BoxContainer.ALIGNMENT_CENTER
	phb.add_theme_constant_override("separation", 10)
	phb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_box.add_child(phb)

	_prompt_icon = TextureRect.new()
	_prompt_icon.texture = AssetLibrary.get_icon("ui_hand")
	_prompt_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_prompt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_prompt_icon.custom_minimum_size = Vector2(22, 22)
	_prompt_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phb.add_child(_prompt_icon)

	_prompt_lbl = Label.new()
	_prompt_lbl.add_theme_font_override("font", _font_sans_bold)
	_prompt_lbl.add_theme_font_size_override("font_size", 16)
	_prompt_lbl.add_theme_color_override("font_color", COL_PAPER)
	_prompt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phb.add_child(_prompt_lbl)

	# 5. BOTTOM-CENTER: Toast + Equipped Readout + 5x 68px Tactical Inventory Slots (NO PC Hint Strip)
	var inv_anchor := VBoxContainer.new()
	_anchor_box(inv_anchor, 0.5, 1.0, 0.5, 1.0, -360.0, -156.0, 360.0, -14.0)
	inv_anchor.alignment = BoxContainer.ALIGNMENT_END
	inv_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_anchor.add_theme_constant_override("separation", 6)
	_hud_root.add_child(inv_anchor)

	_toast_plate = PanelContainer.new()
	_toast_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_plate.add_theme_stylebox_override("panel", _make_box(COL_INK, Color(COL_SODIUM, 0.55), 2, 14, 5, 1))
	_toast_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_plate.visible = false
	inv_anchor.add_child(_toast_plate)

	_toast_lbl = Label.new()
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lbl.add_theme_font_override("font", _font_sans_bold)
	_toast_lbl.add_theme_font_size_override("font_size", 15)
	_toast_lbl.add_theme_color_override("font_color", COL_SODIUM)
	_toast_plate.add_child(_toast_lbl)

	_held_item_lbl = Label.new()
	_held_item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held_item_lbl.add_theme_font_override("font", _font_sans_bold)
	_held_item_lbl.add_theme_font_size_override("font_size", 16)
	_held_item_lbl.add_theme_color_override("font_color", COL_PAPER)
	inv_anchor.add_child(_held_item_lbl)

	var slots_hb := HBoxContainer.new()
	slots_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_hb.add_theme_constant_override("separation", 10)
	inv_anchor.add_child(slots_hb)

	for s_idx in range(ListenerPlayer.MAX_SLOTS):
		var sb := Button.new()
		sb.custom_minimum_size = Vector2(68, 68)
		sb.add_theme_stylebox_override("focus", _make_box(Color.TRANSPARENT, COL_SODIUM, 2, 4, 4, 1))
		var captured := s_idx
		sb.pressed.connect(func():
			if player != null:
				SynthAudio.play_2d("ui_click", -8.0)
				player.select_slot(captured)
		)
		slots_hb.add_child(sb)
		_slot_btns.append(sb)

		var ic := TextureRect.new()
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 12
		ic.offset_top = 12
		ic.offset_right = -12
		ic.offset_bottom = -12
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sb.add_child(ic)
		_slot_icons.append(ic)

		var num := Label.new()
		num.text = str(s_idx + 1)
		num.position = Vector2(6, 3)
		num.add_theme_font_override("font", _font_mono_bold)
		num.add_theme_font_size_override("font_size", 13)
		num.add_theme_color_override("font_color", COL_PAPER_DIM)
		sb.add_child(num)
		_slot_nums.append(num)

	# 6. MOBILE TOUCH CONTROLS:
	#    - Left Floating Virtual Joystick (168x168, 66x66 knob, outer 75% auto-sprint ring)
	#    - Double-Tap Right Side to Interact (no Interact/Sprint buttons!)
	#    - Symmetrical 2x2 Bottom-Right Action Grid (72x72, 14px gaps; Drop appears only when holding an item)
	_joy_base = Panel.new()
	_anchor_box(_joy_base, 0.0, 1.0, 0.0, 1.0, 32.0, -200.0, 200.0, -32.0)
	_joy_base.custom_minimum_size = Vector2(JOY_SIZE, JOY_SIZE)
	_joy_base.add_theme_stylebox_override("panel", _make_box(Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.56), COL_RULE_STRONG, int(JOY_SIZE * 0.5), 0, 0, 1))
	_joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_base.draw.connect(func():
		var c := _joy_base.size * 0.5
		var active := (_joy_touch_idx != -1)
		var outer_col := Color(COL_SODIUM, 0.72) if active else Color(COL_PAPER_DIM, 0.30)
		_joy_base.draw_arc(c, JOY_MAX_R + 6.0, 0.0, TAU, 56, outer_col, 1.4, true)
		var sprint_r := JOY_MAX_R * JOY_SPRINT_RATIO
		var sprint_col := COL_SODIUM if _joy_sprinting else Color(COL_SODIUM, 0.28 if active else 0.16)
		var sprint_w := 2.4 if _joy_sprinting else 1.2
		_joy_base.draw_arc(c, sprint_r, 0.0, TAU, 48, sprint_col, sprint_w, true)
		_joy_base.draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), Color(COL_PAPER_DIM, 0.25), 1.0)
		_joy_base.draw_line(c + Vector2(0, -10), c + Vector2(0, 10), Color(COL_PAPER_DIM, 0.25), 1.0)
	)
	_hud_root.add_child(_joy_base)

	_joy_knob = Panel.new()
	_joy_knob.custom_minimum_size = Vector2(JOY_KNOB_SIZE, JOY_KNOB_SIZE)
	_joy_knob.position = JOY_REST_POS
	_joy_knob.add_theme_stylebox_override("panel", _make_box(Color(COL_PAPER.r, COL_PAPER.g, COL_PAPER.b, 0.80), COL_SODIUM, int(JOY_KNOB_SIZE * 0.5), 0, 0, 1))
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_base.add_child(_joy_knob)

	# Symmetrical 2x2 Thumb Grid (72x72, 14px gap, 24px right margin, 28px bottom margin)
	_btn_breath = _make_icon_action_btn("ui_breath", Vector2(-96, -100), Vector2(72, 72), Control.PRESET_BOTTOM_RIGHT)
	_btn_breath.button_down.connect(func():
		if player != null:
			player.touch_holding_breath = true
	)
	_btn_breath.button_up.connect(func():
		if player != null:
			player.touch_holding_breath = false
	)

	_btn_crouch = _make_icon_action_btn("ui_crouch", Vector2(-182, -100), Vector2(72, 72), Control.PRESET_BOTTOM_RIGHT)
	_btn_crouch.pressed.connect(func():
		if player != null:
			player.toggle_crouch()
	)

	_btn_flashlight = _make_icon_action_btn("ui_flashlight", Vector2(-96, -186), Vector2(72, 72), Control.PRESET_BOTTOM_RIGHT)
	_btn_flashlight.pressed.connect(func():
		if player != null:
			player.toggle_flashlight()
	)

	_btn_drop = _make_icon_action_btn("ui_drop", Vector2(-182, -186), Vector2(72, 72), Control.PRESET_BOTTOM_RIGHT)
	_btn_drop.pressed.connect(func():
		if player != null:
			player.drop_or_throw_equipped()
	)

	# Double-tap visual confirmation ripple
	_tap_ripple_ctrl = Control.new()
	_tap_ripple_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_ripple_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_ripple_ctrl.visible = false
	_tap_ripple_ctrl.draw.connect(func():
		if _tap_ripple_timer <= 0.0:
			return
		var t := 1.0 - (_tap_ripple_timer / 0.28)
		var r := lerpf(10.0, 34.0, t)
		var a := clampf(1.0 - t, 0.0, 1.0) * 0.85
		_tap_ripple_ctrl.draw_arc(_tap_ripple_pos, r, 0.0, TAU, 28, Color(COL_SODIUM, a), 2.0, true)
	)
	_hud_root.add_child(_tap_ripple_ctrl)

	_is_touch_device = OS.get_name() == "Android" or DisplayServer.is_touchscreen_available()
	_set_touch_controls_visible(_is_touch_device)


func _toggle_dossier_pinned() -> void:
	_dossier_pinned = not _dossier_pinned
	SynthAudio.play_2d("ui_click", -7.0)
	_dossier_card.visible = _dossier_pinned or (_dossier_peek_timer > 0.0)
	if _dossier_card.visible:
		_tween_pop_in(_dossier_card, 0.98, 0.90, 0.16)
	_style_button(_btn_dossier, false, _dossier_pinned)
	_btn_dossier.add_theme_font_size_override("font_size", 16)
	advance_tutorial_if_step(4)


func _set_touch_controls_visible(vis: bool) -> void:
	_touch_controls_visible = vis
	for w in [_joy_base, _btn_breath, _btn_flashlight, _btn_crouch]:
		if w != null:
			w.visible = vis
	if _btn_drop != null:
		var has_item := (player != null and not player.get_equipped_item().is_empty())
		_btn_drop.visible = vis and has_item


func _make_icon_action_btn(icon_id: String, pos: Vector2, sz: Vector2, preset: Control.LayoutPreset) -> Button:
	var b := Button.new()
	b.set_anchors_preset(preset)
	b.offset_left = pos.x
	b.offset_top = pos.y
	b.offset_right = pos.x + sz.x
	b.offset_bottom = pos.y + sz.y
	b.custom_minimum_size = sz
	_apply_touch_btn_highlight(b, false, COL_SODIUM)
	_hud_root.add_child(b)

	var tr := TextureRect.new()
	tr.texture = AssetLibrary.get_icon(icon_id)
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 14
	tr.offset_left = pad
	tr.offset_top = pad
	tr.offset_right = -pad
	tr.offset_bottom = -pad
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tr)
	return b


func _apply_touch_btn_highlight(b: Button, active: bool, active_col: Color, idle_border_col: Color = COL_RULE_STRONG) -> void:
	if b == null:
		return
	var state_key := "%s_%s_%s" % [str(active), active_col.to_html(false), idle_border_col.to_html(true)]
	if str(b.get_meta("hl_key", "")) == state_key:
		return
	b.set_meta("hl_key", state_key)
	var bg := Color(active_col.r * 0.24, active_col.g * 0.24, active_col.b * 0.24, 0.90) if active else Color(COL_PANEL.r, COL_PANEL.g, COL_PANEL.b, 0.88)
	var brd := active_col if active else idle_border_col
	var rad := 6
	b.add_theme_stylebox_override("normal", _make_box(bg, brd, rad, 6, 6, 1))
	b.add_theme_stylebox_override("hover", _make_box(COL_PANEL_HI, active_col, rad, 6, 6, 1))
	b.add_theme_stylebox_override("pressed", _make_box(Color(active_col, 0.35), active_col, rad, 6, 6, 1))
	b.add_theme_stylebox_override("focus", _make_box(bg, active_col, rad, 6, 6, 1))
	_attach_corner_ticks(b, active_col if active else idle_border_col, 7.0, 1.5)


func _build_safe_keypad_modal() -> void:
	_safe_modal = PanelContainer.new()
	_safe_modal.theme = _theme
	_anchor_box(_safe_modal, 0.5, 0.5, 0.5, 0.5, -188.0, -236.0, 188.0, 236.0)
	_safe_modal.custom_minimum_size = Vector2(376, 472)
	_safe_modal.add_theme_stylebox_override("panel", _make_box(COL_PANEL, COL_RULE_STRONG, 3, 22, 20, 1))
	_attach_corner_ticks(_safe_modal, COL_SODIUM, 11.0, 1.0)
	_safe_modal.visible = false
	add_child(_safe_modal)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_safe_modal.add_child(vb)

	_safe_title_lbl = Label.new()
	_safe_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_safe_title_lbl.uppercase = true
	_safe_title_lbl.add_theme_font_override("font", _font_display)
	_safe_title_lbl.add_theme_font_size_override("font_size", 24)
	_safe_title_lbl.add_theme_color_override("font_color", COL_PAPER)
	vb.add_child(_safe_title_lbl)

	var disp_bezel := PanelContainer.new()
	disp_bezel.add_theme_stylebox_override("panel", _make_box(COL_INK, COL_RULE_STRONG, 2, 12, 10, 1))
	vb.add_child(disp_bezel)

	_safe_display_lbl = Label.new()
	_safe_display_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_safe_display_lbl.text = "_ _ _ _"
	_safe_display_lbl.add_theme_font_override("font", _font_mono_bold)
	_safe_display_lbl.add_theme_font_size_override("font_size", 34)
	_safe_display_lbl.add_theme_color_override("font_color", COL_SODIUM)
	disp_bezel.add_child(_safe_display_lbl)

	_safe_hint_lbl = Label.new()
	_safe_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_safe_hint_lbl.add_theme_font_override("font", _font_mono)
	_safe_hint_lbl.add_theme_font_size_override("font_size", 14)
	_safe_hint_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
	_safe_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_safe_hint_lbl)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)

	var keys: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "X"]
	for k in keys:
		var kb := Button.new()
		kb.text = k
		kb.custom_minimum_size = Vector2(104, 56)
		if k == "X":
			kb.add_theme_stylebox_override("normal", _make_box(Color(0.16, 0.07, 0.06, 0.94), Color(COL_SIGNAL, 0.7), 2, 0, 0, 1))
			kb.add_theme_stylebox_override("hover", _make_box(Color(0.24, 0.09, 0.08, 0.98), COL_SIGNAL, 2, 0, 0, 1))
			kb.add_theme_stylebox_override("pressed", _make_box(COL_SIGNAL, COL_SIGNAL, 2, 0, 0, 1))
			kb.add_theme_stylebox_override("focus", _make_box(Color.TRANSPARENT, COL_SODIUM, 2, 0, 0, 1))
			kb.add_theme_color_override("font_color", COL_SIGNAL)
			kb.add_theme_color_override("font_hover_color", COL_PAPER)
		else:
			_style_button(kb, false, false)
		kb.add_theme_font_override("font", _font_mono_bold)
		kb.add_theme_font_size_override("font_size", 20)
		var cap_k: String = k
		kb.pressed.connect(func(): _on_safe_key_pressed(cap_k))
		grid.add_child(kb)


func _on_safe_key_pressed(k: String) -> void:
	if k == "X":
		close_safe_modal()
		return
	if k == "CLR":
		_safe_entered = ""
		SynthAudio.play_2d("keypad_beep", -6.0, 0.8)
		_update_safe_display()
		return
	if _safe_entered.length() < 4:
		_safe_entered += k
		SynthAudio.play_2d("keypad_beep", -4.0, 1.0 + float(int(k)) * 0.03)
		_update_safe_display()
		if _safe_entered.length() == 4:
			var code := _safe_entered
			_safe_entered = ""
			safe_code_submitted.emit(code)


func _update_safe_display() -> void:
	var parts: Array[String] = []
	for i in range(4):
		parts.append(_safe_entered[i] if i < _safe_entered.length() else "_")
	_safe_display_lbl.text = " ".join(parts)


func open_safe_modal(known_code: String) -> void:
	_safe_entered = ""
	_update_safe_display()
	if known_code.is_empty():
		_safe_hint_lbl.text = Loc.t("SAFE_NO_NOTE")
	else:
		_safe_hint_lbl.text = Loc.t("SAFE_KNOWN_CODE") % known_code
	_modal_scrim.visible = true
	_safe_modal.visible = true
	_tween_pop_in(_safe_modal, 0.96, 0.88, 0.18)
	if player != null:
		player.controls_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close_safe_modal() -> void:
	_safe_modal.visible = false
	_modal_scrim.visible = _pause_modal.visible or _end_modal.visible
	if player != null and _hud_root.visible and not _pause_modal.visible and not _end_modal.visible:
		player.controls_enabled = true
		if DisplayServer.get_name() != "headless" and OS.get_name() != "Android":
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _build_pause_and_end_modals() -> void:
	var modal_style := _make_box(COL_PANEL, COL_RULE_STRONG, 3, 26, 24, 1)

	_pause_modal = PanelContainer.new()
	_pause_modal.theme = _theme
	_anchor_box(_pause_modal, 0.5, 0.5, 0.5, 0.5, -196.0, -160.0, 196.0, 160.0)
	_pause_modal.custom_minimum_size = Vector2(392, 320)
	_pause_modal.add_theme_stylebox_override("panel", modal_style)
	_attach_corner_ticks(_pause_modal, COL_SODIUM, 11.0, 1.0)
	_pause_modal.visible = false
	add_child(_pause_modal)

	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 12)
	_pause_modal.add_child(pv)

	_pause_title_lbl = Label.new()
	_pause_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_title_lbl.uppercase = true
	_pause_title_lbl.add_theme_font_override("font", _font_display)
	_pause_title_lbl.add_theme_font_size_override("font_size", 32)
	_pause_title_lbl.add_theme_color_override("font_color", COL_PAPER)
	pv.add_child(_pause_title_lbl)

	var p_sep := ColorRect.new()
	p_sep.custom_minimum_size = Vector2(0, 1)
	p_sep.color = COL_RULE
	pv.add_child(p_sep)

	_btn_resume = Button.new()
	_btn_resume.custom_minimum_size = Vector2(0, 52)
	_style_button(_btn_resume, true, false)
	_btn_resume.pressed.connect(func():
		toggle_pause_modal(false)
		resume_requested.emit()
	)
	pv.add_child(_btn_resume)

	_btn_restart = Button.new()
	_btn_restart.custom_minimum_size = Vector2(0, 50)
	_style_button(_btn_restart, false, false)
	_btn_restart.pressed.connect(func():
		toggle_pause_modal(false)
		restart_match_requested.emit()
	)
	pv.add_child(_btn_restart)

	_btn_to_menu = Button.new()
	_btn_to_menu.custom_minimum_size = Vector2(0, 50)
	_style_button(_btn_to_menu, false, false)
	_btn_to_menu.pressed.connect(func():
		toggle_pause_modal(false)
		return_to_menu_requested.emit()
	)
	pv.add_child(_btn_to_menu)

	_end_modal = PanelContainer.new()
	_end_modal.theme = _theme
	_anchor_box(_end_modal, 0.5, 0.5, 0.5, 0.5, -250.0, -172.0, 250.0, 172.0)
	_end_modal.custom_minimum_size = Vector2(500, 344)
	_end_modal.add_theme_stylebox_override("panel", modal_style)
	_attach_corner_ticks(_end_modal, COL_SODIUM, 12.0, 1.0)
	_end_modal.visible = false
	add_child(_end_modal)

	var ev := VBoxContainer.new()
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_theme_constant_override("separation", 14)
	_end_modal.add_child(ev)

	_end_title_lbl = Label.new()
	_end_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title_lbl.uppercase = true
	_end_title_lbl.add_theme_font_override("font", _font_display)
	_end_title_lbl.add_theme_font_size_override("font_size", 36)
	ev.add_child(_end_title_lbl)

	var e_sep := ColorRect.new()
	e_sep.custom_minimum_size = Vector2(0, 1)
	e_sep.color = COL_RULE
	ev.add_child(e_sep)

	_end_sub_lbl = Label.new()
	_end_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_sub_lbl.add_theme_font_override("font", _font_sans)
	_end_sub_lbl.add_theme_font_size_override("font_size", 16)
	_end_sub_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
	ev.add_child(_end_sub_lbl)

	_btn_play_again = Button.new()
	_btn_play_again.custom_minimum_size = Vector2(0, 52)
	_style_button(_btn_play_again, true, false)
	_btn_play_again.pressed.connect(func():
		_end_modal.visible = false
		_modal_scrim.visible = false
		restart_match_requested.emit()
	)
	ev.add_child(_btn_play_again)

	_btn_end_menu = Button.new()
	_btn_end_menu.custom_minimum_size = Vector2(0, 50)
	_style_button(_btn_end_menu, false, false)
	_btn_end_menu.pressed.connect(func():
		_end_modal.visible = false
		_modal_scrim.visible = false
		return_to_menu_requested.emit()
	)
	ev.add_child(_btn_end_menu)


func _reset_chase_panic_fx() -> void:
	_chase_intensity = 0.0
	_chase_prox = 0.0
	_chase_pulse_t = 0.0
	if _chase_panic_overlay != null:
		_chase_panic_overlay.visible = false
	if _chase_vignette != null:
		_chase_vignette.modulate.a = 0.0
	if _chase_interference != null:
		_chase_interference.visible = false
	if _acoustic_scope != null:
		_acoustic_scope.chase_flare = 0.0


func show_main_menu() -> void:
	_menu_root.visible = true
	_hud_root.visible = false
	_safe_modal.visible = false
	_pause_modal.visible = false
	_end_modal.visible = false
	_modal_scrim.visible = false
	_black_curtain.visible = false
	_jumpscare_flash_timer = 0.0
	_jumpscare_overlay.visible = false
	_wakeup_timer = 0.0
	_wakeup_overlay.visible = false
	_blood_vig_alpha = 0.0
	_blood_vignette.modulate.a = 0.0
	_blood_vignette.visible = false
	_reset_chase_panic_fx()
	_tut_active = false
	_tut_step = 0
	_tut_card.visible = false
	_danger_overlay.color.a = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_record_readout()
	_refresh_coop_ui()


func show_gameplay_hud() -> void:
	_menu_root.visible = false
	_hud_root.visible = true
	_safe_modal.visible = false
	_pause_modal.visible = false
	_end_modal.visible = false
	_modal_scrim.visible = false
	_blood_vig_alpha = 0.0
	_blood_vignette.modulate.a = 0.0
	_blood_vignette.visible = false
	_reset_chase_panic_fx()
	_wakeup_timer = 0.0
	_wakeup_overlay.visible = false
	_dossier_pinned = false
	_dossier_peek_timer = 4.0
	_dossier_card.visible = true
	_style_button(_btn_dossier, false, false)
	_btn_dossier.add_theme_font_size_override("font_size", 16)
	_update_sector_label()
	if DisplayServer.get_name() != "headless" and OS.get_name() != "Android":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	refresh_inventory_bar()


func set_sector_name(sector_txt: String) -> void:
	_sector_text = sector_txt.strip_edges()
	_update_sector_label()


func _update_sector_label() -> void:
	if _sector_lbl == null:
		return
	if _sector_text.is_empty():
		_sector_lbl.text = _tr_or("SECTOR_DEFAULT", "НИИ-07 · КАРАНТИННЫЙ ЭТАЖ", "NII-07 · QUARANTINE FLOOR")
	else:
		_sector_lbl.text = _sector_text


func toggle_pause_modal(open: bool) -> void:
	_pause_modal.visible = open
	_modal_scrim.visible = open or _safe_modal.visible or _end_modal.visible
	if open:
		_tween_pop_in(_pause_modal, 0.96, 0.88, 0.18)
	if player != null:
		player.controls_enabled = not open
	if open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif DisplayServer.get_name() != "headless" and OS.get_name() != "Android":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func show_cage_curtain(visible_flag: bool) -> void:
	_black_curtain.visible = visible_flag
	if visible_flag:
		_jumpscare_flash_timer = 0.0
		_jumpscare_overlay.visible = false
		_reset_chase_panic_fx()
		_curtain_title.text = Loc.t("CAGE_TRANSITION_TITLE")
		_curtain_sub.text = ""
		_curtain_sub.visible = false
		_tween_pop_in(_black_curtain, 1.0, 0.86, 0.28)


func _process(delta: float) -> void:
	if _jumpscare_flash_timer > 0.0:
		_jumpscare_flash_timer = maxf(0.0, _jumpscare_flash_timer - delta)
		if _jumpscare_flash_timer <= 0.0:
			_jumpscare_overlay.visible = false
		else:
			_jumpscare_overlay.queue_redraw()

	if _wakeup_timer > 0.0:
		_wakeup_timer = maxf(0.0, _wakeup_timer - delta)
		if _wakeup_timer <= 0.0:
			_wakeup_overlay.visible = false
		else:
			_wakeup_overlay.queue_redraw()

	if _tap_ripple_timer > 0.0:
		_tap_ripple_timer = maxf(0.0, _tap_ripple_timer - delta)
		if _tap_ripple_timer <= 0.0:
			_tap_ripple_ctrl.visible = false
		else:
			_tap_ripple_ctrl.queue_redraw()


func _spawn_tap_ripple(pos: Vector2) -> void:
	if _tap_ripple_ctrl == null or _get_reduce_motion():
		return
	_tap_ripple_pos = pos
	_tap_ripple_timer = 0.28
	_tap_ripple_ctrl.visible = true
	_tap_ripple_ctrl.queue_redraw()


func play_cage_wakeup_effect(duration: float = 2.5) -> void:
	if DisplayServer.get_name() == "headless":
		_wakeup_timer = 0.0
		if _wakeup_overlay != null:
			_wakeup_overlay.visible = false
		return
	_wakeup_duration = maxf(0.2, duration)
	_wakeup_timer = _wakeup_duration
	if _wakeup_overlay != null:
		_wakeup_overlay.visible = true
		_wakeup_overlay.queue_redraw()


func _draw_wakeup_overlay() -> void:
	if _wakeup_timer <= 0.0:
		return
	var sz := _wakeup_overlay.size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	var prog := clampf(1.0 - (_wakeup_timer / _wakeup_duration), 0.0, 1.0)
	var rm := _get_reduce_motion()
	# Smooth ease-out clearing + subtle mid-blink dip unless reduce_motion
	var open_amt := 1.0 - pow(1.0 - prog, 1.8)
	if not rm and prog > 0.20 and prog < 0.44:
		var blink_phase := (prog - 0.20) / 0.24
		open_amt *= (1.0 - 0.55 * sin(blink_phase * PI))

	var haze_a := clampf((1.0 - open_amt) * 0.82, 0.0, 0.90)
	# Murky dark-teal/ink groggy haze
	_wakeup_overlay.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.035, 0.048, 0.045, haze_a), true)

	# Soft multi-band eyelid curtain & peripheral blur darkness
	var lid_ratio := clampf(0.52 * (1.0 - open_amt), 0.0, 0.52)
	if lid_ratio > 0.01:
		var lid_h := sz.y * lid_ratio
		for b_i in range(4):
			var frac := float(b_i + 1) / 4.0
			var band_h := lid_h * (1.35 - frac * 0.25)
			var band_a := clampf((1.0 - open_amt) * (0.28 + 0.18 * frac), 0.0, 0.92)
			var band_col := Color(COL_INK.r, COL_INK.g, COL_INK.b, band_a)
			_wakeup_overlay.draw_rect(Rect2(0, 0, sz.x, minf(sz.y * 0.55, band_h)), band_col, true)
			_wakeup_overlay.draw_rect(Rect2(0, maxf(sz.y * 0.45, sz.y - band_h), sz.x, minf(sz.y * 0.55, band_h)), band_col, true)

	var side_w := sz.x * clampf(0.18 * (1.0 - prog), 0.0, 0.22)
	if side_w > 1.0:
		var side_col := Color(COL_INK.r, COL_INK.g, COL_INK.b, clampf((1.0 - prog) * 0.65, 0.0, 0.8))
		_wakeup_overlay.draw_rect(Rect2(0, 0, side_w, sz.y), side_col, true)
		_wakeup_overlay.draw_rect(Rect2(sz.x - side_w, 0, side_w, sz.y), side_col, true)


func play_jumpscare_flash(duration: float = 0.85) -> void:
	_jumpscare_flash_duration = maxf(0.1, duration)
	_jumpscare_flash_timer = _jumpscare_flash_duration
	_jumpscare_overlay.visible = true
	_jumpscare_overlay.queue_redraw()


func _draw_jumpscare_overlay() -> void:
	if _jumpscare_flash_timer <= 0.0:
		return
	var sz := _jumpscare_overlay.size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	var norm_t := clampf(1.0 - (_jumpscare_flash_timer / _jumpscare_flash_duration), 0.0, 1.0)
	var fade := clampf(_jumpscare_flash_timer / maxf(0.18, _jumpscare_flash_duration * 0.45), 0.0, 1.0)
	var rm := _get_reduce_motion()

	if rm:
		var pulse := sin(norm_t * PI)
		_jumpscare_overlay.draw_rect(Rect2(Vector2.ZERO, sz), Color(COL_SIGNAL.r, COL_SIGNAL.g, COL_SIGNAL.b, 0.34 * pulse), true)
		var border_t := clampf(minf(sz.x, sz.y) * 0.10, 24.0, 96.0)
		var vig := Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.72 * pulse)
		_jumpscare_overlay.draw_rect(Rect2(0, 0, sz.x, border_t), vig, true)
		_jumpscare_overlay.draw_rect(Rect2(0, sz.y - border_t, sz.x, border_t), vig, true)
		_jumpscare_overlay.draw_rect(Rect2(0, border_t, border_t, sz.y - border_t * 2.0), vig, true)
		_jumpscare_overlay.draw_rect(Rect2(sz.x - border_t, border_t, border_t, sz.y - border_t * 2.0), vig, true)
		return

	var strobe_wave := 0.5 + 0.5 * sin(norm_t * PI * 14.0)
	var flash_a := (0.42 * strobe_wave + 0.16) * fade
	_jumpscare_overlay.draw_rect(Rect2(Vector2.ZERO, sz), Color(COL_SIGNAL.r, COL_SIGNAL.g, COL_SIGNAL.b, flash_a), true)

	var vig_h := sz.y * 0.14
	var vig_w := sz.x * 0.09
	var vig_col := Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.86 * fade)
	_jumpscare_overlay.draw_rect(Rect2(0, 0, sz.x, vig_h), vig_col, true)
	_jumpscare_overlay.draw_rect(Rect2(0, sz.y - vig_h, sz.x, vig_h), vig_col, true)
	_jumpscare_overlay.draw_rect(Rect2(0, vig_h, vig_w, sz.y - vig_h * 2.0), vig_col, true)
	_jumpscare_overlay.draw_rect(Rect2(sz.x - vig_w, vig_h, vig_w, sz.y - vig_h * 2.0), vig_col, true)

	var phase := int(floor(norm_t * 26.0))
	for i in range(10):
		var y_frac := fmod(float((i * 37 + phase * 19) % 97) / 97.0, 1.0)
		var bar_y := y_frac * sz.y
		var bar_h := 2.0 + float((i + phase) % 3) * 2.0
		var x_shift := float(((i * 13 + phase * 7) % 21) - 10) * 2.5
		var c_sig := Color(COL_SIGNAL.r, COL_SIGNAL.g, COL_SIGNAL.b, 0.52 * fade)
		var c_cld := Color(COL_COLD.r, COL_COLD.g, COL_COLD.b, 0.34 * fade)
		_jumpscare_overlay.draw_rect(Rect2(maxf(0.0, x_shift), bar_y, sz.x * 0.92, bar_h), c_sig, true)
		_jumpscare_overlay.draw_rect(Rect2(maxf(0.0, -x_shift), bar_y + bar_h, sz.x * 0.88, 1.5), c_cld, true)


func is_tutorial_active() -> bool:
	return _tut_active


func start_tutorial_if_needed(force: bool = false) -> void:
	if not force and SaveState.tutorial_completed:
		_tut_active = false
		_tut_step = 0
		_tut_card.visible = false
		return
	_tut_active = true
	_tut_step = 1
	_refresh_tutorial_card()
	_tut_card.visible = true
	_tween_pop_in(_tut_card, 0.98, 0.90, 0.18)


func advance_tutorial_if_step(step_idx: int) -> void:
	if not _tut_active or _tut_step != step_idx:
		return
	if _tut_step >= 4:
		dismiss_tutorial()
		return
	_tut_step += 1
	_refresh_tutorial_card()
	_tween_pop_in(_tut_card, 0.985, 0.92, 0.14)


func dismiss_tutorial() -> void:
	_tut_active = false
	_tut_step = 0
	if _tut_card != null:
		_tut_card.visible = false
	SaveState.tutorial_completed = true
	SaveState.save_profile()
	refresh_texts()


func _refresh_tutorial_card() -> void:
	if _tut_card == null:
		return
	_tut_header_lbl.text = Loc.t("TUT_HEADER")
	_tut_skip_btn.text = Loc.t("TUT_SKIP")
	var clamped_step := clampi(_tut_step, 1, 4)
	_tut_step_lbl.text = "%d/4" % clamped_step
	var step_key := "TUT_STEP_%d" % clamped_step
	if _is_touch_device:
		var touch_key := step_key + "_TOUCH"
		var touch_txt := Loc.t(touch_key)
		_tut_body_lbl.text = touch_txt if touch_txt != touch_key else Loc.t(step_key)
	else:
		_tut_body_lbl.text = Loc.t(step_key)
	_tut_next_btn.text = Loc.t("TUT_DONE" if clamped_step >= 4 else "TUT_NEXT")


func show_end_screen(victory: bool, elapsed_sec: float) -> void:
	_end_modal.visible = true
	_modal_scrim.visible = true
	if _tut_card != null:
		_tut_card.visible = false
	if player != null:
		player.controls_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if victory:
		var mins := int(elapsed_sec) / 60
		var secs := int(elapsed_sec) % 60
		var t_str := "%02d:%02d" % [mins, secs]
		_end_title_lbl.text = Loc.t("VICTORY_TITLE")
		_end_title_lbl.add_theme_color_override("font_color", COL_PHOSPHOR)
		_set_corner_tick_color(_end_modal, COL_PHOSPHOR)
		_end_sub_lbl.text = Loc.t("VICTORY_STATS") % t_str
	else:
		_end_title_lbl.text = Loc.t("GAMEOVER_TITLE")
		_end_title_lbl.add_theme_color_override("font_color", COL_SIGNAL)
		_set_corner_tick_color(_end_modal, COL_SIGNAL)
		_end_sub_lbl.text = Loc.t("GAMEOVER_SUB")
	_tween_pop_in(_end_modal, 0.96, 0.88, 0.22)


func update_objectives(planks_done: bool, cable_done: bool, power_done: bool, padlock_done: bool) -> void:
	var prev_count := _seals_done_count
	_seals_done_count = int(planks_done) + int(cable_done) + int(power_done) + int(padlock_done)
	_btn_dossier.text = "  %s" % (Loc.t("DOSSIER_BTN") % _seals_done_count)

	if _seals_done_count >= 4:
		_obj_header_lbl.text = Loc.t("OBJ_OPEN_EXIT")
		_obj_header_lbl.add_theme_color_override("font_color", COL_PHOSPHOR)
		_set_corner_tick_color(_dossier_card, COL_PHOSPHOR)
	else:
		_obj_header_lbl.text = Loc.t("OBJ_HEADER") % _seals_done_count
		_obj_header_lbl.add_theme_color_override("font_color", COL_SODIUM)
		_set_corner_tick_color(_dossier_card, COL_SODIUM)

	_set_obj_row("planks", Loc.t("OBJ_PLANKS"), planks_done)
	_set_obj_row("cable", Loc.t("OBJ_CABLE"), cable_done)
	_set_obj_row("power", Loc.t("OBJ_POWER"), power_done)
	_set_obj_row("padlock", Loc.t("OBJ_PADLOCK"), padlock_done)

	if player != null and not player.known_safe_code.is_empty():
		_dossier_code_lbl.text = Loc.t("SAFE_KNOWN_CODE") % player.known_safe_code
		_dossier_code_lbl.add_theme_color_override("font_color", COL_SODIUM)
	else:
		_dossier_code_lbl.text = Loc.t("DOSSIER_HINT_KEY")
		_dossier_code_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)

	if _seals_done_count != prev_count:
		_dossier_peek_timer = 5.0
		_dossier_card.visible = true


func _set_obj_row(key: String, label_txt: String, done: bool) -> void:
	var r: Label = _obj_rows[key]
	r.text = label_txt
	r.add_theme_color_override("font_color", COL_PHOSPHOR if done else COL_PAPER_DIM)
	var b: Control = _obj_boxes.get(key)
	if b != null:
		b.set_meta("done", done)
		b.queue_redraw()


func set_aim_prompt(text: String) -> void:
	if text.is_empty():
		_prompt_box.visible = false
		_reticle_active = false
	else:
		_prompt_lbl.text = text
		_prompt_box.visible = true
		_reticle_active = true


func show_toast(msg: String) -> void:
	_toast_lbl.text = msg
	_toast_plate.visible = not msg.is_empty()
	_toast_timer = 3.6


func show_toast_key(tkey: String) -> void:
	show_toast(Loc.t(tkey))


func refresh_inventory_bar() -> void:
	if player == null:
		return
	for i in range(ListenerPlayer.MAX_SLOTS):
		var item_id := player.inventory[i]
		var active := (i == player.selected_slot)
		var bg := COL_PANEL_HI if active else COL_PANEL
		var brd := COL_SODIUM if active else COL_RULE_STRONG
		var btn := _slot_btns[i]
		btn.add_theme_stylebox_override("normal", _make_box(bg, brd, 2, 4, 4, 1))
		btn.add_theme_stylebox_override("hover", _make_box(COL_PANEL_HI, COL_SODIUM if active else COL_PAPER_DIM, 2, 4, 4, 1))
		btn.add_theme_stylebox_override("pressed", _make_box(COL_PANEL_HI, COL_SODIUM, 2, 4, 4, 1))
		_attach_corner_ticks(btn, COL_SODIUM if active else Color(0, 0, 0, 0), 8.0, 1.0)
		_slot_icons[i].texture = AssetLibrary.get_item_icon(item_id) if not item_id.is_empty() else null
		if i < _slot_nums.size():
			var ncol := COL_SODIUM if active else (COL_PAPER_DIM if not item_id.is_empty() else COL_PAPER_MUTE)
			_slot_nums[i].add_theme_color_override("font_color", ncol)

	var eq := player.get_equipped_item()
	if eq.is_empty():
		_held_item_lbl.text = ""
	elif eq == "code_note":
		var c := player.known_safe_code if not player.known_safe_code.is_empty() else "????"
		_held_item_lbl.text = Loc.t("ITEM_code_note") % c
	else:
		_held_item_lbl.text = Loc.t("ITEM_" + eq)

	if _btn_drop != null:
		_btn_drop.visible = _touch_controls_visible and not eq.is_empty()

	if _dossier_code_lbl != null and not player.known_safe_code.is_empty():
		_dossier_code_lbl.text = Loc.t("SAFE_KNOWN_CODE") % player.known_safe_code
		_dossier_code_lbl.add_theme_color_override("font_color", COL_SODIUM)


func _switch_menu_card(which: String) -> void:
	_active_menu_tab = which
	SynthAudio.play_2d("ui_click", -5.0)
	_card_solo.visible = (which == "solo")
	_card_coop.visible = (which == "coop")
	_card_settings.visible = (which == "settings")
	_card_how.visible = (which == "how")
	_style_nav_switch(_btn_nav_solo, which == "solo")
	_style_nav_switch(_btn_nav_coop, which == "coop")
	_style_nav_switch(_btn_nav_settings, which == "settings")
	_style_nav_switch(_btn_nav_how, which == "how")

	var active_card: PanelContainer = null
	if which == "solo":
		active_card = _card_solo
	elif which == "coop":
		active_card = _card_coop
	elif which == "settings":
		active_card = _card_settings
	elif which == "how":
		active_card = _card_how
	if active_card != null:
		_tween_pop_in(active_card, 0.975, 0.90, 0.19)


func _refresh_diff_buttons() -> void:
	var keys := ["DIFF_PRACTICE", "DIFF_NORMAL", "DIFF_NIGHTMARE"]
	for i in range(3):
		var sel := (i == SaveState.difficulty)
		var btn := _diff_btns[i]
		btn.text = Loc.t(keys[i])
		_style_button(btn, false, sel)
		for st_name in ["normal", "hover", "pressed", "focus"]:
			var sb := btn.get_theme_stylebox(st_name)
			if sb is StyleBoxFlat:
				(sb as StyleBoxFlat).content_margin_left = 36
		btn.add_theme_font_size_override("font_size", 15)
		btn.queue_redraw()


func _refresh_record_readout() -> void:
	if _record_lbl == null:
		return
	var esc := SaveState.total_escapes
	var best := SaveState.best_escape_sec
	if esc > 0:
		if best > 0.0:
			var mins := int(best) / 60
			var secs := int(best) % 60
			var t_str := "%02d:%02d" % [mins, secs]
			_record_lbl.text = ("ПОБЕГОВ: %d · ЛУЧШЕЕ: %s" % [esc, t_str]) if Loc.current_lang == "ru" else ("ESCAPES: %d · BEST: %s" % [esc, t_str])
		else:
			_record_lbl.text = ("ПОБЕГОВ: %d" % esc) if Loc.current_lang == "ru" else ("ESCAPES: %d" % esc)
		_record_lbl.add_theme_color_override("font_color", COL_PHOSPHOR)
		_set_corner_tick_color(_record_plate, COL_PHOSPHOR)
	else:
		_record_lbl.text = "НИИ-07 · ПОБЕГОВ: 0" if Loc.current_lang == "ru" else "NII-07 · ESCAPES: 0"
		_record_lbl.add_theme_color_override("font_color", COL_SODIUM)
		_set_corner_tick_color(_record_plate, Color(COL_SODIUM, 0.65))


func _normalize_relay_url(raw: String) -> String:
	var trimmed := raw.strip_edges()
	var lower := trimmed.to_lower()
	if lower.begins_with("https://"):
		return "wss://" + trimmed.substr(8)
	if lower.begins_with("http://"):
		return "ws://" + trimmed.substr(7)
	return trimmed


func _apply_normalized_relay_url(raw: String, update_field: bool) -> void:
	var norm := _normalize_relay_url(raw)
	if update_field and _relay_input != null and _relay_input.text != norm:
		_relay_input.text = norm
		_relay_input.caret_column = norm.length()
	var low := norm.to_lower()
	if low.begins_with("ws://") or low.begins_with("wss://"):
		SaveState.relay_url = norm
		SaveState.save_profile()


func _on_relay_error(err_code: String, detail: String = "") -> void:
	var low := err_code.to_lower()
	if low.contains("not_found") or low.contains("not found") or low == "missing":
		_coop_error_msg = Loc.t("COOP_ERR_NOT_FOUND")
	elif low.contains("full"):
		_coop_error_msg = Loc.t("COOP_ERR_FULL")
	elif low.contains("unreachable") or low.contains("timeout") or low.contains("connect") or low.contains("closed"):
		_coop_error_msg = Loc.t("COOP_ERR_UNREACHABLE")
	elif not detail.is_empty():
		_coop_error_msg = Loc.t("COOP_ERR_GENERIC") % detail
	else:
		_coop_error_msg = Loc.t("COOP_ERR_GENERIC") % err_code
	_coop_conn_status = "error"
	_refresh_coop_ui()


func _on_relay_connection_status(status: String) -> void:
	var low := status.to_lower()
	if low == "connected" or low == "open":
		_coop_error_msg = ""
		_coop_conn_status = "connected"
	elif low == "connecting":
		_coop_error_msg = ""
		_coop_conn_status = "connecting"
	elif low == "error" or low == "failed" or low == "unreachable":
		_coop_conn_status = "error"
		if _coop_error_msg.is_empty():
			_coop_error_msg = Loc.t("COOP_ERR_UNREACHABLE")
	else:
		_coop_conn_status = ""
	_refresh_coop_ui()


func _refresh_coop_ui() -> void:
	if _coop_status_lbl == null:
		return
	if not NetRelay.room_code.is_empty():
		var role := Loc.t("ROLE_HOST") if NetRelay.is_host else Loc.t("ROLE_CLIENT")
		_coop_status_lbl.text = Loc.t("COOP_ROOM_STATUS_ACTIVE") % [NetRelay.room_code, NetRelay.get_squad_size(), role]
		_coop_status_lbl.add_theme_color_override("font_color", COL_PHOSPHOR)
		_btn_launch_coop.disabled = not NetRelay.is_host
		_btn_launch_coop.text = Loc.t("COOP_START_MATCH") if NetRelay.is_host else Loc.t("COOP_WAITING_HOST")
	elif not _coop_error_msg.is_empty():
		_coop_status_lbl.text = _coop_error_msg
		_coop_status_lbl.add_theme_color_override("font_color", COL_SIGNAL)
		_btn_launch_coop.disabled = true
		_btn_launch_coop.text = Loc.t("COOP_START_MATCH")
	elif _coop_conn_status == "connecting":
		_coop_status_lbl.text = Loc.t("COOP_STATUS_CONNECTING")
		_coop_status_lbl.add_theme_color_override("font_color", COL_SODIUM)
		_btn_launch_coop.disabled = true
		_btn_launch_coop.text = Loc.t("COOP_START_MATCH")
	elif _coop_conn_status == "connected" or NetRelay.connected_to_relay:
		_coop_status_lbl.text = Loc.t("COOP_STATUS_CONNECTED")
		_coop_status_lbl.add_theme_color_override("font_color", COL_PHOSPHOR)
		_btn_launch_coop.disabled = true
		_btn_launch_coop.text = Loc.t("COOP_START_MATCH")
	else:
		_coop_status_lbl.text = Loc.t("COOP_ROOM_STATUS_NONE")
		_coop_status_lbl.add_theme_color_override("font_color", COL_PAPER_DIM)
		_btn_launch_coop.disabled = true
		_btn_launch_coop.text = Loc.t("COOP_START_MATCH")


func _on_open_lobbies(lobbies: Array) -> void:
	_coop_error_msg = ""
	if NetRelay.connected_to_relay:
		_coop_conn_status = "connected"
	for ch in _public_rooms_box.get_children():
		ch.queue_free()
	for entry in lobbies:
		if typeof(entry) == TYPE_DICTIONARY:
			var code := str(entry.get("code", ""))
			var cnt := int(entry.get("count", 1))
			var host_n := str(entry.get("host", "HOST"))
			var rb := Button.new()
			rb.text = "%s  ·  %s (%d/4)" % [code, host_n, cnt]
			_style_button(rb, false, false)
			rb.add_theme_font_override("font", _font_mono)
			rb.add_theme_font_size_override("font_size", 15)
			rb.pressed.connect(func(): NetRelay.join_room(code))
			_public_rooms_box.add_child(rb)
	_refresh_coop_ui()


func refresh_texts() -> void:
	_menu_title_lbl.text = Loc.t("GAME_TITLE")
	_menu_sub_lbl.text = Loc.t("GAME_SUBTITLE")
	_refresh_record_readout()

	_btn_nav_solo.text = Loc.t("MENU_PLAY_SOLO")
	_btn_nav_coop.text = Loc.t("MENU_PLAY_COOP")
	_btn_nav_settings.text = Loc.t("MENU_SETTINGS")
	_btn_nav_how.text = Loc.t("MENU_HOW_TO_PLAY")

	_diff_title_lbl.text = Loc.t("DIFF_TITLE")
	_btn_begin_solo.text = Loc.t("START_GAME_BTN")
	_refresh_diff_buttons()

	_coop_title_lbl.text = Loc.t("COOP_TITLE")
	_lbl_callsign.text = Loc.t("COOP_NAME_LABEL")
	_lbl_relay.text = Loc.t("COOP_SERVER_LABEL")
	_relay_hint_lbl.text = Loc.t("COOP_RELAY_HINT")
	_btn_create_room.text = Loc.t("COOP_CREATE_BTN")
	_btn_copy_code.text = Loc.t("COOP_COPY_CODE")
	_btn_join_code.text = Loc.t("COOP_JOIN_BTN")
	_btn_refresh_public.text = Loc.t("COOP_REFRESH_PUBLIC")
	_refresh_coop_ui()

	_set_title_lbl.text = Loc.t("SETTINGS_TITLE")
	_lbl_sens.text = Loc.t("SET_SENS")
	_val_sens_lbl.text = "%.2fx" % SaveState.look_sensitivity
	_lbl_vol.text = Loc.t("SET_VOL")
	_val_vol_lbl.text = "%d%%" % int(round(SaveState.master_volume * 100.0))
	var mic_keys := ["MIC_AUTO", "MIC_PTT", "MIC_OFF"]
	_btn_mic_mode.text = "%s: %s" % [Loc.t("SET_MIC"), Loc.t(mic_keys[SaveState.mic_mode])]
	_btn_mic_mode.add_theme_font_size_override("font_size", 16)

	var gyro_on := SaveState.gyro_enabled
	_btn_gyro.text = "%s: %s" % [Loc.t("SET_GYRO"), Loc.t("ON" if gyro_on else "OFF")]
	_style_button(_btn_gyro, false, gyro_on)
	_btn_gyro.add_theme_font_size_override("font_size", 15)

	var hap_on := SaveState.haptics_enabled
	_btn_haptics.text = "%s: %s" % [_tr_or("SET_HAPTICS", "Вибрация", "Haptics"), Loc.t("ON" if hap_on else "OFF")]
	_style_button(_btn_haptics, false, hap_on)
	_btn_haptics.add_theme_font_size_override("font_size", 15)

	var rm_on := _get_reduce_motion()
	_btn_reduce_motion.text = "%s: %s" % [_tr_or("SET_REDUCE_MOTION", "Меньше движения", "Reduce motion"), Loc.t("ON" if rm_on else "OFF")]
	_style_button(_btn_reduce_motion, false, rm_on)
	_btn_reduce_motion.add_theme_font_size_override("font_size", 15)

	_btn_lang.text = Loc.t("SET_LANG")
	_btn_lang.add_theme_font_size_override("font_size", 15)

	if _btn_replay_tutorial != null:
		var tut_armed := not SaveState.tutorial_completed
		var tut_lbl := Loc.t("SET_REPLAY_TUTORIAL")
		_btn_replay_tutorial.text = ("%s: %s" % [tut_lbl, Loc.t("ON")]) if tut_armed else tut_lbl
		_style_button(_btn_replay_tutorial, false, tut_armed)
		_btn_replay_tutorial.add_theme_font_size_override("font_size", 15)

	_refresh_tutorial_card()

	_how_title_lbl.text = Loc.t("HOW_TITLE")
	_how_body_lbl.text = Loc.t("HOW_BODY")
	var key_copy := {
		"KEY_MOVE": _tr_or("KEY_MOVE", "Движение", "Move"),
		"KEY_SPRINT": _tr_or("KEY_SPRINT", "Бег", "Sprint"),
		"KEY_INTERACT": _tr_or("KEY_INTERACT", "Действие", "Interact"),
		"KEY_LIGHT": _tr_or("KEY_LIGHT", "Фонарь", "Flashlight"),
		"KEY_CELL": _tr_or("KEY_CELL", "Смена батареи", "Swap battery"),
		"KEY_CROUCH": _tr_or("KEY_CROUCH", "Присед", "Crouch"),
		"KEY_BREATH": _tr_or("KEY_BREATH", "Задержать дыхание", "Hold breath"),
		"KEY_THROW": _tr_or("KEY_THROW", "Бросить", "Throw / drop"),
		"KEY_USE": _tr_or("KEY_USE", "Применить", "Use item"),
		"KEY_DOSSIER": _tr_or("KEY_DOSSIER", "Досье", "Dossier"),
	}
	for row_d in _manual_key_rows:
		var lbl: Label = row_d["lbl"]
		lbl.text = str(key_copy.get(row_d["id"], ""))

	_safe_title_lbl.text = Loc.t("SAFE_MODAL_TITLE")
	_pause_title_lbl.text = Loc.t("PAUSE_TITLE")
	_btn_resume.text = Loc.t("PAUSE_RESUME")
	_btn_restart.text = Loc.t("PAUSE_RESTART")
	_btn_to_menu.text = Loc.t("PAUSE_MAIN_MENU")
	_btn_play_again.text = Loc.t("PAUSE_RESTART")
	_btn_end_menu.text = Loc.t("PAUSE_MAIN_MENU")
	_btn_dossier.text = "  %s" % (Loc.t("DOSSIER_BTN") % _seals_done_count)
	_update_sector_label()
	refresh_inventory_bar()


func update_runtime_hud(
	delta: float,
	_difficulty: int,
	stalker_state: String,
	stalker_dist: float,
	downed_ally_name: String = ""
) -> void:
	if not _hud_root.visible:
		return

	var reduce_motion := _get_reduce_motion()

	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_lbl.text = ""
			_toast_plate.visible = false

	if _dossier_peek_timer > 0.0 and not _dossier_pinned:
		_dossier_peek_timer -= delta
		if _dossier_peek_timer <= 0.0:
			_dossier_card.visible = false

	if minimap != null:
		minimap.tick_minimap(delta)

	var in_chase := (stalker_state == MonsterDirector.STATE_CHASE)
	if in_chase:
		_chase_intensity = move_toward(_chase_intensity, 1.0, delta * 2.5)
		var target_prox := clampf(1.0 - (stalker_dist / 16.0), 0.0, 1.0)
		_chase_prox = target_prox if reduce_motion else move_toward(_chase_prox, target_prox, delta * 3.2)
	else:
		_chase_intensity = move_toward(_chase_intensity, 0.0, delta * 1.0)
		_chase_prox = move_toward(_chase_prox, 0.0, delta * 1.0)

	if _chase_intensity > 0.005:
		_chase_panic_overlay.visible = true
		if reduce_motion:
			_chase_vignette.modulate = Color(1.0, 1.0, 1.0, _chase_intensity * lerpf(0.55, 0.88, _chase_prox))
		else:
			_chase_pulse_t += delta
			var vig_pulse := 0.90 + 0.10 * sin(_chase_pulse_t * 8.5)
			var vig_a := _chase_intensity * lerpf(0.56, 0.94, _chase_prox) * vig_pulse
			_chase_vignette.modulate = Color(1.0, 1.0, 1.0, clampf(vig_a, 0.0, 0.96))
		_chase_interference.update_state(_chase_intensity, _chase_prox, _chase_pulse_t, reduce_motion)
	else:
		_chase_panic_overlay.visible = false
		_chase_vignette.modulate.a = 0.0
		_chase_interference.visible = false

	var chase_flare := _chase_intensity * (1.0 if reduce_motion else (0.76 + 0.24 * absf(sin(_chase_pulse_t * 7.5))))
	if _acoustic_scope != null:
		_acoustic_scope.chase_flare = chase_flare
		_acoustic_scope.tick(delta, player != null and player.is_holding_breath)

	if player != null:
		var nl_bar := AcousticBus.current_noise_level
		var bar_tick_col := COL_COLD if player.is_holding_breath else (
			COL_SIGNAL if nl_bar >= 0.45 else (
				COL_SODIUM if nl_bar >= 0.18 else COL_RULE_STRONG
			)
		)
		_top_bar_style.border_color = COL_RULE_STRONG.lerp(COL_SIGNAL, chase_flare)
		_top_bar_style.bg_color = COL_PANEL.lerp(Color(0.24, 0.05, 0.04, 0.95), chase_flare * 0.45)
		_top_bar_style.set_border_width_all(2 if chase_flare > 0.22 else 1)
		_set_corner_tick_color(_top_status_bar, bar_tick_col.lerp(COL_SIGNAL, chase_flare))

		_breath_bar.visible = (player.is_holding_breath or player.breath_stamina < 0.99)
		_breath_bar.value = player.breath_stamina * 100.0

		# Diegetic blood-edge vignette when wounded or downed
		var is_injured := (player.wounds > 0 or player.is_downed)
		if is_injured:
			_blood_vignette.visible = true
			_blood_vig_alpha = move_toward(_blood_vig_alpha, 1.0, delta * 2.5)
			if reduce_motion:
				_blood_vignette.modulate.a = _blood_vig_alpha * (0.72 if player.is_downed else 0.55)
			else:
				_blood_pulse_t += delta * (4.6 if player.is_downed else 2.8)
				var hb := pow(maxf(0.0, sin(_blood_pulse_t)), 4.0) * 0.24
				var base_a := 0.68 if player.is_downed else 0.58
				_blood_vignette.modulate.a = _blood_vig_alpha * clampf(base_a + hb, 0.44, 0.92)
		else:
			_blood_vig_alpha = move_toward(_blood_vig_alpha, 0.0, delta * 3.0)
			if _blood_vig_alpha <= 0.005:
				_blood_vignette.modulate.a = 0.0
				_blood_vignette.visible = false
			else:
				_blood_vignette.modulate.a = _blood_vig_alpha * 0.55

		# Update touch action button visual states & drop visibility
		if _touch_controls_visible:
			var low_bat := (player.battery_charge <= 0.28)
			var flash_col := COL_SIGNAL if low_bat else COL_SODIUM
			var flash_idle_brd := Color(COL_SIGNAL, 0.80) if low_bat else COL_RULE_STRONG
			_apply_touch_btn_highlight(_btn_flashlight, player.flashlight_on, flash_col, flash_idle_brd)
			_apply_touch_btn_highlight(_btn_crouch, player.is_crouching, COL_SODIUM)
			_apply_touch_btn_highlight(_btn_breath, player.is_holding_breath, COL_COLD)
			if _btn_drop != null:
				_btn_drop.visible = not player.get_equipped_item().is_empty()

		# Precision Reticle Update
		var crouch_or_hide := player.is_crouching or player.is_under_desk or player.is_hiding_in_locker or player.is_holding_breath
		var sprinting := Vector2(player.velocity.x, player.velocity.z).length() > 4.2 and not crouch_or_hide
		_reticle_target_gap = 3.5 if crouch_or_hide else (9.0 if sprinting else 5.5)
		if _reticle_active:
			_reticle_target_gap = maxf(3.0, _reticle_target_gap - 1.5)
		_reticle_gap = _reticle_target_gap if reduce_motion else lerpf(_reticle_gap, _reticle_target_gap, clampf(delta * 14.0, 0.0, 1.0))
		_reticle_dot.color = COL_SODIUM if _reticle_active else Color(COL_PAPER, 0.72)
		_reticle_canvas.queue_redraw()

		# Diegetic top-center status whisper plate
		var status_txt := ""
		var status_col := COL_PAPER
		var border_col := COL_RULE_STRONG
		var urgent := false
		if player.is_downed:
			status_txt = Loc.t("STATUS_DOWNED") % int(ceil(player.downed_timer))
			status_col = COL_SIGNAL
			border_col = COL_SIGNAL
			urgent = true
		elif stalker_state == MonsterDirector.STATE_INSPECT_LOCKER and player.is_hiding_in_locker:
			status_txt = Loc.t("STATUS_SNIFFING")
			status_col = COL_SIGNAL
			border_col = COL_SIGNAL
			urgent = true
		elif stalker_state == MonsterDirector.STATE_CHASE:
			status_txt = Loc.t("STATUS_CHASE")
			status_col = COL_SIGNAL
			border_col = COL_SIGNAL
			urgent = true
		elif stalker_state == MonsterDirector.STATE_ECHOLOCATE and stalker_dist < 22.0:
			status_txt = Loc.t("STATUS_ECHOLOCATE")
			status_col = COL_SODIUM
			border_col = COL_SODIUM
		elif stalker_state == MonsterDirector.STATE_STUNNED and stalker_dist < 18.0:
			status_txt = Loc.t("STATUS_STUNNED")
			status_col = COL_PHOSPHOR
			border_col = COL_PHOSPHOR
		elif player.is_hiding_in_locker:
			status_txt = Loc.t("STATUS_HIDING")
			status_col = COL_COLD
			border_col = Color(COL_COLD, 0.65)
		elif not downed_ally_name.is_empty():
			status_txt = Loc.t("STATUS_ALLY_DOWN") % downed_ally_name
			status_col = COL_SIGNAL
			border_col = COL_SIGNAL
			urgent = true
		elif stalker_state == MonsterDirector.STATE_INVESTIGATE and stalker_dist < 15.0:
			status_txt = Loc.t("STATUS_ALERT")
			status_col = COL_SODIUM
			border_col = COL_SODIUM

		_status_pill.visible = not status_txt.is_empty()
		if not status_txt.is_empty():
			_stalker_alert_lbl.text = status_txt
			_stalker_alert_lbl.add_theme_color_override("font_color", status_col)
			_status_is_urgent = urgent
			if urgent and not reduce_motion:
				_status_pulse_t += delta * (8.0 if in_chase else 6.0)
				var pulse_a := (0.72 + 0.28 * absf(sin(_status_pulse_t))) if in_chase else (0.55 + 0.40 * absf(sin(_status_pulse_t)))
				border_col = Color(border_col, pulse_a)
			var pill_bg := COL_PANEL.lerp(Color(0.28, 0.05, 0.04, 0.96), 0.45 * chase_flare) if in_chase else COL_PANEL
			_status_pill_style.bg_color = pill_bg
			_status_pill_style.border_color = border_col
			_status_pill_style.set_border_width_all(2 if in_chase else 1)
			_status_accent = border_col
			_set_corner_tick_color(_status_pill, COL_SIGNAL if in_chase else border_col)

	var threat := clampf(1.0 - (stalker_dist / 12.0), 0.0, 1.0)
	if stalker_state == MonsterDirector.STATE_CHASE:
		threat = maxf(threat, 0.72)
	if player != null and player.wounds > 0:
		threat = maxf(threat, 0.18)
	if reduce_motion:
		_danger_overlay.color.a = threat * 0.14
	else:
		_danger_pulse += delta * (7.0 if stalker_state == MonsterDirector.STATE_CHASE else 3.2)
		_danger_overlay.color.a = threat * (0.12 + 0.08 * sin(_danger_pulse))


func _keycode_to_digit(kc: Key) -> String:
	if kc >= KEY_0 and kc <= KEY_9:
		return str(int(kc) - int(KEY_0))
	if kc >= KEY_KP_0 and kc <= KEY_KP_9:
		return str(int(kc) - int(KEY_KP_0))
	return ""


func _is_point_in_hud_buttons(pt: Vector2) -> bool:
	for b in [_btn_pause, _btn_dossier, _tut_skip_btn, _tut_next_btn, _btn_breath, _btn_flashlight, _btn_crouch, _btn_drop]:
		if b != null and b.visible and b.get_global_rect().has_point(pt):
			return true
	for sb in _slot_btns:
		if sb != null and sb.visible and sb.get_global_rect().has_point(pt):
			return true
	return false


func _input(event: InputEvent) -> void:
	if _safe_modal.visible and event is InputEventKey:
		var sk := event as InputEventKey
		if sk.pressed and not sk.echo:
			if sk.keycode == KEY_ESCAPE:
				close_safe_modal()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			elif sk.keycode == KEY_BACKSPACE:
				if not _safe_entered.is_empty():
					_safe_entered = _safe_entered.left(_safe_entered.length() - 1)
					SynthAudio.play_2d("keypad_beep", -6.0, 0.85)
					_update_safe_display()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			elif sk.keycode == KEY_DELETE:
				_on_safe_key_pressed("CLR")
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			elif sk.keycode == KEY_ENTER or sk.keycode == KEY_KP_ENTER:
				if _safe_entered.length() == 4:
					var code := _safe_entered
					_safe_entered = ""
					safe_code_submitted.emit(code)
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			else:
				var digit := _keycode_to_digit(sk.keycode)
				if not digit.is_empty():
					_on_safe_key_pressed(digit)
					if get_viewport() != null:
						get_viewport().set_input_as_handled()
					return

	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			if _safe_modal.visible:
				close_safe_modal()
			elif _hud_root.visible and not _end_modal.visible:
				toggle_pause_modal(not _pause_modal.visible)
		elif k.pressed and not k.echo and k.keycode == KEY_K:
			if _hud_root.visible and _tut_active and not _safe_modal.visible and not _pause_modal.visible and not _end_modal.visible:
				SynthAudio.play_2d("ui_click", -6.0)
				dismiss_tutorial()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
				return

	if not _hud_root.visible or _safe_modal.visible or _pause_modal.visible or _end_modal.visible:
		return

	var vp_rect := get_viewport().get_visible_rect()
	var vp_w := vp_rect.size.x
	var vp_h := vp_rect.size.y
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _prompt_box != null and _prompt_box.visible and _prompt_box.get_global_rect().has_point(st.position):
				_spawn_tap_ripple(st.position)
				if player != null:
					player.trigger_interact()
				return
			if _is_point_in_hud_buttons(st.position):
				return
			if st.position.x < vp_w * 0.44 and st.position.y > 88.0 and _joy_touch_idx == -1:
				_joy_touch_idx = st.index
				var half_j := _joy_base.size * 0.5
				var clamped_c := Vector2(
					clampf(st.position.x, half_j.x + 12.0, vp_w * 0.44 - half_j.x),
					clampf(st.position.y, half_j.y + 84.0, vp_h - half_j.y - 12.0)
				)
				_joy_center = clamped_c
				_joy_base.global_position = _joy_center - half_j
				_joy_base.queue_redraw()
				_update_joystick(st.position)
			elif st.position.x >= vp_w * 0.44 and _look_touch_idx == -1:
				_look_touch_idx = st.index
				_look_touch_start_pos = st.position
				_look_touch_start_time = Time.get_ticks_msec() * 0.001
				_look_touch_moved = 0.0
		else:
			if st.index == _joy_touch_idx:
				_joy_touch_idx = -1
				_joy_sprinting = false
				_anchor_box(_joy_base, 0.0, 1.0, 0.0, 1.0, 32.0, -200.0, 200.0, -32.0)
				_joy_knob.position = JOY_REST_POS
				_joy_base.queue_redraw()
				if player != null:
					player.touch_move_vec = Vector2.ZERO
					player.touch_sprinting = false
			elif st.index == _look_touch_idx:
				var now := Time.get_ticks_msec() * 0.001
				var dur := now - _look_touch_start_time
				if dur < 0.24 and _look_touch_moved < 18.0:
					if (now - _last_tap_time) <= 0.35 and st.position.distance_to(_last_tap_pos) <= 64.0:
						_last_tap_time = -10.0
						_spawn_tap_ripple(st.position)
						if player != null:
							player.trigger_interact()
					else:
						_last_tap_time = now
						_last_tap_pos = st.position
				_look_touch_idx = -1
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joy_touch_idx:
			_update_joystick(sd.position)
		elif sd.index == _look_touch_idx:
			_look_touch_moved += sd.relative.length()
			if player != null:
				player.apply_look_delta(sd.relative * 1.45)


func _update_joystick(touch_pos: Vector2) -> void:
	var diff := touch_pos - _joy_center
	var ratio := diff.length() / JOY_MAX_R
	_joy_sprinting = (ratio >= JOY_SPRINT_RATIO)
	if diff.length() > JOY_MAX_R:
		diff = diff.normalized() * JOY_MAX_R
	_joy_knob.position = JOY_REST_POS + diff
	_joy_base.queue_redraw()
	if player != null:
		player.touch_move_vec = diff / JOY_MAX_R
		player.touch_sprinting = _joy_sprinting
