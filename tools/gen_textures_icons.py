import math
import os
import bpy
import numpy as np

BASE_GAME = "/Users/nuralynuriden/Desktop/Хоррор игра/game"
TEX_DIR = os.path.join(BASE_GAME, "assets", "textures")
ICON_DIR = os.path.join(BASE_GAME, "assets", "icons")

os.makedirs(TEX_DIR, exist_ok=True)
os.makedirs(ICON_DIR, exist_ok=True)


def save_png(filepath: str, rgba_uint8: np.ndarray) -> None:
    """Save HxWx4 uint8 array (top-to-bottom) as PNG via Blender Image API."""
    h, w, c = rgba_uint8.shape
    assert c == 4
    img = bpy.data.images.new(name="tmp_export", width=w, height=h, alpha=True)
    flipped = np.flipud(rgba_uint8).astype(np.float32) / 255.0
    img.pixels.foreach_set(flipped.ravel())
    img.filepath_raw = filepath
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


# ===========================================================================
# SEAMLESS PERIODIC PROCEDURAL NOISE TOOLKIT (512x512)
# ===========================================================================
def tileable_value_noise(size: int, freq: int, seed: int) -> np.ndarray:
    """Single-octave seamless periodic value noise in 0..1."""
    rng = np.random.default_rng(seed)
    f = max(1, min(freq, size))
    grid = rng.random((f, f), dtype=np.float32)
    idx = np.arange(size, dtype=np.float32)
    g = (idx / size) * f
    i0 = np.floor(g).astype(np.int32) % f
    i1 = (i0 + 1) % f
    t = g - np.floor(g)
    u = t * t * (3.0 - 2.0 * t)

    v00 = grid[i0[:, None], i0[None, :]]
    v10 = grid[i0[:, None], i1[None, :]]
    v01 = grid[i1[:, None], i0[None, :]]
    v11 = grid[i1[:, None], i1[None, :]]

    top = v00 * (1.0 - u[None, :]) + v10 * u[None, :]
    bot = v01 * (1.0 - u[None, :]) + v11 * u[None, :]
    return top * (1.0 - u[:, None]) + bot * u[:, None]


def tileable_fbm(
    size: int,
    base_freq: int = 4,
    octaves: int = 6,
    persistence: float = 0.5,
    seed: int = 1,
) -> np.ndarray:
    """Seamless periodic Fractal Brownian Motion normalized to 0..1."""
    acc = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    freq = base_freq
    for o in range(octaves):
        acc += tileable_value_noise(size, freq, seed + o * 37) * amp
        norm += amp
        amp *= persistence
        freq *= 2
    res = acc / max(norm, 1e-6)
    return (res - res.min()) / max(res.max() - res.min(), 1e-6)


def tileable_ridge(size: int, base_freq: int = 6, octaves: int = 4, seed: int = 10) -> np.ndarray:
    """Seamless domain-warped ridge noise (great for veins, cracks, mineral seams)."""
    warp_x = (tileable_fbm(size, base_freq, 3, 0.55, seed + 101) - 0.5) * 0.18
    warp_y = (tileable_fbm(size, base_freq, 3, 0.55, seed + 202) - 0.5) * 0.18

    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    wx = (xx + warp_x) % 1.0
    wy = (yy + warp_y) % 1.0

    acc = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    freq = base_freq
    rng = np.random.default_rng(seed)

    for _ in range(octaves):
        f = max(2, min(freq, size))
        grid = rng.random((f, f), dtype=np.float32)
        gx = wx * f
        gy = wy * f
        x0 = np.floor(gx).astype(np.int32) % f
        y0 = np.floor(gy).astype(np.int32) % f
        x1 = (x0 + 1) % f
        y1 = (y0 + 1) % f
        tx = gx - np.floor(gx)
        ty = gy - np.floor(gy)
        ux = tx * tx * (3.0 - 2.0 * tx)
        uy = ty * ty * (3.0 - 2.0 * ty)

        v00 = grid[y0, x0]
        v10 = grid[y0, x1]
        v01 = grid[y1, x0]
        v11 = grid[y1, x1]
        top = v00 * (1.0 - ux) + v10 * ux
        bot = v01 * (1.0 - ux) + v11 * ux
        val = top * (1.0 - uy) + bot * uy
        ridge = 1.0 - np.abs(val * 2.0 - 1.0)
        acc += (ridge * ridge) * amp
        norm += amp
        amp *= 0.5
        freq *= 2

    res = acc / max(norm, 1e-6)
    return (res - res.min()) / max(res.max() - res.min(), 1e-6)


def tileable_voronoi(size: int, cells: int = 8, jitter: float = 0.85, seed: int = 55):
    """Fast vectorized periodic Voronoi returning (f1, f2 - f1, cell_id_0_1)."""
    rng = np.random.default_rng(seed)
    pts_x = (np.arange(cells, dtype=np.float32)[None, :] + 0.5 + (rng.random((cells, cells), dtype=np.float32) - 0.5) * jitter) / cells
    pts_y = (np.arange(cells, dtype=np.float32)[:, None] + 0.5 + (rng.random((cells, cells), dtype=np.float32) - 0.5) * jitter) / cells
    cell_val = rng.random((cells, cells), dtype=np.float32)

    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    cx = np.floor(xx * cells).astype(np.int32)
    cy = np.floor(yy * cells).astype(np.int32)

    d1 = np.full((size, size), 99.0, dtype=np.float32)
    d2 = np.full((size, size), 99.0, dtype=np.float32)
    cid = np.zeros((size, size), dtype=np.float32)

    for dy in (-1, 0, 1):
        ny = (cy + dy) % cells
        for dx in (-1, 0, 1):
            nx = (cx + dx) % cells
            px = pts_x[ny, nx]
            py = pts_y[ny, nx]
            # Shortest toroidal distance
            ddx = xx - px
            ddx -= np.round(ddx)
            ddy = yy - py
            ddy -= np.round(ddy)
            dist = np.sqrt(ddx * ddx + ddy * ddy) * cells

            mask1 = dist < d1
            d2 = np.where(mask1, d1, np.minimum(d2, dist))
            d1 = np.where(mask1, dist, d1)
            cid = np.where(mask1, cell_val[ny, nx], cid)

    edge = np.clip(d2 - d1, 0.0, 1.0)
    return np.clip(d1, 0.0, 1.0), edge, cid


def tileable_directional_streaks(size: int, horiz_freq: int = 18, seed: int = 71) -> np.ndarray:
    """Periodic vertical drip/streak map (for water stains, rust drips)."""
    rng = np.random.default_rng(seed)
    col_noise = tileable_value_noise(size, horiz_freq, seed + 3)
    # Collapse vertically and modulate with multi-scale vertical breakup
    col_profile = np.mean(col_noise, axis=0, keepdims=True)
    col_profile = (col_profile - col_profile.min()) / max(col_profile.max() - col_profile.min(), 1e-6)
    v_break = tileable_fbm(size, 4, 4, 0.55, seed + 19)
    hi_break = tileable_value_noise(size, max(8, horiz_freq * 2), seed + 29)
    streaks = np.clip(col_profile * 0.72 + hi_break * 0.28, 0.0, 1.0)
    streaks = np.power(streaks, 2.2) * np.clip(v_break * 1.45 - 0.15, 0.0, 1.0)
    _ = rng
    return np.clip(streaks, 0.0, 1.0)


def height_to_normal(height: np.ndarray, strength: float = 3.0) -> np.ndarray:
    """Convert seamless 0..1 heightfield into tangent-space OpenGL normal RGBA uint8."""
    # Sobel-weighted periodic gradient for cleaner, less noisy normals at 512x512
    xm = np.roll(height, 1, axis=1)
    xp = np.roll(height, -1, axis=1)
    ym = np.roll(height, 1, axis=0)
    yp = np.roll(height, -1, axis=0)

    dx = ((xp - xm) * 2.0 + (np.roll(xp, -1, axis=0) - np.roll(xm, -1, axis=0)) + (np.roll(xp, 1, axis=0) - np.roll(xm, 1, axis=0))) * (0.25 * strength)
    dy = ((yp - ym) * 2.0 + (np.roll(yp, -1, axis=1) - np.roll(ym, -1, axis=1)) + (np.roll(yp, 1, axis=1) - np.roll(ym, 1, axis=1))) * (0.25 * strength)

    nx = -dx
    ny = -dy
    nz = np.ones_like(height)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    nx *= inv_len
    ny *= inv_len
    nz *= inv_len

    out = np.zeros((height.shape[0], height.shape[1], 4), dtype=np.uint8)
    out[..., 0] = np.clip((nx * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    out[..., 1] = np.clip((ny * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    out[..., 2] = np.clip((nz * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    out[..., 3] = 255
    return out


def rgb_to_rgba(rgb_float_0_1: np.ndarray) -> np.ndarray:
    h, w, _ = rgb_float_0_1.shape
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., :3] = np.clip(rgb_float_0_1 * 255.0, 0, 255).astype(np.uint8)
    out[..., 3] = 255
    return out


# ===========================================================================
# 8 SEAMLESS 512x512 PBR TEXTURE SETS
# ===========================================================================
def build_pbr_textures() -> None:
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S

    # 1. Soviet Bunker Cast Concrete / Wall Panel (calibrated mid-bright base so WALL_TEAL & WALL_CREAM tint cleanly!)
    macro = tileable_fbm(S, 4, 5, 0.52, seed=101)
    grain = tileable_fbm(S, 64, 4, 0.56, seed=102)
    pits_d1, _, _ = tileable_voronoi(S, cells=30, jitter=0.92, seed=103)
    pits = np.clip((0.15 - pits_d1) * 7.0, 0.0, 1.0) * (tileable_value_noise(S, 16, 104) > 0.54)

    # Panel seams (2 horizontal x 2 staggered vertical) + crisp recessed form-tie cones
    seam_y = np.exp(-((((yy * 2.0) % 1.0) - 0.0) ** 2) / 0.00012) + np.exp(-((((yy * 2.0) % 1.0) - 1.0) ** 2) / 0.00012)
    seam_y = np.clip(seam_y, 0.0, 1.0) * 0.44
    vx = (xx * 2.0 + 0.5 * np.floor(yy * 2.0)) % 1.0
    seam_x = (np.exp(-(vx ** 2) / 0.00012) + np.exp(-((vx - 1.0) ** 2) / 0.00012))
    seam_x = np.clip(seam_x, 0.0, 1.0) * 0.38

    # Sharp formwork tie-rod sockets on panels
    tie_holes = np.zeros((S, S), dtype=np.float32)
    for hy in (0.14, 0.36, 0.64, 0.86):
        row_shift = 0.25 if hy > 0.5 else 0.0
        for hx in (0.15, 0.35, 0.65, 0.85):
            dx = xx - ((hx + row_shift) % 1.0)
            dx -= np.round(dx)
            dy = yy - hy
            dy -= np.round(dy)
            r = np.sqrt(dx * dx + dy * dy)
            tie_holes = np.maximum(tie_holes, np.clip((0.011 - r) / 0.003, 0.0, 1.0))

    # Hairline stress cracks + mineral damp drip streaks
    crack_ridge = tileable_ridge(S, 6, 4, seed=105)
    cracks = np.clip((crack_ridge - 0.87) * 7.5, 0.0, 1.0) * 0.48
    drips = tileable_directional_streaks(S, 24, seed=106) * 0.44

    h_wall = np.clip(0.68 + grain * 0.16 + macro * 0.06 - pits * 0.24 - seam_y - seam_x - tie_holes * 0.48 - cracks, 0.0, 1.0)
    val_wall = np.clip(0.56 + macro * 0.11 + grain * 0.12 - pits * 0.12 - seam_y * 0.34 - seam_x * 0.30 - tie_holes * 0.28 - cracks * 0.25 - drips * 0.16, 0.18, 0.88)
    rgb = np.stack([
        val_wall * 0.99 - drips * 0.02,
        val_wall * 1.00 - drips * 0.01,
        val_wall * 0.97 - drips * 0.03,
    ], axis=-1)
    save_png(os.path.join(TEX_DIR, "concrete_wall.png"), rgb_to_rgba(rgb))
    save_png(os.path.join(TEX_DIR, "concrete_wall_n.png"), height_to_normal(h_wall, 2.8))

    # 2. Soviet Institutional Terrazzo / Ceramic Floor Tiles (6x6 grid + angular stone flecks + grout + grime)
    TILES = 6.0
    tx = (xx * TILES) % 1.0
    ty = (yy * TILES) % 1.0
    tile_ix = np.floor(xx * TILES).astype(np.int32)
    tile_iy = np.floor(yy * TILES).astype(np.int32)
    rng_t = np.random.default_rng(201)
    tile_tone_lut = 0.88 + rng_t.random((int(TILES), int(TILES)), dtype=np.float32) * 0.22
    per_tile = tile_tone_lut[tile_iy, tile_ix]

    # Sharp dark mortar joints with chamfered tile edge
    dx_edge = np.minimum(tx, 1.0 - tx)
    dy_edge = np.minimum(ty, 1.0 - ty)
    d_edge = np.minimum(dx_edge, dy_edge)
    grout = np.clip((0.030 - d_edge) / 0.010, 0.0, 1.0)
    bevel = np.clip((d_edge - 0.030) / 0.032, 0.0, 1.0)

    # Angular fractured terrazzo mineral aggregate chips (perturbed Voronoi so they look like crushed stone, NOT circles!)
    chip_warp = tileable_fbm(S, 32, 3, 0.55, seed=206)
    f_d1, f_ed1, f_cid1 = tileable_voronoi(S, cells=48, jitter=0.95, seed=202)
    f_d2, _, f_cid2 = tileable_voronoi(S, cells=92, jitter=0.95, seed=207)
    ang_f1 = f_d1 + (chip_warp - 0.5) * 0.34 - (1.0 - f_ed1) * 0.06
    ang_f2 = f_d2 + (chip_warp - 0.5) * 0.30
    chip_dark = ((ang_f1 < 0.22) & (f_cid1 < 0.28)) | ((ang_f2 < 0.20) & (f_cid2 < 0.24))
    chip_pale = ((ang_f1 < 0.20) & (f_cid1 > 0.78)) | ((ang_f2 < 0.18) & (f_cid2 > 0.80))
    chip_ochre = (ang_f1 < 0.19) & (f_cid1 >= 0.44) & (f_cid1 <= 0.54)

    wear = tileable_fbm(S, 5, 5, 0.55, seed=203)
    rust_stain = np.clip((tileable_fbm(S, 3, 4, 0.52, seed=204) - 0.62) * 2.4, 0.0, 1.0)
    micro = tileable_fbm(S, 48, 3, 0.52, seed=205)

    base_tile = (0.34 + wear * 0.08 + micro * 0.05) * per_tile
    base_tile = np.where(chip_dark, base_tile * 0.68, base_tile)
    base_tile = np.where(chip_pale, base_tile * 1.24 + 0.03, base_tile)
    base_tile = np.where(chip_ochre, base_tile * 1.10, base_tile)

    tile_r = base_tile * 0.96 + np.where(chip_ochre, 0.035, 0.0) + rust_stain * 0.07
    tile_g = base_tile * 1.00 + np.where(chip_ochre, 0.015, 0.0) + rust_stain * 0.015
    tile_b = base_tile * 0.95 - rust_stain * 0.03

    grout_col = 0.065 + micro * 0.035
    rgb = np.stack([
        tile_r * (1.0 - grout) + grout_col * grout,
        tile_g * (1.0 - grout) + grout_col * grout,
        tile_b * (1.0 - grout) + (grout_col * 0.95) * grout,
    ], axis=-1)

    h_floor = np.clip(0.82 * bevel + 0.18 - grout * 0.72 + micro * 0.05 - wear * 0.04, 0.0, 1.0)
    save_png(os.path.join(TEX_DIR, "tile_floor.png"), rgb_to_rgba(rgb))
    save_png(os.path.join(TEX_DIR, "tile_floor_n.png"), height_to_normal(h_floor, 4.0))

    # 3. Industrial Precast Ceiling Concrete
    c_macro = tileable_fbm(S, 4, 5, 0.55, seed=301)
    c_grain = tileable_fbm(S, 28, 4, 0.55, seed=302)
    c_seam = np.exp(-((((yy * 3.0) % 1.0) - 0.5) ** 2) / 0.0003) * 0.35
    mold = np.clip((tileable_fbm(S, 3, 4, 0.55, seed=303) - 0.52) * 2.2, 0.0, 1.0)
    c_crack = np.clip((tileable_ridge(S, 5, 4, seed=304) - 0.87) * 6.5, 0.0, 1.0) * 0.35
    h_ceil = np.clip(0.60 + c_grain * 0.25 + c_macro * 0.12 - c_seam - c_crack, 0.0, 1.0)
    v_ceil = np.clip(0.24 + c_macro * 0.11 + c_grain * 0.06 - mold * 0.09 - c_seam * 0.18 - c_crack * 0.14, 0.08, 0.45)
    rgb = np.stack([v_ceil * 0.95, v_ceil * 0.98 - mold * 0.01, v_ceil * 1.00 - mold * 0.02], axis=-1)
    save_png(os.path.join(TEX_DIR, "ceiling_concrete.png"), rgb_to_rgba(rgb))
    save_png(os.path.join(TEX_DIR, "ceiling_concrete_n.png"), height_to_normal(h_ceil, 3.0))

    # 4. Rusted Oxidized Soviet Steel (Lockers, Doors, Pipes, Specimen Restraints)
    m_base = tileable_fbm(S, 8, 5, 0.54, seed=401)
    m_brush = tileable_value_noise(S, 96, 402) * 0.65 + tileable_fbm(S, 16, 4, 0.5, seed=403) * 0.35
    _, r_edge, _ = tileable_voronoi(S, cells=14, jitter=0.9, seed=404)
    rust_field = tileable_fbm(S, 5, 5, 0.56, seed=405) + (1.0 - r_edge) * 0.14
    rust_mask = np.clip((rust_field - 0.48) * 3.8, 0.0, 1.0)
    deep_rust = np.clip((rust_field - 0.61) * 5.2, 0.0, 1.0)
    scratches = np.clip((tileable_ridge(S, 12, 3, seed=406) - 0.83) * 5.5, 0.0, 1.0)

    steel_rgb = np.stack([
        0.24 + m_base * 0.10 + m_brush * 0.06 + scratches * 0.16,
        0.26 + m_base * 0.11 + m_brush * 0.06 + scratches * 0.16,
        0.28 + m_base * 0.12 + m_brush * 0.06 + scratches * 0.17,
    ], axis=-1)
    rust_outer = np.stack([0.42 + m_base * 0.14, 0.19 + m_base * 0.07, 0.08 + m_base * 0.03], axis=-1)
    rust_core = np.stack([0.21 + m_base * 0.08, 0.09 + m_base * 0.03, 0.05 + m_base * 0.02], axis=-1)
    rust_rgb = rust_outer * (1.0 - deep_rust[..., None]) + rust_core * deep_rust[..., None]

    rgb = steel_rgb * (1.0 - rust_mask[..., None]) + rust_rgb * rust_mask[..., None]
    h_metal = np.clip(0.62 + m_brush * 0.12 - rust_mask * 0.28 - deep_rust * 0.22 - scratches * 0.15, 0.0, 1.0)
    save_png(os.path.join(TEX_DIR, "rusted_metal.png"), rgb_to_rgba(rgb))
    save_png(os.path.join(TEX_DIR, "rusted_metal_n.png"), height_to_normal(h_metal, 3.8))

    # 5. Dirty Splintered Plank Wood (straighter cathedral grain + fine fiber + plank joints)
    PLANK_N = 4.0
    py_idx = np.floor(yy * PLANK_N).astype(np.int32)
    rng_w = np.random.default_rng(501)
    plank_tone = 0.84 + rng_w.random(int(PLANK_N), dtype=np.float32) * 0.30
    plank_var = plank_tone[py_idx]

    w_warp = tileable_fbm(S, 3, 4, 0.50, seed=502) * 0.95
    grain_ring = np.sin((yy * 14.0 + w_warp) * math.tau) * 0.5 + 0.5
    fine_fiber = tileable_value_noise(S, 128, 503) * 0.35 + tileable_fbm(S, 32, 4, 0.5, seed=504) * 0.65
    plank_seam = np.exp(-((((yy * PLANK_N) % 1.0) - 0.0) ** 2) / 0.00028) + np.exp(-((((yy * PLANK_N) % 1.0) - 1.0) ** 2) / 0.00028)
    plank_seam = np.clip(plank_seam, 0.0, 1.0)
    rot_grime = np.clip((tileable_fbm(S, 5, 4, 0.55, seed=505) - 0.56) * 2.2, 0.0, 1.0)

    h_wood = np.clip(grain_ring * 0.24 + fine_fiber * 0.42 + 0.16 - plank_seam * 0.62, 0.0, 1.0)
    base_w = (0.24 + grain_ring * 0.07 + fine_fiber * 0.09 - rot_grime * 0.08) * plank_var * (1.0 - plank_seam * 0.72)
    rgb = np.stack([base_w * 1.12, base_w * 0.76, base_w * 0.48], axis=-1)
    save_png(os.path.join(TEX_DIR, "dirty_wood.png"), rgb_to_rgba(rgb))
    save_png(os.path.join(TEX_DIR, "dirty_wood_n.png"), height_to_normal(h_wood, 3.6))

    # 6. Necrotic Mutant Flesh (Specimen-07: cold dead ash-grey / bruised slate pallor, dark veins, coagulated dark clots — ZERO PINK!)
    skin_macro = tileable_fbm(S, 6, 5, 0.55, seed=601)
    pores_d1, _, _ = tileable_voronoi(S, cells=38, jitter=0.92, seed=602)
    pores = np.clip(1.0 - pores_d1 * 1.25, 0.0, 1.0)
    sinew = tileable_fbm(S, 20, 4, 0.55, seed=603)

    v_ridge1 = tileable_ridge(S, 7, 4, seed=604)
    v_ridge2 = tileable_ridge(S, 14, 3, seed=605)
    veins = np.clip((v_ridge1 - 0.75) * 4.8, 0.0, 1.0) * 0.8 + np.clip((v_ridge2 - 0.79) * 5.2, 0.0, 1.0) * 0.6
    veins = np.clip(veins, 0.0, 1.0)

    bruise = np.clip((tileable_fbm(S, 4, 4, 0.55, seed=606) - 0.44) * 2.4, 0.0, 1.0)
    scar_mask = np.clip((tileable_ridge(S, 5, 3, seed=607) - 0.82) * 7.0, 0.0, 1.0)
    clot_noise = tileable_fbm(S, 9, 4, 0.56, seed=608)
    clotted = np.clip((clot_noise - 0.64) * 4.2, 0.0, 1.0) * (0.30 + scar_mask * 0.70)
    clotted = np.power(clotted, 1.35)

    # Cold ash-slate corpse skin -> bruised slate -> dark dried venous clot (#22090A)
    ash = 0.34 + skin_macro * 0.13 + sinew * 0.07 - pores * 0.04
    r_f = ash * 0.94 - bruise * 0.07 - veins * 0.15
    g_f = ash * 0.97 - bruise * 0.05 - veins * 0.20
    b_f = ash * 0.98 - bruise * 0.01 - veins * 0.13
    # Blend toward deep coagulated dried-blood burgundy-black (never salmon/pink!)
    clot_r, clot_g, clot_b = 0.15, 0.035, 0.035
    r_f = r_f * (1.0 - clotted) + clot_r * clotted
    g_f = g_f * (1.0 - clotted) + clot_g * clotted
    b_f = b_f * (1.0 - clotted) + clot_b * clotted

    rgb = np.stack([r_f, g_f, b_f], axis=-1)
    h_flesh = np.clip(0.55 + skin_macro * 0.22 + sinew * 0.15 + veins * 0.18 - pores * 0.12 - scar_mask * 0.34, 0.0, 1.0)
    save_png(os.path.join(TEX_DIR, "flesh_mutant.png"), rgb_to_rgba(rgb))
    save_png(os.path.join(TEX_DIR, "flesh_mutant_n.png"), height_to_normal(h_flesh, 4.2))

    # 7. Weathered Soviet L-1 / OZK Hazmat Suit Fabric (olive-ochre rubberized weave)
    weave_x = np.sin(xx * S * math.pi * 0.5)
    weave_y = np.sin(yy * S * math.pi * 0.5)
    ripstop = (np.exp(-((((xx * 24.0) % 1.0) - 0.5) ** 2) / 0.008) + np.exp(-((((yy * 24.0) % 1.0) - 0.5) ** 2) / 0.008)) * 0.08
    micro_weave = (weave_x * weave_y) * 0.035
    fold_grain = tileable_fbm(S, 5, 5, 0.55, seed=701)
    soot = np.clip((tileable_fbm(S, 4, 4, 0.55, seed=702) - 0.55) * 2.4, 0.0, 1.0)

    base_haz = 0.42 + fold_grain * 0.14 + micro_weave - soot * 0.14
    rgb = np.stack([
        base_haz * 1.02 + ripstop * 0.15,
        base_haz * 0.94 + ripstop * 0.14,
        base_haz * 0.52 + ripstop * 0.08,
    ], axis=-1)
    h_haz = np.clip(0.50 + fold_grain * 0.24 + micro_weave * 2.5 + ripstop * 0.4, 0.0, 1.0)
    save_png(os.path.join(TEX_DIR, "hazmat_fabric.png"), rgb_to_rgba(rgb))
    save_png(os.path.join(TEX_DIR, "hazmat_fabric_n.png"), height_to_normal(h_haz, 2.8))

    # 8. Worn Soviet Industrial Hazard Stripes (SODIUM #E3A23B & INK #121514 with chipped paint)
    diag = ((xx + yy) * 6.0) % 1.0
    stripe = (diag < 0.5).astype(np.float32)
    wear = tileable_fbm(S, 8, 5, 0.55, seed=801)
    scuff = tileable_ridge(S, 10, 3, seed=802)
    chip = np.clip((wear - 0.67) * 5.0 + (scuff - 0.85) * 3.0, 0.0, 1.0)
    grime = np.clip((tileable_fbm(S, 4, 4, 0.55, seed=803) - 0.50) * 1.8, 0.0, 1.0)

    # SODIUM #E3A23B aged ochre-amber & deep bunker charcoal
    yel = np.stack([np.full((S, S), 0.78), np.full((S, S), 0.55), np.full((S, S), 0.16)], axis=-1)
    blk = np.stack([np.full((S, S), 0.08), np.full((S, S), 0.09), np.full((S, S), 0.085)], axis=-1)
    primer = np.stack([0.20 + wear * 0.08, 0.17 + wear * 0.06, 0.15 + wear * 0.05], axis=-1)

    rgb = yel * stripe[..., None] + blk * (1.0 - stripe[..., None])
    rgb = rgb * (0.82 + wear[..., None] * 0.22 - grime[..., None] * 0.25)
    rgb = rgb * (1.0 - chip[..., None]) + primer * chip[..., None]
    save_png(os.path.join(TEX_DIR, "hazard_stripes.png"), rgb_to_rgba(rgb))


# ===========================================================================
# 4x SUPERSAMPLED SDF VECTOR ICON BUILDER (512 -> 128 Crisp RGBA)
# ===========================================================================
# DESIGN.md tokens in sRGB 0..1
COL_INK = (0.04, 0.05, 0.045)
COL_DARK_STEEL = (0.20, 0.23, 0.24)
COL_PAPER = (0.867, 0.839, 0.769)      # #DDD6C4
COL_PAPER_DIM = (0.612, 0.592, 0.541)  # #9C978A
COL_STEEL = (0.72, 0.75, 0.77)
COL_SODIUM = (0.890, 0.635, 0.231)     # #E3A23B
COL_SIGNAL = (0.800, 0.227, 0.180)     # #CC3A2E
COL_PHOSPHOR = (0.557, 0.863, 0.620)   # #8EDC9E
COL_COLD = (0.498, 0.722, 0.784)       # #7FB8C8


def make_ss_canvas(ss_size: int = 512):
    yy, xx = np.mgrid[0:ss_size, 0:ss_size].astype(np.float32)
    nx = (xx / (ss_size - 1)) * 2.0 - 1.0
    ny = (yy / (ss_size - 1)) * 2.0 - 1.0
    return nx, ny, np.zeros((ss_size, ss_size, 4), dtype=np.float32)


def sd_segment(px, py, ax, ay, bx, by):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = np.clip((pax * bax + pay * bay) / max(bax * bax + bay * bay, 1e-6), 0.0, 1.0)
    dx = pax - bax * h
    dy = pay - bay * h
    return np.sqrt(dx * dx + dy * dy)


def sd_box(px, py, cx, cy, hx, hy, angle=0.0, r=0.0):
    dx, dy = px - cx, py - cy
    if angle != 0.0:
        c, s = math.cos(-angle), math.sin(-angle)
        dx, dy = c * dx - s * dy, s * dx + c * dy
    qx = np.abs(dx) - hx + r
    qy = np.abs(dy) - hy + r
    out_d = np.sqrt(np.maximum(qx, 0.0) ** 2 + np.maximum(qy, 0.0) ** 2)
    in_d = np.minimum(np.maximum(qx, qy), 0.0)
    return out_d + in_d - r


def sd_circle(px, py, cx, cy, r):
    return np.sqrt((px - cx) ** 2 + (py - cy) ** 2) - r


def sd_ellipse(px, py, cx, cy, rx, ry, angle=0.0):
    dx, dy = px - cx, py - cy
    if angle != 0.0:
        c, s = math.cos(-angle), math.sin(-angle)
        dx, dy = c * dx - s * dy, s * dx + c * dy
    k0 = np.sqrt((dx / rx) ** 2 + (dy / ry) ** 2)
    k1 = np.sqrt((dx / (rx * rx)) ** 2 + (dy / (ry * ry)) ** 2)
    return np.where(k1 > 1e-6, k0 * (k0 - 1.0) / k1, -min(rx, ry))


def sd_triangle(px, py, ax, ay, bx, by, cx, cy):
    d1 = sd_segment(px, py, ax, ay, bx, by)
    d2 = sd_segment(px, py, bx, by, cx, cy)
    d3 = sd_segment(px, py, cx, cy, ax, ay)
    edge_d = np.minimum(d1, np.minimum(d2, d3))
    s1 = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
    s2 = (cx - bx) * (py - by) - (cy - by) * (px - bx)
    s3 = (ax - cx) * (py - cy) - (ay - cy) * (px - cx)
    inside = ((s1 >= 0) & (s2 >= 0) & (s3 >= 0)) | ((s1 <= 0) & (s2 <= 0) & (s3 <= 0))
    return np.where(inside, -edge_d, edge_d)


def smin(a, b, k=0.05):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def layer_sdf(
    canvas: np.ndarray,
    ny: np.ndarray,
    d: np.ndarray,
    color_rgb,
    outline: float = 0.026,
    rim_boost: float = 0.14,
    grad_amp: float = 0.10,
):
    """Smooth clean SDF compositing without diagonal pyramid creases."""
    aa = 0.008
    # Crisp #0A0C0B outer border
    if outline > 0.0:
        out_alpha = np.clip((outline - d) / aa, 0.0, 1.0)
        out_col = np.array(COL_INK, dtype=np.float32)
        canvas[..., :3] = canvas[..., :3] * (1.0 - out_alpha[..., None]) + out_col * out_alpha[..., None]
        canvas[..., 3] = np.maximum(canvas[..., 3], out_alpha * 0.96)

    fill_alpha = np.clip((-d) / aa, 0.0, 1.0)
    # Top-to-bottom subtle directional lighting + delicate interior rim glow
    grad = np.clip(-ny * grad_amp, -0.14, 0.14)
    inner_rim = np.exp(-np.maximum(-d, 0.0) / 0.045) * np.clip((-ny + 0.25) * 0.65, 0.0, 1.0) * rim_boost
    col = np.clip(np.array(color_rgb, dtype=np.float32)[None, None, :] + grad[..., None] + inner_rim[..., None], 0.0, 1.0)

    canvas[..., :3] = canvas[..., :3] * (1.0 - fill_alpha[..., None]) + col * fill_alpha[..., None]
    canvas[..., 3] = np.maximum(canvas[..., 3], fill_alpha)


def add_drop_shadow(canvas: np.ndarray, d_union: np.ndarray, dx: float = 0.04, dy: float = 0.05):
    """Shift SDF slightly down-right to cast a subtle grounding shadow behind icon."""
    sh_y = int(round(dy * 256))
    sh_x = int(round(dx * 256))
    shifted = np.roll(d_union, shift=(sh_y, sh_x), axis=(0, 1))
    alpha = np.clip((0.028 - shifted) / 0.024, 0.0, 1.0) * 0.38
    canvas[..., :3] = np.array(COL_INK, dtype=np.float32)[None, None, :]
    canvas[..., 3] = alpha


def save_icon_ss(name: str, ss_canvas: np.ndarray, out_size: int = 128) -> None:
    """Premultiply, box-downsample 4x4 (512->128), and un-premultiply cleanly."""
    h, w, _ = ss_canvas.shape
    f = h // out_size
    assert f * out_size == h and w == h
    pre = np.empty_like(ss_canvas)
    pre[..., :3] = ss_canvas[..., :3] * ss_canvas[..., 3:4]
    pre[..., 3] = ss_canvas[..., 3]
    down = pre.reshape(out_size, f, out_size, f, 4).mean(axis=(1, 3))
    alpha = down[..., 3:4]
    rgb = np.where(alpha > 1e-4, down[..., :3] / np.maximum(alpha, 1e-4), 0.0)
    rgba = np.concatenate([rgb, alpha], axis=-1)
    save_png(os.path.join(ICON_DIR, name), np.clip(rgba * 255.0, 0, 255).astype(np.uint8))


def build_icons() -> None:
    # 1. Crowbar (Монтировка)
    nx, ny, c = make_ss_canvas()
    shaft = sd_segment(nx, ny, -0.44, 0.44, 0.36, -0.36) - 0.070
    hook_b = sd_segment(nx, ny, 0.36, -0.36, 0.56, -0.24) - 0.064
    hook_t = sd_segment(nx, ny, 0.56, -0.24, 0.62, 0.02) - 0.050
    chisel = sd_segment(nx, ny, -0.44, 0.44, -0.66, 0.66) - 0.054
    steel_ends = np.minimum(np.minimum(hook_b, hook_t), chisel)
    body_all = np.minimum(shaft, steel_ends)
    add_drop_shadow(c, body_all)
    layer_sdf(c, ny, body_all, COL_SIGNAL, outline=0.032)
    layer_sdf(c, ny, steel_ends, COL_STEEL, outline=0.016)
    save_icon_ss("item_crowbar.png", c)

    # 2. Wire / Bolt Cutters (Кусачки)
    nx, ny, c = make_ss_canvas()
    h1 = sd_segment(nx, ny, -0.42, 0.60, -0.06, 0.06) - 0.070
    h2 = sd_segment(nx, ny, 0.42, 0.60, 0.06, 0.06) - 0.070
    collar1 = sd_segment(nx, ny, -0.13, 0.16, -0.07, 0.07) - 0.078
    collar2 = sd_segment(nx, ny, 0.13, 0.16, 0.07, 0.07) - 0.078
    jaw1 = sd_segment(nx, ny, -0.05, 0.04, -0.14, -0.52) - 0.065
    jaw2 = sd_segment(nx, ny, 0.05, 0.04, 0.14, -0.52) - 0.065
    jaw_cut = sd_triangle(nx, ny, 0.0, -0.16, -0.09, -0.60, 0.09, -0.60)
    jaws = np.maximum(np.minimum(jaw1, jaw2), -jaw_cut)
    pivot = sd_circle(nx, ny, 0.0, -0.02, 0.13)
    handles = np.minimum(h1, h2)
    steel = np.minimum(np.minimum(jaws, pivot), np.minimum(collar1, collar2))
    add_drop_shadow(c, np.minimum(handles, steel))
    layer_sdf(c, ny, steel, COL_PAPER_DIM, outline=0.032)
    layer_sdf(c, ny, handles, COL_SODIUM, outline=0.032)
    layer_sdf(c, ny, sd_circle(nx, ny, 0.0, -0.02, 0.052), COL_DARK_STEEL, outline=0.012)
    save_icon_ss("item_cutters.png", c)

    # 3. High-Voltage Fuse (Предохранитель)
    nx, ny, c = make_ss_canvas()
    ang = 0.65
    glass = sd_box(nx, ny, 0.0, 0.0, 0.21, 0.42, angle=ang, r=0.03)
    cap1 = sd_box(nx, ny, -0.24, 0.33, 0.23, 0.12, angle=ang, r=0.03)
    cap2 = sd_box(nx, ny, 0.24, -0.33, 0.23, 0.12, angle=ang, r=0.03)
    rib1 = sd_box(nx, ny, -0.17, 0.24, 0.24, 0.03, angle=ang, r=0.01)
    rib2 = sd_box(nx, ny, 0.17, -0.24, 0.24, 0.03, angle=ang, r=0.01)
    caps = np.minimum(np.minimum(cap1, cap2), np.minimum(rib1, rib2))
    fil_1 = sd_segment(nx, ny, -0.18, 0.25, 0.18, -0.25) - 0.030
    fil_coil = sd_circle(nx, ny, 0.0, 0.0, 0.075)
    add_drop_shadow(c, np.minimum(glass, caps))
    layer_sdf(c, ny, glass, (0.24, 0.38, 0.44), outline=0.030)
    layer_sdf(c, ny, sd_box(nx, ny, -0.05, -0.03, 0.05, 0.30, angle=ang), COL_COLD, outline=0.0, rim_boost=0.05)
    layer_sdf(c, ny, np.minimum(fil_1, fil_coil), COL_SODIUM, outline=0.010, rim_boost=0.22)
    layer_sdf(c, ny, caps, COL_SODIUM, outline=0.030)
    save_icon_ss("item_fuse.png", c)

    # 4. Master Key (Мастер-ключ)
    nx, ny, c = make_ss_canvas()
    bow_outer = sd_box(nx, ny, -0.38, -0.36, 0.24, 0.24, angle=0.785, r=0.08)
    bow_hole = sd_circle(nx, ny, -0.40, -0.38, 0.095)
    bow = np.maximum(bow_outer, -bow_hole)
    collar = sd_box(nx, ny, -0.18, -0.16, 0.11, 0.042, angle=-0.785, r=0.015)
    stem = sd_segment(nx, ny, -0.22, -0.20, 0.56, 0.58) - 0.056
    t1 = sd_segment(nx, ny, 0.48, 0.50, 0.30, 0.68) - 0.048
    t2 = sd_segment(nx, ny, 0.31, 0.33, 0.16, 0.48) - 0.044
    t3 = sd_segment(nx, ny, 0.17, 0.19, 0.06, 0.30) - 0.038
    d_key = np.minimum(np.minimum(bow, collar), np.minimum(stem, np.minimum(t1, np.minimum(t2, t3))))
    add_drop_shadow(c, d_key)
    layer_sdf(c, ny, d_key, COL_SODIUM, outline=0.032)
    save_icon_ss("item_key.png", c)

    # 5. Safe Code Note (Записка с кодом)
    nx, ny, c = make_ss_canvas()
    ang = -0.09
    sheet = sd_box(nx, ny, 0.0, 0.04, 0.48, 0.60, angle=ang, r=0.035)
    clip_b = sd_box(nx, ny, -0.05, -0.54, 0.20, 0.08, angle=ang, r=0.02)
    stamp = sd_box(nx, ny, 0.18, -0.24, 0.14, 0.10, angle=ang + 0.12, r=0.015)
    l1 = sd_box(nx, ny, -0.04, -0.02, 0.30, 0.032, angle=ang, r=0.01)
    l2 = sd_box(nx, ny, -0.02, 0.16, 0.30, 0.032, angle=ang, r=0.01)
    l3 = sd_box(nx, ny, -0.08, 0.34, 0.20, 0.032, angle=ang, r=0.01)
    add_drop_shadow(c, np.minimum(sheet, clip_b))
    layer_sdf(c, ny, sheet, COL_PAPER, outline=0.030)
    layer_sdf(c, ny, clip_b, COL_PAPER_DIM, outline=0.024)
    layer_sdf(c, ny, stamp, COL_SIGNAL, outline=0.0, rim_boost=0.05)
    layer_sdf(c, ny, np.minimum(l1, np.minimum(l2, l3)), COL_DARK_STEEL, outline=0.0, rim_boost=0.02)
    save_icon_ss("item_code_note.png", c)

    # 6. Decoy Glass Bottle (Бутылка)
    nx, ny, c = make_ss_canvas()
    b_body = sd_box(nx, ny, 0.0, 0.26, 0.24, 0.34, r=0.08)
    b_shld = sd_ellipse(nx, ny, 0.0, -0.04, 0.23, 0.18)
    b_neck = sd_box(nx, ny, 0.0, -0.34, 0.082, 0.22, r=0.02)
    b_lip = sd_box(nx, ny, 0.0, -0.58, 0.11, 0.04, r=0.02)
    bottle = np.minimum(smin(b_body, b_shld, 0.04), np.minimum(b_neck, b_lip))
    lbl = sd_box(nx, ny, 0.0, 0.24, 0.21, 0.14, r=0.015)
    lbl_stripe = sd_box(nx, ny, 0.0, 0.24, 0.20, 0.03)
    glint = sd_box(nx, ny, -0.11, 0.22, 0.03, 0.24, r=0.015)
    add_drop_shadow(c, bottle)
    layer_sdf(c, ny, bottle, (0.22, 0.46, 0.33), outline=0.032)
    layer_sdf(c, ny, glint, COL_PHOSPHOR, outline=0.0, rim_boost=0.08)
    layer_sdf(c, ny, lbl, COL_PAPER, outline=0.014)
    layer_sdf(c, ny, lbl_stripe, COL_SIGNAL, outline=0.0, rim_boost=0.02)
    save_icon_ss("item_bottle.png", c)

    # 7. Adrenaline Syringe (Шприц)
    nx, ny, c = make_ss_canvas()
    ang = 0.785
    barrel = sd_box(nx, ny, 0.0, 0.0, 0.15, 0.36, angle=ang, r=0.02)
    flange = sd_box(nx, ny, -0.26, 0.26, 0.23, 0.035, angle=ang, r=0.015)
    plunger_rod = sd_segment(nx, ny, -0.26, 0.26, -0.48, 0.48) - 0.032
    plunger_cap = sd_box(nx, ny, -0.49, 0.49, 0.15, 0.035, angle=ang, r=0.015)
    needle_hub = sd_box(nx, ny, 0.28, -0.28, 0.065, 0.06, angle=ang, r=0.015)
    needle = sd_segment(nx, ny, 0.32, -0.32, 0.64, -0.64) - 0.018
    serum = sd_box(nx, ny, 0.05, -0.05, 0.10, 0.22, angle=ang, r=0.01)
    all_parts = np.minimum(np.minimum(barrel, flange), np.minimum(np.minimum(plunger_rod, plunger_cap), np.minimum(needle_hub, needle)))
    add_drop_shadow(c, all_parts)
    layer_sdf(c, ny, np.minimum(plunger_rod, np.minimum(plunger_cap, needle)), COL_STEEL, outline=0.026)
    layer_sdf(c, ny, np.minimum(barrel, np.minimum(flange, needle_hub)), COL_COLD, outline=0.028)
    layer_sdf(c, ny, serum, COL_PHOSPHOR, outline=0.0, rim_boost=0.14)
    save_icon_ss("item_syringe.png", c)

    # 8. Flashlight Battery (Батарейка)
    nx, ny, c = make_ss_canvas()
    body = sd_box(nx, ny, 0.0, 0.07, 0.33, 0.48, r=0.055)
    nub = sd_box(nx, ny, 0.0, -0.47, 0.14, 0.08, r=0.02)
    band = sd_box(nx, ny, 0.0, -0.22, 0.33, 0.15, r=0.02)
    b1 = sd_triangle(nx, ny, 0.08, -0.02, -0.14, 0.22, 0.04, 0.22)
    b2 = sd_triangle(nx, ny, -0.08, 0.44, 0.14, 0.18, -0.04, 0.18)
    bolt = np.minimum(b1, b2)
    add_drop_shadow(c, np.minimum(body, nub))
    layer_sdf(c, ny, nub, COL_PAPER_DIM, outline=0.028)
    layer_sdf(c, ny, body, (0.16, 0.19, 0.18), outline=0.032)
    layer_sdf(c, ny, band, COL_SODIUM, outline=0.015)
    layer_sdf(c, ny, bolt, COL_SODIUM, outline=0.010, rim_boost=0.22)
    save_icon_ss("item_battery.png", c)

    # 9. Sonic Strobe Flare (Фальшфейер)
    nx, ny, c = make_ss_canvas()
    ang = 0.72
    tube = sd_box(nx, ny, -0.12, 0.12, 0.135, 0.42, angle=ang, r=0.03)
    cap = sd_box(nx, ny, 0.14, -0.14, 0.15, 0.09, angle=ang, r=0.02)
    r1 = sd_segment(nx, ny, 0.24, -0.24, 0.60, -0.60) - 0.038
    r2 = sd_segment(nx, ny, 0.26, -0.12, 0.66, -0.18) - 0.030
    r3 = sd_segment(nx, ny, 0.12, -0.26, 0.18, -0.66) - 0.030
    core = sd_circle(nx, ny, 0.22, -0.22, 0.11)
    rays = np.minimum(core, np.minimum(r1, np.minimum(r2, r3)))
    add_drop_shadow(c, np.minimum(tube, rays))
    layer_sdf(c, ny, tube, COL_SIGNAL, outline=0.032)
    layer_sdf(c, ny, cap, COL_DARK_STEEL, outline=0.026)
    layer_sdf(c, ny, rays, COL_SODIUM, outline=0.022, rim_boost=0.24)
    layer_sdf(c, ny, sd_circle(nx, ny, 0.22, -0.22, 0.055), COL_PAPER, outline=0.0)
    save_icon_ss("item_flare.png", c)

    # 10. First-Aid Medkit (Аптечка)
    nx, ny, c = make_ss_canvas()
    case = sd_box(nx, ny, 0.0, 0.08, 0.54, 0.40, r=0.07)
    handle_out = sd_box(nx, ny, 0.0, -0.36, 0.22, 0.10, r=0.04)
    handle_in = sd_box(nx, ny, 0.0, -0.34, 0.13, 0.05, r=0.02)
    handle = np.maximum(handle_out, -handle_in)
    clasp1 = sd_box(nx, ny, -0.32, -0.31, 0.065, 0.04, r=0.01)
    clasp2 = sd_box(nx, ny, 0.32, -0.31, 0.065, 0.04, r=0.01)
    cr_h = sd_box(nx, ny, 0.0, 0.08, 0.22, 0.072, r=0.015)
    cr_v = sd_box(nx, ny, 0.0, 0.08, 0.072, 0.22, r=0.015)
    cross = np.minimum(cr_h, cr_v)
    add_drop_shadow(c, np.minimum(case, handle))
    layer_sdf(c, ny, handle, COL_PAPER_DIM, outline=0.028)
    layer_sdf(c, ny, case, COL_PAPER, outline=0.032)
    layer_sdf(c, ny, np.minimum(clasp1, clasp2), COL_DARK_STEEL, outline=0.015)
    layer_sdf(c, ny, cross, COL_SIGNAL, outline=0.018)
    save_icon_ss("item_medkit.png", c)

    # 11. Heavy Screwdriver (Отвёртка)
    nx, ny, c = make_ss_canvas()
    ang = 0.785
    grip = sd_box(nx, ny, -0.30, 0.30, 0.125, 0.28, angle=ang, r=0.05)
    bolster = sd_box(nx, ny, -0.09, 0.09, 0.085, 0.06, angle=ang, r=0.02)
    shaft = sd_segment(nx, ny, -0.06, 0.06, 0.46, -0.46) - 0.034
    tip = sd_box(nx, ny, 0.52, -0.52, 0.052, 0.09, angle=ang, r=0.012)
    flute = sd_box(nx, ny, -0.32, 0.32, 0.032, 0.20, angle=ang, r=0.015)
    all_sd = np.minimum(np.minimum(grip, bolster), np.minimum(shaft, tip))
    add_drop_shadow(c, all_sd)
    layer_sdf(c, ny, np.minimum(shaft, tip), COL_STEEL, outline=0.026)
    layer_sdf(c, ny, bolster, COL_DARK_STEEL, outline=0.022)
    layer_sdf(c, ny, grip, COL_SODIUM, outline=0.032)
    layer_sdf(c, ny, flute, (0.62, 0.40, 0.10), outline=0.0, rim_boost=0.0)
    save_icon_ss("item_screwdriver.png", c)

    # 12. UI Hand (Взаимодействие)
    nx, ny, c = make_ss_canvas()
    palm = sd_box(nx, ny, 0.02, 0.24, 0.24, 0.23, r=0.11)
    f1 = sd_segment(nx, ny, -0.20, 0.06, -0.23, -0.40) - 0.068
    f2 = sd_segment(nx, ny, -0.05, 0.02, -0.05, -0.52) - 0.070
    f3 = sd_segment(nx, ny, 0.10, 0.02, 0.12, -0.46) - 0.068
    f4 = sd_segment(nx, ny, 0.24, 0.10, 0.28, -0.30) - 0.064
    thumb = sd_segment(nx, ny, -0.20, 0.30, -0.46, 0.02) - 0.074
    hand = smin(palm, np.minimum(thumb, np.minimum(np.minimum(f1, f2), np.minimum(f3, f4))), 0.035)
    add_drop_shadow(c, hand)
    layer_sdf(c, ny, hand, COL_PAPER, outline=0.032)
    save_icon_ss("ui_hand.png", c)

    # 13. UI Flashlight (Фонарик)
    nx, ny, c = make_ss_canvas()
    ang = 0.785
    handle = sd_box(nx, ny, -0.24, 0.24, 0.115, 0.32, angle=ang, r=0.035)
    head = sd_box(nx, ny, 0.06, -0.06, 0.19, 0.12, angle=ang, r=0.03)
    sw = sd_box(nx, ny, -0.14, 0.02, 0.04, 0.06, angle=ang, r=0.015)
    b1 = sd_segment(nx, ny, 0.28, -0.28, 0.60, -0.60) - 0.035
    b2 = sd_segment(nx, ny, 0.34, -0.12, 0.68, -0.26) - 0.032
    b3 = sd_segment(nx, ny, 0.12, -0.34, 0.26, -0.68) - 0.032
    torch = np.minimum(np.minimum(handle, head), sw)
    beams = np.minimum(b1, np.minimum(b2, b3))
    add_drop_shadow(c, np.minimum(torch, beams))
    layer_sdf(c, ny, torch, COL_PAPER, outline=0.030)
    layer_sdf(c, ny, sw, COL_SODIUM, outline=0.014)
    layer_sdf(c, ny, beams, COL_SODIUM, outline=0.022, rim_boost=0.2)
    save_icon_ss("ui_flashlight.png", c)

    # 14. UI Crouch (Присесть)
    nx, ny, c = make_ss_canvas()
    head_c = sd_circle(nx, ny, 0.14, -0.44, 0.15)
    back = sd_segment(nx, ny, 0.04, -0.20, -0.24, 0.16) - 0.088
    thigh = sd_segment(nx, ny, -0.24, 0.16, 0.20, 0.26) - 0.078
    shin = sd_segment(nx, ny, 0.20, 0.26, -0.06, 0.62) - 0.072
    boot = sd_segment(nx, ny, -0.06, 0.62, 0.12, 0.62) - 0.062
    arm = sd_segment(nx, ny, -0.02, -0.12, 0.32, 0.08) - 0.062
    crouch = np.minimum(head_c, np.minimum(back, np.minimum(thigh, np.minimum(shin, np.minimum(boot, arm)))))
    add_drop_shadow(c, crouch)
    layer_sdf(c, ny, crouch, COL_PAPER, outline=0.032)
    save_icon_ss("ui_crouch.png", c)

    # 15. UI Drop Item (Бросить)
    nx, ny, c = make_ss_canvas()
    stem = sd_segment(nx, ny, 0.0, -0.52, 0.0, 0.22) - 0.085
    head_tri = sd_triangle(nx, ny, 0.0, 0.42, -0.32, 0.04, 0.32, 0.04) - 0.02
    arrow = np.minimum(stem, head_tri)
    tray_b = sd_segment(nx, ny, -0.48, 0.60, 0.48, 0.60) - 0.062
    tray_l = sd_segment(nx, ny, -0.48, 0.60, -0.48, 0.38) - 0.062
    tray_r = sd_segment(nx, ny, 0.48, 0.60, 0.48, 0.38) - 0.062
    tray = np.minimum(tray_b, np.minimum(tray_l, tray_r))
    add_drop_shadow(c, np.minimum(arrow, tray))
    layer_sdf(c, ny, tray, COL_PAPER_DIM, outline=0.028)
    layer_sdf(c, ny, arrow, COL_SODIUM, outline=0.030)
    save_icon_ss("ui_drop.png", c)

    # 16. UI Sprint (Бег)
    nx, ny, c = make_ss_canvas()
    head_r = sd_circle(nx, ny, 0.24, -0.48, 0.145)
    torso = sd_segment(nx, ny, 0.14, -0.28, -0.12, 0.12) - 0.084
    leg1 = sd_segment(nx, ny, -0.12, 0.12, 0.34, 0.56) - 0.072
    leg2 = sd_segment(nx, ny, -0.12, 0.12, -0.48, 0.44) - 0.072
    arm1 = sd_segment(nx, ny, 0.08, -0.20, 0.44, -0.04) - 0.060
    arm2 = sd_segment(nx, ny, 0.04, -0.16, -0.34, -0.26) - 0.060
    streak1 = sd_segment(nx, ny, -0.68, -0.14, -0.42, -0.14) - 0.032
    streak2 = sd_segment(nx, ny, -0.74, 0.06, -0.46, 0.06) - 0.032
    runner = np.minimum(head_r, np.minimum(torso, np.minimum(np.minimum(leg1, leg2), np.minimum(arm1, arm2))))
    streaks = np.minimum(streak1, streak2)
    add_drop_shadow(c, np.minimum(runner, streaks))
    layer_sdf(c, ny, streaks, COL_SODIUM, outline=0.020)
    layer_sdf(c, ny, runner, COL_PAPER, outline=0.032)
    save_icon_ss("ui_run.png", c)

    # 17. UI Hold Breath (Задержка дыхания — anatomical lungs & bronchi)
    nx, ny, c = make_ss_canvas()
    l_up = sd_ellipse(nx, ny, -0.24, -0.04, 0.19, 0.34, angle=0.22)
    l_lw = sd_ellipse(nx, ny, -0.31, 0.20, 0.22, 0.26, angle=0.10)
    lung_l = smin(l_up, l_lw, 0.08)
    # Trim medial inner edge of left lung cleanly
    lung_l = np.maximum(lung_l, nx + 0.08)

    r_up = sd_ellipse(nx, ny, 0.24, -0.04, 0.19, 0.34, angle=-0.22)
    r_lw = sd_ellipse(nx, ny, 0.31, 0.20, 0.22, 0.26, angle=-0.10)
    lung_r = smin(r_up, r_lw, 0.08)
    lung_r = np.maximum(lung_r, -nx + 0.08)

    trachea = sd_segment(nx, ny, 0.0, -0.56, 0.0, -0.08) - 0.055
    bron_l = sd_segment(nx, ny, 0.0, -0.10, -0.26, 0.10) - 0.042
    bron_r = sd_segment(nx, ny, 0.0, -0.10, 0.26, 0.10) - 0.042
    lungs = np.minimum(lung_l, lung_r)
    airway = np.minimum(trachea, np.minimum(bron_l, bron_r))
    add_drop_shadow(c, np.minimum(lungs, airway))
    layer_sdf(c, ny, lungs, COL_COLD, outline=0.030)
    layer_sdf(c, ny, airway, COL_PAPER, outline=0.018)
    save_icon_ss("ui_breath.png", c)

    # 18. UI Journal / Field Dossier (Полевое досье)
    nx, ny, c = make_ss_canvas()
    board = sd_box(nx, ny, 0.0, 0.06, 0.48, 0.56, r=0.05)
    page = sd_box(nx, ny, 0.0, 0.08, 0.39, 0.46, r=0.02)
    clip = sd_box(nx, ny, 0.0, -0.46, 0.19, 0.09, r=0.025)
    clip_ring = sd_circle(nx, ny, 0.0, -0.56, 0.075)
    ln1 = sd_box(nx, ny, -0.04, -0.12, 0.22, 0.030, r=0.01)
    ln2 = sd_box(nx, ny, 0.0, 0.08, 0.26, 0.030, r=0.01)
    ln3 = sd_box(nx, ny, -0.06, 0.28, 0.20, 0.030, r=0.01)
    mark = sd_box(nx, ny, 0.18, -0.28, 0.09, 0.06, r=0.01)
    add_drop_shadow(c, np.minimum(board, np.minimum(clip, clip_ring)))
    layer_sdf(c, ny, board, (0.20, 0.24, 0.22), outline=0.030)
    layer_sdf(c, ny, page, COL_PAPER, outline=0.014)
    layer_sdf(c, ny, np.minimum(clip, clip_ring), COL_SODIUM, outline=0.022)
    layer_sdf(c, ny, mark, COL_SIGNAL, outline=0.0)
    layer_sdf(c, ny, np.minimum(ln1, np.minimum(ln2, ln3)), COL_DARK_STEEL, outline=0.0)
    save_icon_ss("ui_journal.png", c)


if __name__ == "__main__":
    build_pbr_textures()
    build_icons()
    print("TEXTURES_AND_ICONS_COMPLETE")
