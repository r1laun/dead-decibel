class_name LoSMinimapControl
extends Control

const SCOPE_CENTER := Vector2(102.0, 99.0)
const SCOPE_RADIUS := 77.0
const WORLD_RANGE := 17.0
const RAY_COUNT := 108

# НИИ-07 Design System Tokens
const COL_INK := Color(0.039, 0.047, 0.043, 0.96)
const COL_PANEL := Color(0.067, 0.082, 0.075, 0.92)
const COL_RULE := Color(0.851, 0.824, 0.757, 0.14)
const COL_PAPER := Color(0.867, 0.839, 0.769, 1.0)
const COL_PAPER_DIM := Color(0.612, 0.592, 0.541, 1.0)
const COL_SODIUM := Color(0.890, 0.635, 0.231, 1.0)
const COL_SIGNAL := Color(0.800, 0.227, 0.180, 1.0)
const COL_PHOSPHOR := Color(0.557, 0.863, 0.620, 1.0)
const COL_COLD := Color(0.498, 0.722, 0.784, 1.0)

var player: ListenerPlayer = null
var monster_director: MonsterDirector = null
var remote_players: Dictionary = {}
var wall_segments: Array[Dictionary] = []
var doors_ref: Array[Dictionary] = []
var vents_ref: Dictionary = {}

var _open_doors_lookup: Dictionary = {}
var _open_vents_lookup: Dictionary = {}
var _wave_history: PackedFloat32Array = PackedFloat32Array()
var _wave_accum: float = 0.0
var _pulse_time: float = 0.0
var _sweep_angle: float = -PI * 0.5
var _echo_ping_dir: Vector2 = Vector2.ZERO
var _echo_ping_alpha: float = 0.0
var _mono_font: Font = null
var _mono_bold: Font = null


func _ready() -> void:
	custom_minimum_size = Vector2(204, 246)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_history.resize(48)
	_wave_history.fill(0.0)

	if ResourceLoader.exists("res://assets/fonts/IBMPlexMono-Regular.ttf"):
		_mono_font = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	if ResourceLoader.exists("res://assets/fonts/IBMPlexMono-SemiBold.ttf"):
		_mono_bold = load("res://assets/fonts/IBMPlexMono-SemiBold.ttf") as Font
	if _mono_font == null:
		_mono_font = ThemeDB.fallback_font
	if _mono_bold == null:
		_mono_bold = _mono_font


func configure_map(
	p_player: ListenerPlayer,
	p_monster: MonsterDirector,
	p_remotes: Dictionary,
	p_wall_segs: Array[Dictionary],
	p_doors: Array[Dictionary],
	p_vents: Dictionary
) -> void:
	player = p_player
	monster_director = p_monster
	remote_players = p_remotes
	wall_segments = p_wall_segs
	doors_ref = p_doors
	vents_ref = p_vents
	if monster_director != null and not monster_director.echolocation_pulsed.is_connected(_on_echolocation_pulsed):
		monster_director.echolocation_pulsed.connect(_on_echolocation_pulsed)


func _on_echolocation_pulsed(origin: Vector3) -> void:
	if player == null:
		return
	var diff := Vector2(origin.x - player.global_position.x, origin.z - player.global_position.z)
	if diff.length() > 0.1 and diff.length() < 34.0:
		_echo_ping_dir = diff.normalized()
		_echo_ping_alpha = 1.0


func tick_minimap(delta: float) -> void:
	_pulse_time += delta
	_sweep_angle = fmod(_sweep_angle + delta * 1.45, TAU)
	_echo_ping_alpha = move_toward(_echo_ping_alpha, 0.0, delta * 0.65)

	_wave_accum += delta
	if _wave_accum >= 0.04:
		_wave_accum = 0.0
		var nl := AcousticBus.current_noise_level
		for i in range(_wave_history.size() - 1):
			_wave_history[i] = _wave_history[i + 1]
		var jitter := sin(_pulse_time * 37.0) * cos(_pulse_time * 19.0)
		var sample := jitter * (0.03 + nl * 0.92)
		if player != null and player.is_holding_breath:
			sample *= 0.22
		_wave_history[_wave_history.size() - 1] = clampf(sample, -1.0, 1.0)

	_open_doors_lookup.clear()
	for d in doors_ref:
		if bool(d.get("is_open", false)):
			_open_doors_lookup[str(d["id"])] = true

	_open_vents_lookup.clear()
	for vid in vents_ref.keys():
		if bool(vents_ref[vid].get("is_open", false)):
			_open_vents_lookup[str(vid)] = true

	queue_redraw()


func _world_to_scope(world_xz: Vector2, p_xz: Vector2, cos_y: float, sin_y: float, px_per_m: float) -> Vector2:
	var dx := world_xz.x - p_xz.x
	var dz := world_xz.y - p_xz.y
	var rel_right := dx * cos_y - dz * sin_y
	var rel_fwd := -dx * sin_y - dz * cos_y
	return SCOPE_CENTER + Vector2(rel_right * px_per_m, -rel_fwd * px_per_m)


static func _ray_segment_hit(ro: Vector2, rd: Vector2, max_t: float, a: Vector2, b: Vector2) -> float:
	var v1 := ro - a
	var v2 := b - a
	var v3 := Vector2(-rd.y, rd.x)
	var denom := v2.dot(v3)
	if absf(denom) < 0.00001:
		return -1.0
	var t1 := (v2.x * v1.y - v2.y * v1.x) / denom
	var t2 := v1.dot(v3) / denom
	if t1 >= 0.0 and t1 <= max_t and t2 >= 0.0 and t2 <= 1.0:
		return t1
	return -1.0


func _is_segment_blocking(seg: Dictionary) -> bool:
	var kind := str(seg.get("kind", "wall"))
	if kind == "wall":
		return true
	if kind == "door":
		return not _open_doors_lookup.has(str(seg.get("id", "")))
	if kind == "vent":
		return not _open_vents_lookup.has(str(seg.get("id", "")))
	return true


func _draw_corner_ticks(rect: Rect2, col: Color, tick_len: float = 8.0) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	var w := 1.5
	draw_line(Vector2(x0, y0 + tick_len), Vector2(x0, y0), col, w)
	draw_line(Vector2(x0, y0), Vector2(x0 + tick_len, y0), col, w)
	draw_line(Vector2(x1 - tick_len, y0), Vector2(x1, y0), col, w)
	draw_line(Vector2(x1, y0), Vector2(x1, y0 + tick_len), col, w)
	draw_line(Vector2(x0, y1 - tick_len), Vector2(x0, y1), col, w)
	draw_line(Vector2(x0, y1), Vector2(x0 + tick_len, y1), col, w)
	draw_line(Vector2(x1 - tick_len, y1), Vector2(x1, y1), col, w)
	draw_line(Vector2(x1, y1 - tick_len), Vector2(x1, y1), col, w)


func _draw() -> void:
	var reduce_motion := bool(SaveState.get("reduce_motion"))
	var in_chase := (monster_director != null and monster_director.active and monster_director.state == MonsterDirector.STATE_CHASE)
	var bezel_accent := COL_SIGNAL if in_chase else (COL_SODIUM if _echo_ping_alpha > 0.1 else Color(COL_PHOSPHOR, 0.45))

	# 1. Outer Instrument Housing & Corner Registration Ticks
	var scope_box := Rect2(Vector2(4, 2), Vector2(196, 188))
	_draw_corner_ticks(scope_box, Color(bezel_accent, 0.65), 9.0)

	# CRT Glass & Recessed Bezel
	draw_circle(SCOPE_CENTER, SCOPE_RADIUS + 4.5, COL_PANEL)
	draw_circle(SCOPE_CENTER, SCOPE_RADIUS, COL_INK)
	draw_circle(SCOPE_CENTER, SCOPE_RADIUS * 0.72, Color(COL_PHOSPHOR, 0.025))
	draw_circle(SCOPE_CENTER, SCOPE_RADIUS * 0.36, Color(COL_PHOSPHOR, 0.035))

	# Subtle CRT Horizontal Scanlines clipped to scope circle
	var scan_y := -SCOPE_RADIUS + 4.0
	while scan_y < SCOPE_RADIUS - 2.0:
		var chord := sqrt(maxf(0.0, (SCOPE_RADIUS - 1.5) * (SCOPE_RADIUS - 1.5) - scan_y * scan_y))
		draw_line(
			SCOPE_CENTER + Vector2(-chord, scan_y),
			SCOPE_CENTER + Vector2(chord, scan_y),
			Color(COL_PHOSPHOR, 0.03),
			1.0
		)
		scan_y += 4.0

	# 5m, 10m, 15m Concentric Range Rings
	var px_per_m: float = SCOPE_RADIUS / WORLD_RANGE
	for meters: float in [5.0, 10.0, 15.0]:
		var rr: float = meters * px_per_m
		draw_arc(SCOPE_CENTER, rr, 0.0, TAU, 56, Color(COL_PHOSPHOR, 0.14), 1.0, true)
		if _mono_font != null:
			var label_m := "%d" % int(meters)
			draw_string(_mono_font, SCOPE_CENTER + Vector2(3.0, -rr + 9.0), label_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(COL_PHOSPHOR, 0.42))

	# Outer Degree Ticks (every 15 deg, major every 45 deg)
	for deg_idx in range(24):
		var a := float(deg_idx) * TAU / 24.0
		var dir := Vector2(cos(a), sin(a))
		var major := (deg_idx % 3 == 0)
		var r_in := SCOPE_RADIUS - (4.5 if major else 2.5)
		var t_col := Color(COL_PHOSPHOR, 0.32 if major else 0.16)
		draw_line(SCOPE_CENTER + dir * r_in, SCOPE_CENTER + dir * SCOPE_RADIUS, t_col, 1.2 if major else 1.0)

	# Outer Rim Hairline
	draw_arc(SCOPE_CENTER, SCOPE_RADIUS, 0.0, TAU, 72, Color(COL_PHOSPHOR, 0.34), 1.5, true)
	draw_arc(SCOPE_CENTER, SCOPE_RADIUS + 4.5, 0.0, TAU, 72, COL_RULE, 1.0, true)

	# Crosshair Hairlines with Open Center Gap
	draw_line(SCOPE_CENTER + Vector2(-SCOPE_RADIUS + 6.0, 0), SCOPE_CENTER + Vector2(-8.0, 0), Color(COL_PHOSPHOR, 0.10), 1.0)
	draw_line(SCOPE_CENTER + Vector2(8.0, 0), SCOPE_CENTER + Vector2(SCOPE_RADIUS - 6.0, 0), Color(COL_PHOSPHOR, 0.10), 1.0)
	draw_line(SCOPE_CENTER + Vector2(0, -SCOPE_RADIUS + 6.0), SCOPE_CENTER + Vector2(0, -8.0), Color(COL_PHOSPHOR, 0.10), 1.0)
	draw_line(SCOPE_CENTER + Vector2(0, 8.0), SCOPE_CENTER + Vector2(0, SCOPE_RADIUS - 6.0), Color(COL_PHOSPHOR, 0.10), 1.0)

	# 2. Rotating Phosphor Sweep Trail (disabled if reduce_motion)
	if not reduce_motion:
		var trail_slices := 10
		var trail_arc := 0.52
		for s_i in range(trail_slices):
			var f0 := float(s_i) / float(trail_slices)
			var f1 := float(s_i + 1) / float(trail_slices)
			var a0 := _sweep_angle - trail_arc * (1.0 - f0)
			var a1 := _sweep_angle - trail_arc * (1.0 - f1)
			var tri := PackedVector2Array([
				SCOPE_CENTER,
				SCOPE_CENTER + Vector2(cos(a0), sin(a0)) * (SCOPE_RADIUS - 1.5),
				SCOPE_CENTER + Vector2(cos(a1), sin(a1)) * (SCOPE_RADIUS - 1.5)
			])
			draw_colored_polygon(tri, Color(COL_PHOSPHOR, 0.095 * f1 * f1))
		var sweep_end := SCOPE_CENTER + Vector2(cos(_sweep_angle), sin(_sweep_angle)) * (SCOPE_RADIUS - 1.5)
		draw_line(SCOPE_CENTER, sweep_end, Color(COL_PHOSPHOR, 0.48), 1.4, true)

	# 3. Real-Time Line-of-Sight Raycast & Contacts
	if player != null and not wall_segments.is_empty():
		var p_xz := Vector2(player.global_position.x, player.global_position.z)
		var yaw := player.rotation.y
		var cos_y := cos(yaw)
		var sin_y := sin(yaw)
		var fwd_xz := Vector2(-sin_y, -cos_y)

		var active_segs: Array[Dictionary] = []
		var r_sq := (WORLD_RANGE + 6.0) * (WORLD_RANGE + 6.0)
		for idx in range(wall_segments.size()):
			var seg: Dictionary = wall_segments[idx]
			if not _is_segment_blocking(seg):
				continue
			var sa: Vector2 = seg["a"]
			var sb: Vector2 = seg["b"]
			var closest := Geometry2D.get_closest_point_to_segment(p_xz, sa, sb)
			if p_xz.distance_squared_to(closest) <= r_sq:
				active_segs.append({
					"idx": idx,
					"a": sa,
					"b": sb,
					"kind": seg.get("kind", "wall")
				})

		var fan_pts := PackedVector2Array()
		fan_pts.append(SCOPE_CENTER)
		var hit_pts: Array[Vector2] = []
		var hit_blocked: Array[bool] = []
		var hit_seg_ids: Array[int] = []
		var hit_kinds: Array[String] = []

		var cone_max := (WORLD_RANGE - 0.5) if player.flashlight_on else 8.8
		var periph_max := 3.4 if not player.is_hiding_in_locker else 1.8

		for i in range(RAY_COUNT):
			var ang := float(i) * TAU / float(RAY_COUNT)
			var rd := Vector2(cos(ang), sin(ang))
			var align := rd.dot(fwd_xz)
			var ray_reach := periph_max
			if player.is_hiding_in_locker:
				if align > 0.72:
					ray_reach = 11.5
			else:
				if align > 0.32:
					var blend := clampf((align - 0.32) / 0.40, 0.0, 1.0)
					ray_reach = lerpf(periph_max, cone_max, blend)

			var best_t := ray_reach
			var best_id := -1
			var best_kind := ""
			for s in active_segs:
				var t := _ray_segment_hit(p_xz, rd, best_t, s["a"], s["b"])
				if t >= 0.0 and t < best_t:
					best_t = t
					best_id = int(s["idx"])
					best_kind = str(s["kind"])

			var world_end := p_xz + rd * best_t
			var scr_pt := _world_to_scope(world_end, p_xz, cos_y, sin_y, px_per_m)
			var off := scr_pt - SCOPE_CENTER
			if off.length() > SCOPE_RADIUS - 1.5:
				scr_pt = SCOPE_CENTER + off.normalized() * (SCOPE_RADIUS - 1.5)

			fan_pts.append(scr_pt)
			hit_pts.append(scr_pt)
			hit_blocked.append(best_id != -1)
			hit_seg_ids.append(best_id)
			hit_kinds.append(best_kind)

		fan_pts.append(fan_pts[1])
		var cone_col := Color(COL_SODIUM, 0.065) if player.flashlight_on else Color(COL_PHOSPHOR, 0.06)
		for i in range(1, fan_pts.size() - 1):
			var tri := PackedVector2Array([SCOPE_CENTER, fan_pts[i], fan_pts[i + 1]])
			draw_colored_polygon(tri, cone_col)

		# Phosphor-Etched Wall, Closed-Door & Closed-Vent Contours
		for i in range(RAY_COUNT):
			var ni := (i + 1) % RAY_COUNT
			if hit_blocked[i] and hit_blocked[ni]:
				var p1 := hit_pts[i]
				var p2 := hit_pts[ni]
				if hit_seg_ids[i] == hit_seg_ids[ni] or p1.distance_to(p2) <= 6.5:
					var k := hit_kinds[i]
					var col := Color(COL_PHOSPHOR, 0.90)
					var w := 1.8
					if k == "door":
						col = Color(COL_SODIUM, 0.96)
						w = 2.4
					elif k == "vent":
						col = Color(COL_COLD, 0.94)
						w = 2.2
					draw_line(p1, p2, Color(col, 0.22), w + 2.2, true)
					draw_line(p1, p2, col, w, true)

		# Rotating North Azimuth Tick + N Glyph on Bezel
		var north_scr := _world_to_scope(p_xz + Vector2(0, -WORLD_RANGE), p_xz, cos_y, sin_y, px_per_m)
		var n_dir := (north_scr - SCOPE_CENTER).normalized()
		draw_line(SCOPE_CENTER + n_dir * (SCOPE_RADIUS - 5.0), SCOPE_CENTER + n_dir * (SCOPE_RADIUS + 3.5), COL_SODIUM, 2.0, true)
		if _mono_bold != null:
			var n_pos := SCOPE_CENTER + n_dir * (SCOPE_RADIUS + 9.5)
			draw_string(_mono_bold, n_pos + Vector2(-3.5, 4.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_SODIUM)

		# 4. Distant Echolocation Directional Rim Arc
		if _echo_ping_alpha > 0.02 and _echo_ping_dir.length() > 0.1:
			var ep_scr := _world_to_scope(p_xz + _echo_ping_dir * WORLD_RANGE, p_xz, cos_y, sin_y, px_per_m)
			var ep_ang := (ep_scr - SCOPE_CENTER).angle()
			draw_arc(SCOPE_CENTER, SCOPE_RADIUS - 3.0, ep_ang - 0.44, ep_ang + 0.44, 18, Color(COL_SIGNAL, _echo_ping_alpha * 0.92), 3.0, true)
			draw_arc(SCOPE_CENTER, SCOPE_RADIUS - 7.0, ep_ang - 0.28, ep_ang + 0.28, 14, Color(COL_SODIUM, _echo_ping_alpha * 0.65), 1.5, true)

		# 5. Specimen-07 Blip (ONLY if directly visible in Player's Line-of-Sight!)
		if monster_director != null and monster_director.active and monster_director.stalker_node != null:
			if monster_director.is_visible_from_point(player.camera.global_position):
				var m_xz := Vector2(monster_director.stalker_node.global_position.x, monster_director.stalker_node.global_position.z)
				var m_scr := _world_to_scope(m_xz, p_xz, cos_y, sin_y, px_per_m)
				if m_scr.distance_to(SCOPE_CENTER) <= SCOPE_RADIUS - 5.0:
					var ring_r := 8.5 if reduce_motion else (7.5 + fmod(_pulse_time * 14.0, 7.0))
					var ring_a := 0.85 if reduce_motion else clampf(1.0 - (ring_r - 7.5) / 7.0, 0.15, 0.9)
					draw_arc(m_scr, ring_r, 0.0, TAU, 24, Color(COL_SIGNAL, ring_a), 1.5, true)
					var d_sz := 5.5
					var d_pts := PackedVector2Array([
						m_scr + Vector2(0, -d_sz),
						m_scr + Vector2(d_sz, 0),
						m_scr + Vector2(0, d_sz),
						m_scr + Vector2(-d_sz, 0)
					])
					draw_colored_polygon(d_pts, COL_SIGNAL)
					draw_circle(m_scr, 1.8, COL_PAPER)

		# 6. Co-op Squad Transponder Beacons (with anti-overlap label placement)
		var placed_label_rects: Array[Rect2] = []
		for pid in remote_players.keys():
			var rp: RemoteListener = remote_players[pid]
			if not is_instance_valid(rp):
				continue
			var r_xz := Vector2(rp.global_position.x, rp.global_position.z)
			var r_scr := _world_to_scope(r_xz, p_xz, cos_y, sin_y, px_per_m)
			var need_help := rp.is_downed or rp.is_caged
			var beacon_col := COL_SIGNAL if need_help else COL_PHOSPHOR
			var off_r := r_scr - SCOPE_CENTER
			if off_r.length() <= SCOPE_RADIUS - 8.0:
				draw_circle(r_scr, 4.0, beacon_col)
				draw_arc(r_scr, 6.0, 0.0, TAU, 16, Color(beacon_col, 0.45), 1.0, true)
				if need_help:
					var pr := 9.0 if reduce_motion else (6.0 + fmod(_pulse_time * 12.0, 9.0))
					var pa := 0.85 if reduce_motion else (1.0 - (pr - 6.0) / 9.0)
					draw_arc(r_scr, pr, 0.0, TAU, 20, Color(COL_SIGNAL, pa), 1.5, true)
				if _mono_bold != null:
					var tag_txt := rp.callsign.left(6)
					var t_sz := _mono_bold.get_string_size(tag_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
					var candidates: Array[Vector2] = [
						r_scr + Vector2(7.0, 3.5),
						r_scr + Vector2(-t_sz.x - 7.0, 3.5),
						r_scr + Vector2(-t_sz.x * 0.5, -8.0),
						r_scr + Vector2(-t_sz.x * 0.5, 14.0),
					]
					if r_scr.x > SCOPE_CENTER.x + 12.0:
						candidates = [
							r_scr + Vector2(-t_sz.x - 7.0, 3.5),
							r_scr + Vector2(-t_sz.x * 0.5, -8.0),
							r_scr + Vector2(-t_sz.x * 0.5, 14.0),
							r_scr + Vector2(7.0, 3.5),
						]
					var chosen_pos := candidates[0]
					var chosen_rect := Rect2(chosen_pos + Vector2(-2.0, -10.0), Vector2(t_sz.x + 4.0, 13.0))
					for cand in candidates:
						var r_box := Rect2(cand + Vector2(-2.0, -10.0), Vector2(t_sz.x + 4.0, 13.0))
						var overlaps := false
						for prev_r in placed_label_rects:
							if r_box.intersects(prev_r):
								overlaps = true
								break
						if not overlaps:
							chosen_pos = cand
							chosen_rect = r_box
							break
					placed_label_rects.append(chosen_rect)
					draw_rect(Rect2(chosen_pos + Vector2(-2.0, -9.0), Vector2(t_sz.x + 4.0, 11.5)), Color(COL_INK, 0.72), true)
					draw_string(_mono_bold, chosen_pos, tag_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, beacon_col)
			else:
				var dir_n := off_r.normalized()
				var tip := SCOPE_CENTER + dir_n * (SCOPE_RADIUS - 3.5)
				var perp := Vector2(-dir_n.y, dir_n.x)
				var chev := PackedVector2Array([
					tip,
					tip - dir_n * 8.0 + perp * 4.5,
					tip - dir_n * 8.0 - perp * 4.5
				])
				draw_colored_polygon(chev, beacon_col)
				if need_help:
					var h_r := 7.0 if reduce_motion else (6.0 + 3.0 * absf(sin(_pulse_time * 5.0)))
					draw_arc(tip, h_r, 0.0, TAU, 16, Color(COL_SIGNAL, 0.78), 1.5, true)

	# 7. Player Center Chevron (Facing Up)
	var self_pts := PackedVector2Array([
		SCOPE_CENTER + Vector2(0, -6.0),
		SCOPE_CENTER + Vector2(4.4, 4.4),
		SCOPE_CENTER + Vector2(0, 2.0),
		SCOPE_CENTER + Vector2(-4.4, 4.4)
	])
	draw_colored_polygon(self_pts, COL_PAPER)

	# 8. Gridded Cathode Oscilloscope Plate Below Scope (y = 196..244)
	var plate_rect := Rect2(Vector2(6, 196), Vector2(192, 48))
	draw_rect(plate_rect, COL_INK, true)
	draw_rect(plate_rect, COL_RULE, false, 1.0)
	_draw_corner_ticks(plate_rect, Color(COL_PHOSPHOR, 0.42), 6.0)

	# Graticule grid inside oscilloscope
	for gx_i in range(1, 6):
		var gx := lerpf(plate_rect.position.x, plate_rect.end.x, float(gx_i) / 6.0)
		draw_line(Vector2(gx, plate_rect.position.y + 3.0), Vector2(gx, plate_rect.end.y - 3.0), Color(COL_PHOSPHOR, 0.065), 1.0)
	var mid_y := plate_rect.position.y + plate_rect.size.y * 0.56
	draw_line(Vector2(plate_rect.position.x + 4.0, mid_y), Vector2(plate_rect.end.x - 4.0, mid_y), Color(COL_PHOSPHOR, 0.12), 1.0)
	draw_line(Vector2(plate_rect.position.x + 4.0, mid_y - 11.0), Vector2(plate_rect.end.x - 4.0, mid_y - 11.0), Color(COL_PHOSPHOR, 0.05), 1.0)
	draw_line(Vector2(plate_rect.position.x + 4.0, mid_y + 11.0), Vector2(plate_rect.end.x - 4.0, mid_y + 11.0), Color(COL_PHOSPHOR, 0.05), 1.0)

	var nl_cur := AcousticBus.current_noise_level
	var trace_col := COL_SIGNAL if nl_cur >= 0.45 else (
		COL_SODIUM if nl_cur >= 0.18 else COL_PHOSPHOR
	)
	if player != null and player.is_holding_breath:
		trace_col = COL_COLD

	if _mono_font != null:
		var tag_left := "HOLD" if (player != null and player.is_holding_breath) else "ACOUSTIC"
		draw_string(_mono_font, plate_rect.position + Vector2(6.0, 11.5), tag_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(trace_col, 0.78))
		var db_val := clampi(int(round(nl_cur * 96.0)), 0, 99)
		var db_str := "%02d dB" % db_val
		draw_string(_mono_bold, Vector2(plate_rect.end.x - 38.0, plate_rect.position.y + 11.5), db_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, trace_col)

	var poly := PackedVector2Array()
	var n_pts := _wave_history.size()
	for i in range(n_pts):
		var px := lerpf(plate_rect.position.x + 6.0, plate_rect.end.x - 6.0, float(i) / float(max(1, n_pts - 1)))
		var py := mid_y - _wave_history[i] * 14.0
		poly.append(Vector2(px, py))
	if poly.size() >= 2:
		draw_polyline(poly, Color(trace_col, 0.25), 3.4, true)
		draw_polyline(poly, trace_col, 1.5, true)
