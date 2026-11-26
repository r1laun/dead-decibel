import math
import os
import sys
from collections import Counter
import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

BASE_GAME = "/Users/nuralynuriden/Desktop/Хоррор игра/game"
TEX_DIR = os.path.join(BASE_GAME, "assets", "textures")
MODEL_DIR = os.path.join(BASE_GAME, "assets", "models")
os.makedirs(MODEL_DIR, exist_ok=True)


def load_img(filename: str, non_color: bool = False, max_size: int = 0):
    path = os.path.join(TEX_DIR, filename)
    img = bpy.data.images.load(path, check_existing=True)
    if max_size > 0 and (img.size[0] > max_size or img.size[1] > max_size):
        w, h = img.size[0], img.size[1]
        scale = max_size / max(w, h)
        img.scale(max(1, int(round(w * scale))), max(1, int(round(h * scale))))
        img.pack()
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def make_uv_pbr_mat(
    name: str,
    tex_file: str = "",
    norm_file: str = "",
    base_col=(1.0, 1.0, 1.0, 1.0),
    roughness: float = 0.65,
    metallic: float = 0.0,
    emission_col=None,
    emission_strength: float = 0.0,
    normal_strength: float = 1.0,
    specular_ior: float = 0.5,
    max_tex_size: int = 0,
):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base_col
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular_ior
    if emission_col is not None and emission_strength > 0.0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*emission_col[:3], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if tex_file:
        ti = nodes.new("ShaderNodeTexImage")
        ti.image = load_img(tex_file, False, max_size=max_tex_size)
        if tuple(round(x, 3) for x in base_col[:3]) != (1.0, 1.0, 1.0):
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            links.new(ti.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = base_col
            links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            links.new(ti.outputs["Color"], bsdf.inputs["Base Color"])
        if norm_file:
            ni = nodes.new("ShaderNodeTexImage")
            ni.image = load_img(norm_file, True, max_size=max_tex_size)
            nm = nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = normal_strength
            links.new(ni.outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def assign_cubic_uvs_bmesh(bm: bmesh.types.BMesh, tex_repeat: float = 2.0, uv_name: str = "UVMap") -> None:
    uv_layer = bm.loops.layers.uv.get(uv_name) or bm.loops.layers.uv.new(uv_name)
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for lp in f.loops:
            co = lp.vert.co
            if az >= ax and az >= ay:
                u, v = co.x, co.y
            elif ax >= ay and ax >= az:
                u, v = co.y, co.z
            else:
                u, v = co.x, co.z
            lp[uv_layer].uv = (u * tex_repeat + 0.5, v * tex_repeat + 0.5)


def assign_continuous_uvs_bmesh(bm: bmesh.types.BMesh, tex_repeat: float = 2.0, uv_name: str = "UVMap") -> None:
    """Seam-free continuous projection for thin tubes, chains, fangs, and untextured meshes."""
    uv_layer = bm.loops.layers.uv.get(uv_name) or bm.loops.layers.uv.new(uv_name)
    for f in bm.faces:
        f.smooth = True
        for lp in f.loops:
            co = lp.vert.co
            lp[uv_layer].uv = ((co.x + co.y) * tex_repeat + 0.5, co.z * tex_repeat + 0.5)


def apply_modifiers_and_uv(obj, mat, tex_repeat: float = 2.2) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    assign_cubic_uvs_bmesh(bm, tex_repeat=tex_repeat, uv_name="UVMap")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.validate()

    obj.data.materials.clear()
    obj.data.materials.append(mat)
    obj.select_set(False)


def join_with_exact_materials(base_obj, base_mat, detail_items: list, palette: list) -> None:
    """Register the full ordered material palette on base_obj and every detail object,
    assign exact poly.material_index BEFORE bpy.ops.object.join(), then verify slots."""
    mat_to_idx = {m.name: idx for idx, m in enumerate(palette)}

    def _prepare(obj, target_mat):
        mesh = obj.data
        mesh.materials.clear()
        for m in palette:
            mesh.materials.append(m)
        # Ensure consistent single UVMap name so join() merges UVs seamlessly
        if not mesh.uv_layers:
            mesh.uv_layers.new(name="UVMap")
        else:
            mesh.uv_layers[0].name = "UVMap"
        t_idx = mat_to_idx[target_mat.name]
        for poly in mesh.polygons:
            poly.material_index = t_idx
            poly.use_smooth = True

    _prepare(base_obj, base_mat)
    for det_obj, det_mat in detail_items:
        _prepare(det_obj, det_mat)

    bpy.ops.object.select_all(action="DESELECT")
    base_obj.select_set(True)
    for det_obj, _ in detail_items:
        det_obj.select_set(True)
    bpy.context.view_layer.objects.active = base_obj
    bpy.ops.object.join()
    base_obj.data.validate()

    counts = Counter(p.material_index for p in base_obj.data.polygons)
    print(
        f"[{base_obj.name}] joined polygons={len(base_obj.data.polygons)} material_counts=",
        {palette[idx].name: cnt for idx, cnt in sorted(counts.items())},
    )


def create_detail_obj(name: str, bm: bmesh.types.BMesh, tex_repeat: float = 2.0, continuous_uv: bool = False):
    m = bpy.data.meshes.new(name + "_mesh")
    if continuous_uv:
        assign_continuous_uvs_bmesh(bm, tex_repeat=tex_repeat, uv_name="UVMap")
    else:
        assign_cubic_uvs_bmesh(bm, tex_repeat=tex_repeat, uv_name="UVMap")
    bm.to_mesh(m)
    bm.free()
    m.validate()
    o = bpy.data.objects.new(name, m)
    bpy.context.collection.objects.link(o)
    return o


# ===========================================================================
# PROCEDURAL BMESH SCULPTING PRIMITIVES (Curves, Rings, Chains, Straps, Fangs)
# ===========================================================================
def add_tube_along_points(bm: bmesh.types.BMesh, pts_radii: list, segs: int = 10, cap_start: bool = True, cap_end: bool = True):
    """Build a smooth closed-ring tube along [(Vector, rx, ry), ...]."""
    rings = []
    n_pts = len(pts_radii)
    prev_up = Vector((0.0, 0.0, 1.0))

    for idx, (pt, rx, ry) in enumerate(pts_radii):
        if idx == 0:
            tangent = (pts_radii[1][0] - pt).normalized()
        elif idx == n_pts - 1:
            tangent = (pt - pts_radii[idx - 1][0]).normalized()
        else:
            tangent = (pts_radii[idx + 1][0] - pts_radii[idx - 1][0]).normalized()
        if tangent.length < 1e-6:
            tangent = Vector((0.0, 0.0, 1.0))

        # Parallel-transport frame to avoid twist flips
        if abs(tangent.dot(prev_up)) > 0.94:
            ref = Vector((1.0, 0.0, 0.0)) if abs(tangent.x) < 0.8 else Vector((0.0, 1.0, 0.0))
        else:
            ref = prev_up
        side = tangent.cross(ref).normalized()
        up = side.cross(tangent).normalized()
        prev_up = up

        ring = []
        for si in range(segs):
            a = (si / segs) * math.tau
            offset = side * (math.cos(a) * rx) + up * (math.sin(a) * ry)
            ring.append(bm.verts.new(pt + offset))
        rings.append(ring)

    for r_i in range(len(rings) - 1):
        r0 = rings[r_i]
        r1 = rings[r_i + 1]
        for si in range(segs):
            sn = (si + 1) % segs
            bm.faces.new((r0[si], r0[sn], r1[sn], r1[si]))

    if cap_start and rings:
        bm.faces.new(list(reversed(rings[0])))
    if cap_end and rings:
        bm.faces.new(rings[-1])


def add_chain_link(bm: bmesh.types.BMesh, center: Vector, rot_euler: Euler, major_rx: float = 0.022, major_ry: float = 0.034, wire_r: float = 0.0065, ring_pts: int = 16, tube_segs: int = 7):
    """Add a 3D iron chain link oriented by rot_euler."""
    rot_m = rot_euler.to_matrix()
    pts = []
    for i in range(ring_pts):
        a = (i / ring_pts) * math.tau
        # Elongated oval chain link in local XZ plane
        lx = math.cos(a) * major_rx
        lz = math.sin(a) * major_ry
        local = Vector((lx, 0.0, lz))
        pts.append((center + rot_m @ local, wire_r, wire_r))

    rings = []
    for idx in range(ring_pts):
        p_prev = pts[(idx - 1) % ring_pts][0]
        p_cur = pts[idx][0]
        p_next = pts[(idx + 1) % ring_pts][0]
        tang = (p_next - p_prev).normalized()
        up = (rot_m @ Vector((0.0, 1.0, 0.0))).normalized()
        side = tang.cross(up).normalized()
        up = side.cross(tang).normalized()
        ring = []
        for si in range(tube_segs):
            sa = (si / tube_segs) * math.tau
            ring.append(bm.verts.new(p_cur + side * (math.cos(sa) * wire_r) + up * (math.sin(sa) * wire_r)))
        rings.append(ring)

    for idx in range(ring_pts):
        r0 = rings[idx]
        r1 = rings[(idx + 1) % ring_pts]
        for si in range(tube_segs):
            sn = (si + 1) % tube_segs
            bm.faces.new((r0[si], r0[sn], r1[sn], r1[si]))


def add_curved_visor_band(
    bm: bmesh.types.BMesh,
    center: Vector,
    radius_x: float,
    radius_y: float,
    ang_start: float,
    ang_end: float,
    z_bot: float,
    z_top: float,
    thickness: float,
    arc_steps: int = 16,
):
    """Build a solid curved shell wrapping +Y front around `center` (ang=0 is +Y)."""
    outer_bot, outer_top, inner_bot, inner_top = [], [], [], []
    for i in range(arc_steps + 1):
        t = i / arc_steps
        a = ang_start + (ang_end - ang_start) * t
        sx, cy = math.sin(a), math.cos(a)
        ox = center.x + sx * (radius_x + thickness)
        oy = center.y + cy * (radius_y + thickness)
        ix = center.x + sx * radius_x
        iy = center.y + cy * radius_y
        outer_bot.append(bm.verts.new((ox, oy, z_bot)))
        outer_top.append(bm.verts.new((ox, oy, z_top)))
        inner_bot.append(bm.verts.new((ix, iy, z_bot)))
        inner_top.append(bm.verts.new((ix, iy, z_top)))

    for i in range(arc_steps):
        bm.faces.new((outer_bot[i], outer_bot[i + 1], outer_top[i + 1], outer_top[i]))
        bm.faces.new((inner_top[i], inner_top[i + 1], inner_bot[i + 1], inner_bot[i]))
        bm.faces.new((outer_top[i], outer_top[i + 1], inner_top[i + 1], inner_top[i]))
        bm.faces.new((inner_bot[i], inner_bot[i + 1], outer_bot[i + 1], outer_bot[i]))
    # End caps
    bm.faces.new((inner_bot[0], outer_bot[0], outer_top[0], inner_top[0]))
    bm.faces.new((outer_bot[-1], inner_bot[-1], inner_top[-1], outer_top[-1]))


def add_box_bm(bm_target, size_vec, center_vec, rot_eu=Euler((0, 0, 0))):
    ret = bmesh.ops.create_cube(bm_target, size=1.0)
    verts = ret["verts"]
    bmesh.ops.scale(bm_target, vec=size_vec, verts=verts)
    bmesh.ops.rotate(bm_target, cent=(0, 0, 0), matrix=rot_eu.to_matrix(), verts=verts)
    bmesh.ops.translate(bm_target, vec=center_vec, verts=verts)


def add_cyl_bm(bm_target, r1: float, r2: float, depth: float, center_vec, rot_eu=Euler((0, 0, 0)), segs: int = 14):
    ret = bmesh.ops.create_cone(bm_target, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    verts = ret["verts"]
    bmesh.ops.rotate(bm_target, cent=(0, 0, 0), matrix=rot_eu.to_matrix(), verts=verts)
    bmesh.ops.translate(bm_target, vec=center_vec, verts=verts)


def add_helical_coil(
    bm: bmesh.types.BMesh,
    p_start: Vector,
    p_end: Vector,
    turns: float = 6.5,
    coil_radius: float = 0.011,
    wire_radius: float = 0.0032,
    bow_offset: Vector = Vector((0.0, 0.0, 0.0)),
    steps: int = 44,
    segs: int = 6,
):
    """Build a 3D coiled acoustic cable along an arched path from p_start to p_end."""
    axis = (p_end - p_start).normalized()
    ref = Vector((0.0, 1.0, 0.0)) if abs(axis.y) < 0.85 else Vector((1.0, 0.0, 0.0))
    u = axis.cross(ref).normalized()
    v = axis.cross(u).normalized()
    pts = []
    for i in range(steps + 1):
        t = i / steps
        base = p_start.lerp(p_end, t) + bow_offset * math.sin(t * math.pi)
        ang = t * turns * math.tau
        env = math.sin(min(1.0, t * 5.0) * math.pi * 0.5) * math.sin(min(1.0, (1.0 - t) * 5.0) * math.pi * 0.5)
        offset = (u * math.cos(ang) + v * math.sin(ang)) * (coil_radius * env)
        pts.append((base + offset, wire_radius, wire_radius))
    add_tube_along_points(bm, pts, segs=segs)


def add_parabolic_ear_cup(
    bm_iron: bmesh.types.BMesh,
    center: Vector,
    out_dir: Vector,
    outer_r: float = 0.074,
    depth: float = 0.056,
    baffle_rings: int = 3,
    cross_bars: bool = False,
    ring_steps: int = 20,
    rib_steps: int = 16,
    rib_segs: int = 6,
    needle_segs: int = 8,
    bar_segs: int = 6,
):
    """Build a bolted Soviet acoustic parabolic amplifier dish with concentric baffle ribs."""
    n_dir = out_dir.normalized()
    up_ref = Vector((0.0, 0.0, 1.0)) if abs(n_dir.z) < 0.9 else Vector((0.0, 1.0, 0.0))
    u = n_dir.cross(up_ref).normalized()
    v = n_dir.cross(u).normalized()

    # Flared parabolic outer shell (lathed along n_dir)
    profile = [
        (0.0, outer_r * 0.30, outer_r * 0.30),
        (0.28, outer_r * 0.56, outer_r * 0.56),
        (0.65, outer_r * 0.86, outer_r * 0.86),
        (1.0, outer_r, outer_r),
    ]
    outer_rings, inner_rings = [], []
    wall = 0.0065
    for pt_t, rx, ry in profile:
        c = center + n_dir * (pt_t * depth)
        ro, ri = [], []
        for si in range(ring_steps):
            a = (si / ring_steps) * math.tau
            dir_r = u * math.cos(a) + v * math.sin(a)
            ro.append(bm_iron.verts.new(c + dir_r * (rx + wall)))
            ri.append(bm_iron.verts.new(c + dir_r * max(0.008, rx - wall)))
        outer_rings.append(ro)
        inner_rings.append(ri)

    for r_i in range(len(profile) - 1):
        for si in range(ring_steps):
            sn = (si + 1) % ring_steps
            bm_iron.faces.new((outer_rings[r_i][si], outer_rings[r_i][sn], outer_rings[r_i + 1][sn], outer_rings[r_i + 1][si]))
            bm_iron.faces.new((inner_rings[r_i][sn], inner_rings[r_i][si], inner_rings[r_i + 1][si], inner_rings[r_i + 1][sn]))
    # Rim lip & solid backplate
    for si in range(ring_steps):
        sn = (si + 1) % ring_steps
        bm_iron.faces.new((outer_rings[-1][si], outer_rings[-1][sn], inner_rings[-1][sn], inner_rings[-1][si]))
    bm_iron.faces.new(list(reversed(outer_rings[0])))
    bm_iron.faces.new(inner_rings[0])

    # Concentric ribbed acoustic baffle rings inside dish
    for bi in range(baffle_rings):
        bt = 0.38 + bi * 0.24
        br = outer_r * (0.38 + bi * 0.20)
        bc = center + n_dir * (bt * depth)
        rib_pts = []
        for si in range(rib_steps + 1):
            a = (si / float(rib_steps)) * math.tau
            rib_pts.append((bc + (u * math.cos(a) + v * math.sin(a)) * br, 0.0032, 0.0042))
        add_tube_along_points(bm_iron, rib_pts, segs=rib_segs, cap_start=False, cap_end=False)

    # Central acoustic transducer needle cone
    add_tube_along_points(bm_iron, [
        (center + n_dir * 0.005, 0.015, 0.015),
        (center + n_dir * (depth * 0.72), 0.006, 0.006),
        (center + n_dir * (depth * 0.96), 0.0025, 0.0025),
    ], segs=needle_segs)

    if cross_bars:
        mouth_c = center + n_dir * (depth * 0.94)
        for ang_b in (0.35, 0.35 + math.pi * 0.5):
            bdir = u * math.cos(ang_b) + v * math.sin(ang_b)
            add_tube_along_points(bm_iron, [
                (mouth_c - bdir * (outer_r * 0.96), 0.0032, 0.0032),
                (mouth_c + n_dir * 0.006, 0.0032, 0.0032),
                (mouth_c + bdir * (outer_r * 0.96), 0.0032, 0.0032),
            ], segs=bar_segs)


def push_nla_action(arm_obj, action_name: str):
    act = arm_obj.animation_data.action
    act.name = action_name
    track = arm_obj.animation_data.nla_tracks.new()
    track.name = action_name
    strip = track.strips.new(action_name, int(act.frame_range[0]), act)
    strip.name = action_name
    arm_obj.animation_data.action = None


# ===========================================================================
# 1. RE-SCULPTED SPECIMEN-07 ("ОБЪЕКТ-07") — ~2.25m GAUNT CONTAINMENT HORROR
# ===========================================================================
def build_sculpted_monster() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)

    mat_flesh = make_uv_pbr_mat(
        "SpecimenFlesh",
        "flesh_mutant.png",
        "flesh_mutant_n.png",
        base_col=(0.95, 0.96, 0.97, 1.0),
        roughness=0.56,
        metallic=0.02,
        normal_strength=1.25,
        max_tex_size=256,
    )
    mat_iron = make_uv_pbr_mat(
        "SpecimenIron",
        "rusted_metal.png",
        "rusted_metal_n.png",
        base_col=(0.48, 0.45, 0.43, 1.0),
        roughness=0.44,
        metallic=0.88,
        normal_strength=1.1,
        max_tex_size=256,
    )
    mat_bone = make_uv_pbr_mat(
        "SpecimenBone",
        "",
        "",
        base_col=(0.48, 0.42, 0.30, 1.0),
        roughness=0.40,
        metallic=0.04,
    )
    mat_glow = make_uv_pbr_mat(
        "VisorGlow",
        "",
        "",
        base_col=(0.35, 0.04, 0.02, 1.0),
        roughness=0.22,
        emission_col=(0.88, 0.14, 0.04),
        emission_strength=1.10,
    )
    mat_maw = make_uv_pbr_mat(
        "MawAbyss",
        "",
        "",
        base_col=(0.001, 0.001, 0.0015, 1.0),
        roughness=1.0,
        specular_ior=0.0,
    )
    mat_strap = make_uv_pbr_mat(
        "SpecimenStrap",
        "concrete_wall.png",
        "concrete_wall_n.png",
        base_col=(0.032, 0.022, 0.018, 1.0),
        roughness=0.84,
        metallic=0.04,
        max_tex_size=256,
    )
    mat_rag = make_uv_pbr_mat(
        "SpecimenRag",
        "concrete_wall.png",
        "hazmat_fabric_n.png",
        base_col=(0.11, 0.022, 0.020, 1.0),
        roughness=0.95,
        metallic=0.0,
        max_tex_size=256,
    )
    palette = [mat_flesh, mat_iron, mat_bone, mat_glow, mat_maw, mat_strap, mat_rag]

    # 1. Continuous Multi-Station Skin-Modifier Skeleton (+Y forward, +Z up, ~2.26m tall)
    mesh = bpy.data.meshes.new("SpecimenBodyGraph")
    body_obj = bpy.data.objects.new("SpecimenBody", mesh)
    bpy.context.collection.objects.link(body_obj)

    nodes_spec = {
        "pelvis": ((0.0, 0.0, 1.02), 0.145, 0.105),
        "sacrum": ((0.0, -0.01, 1.13), 0.105, 0.082),
        "lumbar": ((0.0, -0.02, 1.26), 0.092, 0.074),      # Emaciated sunken waist!
        "diaphragm": ((0.0, 0.02, 1.40), 0.138, 0.105),
        "thorax_low": ((0.0, 0.07, 1.53), 0.195, 0.135),
        "thorax_up": ((0.0, 0.11, 1.66), 0.225, 0.142),    # Broad hunched ribcage!
        "neck_base": ((0.0, 0.17, 1.77), 0.078, 0.082),
        "neck_mid": ((0.0, 0.23, 1.87), 0.064, 0.072),
        "head_base": ((0.0, 0.25, 1.98), 0.114, 0.134),
        "head_brow": ((0.0, 0.28, 2.08), 0.106, 0.122),
        "head_crown": ((0.0, 0.25, 2.18), 0.082, 0.095),
    }
    edges_spec = [
        ("pelvis", "sacrum"),
        ("sacrum", "lumbar"),
        ("lumbar", "diaphragm"),
        ("diaphragm", "thorax_low"),
        ("thorax_low", "thorax_up"),
        ("thorax_up", "neck_base"),
        ("neck_base", "neck_mid"),
        ("neck_mid", "head_base"),
        ("head_base", "head_brow"),
        ("head_brow", "head_crown"),
    ]

    # Elongated sinewy arms (reaching past knees) & gaunt bowed stalking legs
    for side, s in ((-1, "L"), (1, "R")):
        asym_z = -0.025 if side == -1 else 0.0
        asym_y = 0.025 if side == 1 else 0.0
        nodes_spec.update({
            f"clav_{s}": ((side * 0.17, 0.12, 1.69 + asym_z * 0.5), 0.080, 0.072),
            f"shld_{s}": ((side * 0.27, 0.09 + asym_y * 0.4, 1.66 + asym_z), 0.092, 0.086),
            f"bicep_{s}": ((side * 0.34, 0.06, 1.44 + asym_z), 0.056, 0.056),
            f"elbow_{s}": ((side * 0.37, 0.03 + asym_y, 1.22 + asym_z), 0.064, 0.064),
            f"fore_{s}": ((side * 0.35, 0.12 + asym_y, 0.99 + asym_z), 0.044, 0.048),
            f"wrist_{s}": ((side * 0.33, 0.22 + asym_y, 0.77 + asym_z), 0.036, 0.040),
            f"palm_{s}": ((side * 0.32, 0.26 + asym_y, 0.67 + asym_z), 0.054, 0.030),
            # 4 articulated splayed finger knuckles & mid-phalanges (multi-segment talons added in bone mat!)
            f"kn1_{s}": ((side * 0.27, 0.29 + asym_y, 0.61 + asym_z), 0.013, 0.013),
            f"mid1_{s}": ((side * 0.25, 0.33 + asym_y, 0.54 + asym_z), 0.009, 0.009),
            f"kn2_{s}": ((side * 0.31, 0.30 + asym_y, 0.60 + asym_z), 0.014, 0.014),
            f"mid2_{s}": ((side * 0.30, 0.34 + asym_y, 0.52 + asym_z), 0.009, 0.009),
            f"kn3_{s}": ((side * 0.35, 0.29 + asym_y, 0.60 + asym_z), 0.013, 0.013),
            f"mid3_{s}": ((side * 0.35, 0.33 + asym_y, 0.53 + asym_z), 0.009, 0.009),
            f"kn4_{s}": ((side * 0.38, 0.26 + asym_y, 0.62 + asym_z), 0.012, 0.012),
            f"mid4_{s}": ((side * 0.40, 0.29 + asym_y, 0.56 + asym_z), 0.008, 0.008),
            # Bowed gaunt legs with hollowed calves
            f"hip_{s}": ((side * 0.145, 0.0, 0.98), 0.094, 0.094),
            f"thigh_{s}": ((side * 0.175, 0.04, 0.75), 0.072, 0.076),
            f"knee_{s}": ((side * 0.185, 0.08, 0.52), 0.068, 0.072),
            f"calf_{s}": ((side * 0.165, 0.01, 0.32), 0.050, 0.058),
            f"ankle_{s}": ((side * 0.155, -0.03, 0.09), 0.038, 0.042),
            f"foot_{s}": ((side * 0.165, 0.14, 0.038), 0.054, 0.032),
            f"heel_{s}": ((side * 0.155, -0.09, 0.038), 0.040, 0.032),
        })
        edges_spec.extend([
            ("thorax_up", f"clav_{s}"),
            (f"clav_{s}", f"shld_{s}"),
            (f"shld_{s}", f"bicep_{s}"),
            (f"bicep_{s}", f"elbow_{s}"),
            (f"elbow_{s}", f"fore_{s}"),
            (f"fore_{s}", f"wrist_{s}"),
            (f"wrist_{s}", f"palm_{s}"),
            (f"palm_{s}", f"kn1_{s}"), (f"kn1_{s}", f"mid1_{s}"),
            (f"palm_{s}", f"kn2_{s}"), (f"kn2_{s}", f"mid2_{s}"),
            (f"palm_{s}", f"kn3_{s}"), (f"kn3_{s}", f"mid3_{s}"),
            (f"palm_{s}", f"kn4_{s}"), (f"kn4_{s}", f"mid4_{s}"),
            ("pelvis", f"hip_{s}"),
            (f"hip_{s}", f"thigh_{s}"),
            (f"thigh_{s}", f"knee_{s}"),
            (f"knee_{s}", f"calf_{s}"),
            (f"calf_{s}", f"ankle_{s}"),
            (f"ankle_{s}", f"foot_{s}"),
            (f"ankle_{s}", f"heel_{s}"),
        ])

    keys = list(nodes_spec.keys())
    idx_map = {k: i for i, k in enumerate(keys)}
    mesh.from_pydata([nodes_spec[k][0] for k in keys], [(idx_map[a], idx_map[b]) for a, b in edges_spec], [])
    mesh.update()

    skin_mod = body_obj.modifiers.new(name="Skin", type="SKIN")
    skin_mod.use_smooth_shade = True
    for i, k in enumerate(keys):
        _, rx, ry = nodes_spec[k]
        body_obj.data.skin_vertices[0].data[i].radius = (rx, ry)
    body_obj.data.skin_vertices[0].data[idx_map["pelvis"]].use_root = True

    sub_mod = body_obj.modifiers.new(name="Subsurf", type="SUBSURF")
    sub_mod.levels = 2
    sub_mod.render_levels = 2

    tex_disp = bpy.data.textures.new("MuscleClouds", type="CLOUDS")
    tex_disp.noise_scale = 0.095
    tex_disp.noise_depth = 3
    disp = body_obj.modifiers.new(name="MuscleDisp", type="DISPLACE")
    disp.texture = tex_disp
    disp.strength = 0.012

    apply_modifiers_and_uv(body_obj, mat_flesh, tex_repeat=2.2)

    # 2. Anatomical Vertex Sculpting Pass on Subdivided Mesh (gaunt waist, deep ribs, sternal scar, scapulae, hollowed limbs)
    for v in body_obj.data.vertices:
        co = v.co
        # Emaciated concave abdominal hollow & protruding lower costal V-arch
        if 1.13 < co.z < 1.46 and co.y > 0.01 and abs(co.x) < 0.15:
            belly_factor = math.sin(((co.z - 1.13) / 0.33) * math.pi)
            center_factor = max(0.0, 1.0 - abs(co.x) / 0.15)
            co.y -= 0.042 * belly_factor * center_factor
        # Deep intercostal rib grooves across lateral & anterior thorax
        if 1.40 < co.z < 1.66 and co.y > -0.03 and 0.035 < abs(co.x) < 0.22:
            groove = max(0.0, -math.sin((co.z - 1.40) / 0.043 * math.tau))
            lat = math.sin(min(1.0, (abs(co.x) - 0.035) / 0.185) * math.pi)
            co.x -= math.copysign(0.011 * groove * lat, co.x)
            co.y -= 0.008 * groove * lat
        # Sternum surgical incision furrow & raised scarred wound lips
        if 1.38 < co.z < 1.70 and co.y > 0.11 and abs(co.x) < 0.045:
            ax = abs(co.x)
            if ax < 0.014:
                co.y -= 0.022 * (1.0 - ax / 0.014)
            elif ax < 0.034:
                co.y += 0.006 * math.sin(((ax - 0.014) / 0.020) * math.pi)
        # Sharper protruding shoulder blades (scapulae) on upper back
        if 1.48 < co.z < 1.73 and co.y < 0.03 and 0.06 < abs(co.x) < 0.21:
            scap = math.sin(((abs(co.x) - 0.06) / 0.15) * math.pi) * math.sin(((co.z - 1.48) / 0.25) * math.pi)
            co.y -= 0.038 * (scap ** 0.85)
        # Gaunt hollowed calves (carve lateral/medial flanks, keep anterior shin ridge)
        if 0.14 < co.z < 0.45 and 0.11 < abs(co.x) < 0.22:
            calf_env = math.sin(((co.z - 0.14) / 0.31) * math.pi)
            if co.y < 0.04:
                co.x -= math.copysign(0.010 * calf_env, co.x)
            else:
                co.y += 0.007 * calf_env
        # Gaunt hollowed forearms (carve soft tissue between radius/ulna)
        if 0.81 < co.z < 1.16 and abs(co.x) > 0.29:
            fore_env = math.sin(((co.z - 0.81) / 0.35) * math.pi)
            co.x -= math.copysign(0.008 * fore_env, co.x)
        # Sunken hollow cheeks & deeper/wider dark oral concavity on front lower face (+Y)
        if 1.86 < co.z < 2.02 and co.y > 0.25:
            if 0.042 < abs(co.x) < 0.115:
                co.y -= 0.026 * (1.0 - abs(abs(co.x) - 0.078) / 0.037)
        if 1.82 < co.z < 1.98 and co.y > 0.26 and abs(co.x) < 0.084:
            # Push mouth area backward to carve space for the pitch-black maw abyss
            co.y -= 0.058 * (1.0 - abs(co.x) / 0.084)

    body_obj.data.update()

    # Cleanly decimate sculpted base body BEFORE sampling sternum & rigging so skin weights remain 100% clean
    dec_mod = body_obj.modifiers.new(name="MobileDecimate", type="DECIMATE")
    dec_mod.decimate_type = "COLLAPSE"
    dec_mod.ratio = 0.36
    bpy.context.view_layer.objects.active = body_obj
    body_obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=dec_mod.name)
    body_obj.select_set(False)
    body_obj.data.validate()

    # Sample front sternum surface Y along center chest so incision & surgical staples sit flush
    def sample_chest_front_y(z_target: float) -> float:
        best_y = 0.18
        best_d = 999.0
        for v in body_obj.data.vertices:
            if abs(v.co.x) < 0.028 and v.co.y > 0.10:
                d = abs(v.co.z - z_target)
                if d < best_d:
                    best_d = d
                    best_y = v.co.y
        return best_y

    # 3. Build Secondary & Tertiary Sculpted Details with EXACT Material Tagging
    detail_items = []

    def push_part(name: str, bm_part: bmesh.types.BMesh, mat_part, tex_rep: float = 2.0, continuous_uv: bool = False):
        obj = create_detail_obj(name, bm_part, tex_repeat=tex_rep, continuous_uv=continuous_uv)
        detail_items.append((obj, mat_part))
        return obj

    # A) Jutting Anatomical Ribcage Arches (6 pairs wrapping lateral-to-anterior thorax cleanly without poking scapulae)
    bm_ribs = bmesh.new()
    for ri in range(6):
        rz = 1.38 + ri * 0.044
        width = 0.124 + math.sin((ri / 5.0) * math.pi * 0.85) * 0.052
        depth = 0.098 + math.sin((ri / 5.0) * math.pi * 0.85) * 0.024
        cy = 0.068 + ri * 0.007
        for side in (-1, 1):
            rib_pts = []
            for k in range(6):
                t = k / 5.0
                ang = 0.45 + t * 2.02
                px = side * math.sin(ang) * width
                py = cy - math.cos(ang) * depth
                pz = rz + (0.010 if t < 0.3 else -t * 0.024)
                # Taper ends smoothly inside the flesh so no sharp cut-ends protrude
                end_taper = math.sin(max(0.08, min(0.92, t)) * math.pi)
                rad = (0.0050 + end_taper * 0.0068)
                rib_pts.append((Vector((px, py, pz)), rad * 0.72, rad * 1.15))
            add_tube_along_points(bm_ribs, rib_pts, segs=5)
    push_part("Ribs", bm_ribs, mat_flesh, 2.4, continuous_uv=True)

    # A2) Protruding Collarbones (Clavicles) & Taut Neck Tendons
    bm_clav = bmesh.new()
    for side in (-1, 1):
        asym_z = -0.025 if side == -1 else 0.0
        asym_y = 0.025 if side == 1 else 0.0
        clav_pts = [
            (Vector((side * 0.022, 0.188, 1.695)), 0.013, 0.012),
            (Vector((side * 0.095, 0.175 + asym_y * 0.2, 1.712 + asym_z * 0.3)), 0.011, 0.010),
            (Vector((side * 0.175, 0.145 + asym_y * 0.3, 1.705 + asym_z * 0.5)), 0.012, 0.011),
            (Vector((side * 0.235, 0.112 + asym_y * 0.4, 1.685 + asym_z * 0.7)), 0.014, 0.012),
        ]
        add_tube_along_points(bm_clav, clav_pts, segs=5)
    push_part("Clavicles", bm_clav, mat_flesh, 2.4, continuous_uv=True)

    bm_tendons = bmesh.new()
    for side in (-1, 1):
        # Anterior sternocleidomastoid cord from behind ear down to sternal notch
        scm_pts = [
            (Vector((side * 0.088, 0.228, 1.965)), 0.012, 0.012),
            (Vector((side * 0.068, 0.226, 1.885)), 0.010, 0.011),
            (Vector((side * 0.044, 0.214, 1.800)), 0.011, 0.012),
            (Vector((side * 0.022, 0.194, 1.715)), 0.012, 0.011),
        ]
        add_tube_along_points(bm_tendons, scm_pts, segs=4)
        # Posterior nuchal cord from skull base down to upper scapula/spine
        nuchal_pts = [
            (Vector((side * 0.042, 0.165, 1.975)), 0.013, 0.013),
            (Vector((side * 0.056, 0.135, 1.870)), 0.014, 0.014),
            (Vector((side * 0.072, 0.078, 1.755)), 0.015, 0.014),
        ]
        add_tube_along_points(bm_tendons, nuchal_pts, segs=4)
    push_part("NeckTendons", bm_tendons, mat_flesh, 2.4, continuous_uv=True)

    # A3) Sternal Surgical Incision Seam & 11 Metallic Surgical Staples
    bm_incision = bmesh.new()
    inc_pts = []
    for k in range(8):
        iz = 1.39 + (k / 7.0) * 0.29
        iy = sample_chest_front_y(iz) + 0.002
        ix = math.sin(k * 1.4) * 0.003
        inc_pts.append((Vector((ix, iy, iz)), 0.007, 0.004))
    add_tube_along_points(bm_incision, inc_pts, segs=4)
    push_part("SurgicalIncision", bm_incision, mat_rag, 2.4, continuous_uv=True)

    bm_staples = bmesh.new()
    for si in range(11):
        sz = 1.40 + si * 0.027
        sy = sample_chest_front_y(sz)
        tilt = (0.08 if si % 2 == 0 else -0.08)
        st_pts = [
            (Vector((-0.018, sy - 0.006, sz - tilt * 0.03)), 0.0024, 0.0024),
            (Vector((-0.015, sy + 0.009, sz - tilt * 0.02)), 0.0026, 0.0026),
            (Vector((0.0, sy + 0.012, sz)), 0.0026, 0.0026),
            (Vector((0.015, sy + 0.009, sz + tilt * 0.02)), 0.0026, 0.0026),
            (Vector((0.018, sy - 0.006, sz + tilt * 0.03)), 0.0024, 0.0024),
        ]
        add_tube_along_points(bm_staples, st_pts, segs=3)
    push_part("SurgicalStaples", bm_staples, mat_iron, 2.5, continuous_uv=True)

    # B) Protruding Dorsal Spine Vertebrae (9 sharp hunched spinous processes rooted cleanly inside spine)
    bm_spine = bmesh.new()
    spine_pts_z = [1.14, 1.22, 1.30, 1.38, 1.46, 1.54, 1.62, 1.70, 1.77]
    spine_pts_y = [-0.075, -0.092, -0.095, -0.084, -0.065, -0.044, -0.012, 0.032, 0.095]
    for si, (sy, sz) in enumerate(zip(spine_pts_y, spine_pts_z)):
        ln = 0.056 + (0.028 if 3 <= si <= 7 else 0.0)
        pts = [
            (Vector((0.0, sy + 0.050, sz + 0.012)), 0.020, 0.024),
            (Vector((0.0, sy - ln * 0.55, sz - 0.004)), 0.012, 0.016),
            (Vector((0.0, sy - ln, sz - 0.018)), 0.0035, 0.005),
        ]
        add_tube_along_points(bm_spine, pts, segs=4)
    push_part("SpineVertebrae", bm_spine, mat_flesh, 2.4, continuous_uv=True)

    # C) Longer Multi-Segmented Gnarled Bone Talons on 8 fingers + thumb spurs + toe claws
    bm_talons = bmesh.new()
    for side in (-1, 1):
        asym_z = -0.025 if side == -1 else 0.0
        asym_y = 0.025 if side == 1 else 0.0
        finger_bases = [
            Vector((side * 0.25, 0.33 + asym_y, 0.54 + asym_z)),
            Vector((side * 0.30, 0.34 + asym_y, 0.52 + asym_z)),
            Vector((side * 0.35, 0.33 + asym_y, 0.53 + asym_z)),
            Vector((side * 0.40, 0.29 + asym_y, 0.56 + asym_z)),
        ]
        for fi, fb in enumerate(finger_bases):
            hook_in = -side * (0.030 + fi * 0.004)
            knuckle_wobble = (0.008 if fi % 2 == 0 else -0.008)
            pts = [
                (fb, 0.010, 0.010),
                (fb + Vector((knuckle_wobble, 0.022, -0.032)), 0.009, 0.009),
                (fb + Vector((hook_in * 0.45, 0.044, -0.074)), 0.0065, 0.0075),
                (fb + Vector((hook_in * 1.15, 0.056, -0.128)), 0.0014, 0.0014),
            ]
            add_tube_along_points(bm_talons, pts, segs=4)
        # Inner gnarled thumb dewclaw talon
        thumb_b = Vector((side * 0.26, 0.28 + asym_y, 0.65 + asym_z))
        add_tube_along_points(bm_talons, [
            (thumb_b, 0.010, 0.010),
            (thumb_b + Vector((-side * 0.024, 0.026, -0.026)), 0.0065, 0.0065),
            (thumb_b + Vector((-side * 0.042, 0.034, -0.068)), 0.0015, 0.0015),
        ], segs=4)
        # Hooked toe talons
        for tx in (side * 0.132, side * 0.165, side * 0.195):
            t_base = Vector((tx, 0.18, 0.034))
            add_tube_along_points(bm_talons, [
                (t_base, 0.009, 0.008),
                (t_base + Vector((0.0, 0.032, 0.004)), 0.006, 0.006),
                (t_base + Vector((0.0, 0.062, -0.014)), 0.0016, 0.0016),
            ], segs=4)
    push_part("Talons", bm_talons, mat_bone, 1.0, continuous_uv=True)

    # D) Soviet Acoustic-Containment Iron Blind-Visor & Bolted Cranial Cage + Recessed Slit
    head_c = Vector((0.0, 0.275, 2.025))
    bm_cage = bmesh.new()
    add_curved_visor_band(bm_cage, head_c, 0.115, 0.136, -1.28, 1.28, 2.044, 2.092, 0.017, arc_steps=12)
    add_curved_visor_band(bm_cage, head_c, 0.115, 0.136, -1.28, 1.28, 1.984, 2.026, 0.017, arc_steps=12)
    add_curved_visor_band(bm_cage, head_c, 0.106, 0.126, -1.22, 1.22, 2.020, 2.052, 0.010, arc_steps=10)
    # Center iron nose bridge + brow rivets + side hinge plates + temple hex bolts
    add_box_bm(bm_cage, (0.028, 0.024, 0.114), (0.0, 0.422, 2.038))
    for rx in (-0.072, -0.036, 0.036, 0.072):
        add_cyl_bm(bm_cage, 0.007, 0.007, 0.014, Vector((rx, 0.275 + math.cos(rx * 5.0) * 0.148, 2.072)), Euler((1.57, 0, -rx * 4.0)), segs=5)
    for side in (-1, 1):
        add_box_bm(bm_cage, (0.024, 0.056, 0.114), (side * 0.124, 0.312, 2.038), Euler((0, 0, side * 0.28)))
        for bz in (2.002, 2.072):
            add_cyl_bm(bm_cage, 0.012, 0.012, 0.026, Vector((side * 0.134, 0.305, bz)), Euler((0, math.pi * 0.5, 0)), segs=6)
    # Crown & occipital skull cage straps (snug against cranium)
    add_curved_visor_band(bm_cage, Vector((0.0, 0.26, 2.03)), 0.110, 0.128, math.pi * 0.5, math.pi * 1.5, 1.995, 2.040, 0.012, arc_steps=10)
    crown_pts = []
    for k in range(7):
        t = k / 6.0
        a = -0.25 + t * (math.pi + 0.5)
        crown_pts.append((Vector((0.0, 0.262 + math.cos(a) * 0.130, 2.042 + math.sin(a) * 0.138)), 0.012, 0.007))
    add_tube_along_points(bm_cage, crown_pts, segs=4)
    push_part("CranialCage", bm_cage, mat_iron, 2.5)

    # Recessed dual sinister crimson-amber sensor slits inside the visor slot
    bm_slit = bmesh.new()
    for side in (-1, 1):
        a0 = 0.14 if side == 1 else -0.82
        a1 = 0.82 if side == 1 else -0.14
        add_curved_visor_band(bm_slit, head_c, 0.112, 0.132, a0, a1, 2.029, 2.041, 0.008, arc_steps=5)
    push_part("VisorSlit", bm_slit, mat_glow, 1.0, continuous_uv=True)

    # D2) Asymmetrical Bolted Soviet Acoustic-Ear Amplifier Cups / Parabolic Listening Plates + Coiled Wires to Collar!
    bm_ears = bmesh.new()
    # Left (-X): Larger flared parabolic acoustic dish angled outward & forward
    l_ear_c = Vector((-0.128, 0.265, 2.026))
    l_ear_dir = Vector((-0.92, 0.36, 0.08))
    add_parabolic_ear_cup(
        bm_ears, l_ear_c, l_ear_dir, outer_r=0.080, depth=0.060,
        baffle_rings=2, cross_bars=False, ring_steps=12, rib_steps=10, rib_segs=4, needle_segs=5, bar_segs=4,
    )
    # Clamping bracket & bolts attaching left ear cup to cranial cage
    add_box_bm(bm_ears, (0.032, 0.038, 0.095), (-0.122, 0.278, 2.026), Euler((0, 0, -0.22)))
    add_cyl_bm(bm_ears, 0.012, 0.012, 0.028, Vector((-0.132, 0.260, 1.960)), Euler((0.2, 0, 0)), segs=6)

    # Right (+X): Asymmetrical smaller, higher-mounted acoustic horn plate with protective cross-bars!
    r_ear_c = Vector((0.124, 0.254, 2.044))
    r_ear_dir = Vector((0.90, 0.40, -0.06))
    add_parabolic_ear_cup(
        bm_ears, r_ear_c, r_ear_dir, outer_r=0.066, depth=0.052,
        baffle_rings=1, cross_bars=True, ring_steps=12, rib_steps=10, rib_segs=4, needle_segs=5, bar_segs=4,
    )
    add_box_bm(bm_ears, (0.030, 0.034, 0.088), (0.118, 0.270, 2.040), Euler((0, 0, 0.22)))
    add_cyl_bm(bm_ears, 0.011, 0.011, 0.026, Vector((0.128, 0.252, 1.980)), Euler((0.2, 0, 0)), segs=6)
    push_part("AcousticEars", bm_ears, mat_iron, 2.5)

    # Coiled wires running from BOTH acoustic ear cups into bolted junction lugs on the neck collar
    bm_wires = bmesh.new()
    add_helical_coil(
        bm_wires,
        Vector((-0.132, 0.258, 1.954)),
        Vector((-0.098, 0.205, 1.805)),
        turns=6.0,
        coil_radius=0.011,
        wire_radius=0.0034,
        bow_offset=Vector((-0.024, 0.008, 0.0)),
        steps=24,
        segs=4,
    )
    add_helical_coil(
        bm_wires,
        Vector((0.128, 0.250, 1.974)),
        Vector((0.098, 0.202, 1.805)),
        turns=5.5,
        coil_radius=0.010,
        wire_radius=0.0034,
        bow_offset=Vector((0.022, 0.004, 0.0)),
        steps=24,
        segs=4,
    )
    push_part("AcousticWires", bm_wires, mat_strap, 2.0, continuous_uv=True)

    # E) Pitch-Black Recessed Oral Maw Abyss + Sinewy Cheek Tendons + Distended Split Lower Mandible + Double-Row Fangs
    bm_maw = bmesh.new()
    ret = bmesh.ops.create_icosphere(bm_maw, subdivisions=1, radius=0.062)
    bmesh.ops.scale(bm_maw, vec=(1.06, 0.90, 1.18), verts=ret["verts"])
    bmesh.ops.translate(bm_maw, vec=(0.0, 0.274, 1.882), verts=ret["verts"])
    push_part("MawAbyss", bm_maw, mat_maw, 1.0, continuous_uv=True)

    # Split Distended Lower Mandible (left & right jaw rami hinged to a gruesome cleft chin)
    bm_jaw = bmesh.new()
    for side in (-1, 1):
        ramus = [
            (Vector((side * 0.092, 0.252, 1.958)), 0.018, 0.020),
            (Vector((side * 0.078, 0.286, 1.866)), 0.016, 0.019),
            (Vector((side * 0.048, 0.346, 1.798)), 0.015, 0.017),
            (Vector((side * 0.015, 0.376, 1.778)), 0.011, 0.014),
        ]
        add_tube_along_points(bm_jaw, ramus, segs=5)
    push_part("SplitJaw", bm_jaw, mat_flesh, 2.2, continuous_uv=True)

    # Dark Sinewy Cheek Tendons stretching taut between upper skull maxilla & distended lower mandible
    bm_cheek = bmesh.new()
    for side in (-1, 1):
        tendon_specs = [
            (Vector((side * 0.088, 0.290, 1.968)), Vector((side * 0.072, 0.312, 1.832)), 0.008),
            (Vector((side * 0.076, 0.314, 1.962)), Vector((side * 0.056, 0.336, 1.816)), 0.006),
            (Vector((side * 0.096, 0.268, 1.960)), Vector((side * 0.080, 0.282, 1.856)), 0.007),
        ]
        for p_top, p_bot, r_t in tendon_specs:
            mid = p_top.lerp(p_bot, 0.5) + Vector((-side * 0.008, -0.012, 0.0))
            add_tube_along_points(bm_cheek, [
                (p_top, r_t * 1.25, r_t * 1.25),
                (mid, r_t * 0.72, r_t * 0.85),
                (p_bot, r_t * 1.15, r_t * 1.15),
            ], segs=4)
    push_part("CheekTendons", bm_cheek, mat_rag, 2.0, continuous_uv=True)

    # Double-Row Crooked Bone Fangs (outer jagged fangs + recessed inner needle fangs)
    # Kept split into upper (Head) and lower (Jaw) meshes so jaw articulation never stretches fangs!
    bm_teeth_upper = bmesh.new()
    bm_teeth_lower = bmesh.new()
    for ti in range(-4, 5):
        ang = ti * 0.20
        # Outer upper fangs
        ux = math.sin(ang) * 0.074
        uy = 0.298 + math.cos(ang) * 0.078
        flen_u = 0.038 + (0.016 if abs(ti) in (1, 3) else 0.005)
        tilt_u = ti * 0.055
        add_tube_along_points(bm_teeth_upper, [
            (Vector((ux, uy, 1.950)), 0.0078, 0.0078),
            (Vector((ux * 0.96, uy + 0.004, 1.950 - flen_u * 0.55)), 0.0045, 0.0045),
            (Vector((ux * 0.88 + tilt_u * 0.06, uy - 0.005, 1.950 - flen_u)), 0.0011, 0.0011),
        ], segs=4)

        # Inner row upper needle teeth
        if abs(ti) <= 3:
            ix = math.sin(ang * 0.95) * 0.056
            iy = 0.292 + math.cos(ang * 0.95) * 0.062
            flen_iu = 0.026 + (0.010 if abs(ti) == 2 else 0.002)
            add_tube_along_points(bm_teeth_upper, [
                (Vector((ix, iy, 1.946)), 0.0045, 0.0045),
                (Vector((ix * 0.92, iy - 0.008, 1.946 - flen_iu)), 0.0009, 0.0009),
            ], segs=3)

        if ti == 0:
            continue  # Leave gruesome split cleft gap right at the center!
        split_ofs = 0.008 if ti > 0 else -0.008
        lx = math.sin(ang) * 0.068 + split_ofs
        ly = 0.314 + math.cos(ang) * 0.078
        lz = 1.796 + abs(ti) * 0.010
        flen_l = 0.036 + (0.014 if abs(ti) == 2 else 0.003)
        add_tube_along_points(bm_teeth_lower, [
            (Vector((lx, ly, lz)), 0.0070, 0.0070),
            (Vector((lx * 0.96, ly + 0.002, lz + flen_l * 0.55)), 0.0042, 0.0042),
            (Vector((lx * 0.90, ly - 0.007, lz + flen_l)), 0.0011, 0.0011),
        ], segs=4)

        # Inner row lower needle teeth
        if abs(ti) <= 3:
            ilx = math.sin(ang * 0.92) * 0.052 + split_ofs * 0.7
            ily = 0.308 + math.cos(ang * 0.92) * 0.062
            ilz = lz + 0.005
            flen_il = 0.024 + (0.008 if abs(ti) == 1 else 0.002)
            add_tube_along_points(bm_teeth_lower, [
                (Vector((ilx, ily, ilz)), 0.0042, 0.0042),
                (Vector((ilx * 0.92, ily - 0.007, ilz + flen_il)), 0.0009, 0.0009),
            ], segs=3)
    push_part("FangsUpper", bm_teeth_upper, mat_bone, 1.0, continuous_uv=True)
    push_part("FangsLower", bm_teeth_lower, mat_bone, 1.0, continuous_uv=True)

    # F) Heavy Containment Decay: Bolted Neck Collar, Harness Plates, Broken Shackles + Multi-Link Chains
    bm_iron_hw = bmesh.new()
    # Neck Collar + ear-wire junction lugs + side bolts
    neck_c = Vector((0.0, 0.19, 1.795))
    add_curved_visor_band(bm_iron_hw, neck_c, 0.084, 0.090, 0.0, math.tau, 1.772, 1.828, 0.020, arc_steps=12)
    for side in (-1, 1):
        add_box_bm(bm_iron_hw, (0.028, 0.036, 0.058), (side * 0.100, 0.19, 1.80))
        # Terminal lug for acoustic ear cable
        add_cyl_bm(bm_iron_hw, 0.012, 0.012, 0.024, Vector((side * 0.098, 0.205, 1.812)), Euler((0, side * 1.1, 0)), segs=6)
    # Chest hanging broken shackle ring + 4-link chain from front collar D-ring
    add_chain_link(bm_iron_hw, Vector((0.0, 0.292, 1.778)), Euler((0.2, 0.0, 0.0)), major_rx=0.020, major_ry=0.024, wire_r=0.0065, ring_pts=8, tube_segs=4)
    for ci in range(4):
        c_pos = Vector((math.sin(ci * 0.4) * 0.008, 0.286 - ci * 0.014, 1.736 - ci * 0.042))
        c_rot = Euler((0.26, 0.0, math.pi * 0.5 if ci % 2 == 1 else 0.0))
        add_chain_link(bm_iron_hw, c_pos, c_rot, major_rx=0.018, major_ry=0.028, wire_r=0.0055, ring_pts=8, tube_segs=4)

    # Bolted iron harness buckles & shoulder strap anchor plates
    add_box_bm(bm_iron_hw, (0.068, 0.026, 0.052), (0.0, 0.184, 1.465))
    add_box_bm(bm_iron_hw, (0.058, 0.024, 0.048), (0.0, 0.112, 1.032))
    for side in (-1, 1):
        add_box_bm(bm_iron_hw, (0.044, 0.032, 0.052), (side * 0.128, 0.095, 1.705), Euler((0.25, side * 0.2, 0)))

    # Heavy Wrist Manacles + Broken Shackle Rings + 4-link Dangling Broken Chains
    for side in (-1, 1):
        asym_z = -0.025 if side == -1 else 0.0
        asym_y = 0.025 if side == 1 else 0.0
        wc = Vector((side * 0.33, 0.22 + asym_y, 0.77 + asym_z))
        add_curved_visor_band(bm_iron_hw, wc, 0.044, 0.048, 0.0, math.tau, wc.z - 0.028, wc.z + 0.028, 0.015, arc_steps=10)
        add_box_bm(bm_iron_hw, (0.022, 0.028, 0.054), wc + Vector((side * 0.054, 0.0, 0.0)))
        for ci in range(4):
            ch_pos = wc + Vector((side * 0.058, 0.014 - ci * 0.008, -0.040 - ci * 0.040))
            ch_rot = Euler((0.08, side * 0.15, math.pi * 0.5 if ci % 2 == 1 else 0.0))
            add_chain_link(bm_iron_hw, ch_pos, ch_rot, major_rx=0.016, major_ry=0.026, wire_r=0.0052, ring_pts=8, tube_segs=4)

    # Right Ankle Shackle + 3-link broken trailing chain (stays safely above z = 0.03)
    ac = Vector((0.155, -0.025, 0.135))
    add_curved_visor_band(bm_iron_hw, ac, 0.044, 0.048, 0.0, math.tau, ac.z - 0.024, ac.z + 0.024, 0.014, arc_steps=10)
    for ci in range(3):
        a_pos = ac + Vector((0.054 + ci * 0.014, -0.02 - ci * 0.028, -0.032 - ci * 0.026))
        a_rot = Euler((0.65, 0.2, math.pi * 0.5 if ci % 2 == 1 else 0.0))
        add_chain_link(bm_iron_hw, a_pos, a_rot, major_rx=0.015, major_ry=0.024, wire_r=0.0048, ring_pts=8, tube_segs=4)
    push_part("RestraintIron", bm_iron_hw, mat_iron, 2.5, continuous_uv=True)

    # Heavy Leather-Iron Containment Harness Straps (routed cleanly outside back scapulae!)
    bm_straps = bmesh.new()
    chest_band = []
    for k in range(13):
        a = (k / 12.0) * math.tau
        chest_band.append((Vector((math.sin(a) * 0.176, 0.052 + math.cos(a) * 0.134, 1.47)), 0.014, 0.018))
    add_tube_along_points(bm_straps, chest_band, segs=4, cap_start=False, cap_end=False)
    for side in (-1, 1):
        strap_pts = [
            (Vector((side * 0.095, 0.150, 1.46)), 0.019, 0.008),
            (Vector((side * 0.120, 0.140, 1.59)), 0.019, 0.008),
            (Vector((side * 0.132, 0.088, 1.708)), 0.019, 0.008),
            (Vector((side * 0.126, -0.048, 1.65)), 0.019, 0.008),
            (Vector((side * 0.105, -0.070, 1.47)), 0.019, 0.008),
        ]
        add_tube_along_points(bm_straps, strap_pts, segs=4)
    waist_band = []
    for k in range(13):
        a = (k / 12.0) * math.tau
        waist_band.append((Vector((math.sin(a) * 0.144, 0.0 + math.cos(a) * 0.104, 1.03)), 0.013, 0.015))
    add_tube_along_points(bm_straps, waist_band, segs=4, cap_start=False, cap_end=False)
    push_part("SurgicalStraps", bm_straps, mat_strap, 2.2, continuous_uv=True)

    # Asymmetric Tattered Bloodied Containment Rags draping smoothly from waist
    bm_rags = bmesh.new()
    waist_wrap = []
    for k in range(13):
        a = (k / 12.0) * math.tau
        waist_wrap.append((Vector((math.sin(a) * 0.136, math.cos(a) * 0.096, 1.005)), 0.006, 0.024))
    add_tube_along_points(bm_rags, waist_wrap, segs=4, cap_start=False, cap_end=False)
    rag_defs = [
        (-0.132, 0.062, 0.42, -0.030, 0.072, 0.056),
        (-0.062, 0.090, 0.28, -0.008, 0.082, 0.054),
        ( 0.025, 0.092, 0.36,  0.008, 0.080, 0.058),
        ( 0.110, 0.078, 0.24,  0.022, 0.068, 0.050),
        ( 0.140, 0.005, 0.37,  0.028, 0.012, 0.054),
        ( 0.105,-0.082, 0.44,  0.016,-0.076, 0.060),
        (-0.005,-0.092, 0.32, -0.006,-0.084, 0.064),
        (-0.122,-0.062, 0.39, -0.024,-0.068, 0.056),
    ]
    for rx, ry, rlen, flare_x, end_y, w_strip in rag_defs:
        pts = [
            (Vector((rx * 0.94, ry * 0.94, 1.010)), w_strip, 0.0045),
            (Vector((rx + flare_x * 0.45, (ry + end_y) * 0.55, 1.010 - rlen * 0.45)), w_strip * 0.82, 0.0040),
            (Vector((rx + flare_x, end_y, 1.010 - rlen)), 0.010, 0.0035),
        ]
        add_tube_along_points(bm_rags, pts, segs=4)
    push_part("TornGarmentRags", bm_rags, mat_rag, 2.2, continuous_uv=True)

    # 4. Create Fully Articulated Horror Armature (MonsterArmature) & Bind Watertight Body First
    arm_data = bpy.data.armatures.new("MonsterArmature")
    arm_obj = bpy.data.objects.new("MonsterRig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def add_bone(bname, head, tail, parent_name=None, roll_axis=(0.0, 1.0, 0.0), use_deform=True):
        b = eb.new(bname)
        b.head = Vector(head)
        b.tail = Vector(tail)
        b.align_roll(Vector(roll_axis))
        b.use_deform = use_deform
        if parent_name:
            b.parent = eb[parent_name]
        return b

    # Spine/Neck/Head z_axis aligned to +Y_world (forward) so +X rotation pitches forward!
    # Jaw z_axis aligned to -Z_world so +X rotation hinges the split jaw wide OPEN!
    # Arms/Legs z_axis aligned to +Y_world so +X rotation swings limb forward; Foot z_axis +Z_world so +X pitches toe UP!
    add_bone("Root", (0, 0, 0), (0, 0, 0.35), None, (0.0, 1.0, 0.0), use_deform=False)
    add_bone("Pelvis", (0, 0, 1.00), (0, -0.01, 1.15), "Root", (0.0, 1.0, 0.0))
    add_bone("SpineLow", (0, -0.01, 1.15), (0, -0.01, 1.33), "Pelvis", (0.0, 1.0, 0.0))
    add_bone("SpineMid", (0, -0.01, 1.33), (0, 0.06, 1.53), "SpineLow", (0.0, 1.0, 0.0))
    add_bone("SpineUpper", (0, 0.06, 1.53), (0, 0.16, 1.76), "SpineMid", (0.0, 1.0, 0.0))
    add_bone("Neck", (0, 0.16, 1.76), (0, 0.24, 1.94), "SpineUpper", (0.0, 1.0, 0.0))
    add_bone("Head", (0, 0.24, 1.94), (0, 0.27, 2.18), "Neck", (0.0, 1.0, 0.0))
    add_bone("Jaw", (0, 0.25, 1.955), (0, 0.376, 1.780), "Head", (0.0, 0.0, -1.0))

    for side, s in ((-1, "L"), (1, "R")):
        asym_z = -0.025 if side == -1 else 0.0
        asym_y = 0.025 if side == 1 else 0.0
        sh_head = (side * 0.06, 0.12, 1.69)
        sh_tail = (side * 0.26, 0.09 + asym_y * 0.4, 1.66 + asym_z)
        elb_pt = (side * 0.37, 0.03 + asym_y, 1.22 + asym_z)
        wrs_pt = (side * 0.33, 0.22 + asym_y, 0.77 + asym_z)
        hnd_pt = (side * 0.31, 0.32 + asym_y, 0.54 + asym_z)
        add_bone(f"Shoulder.{s}", sh_head, sh_tail, "SpineUpper", (0.0, 1.0, 0.0))
        add_bone(f"UpperArm.{s}", sh_tail, elb_pt, f"Shoulder.{s}", (0.0, 1.0, 0.0))
        add_bone(f"Forearm.{s}", elb_pt, wrs_pt, f"UpperArm.{s}", (0.0, 1.0, 0.0))
        add_bone(f"Hand.{s}", wrs_pt, hnd_pt, f"Forearm.{s}", (0.0, 1.0, 0.0))

        hip_pt = (side * 0.145, 0.0, 0.98)
        knee_pt = (side * 0.185, 0.08, 0.52)
        ank_pt = (side * 0.155, -0.03, 0.09)
        foot_pt = (side * 0.165, 0.18, 0.03)
        add_bone(f"Thigh.{s}", hip_pt, knee_pt, "Pelvis", (0.0, 1.0, 0.0))
        add_bone(f"Shin.{s}", knee_pt, ank_pt, f"Thigh.{s}", (0.0, 1.0, 0.0))
        add_bone(f"Foot.{s}", ank_pt, foot_pt, f"Shin.{s}", (0.0, 0.0, 1.0))

    bpy.ops.object.mode_set(mode="OBJECT")

    # Disable Jaw deform during ARMATURE_AUTO on body_obj so neck/throat flesh never tears when jaw opens!
    arm_data.bones["Jaw"].use_deform = False
    bpy.ops.object.select_all(action="DESELECT")
    body_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    arm_data.bones["Jaw"].use_deform = True

    # 5. Pre-assign Exact Bone Vertex Groups on Each Detail Object Before Joining!
    def bind_obj_by_fn(obj, weight_fn):
        for v in obj.data.vertices:
            weights = weight_fn(v.co)
            total = sum(weights.values())
            if total <= 1e-6:
                continue
            for bname, w in weights.items():
                if w <= 1e-5:
                    continue
                vg = obj.vertex_groups.get(bname) or obj.vertex_groups.new(name=bname)
                vg.add([v.index], w / total, "REPLACE")

    det_map = {o.name: o for o, _ in detail_items}

    def rib_w(co):
        if co.z >= 1.56:
            return {"SpineUpper": 1.0}
        if co.z >= 1.44:
            t = (co.z - 1.44) / 0.12
            return {"SpineUpper": t, "SpineMid": 1.0 - t}
        if co.z >= 1.35:
            return {"SpineMid": 1.0}
        t = max(0.0, min(1.0, (co.z - 1.30) / 0.05))
        return {"SpineMid": t, "SpineLow": 1.0 - t}

    bind_obj_by_fn(det_map["Ribs"], rib_w)

    def clav_w(co):
        side_s = "L" if co.x < 0 else "R"
        t = max(0.0, min(1.0, (abs(co.x) - 0.05) / 0.18))
        return {f"Shoulder.{side_s}": t, "SpineUpper": 1.0 - t}

    bind_obj_by_fn(det_map["Clavicles"], clav_w)

    def neck_tendon_w(co):
        if co.z <= 1.76:
            return {"SpineUpper": 1.0}
        if co.z < 1.86:
            t = (co.z - 1.76) / 0.10
            return {"Neck": t, "SpineUpper": 1.0 - t}
        if co.z < 1.95:
            t = (co.z - 1.86) / 0.09
            return {"Head": t, "Neck": 1.0 - t}
        return {"Head": 1.0}

    bind_obj_by_fn(det_map["NeckTendons"], neck_tendon_w)

    def chest_seam_w(co):
        if co.z >= 1.56:
            return {"SpineUpper": 1.0}
        if co.z >= 1.44:
            t = (co.z - 1.44) / 0.12
            return {"SpineUpper": t, "SpineMid": 1.0 - t}
        return {"SpineMid": 1.0}

    bind_obj_by_fn(det_map["SurgicalIncision"], chest_seam_w)
    bind_obj_by_fn(det_map["SurgicalStaples"], chest_seam_w)

    def spine_vert_w(co):
        if co.z >= 1.74:
            return {"Neck": 0.65, "SpineUpper": 0.35}
        if co.z >= 1.53:
            return {"SpineUpper": 1.0}
        if co.z >= 1.33:
            return {"SpineMid": 1.0}
        if co.z >= 1.15:
            return {"SpineLow": 1.0}
        return {"Pelvis": 1.0}

    bind_obj_by_fn(det_map["SpineVertebrae"], spine_vert_w)

    bind_obj_by_fn(det_map["Talons"], lambda co: {
        ("Hand.L" if co.x < 0 else "Hand.R") if co.z > 0.30 else ("Foot.L" if co.x < 0 else "Foot.R"): 1.0
    })
    for head_det in ("CranialCage", "VisorSlit", "MawAbyss", "AcousticEars"):
        bind_obj_by_fn(det_map[head_det], lambda co: {"Head": 1.0})

    def acoustic_wire_w(co):
        if co.z <= 1.815:
            return {"Neck": 0.65, "SpineUpper": 0.35}
        if co.z >= 1.945:
            return {"Head": 1.0}
        t = (co.z - 1.815) / 0.130
        return {"Head": t, "Neck": (1.0 - t) * 0.65, "SpineUpper": (1.0 - t) * 0.35}

    bind_obj_by_fn(det_map["AcousticWires"], acoustic_wire_w)

    def cheek_tendon_w(co):
        t = max(0.0, min(1.0, (co.z - 1.83) / 0.12))
        return {"Head": t, "Jaw": 1.0 - t}

    bind_obj_by_fn(det_map["CheekTendons"], cheek_tendon_w)

    def split_jaw_w(co):
        if co.z <= 1.89:
            return {"Jaw": 1.0}
        t = max(0.0, min(1.0, (co.z - 1.89) / 0.06))
        return {"Head": 0.70 * t, "Jaw": 1.0 - 0.70 * t}

    bind_obj_by_fn(det_map["SplitJaw"], split_jaw_w)
    bind_obj_by_fn(det_map["FangsUpper"], lambda co: {"Head": 1.0})
    bind_obj_by_fn(det_map["FangsLower"], lambda co: {"Jaw": 1.0})

    def restraint_iron_w(co):
        if co.z > 1.765 and abs(co.x) < 0.14:
            return {"Neck": 0.65, "SpineUpper": 0.35}
        if co.z > 1.54 and abs(co.x) < 0.22:
            return {"SpineUpper": 1.0}
        if co.z > 1.35 and abs(co.x) < 0.22:
            return {"SpineMid": 1.0}
        if co.z > 0.98 and abs(co.x) < 0.16:
            return {"Pelvis": 1.0}
        if co.z < 0.30:
            return {"Shin.R": 1.0}
        return {"Forearm.L" if co.x < 0 else "Forearm.R": 1.0}

    bind_obj_by_fn(det_map["RestraintIron"], restraint_iron_w)

    def strap_w(co):
        if co.z >= 1.55:
            return {"SpineUpper": 1.0}
        if co.z >= 1.42:
            t = (co.z - 1.42) / 0.13
            return {"SpineUpper": t, "SpineMid": 1.0 - t}
        if co.z >= 1.30:
            return {"SpineMid": 1.0}
        return {"Pelvis": 1.0}

    bind_obj_by_fn(det_map["SurgicalStraps"], strap_w)

    def rag_weights(co):
        if co.z >= 0.91:
            return {"Pelvis": 1.0}
        t = max(0.0, min(1.0, (0.91 - co.z) / 0.18))
        side_b = "Thigh.L" if co.x < 0 else "Thigh.R"
        return {"Pelvis": 1.0 - t * 0.75, side_b: t * 0.75}

    bind_obj_by_fn(det_map["TornGarmentRags"], rag_weights)

    # Join all detail parts into rigged body_obj (Blender merges vertex groups & material slots cleanly!)
    join_with_exact_materials(body_obj, mat_flesh, detail_items, palette)

    # Safety check for any zero-weight vertices on joined mesh
    vg_chest = body_obj.vertex_groups.get("SpineUpper") or body_obj.vertex_groups.new(name="SpineUpper")
    vg_head = body_obj.vertex_groups.get("Head") or body_obj.vertex_groups.new(name="Head")
    vg_pelvis = body_obj.vertex_groups.get("Pelvis") or body_obj.vertex_groups.new(name="Pelvis")
    zero_w_count = 0
    for v in body_obj.data.vertices:
        if sum(g.weight for g in v.groups) < 0.05:
            zero_w_count += 1
            if v.co.z > 1.92:
                vg_head.add([v.index], 1.0, "REPLACE")
            elif v.co.z > 1.35:
                vg_chest.add([v.index], 1.0, "REPLACE")
            else:
                vg_pelvis.add([v.index], 1.0, "REPLACE")
    print(f"[Monster] vertices={len(body_obj.data.vertices)} zero_weight_patched={zero_w_count}")

    # 6. Bake 4 Terrifying Horror Animations (Idle, Walk, Run, Attack) at 24 FPS!
    bpy.context.scene.render.fps = 24
    arm_obj.animation_data_create()
    pb = arm_obj.pose.bones
    for b in pb:
        b.rotation_mode = "XYZ"

    ALL_MONSTER_BONES = (
        "Pelvis", "SpineLow", "SpineMid", "SpineUpper", "Neck", "Head", "Jaw",
        "Shoulder.L", "UpperArm.L", "Forearm.L", "Hand.L",
        "Shoulder.R", "UpperArm.R", "Forearm.R", "Hand.R",
        "Thigh.L", "Shin.L", "Foot.L",
        "Thigh.R", "Shin.R", "Foot.R",
    )

    pelvis_inv = arm_obj.data.bones["Pelvis"].matrix_local.to_3x3().inverted()

    def set_pelvis_world_offset(dx: float, dy: float, dz: float) -> None:
        pb["Pelvis"].location = pelvis_inv @ Vector((dx, dy, dz))

    def monster_leg_drop_z(th_x: float, sh_x: float) -> float:
        """Pelvis world Z drop so the stance ankle stays grounded near rest height (0.09m -> sole at z=0)."""
        # Rest leg vectors: Thigh (0.467m @ +0.172 rad fwd), Shin (0.444m @ -0.250 rad back)
        thigh_len = 0.467
        shin_len = 0.444
        rest_h = thigh_len * math.cos(0.172) + shin_len * math.cos(-0.250)
        cur_h = thigh_len * math.cos(0.172 + th_x) + shin_len * math.cos(-0.250 + th_x + sh_x)
        return cur_h - rest_h

    def reset_pose():
        for b in pb:
            b.location = (0, 0, 0)
            b.rotation_euler = (0, 0, 0)

    def key_all(f: int, linear: bool = False):
        prev_interp = bpy.context.preferences.edit.keyframe_new_interpolation_type
        bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR" if linear else "BEZIER"
        pb["Pelvis"].keyframe_insert(data_path="location", frame=f)
        for bn in ALL_MONSTER_BONES:
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
        bpy.context.preferences.edit.keyframe_new_interpolation_type = prev_interp

    # -----------------------------------------------------------------------
    # ACTION 1: Idle (48 frames looping: frames 1..49)
    # Twitching Broken-Marionette Horror (Silent Hill / Clicker snaps)
    # -----------------------------------------------------------------------
    act = bpy.data.actions.new("Idle")
    arm_obj.animation_data.action = act
    # (frame, breath, head_yaw, head_roll, jaw_open, twitch_burst, is_snap)
    idle_frames = [
        (1,  0.00, -0.14,  0.16, 0.12, 0.00, False),
        (7,  0.65, -0.15,  0.18, 0.18, 0.04, False),
        (10, 0.72, -0.14,  0.17, 0.14, 0.00, True),
        (12, 0.85,  0.18,  0.42, 0.30, 0.90, True),   # Violent 2-frame head-snap + jaw click!
        (14, 0.40, -0.26, -0.35, 0.08, 1.00, True),   # Whip snap opposite way!
        (17, 0.25,  0.14,  0.18, 0.20, 0.35, True),   # Settle twitch
        (22, -0.30, 0.16,  0.20, 0.10, 0.02, False),  # Eerie frozen hold with ragged exhale
        (26, -0.45, 0.15,  0.19, 0.19, 0.06, False),  # Jaw quiver
        (29, -0.20, 0.16,  0.20, 0.09, 0.00, True),
        (31,  0.25, -0.22, -0.36, 0.28, 0.85, True),  # Second spasmodic marionette twitch!
        (33,  0.45,  0.22,  0.34, 0.11, 0.95, True),
        (36,  0.55, -0.10,  0.15, 0.22, 0.25, True),
        (42,  0.20, -0.13,  0.17, 0.14, 0.04, False),
        (49,  0.00, -0.14,  0.16, 0.12, 0.00, False),
    ]
    for f, breath, hd_y, hd_z, jaw_x, tw, is_snap in idle_frames:
        reset_pose()
        th_l, sh_l = 0.24, -0.44
        th_r, sh_r = 0.28, -0.50
        pel_z = max(monster_leg_drop_z(th_l, sh_l), monster_leg_drop_z(th_r, sh_r)) - 0.015
        set_pelvis_world_offset(0.0, -0.01, pel_z)
        pb["Pelvis"].rotation_euler = (0.04, -0.06, -0.05)
        pb["SpineLow"].rotation_euler = (0.14 + breath * 0.03, -0.05, 0.04)
        pb["SpineMid"].rotation_euler = (0.20 + breath * 0.08 + tw * 0.05, 0.06, 0.06)
        pb["SpineUpper"].rotation_euler = (0.16 + breath * 0.05, 0.08, 0.14 + tw * 0.06)  # Cocked +0.14 roll!
        pb["Neck"].rotation_euler = (0.18 + tw * 0.08, hd_y * 0.35, -0.06)
        pb["Head"].rotation_euler = (-0.36 - breath * 0.04, hd_y, hd_z)
        pb["Jaw"].rotation_euler = (jaw_x, 0.0, 0.0)

        # Uneven hunched shoulders & dangling twitching claw arms (keep outside hips!)
        pb["Shoulder.L"].rotation_euler = (0.06, 0.0, 0.12 + tw * 0.05)   # Left shoulder drooped/angled
        pb["Shoulder.R"].rotation_euler = (-0.04, 0.0, -0.06 - tw * 0.05)  # Right shoulder hunched up
        pb["UpperArm.L"].rotation_euler = (0.28 + breath * 0.04 + tw * 0.12, 0.06, 0.15)
        pb["Forearm.L"].rotation_euler = (0.30 + tw * 0.22, 0.0, -0.04)
        pb["Hand.L"].rotation_euler = (0.18 - tw * 0.34, 0.0, 0.12 * tw)
        pb["UpperArm.R"].rotation_euler = (0.22 - breath * 0.03 + tw * 0.10, -0.06, -0.18)
        pb["Forearm.R"].rotation_euler = (0.44 - tw * 0.20, 0.0, 0.05)
        pb["Hand.R"].rotation_euler = (0.24 + tw * 0.30, 0.0, -0.12 * tw)

        pb["Thigh.L"].rotation_euler = (th_l, 0.0, -0.06)
        pb["Shin.L"].rotation_euler = (sh_l, 0.0, 0.0)
        pb["Foot.L"].rotation_euler = (-(th_l + sh_l) * 0.85, 0.0, 0.0)
        pb["Thigh.R"].rotation_euler = (th_r, 0.0, 0.06)
        pb["Shin.R"].rotation_euler = (sh_r, 0.0, 0.0)
        pb["Foot.R"].rotation_euler = (-(th_r + sh_r) * 0.85, 0.0, 0.0)
        key_all(f, linear=is_snap)
    push_nla_action(arm_obj, "Idle")

    # -----------------------------------------------------------------------
    # ACTION 2: Walk (36 frames looping: frames 1..37)
    # Grotesque Limping Asymmetric Stalk (dragging left leg + groping claws)
    # -----------------------------------------------------------------------
    act = bpy.data.actions.new("Walk")
    arm_obj.animation_data.action = act
    for idx in range(19):
        f = 1 + idx * 2  # frames 1..37
        t = idx / 18.0
        ang = t * math.tau
        s, c = math.sin(ang), math.cos(ang)
        reset_pose()

        # Right leg: heavy predatory bent-knee lunge; Left leg: injured dragging limp!
        th_r = 0.22 + s * 0.48
        sh_r = -0.38 - max(0.0, c) * 0.58
        ft_r = -(th_r + sh_r) * 0.65

        # Left leg drags behind during swing with reduced lift and trailing foot
        limp_swing = max(0.0, -s)
        th_l = -0.02 - s * 0.30
        sh_l = -0.22 - max(0.0, -c) * 0.22 - limp_swing * 0.10
        ft_l = -(th_l + sh_l) * 0.45 - limp_swing * 0.18

        # Hip drop plunges extra hard when weight shifts onto the crippled left leg (s > 0),
        # while keeping stance sole cleanly near z = 0!
        limp_drop = max(0.0, s) * 0.020
        pel_z = max(monster_leg_drop_z(th_l, sh_l), monster_leg_drop_z(th_r, sh_r)) + 0.052 - limp_drop
        set_pelvis_world_offset(s * 0.025, 0.0, pel_z)
        pb["Pelvis"].rotation_euler = (0.0, -s * 0.09, -0.04 - max(0.0, s) * 0.08)

        # Deep hunched stalk (~0.35-0.45 rad total forward) + uneven twisted shoulders
        pb["SpineLow"].rotation_euler = (0.24 + abs(s) * 0.04, s * 0.07, 0.05)
        pb["SpineMid"].rotation_euler = (0.22, -s * 0.08 + 0.04, 0.09 + max(0.0, s) * 0.06)
        pb["SpineUpper"].rotation_euler = (0.18, -s * 0.10, 0.12 - s * 0.06)

        # Slow acoustic ear-cup sweep + sharp mid-stride head-jerk around f=17..21 (t ~ 0.44..0.56)
        jerk_env = math.exp(-((t - 0.50) / 0.055) ** 2)
        jerk_snap = math.sin((t - 0.50) * 58.0) * 0.34 * jerk_env
        pb["Neck"].rotation_euler = (0.24, s * 0.14 + jerk_snap * 0.3, -0.05)
        pb["Head"].rotation_euler = (-0.42 + abs(c) * 0.06, c * 0.26, -s * 0.12 + jerk_snap)
        pb["Jaw"].rotation_euler = (0.26 + abs(s) * 0.14 + jerk_env * 0.12, 0.0, 0.0)

        # Uneven shoulders (Left droops lower) + dangling gaunt arms groping blindly
        pb["Shoulder.L"].rotation_euler = (0.10 - s * 0.08, 0.0, 0.14)
        pb["Shoulder.R"].rotation_euler = (0.04 + s * 0.10, 0.0, -0.08)
        pb["UpperArm.L"].rotation_euler = (0.44 - s * 0.30, 0.06, 0.18)
        pb["Forearm.L"].rotation_euler = (0.36 + max(0.0, -s) * 0.24, 0.0, -0.04)
        pb["Hand.L"].rotation_euler = (0.24 + math.sin(ang * 2.0) * 0.26, 0.0, 0.08)

        pb["UpperArm.R"].rotation_euler = (0.36 + s * 0.38, -0.08, -0.20)
        pb["Forearm.R"].rotation_euler = (0.44 + max(0.0, s) * 0.26, 0.0, 0.06)
        pb["Hand.R"].rotation_euler = (0.28 - math.cos(ang * 2.0) * 0.28, 0.0, -0.08)

        pb["Thigh.L"].rotation_euler = (th_l, 0.0, -0.05)
        pb["Shin.L"].rotation_euler = (sh_l, 0.0, 0.0)
        pb["Foot.L"].rotation_euler = (ft_l, 0.0, 0.0)
        pb["Thigh.R"].rotation_euler = (th_r, 0.0, 0.06)
        pb["Shin.R"].rotation_euler = (sh_r, 0.0, 0.0)
        pb["Foot.R"].rotation_euler = (ft_r, 0.0, 0.0)
        key_all(f, linear=(jerk_env > 0.25))
    push_nla_action(arm_obj, "Walk")

    # -----------------------------------------------------------------------
    # ACTION 3: Run (20 frames looping: frames 1..21)
    # Unhinged Predatory Lunging Sprint: outstretched reaching/slashing claws,
    # 35-40 deg hunched twisting spine, craning twitching head, wide screaming jaw!
    # -----------------------------------------------------------------------
    act = bpy.data.actions.new("Run")
    arm_obj.animation_data.action = act
    for idx in range(11):
        f = 1 + idx * 2  # frames 1..21
        t = idx / 10.0
        ang = t * math.tau
        s, c = math.sin(ang), math.cos(ang)
        s2, c2 = math.sin(ang * 2.0), math.cos(ang * 2.0)
        s3 = math.sin(ang * 3.0 + 0.7)
        reset_pose()

        # Lanky, driving, slightly uneven predatory bounding strides (feet stay above z=0)
        th_l = 0.30 + s * 0.78
        sh_l = -0.44 - max(0.0, -c) * 0.88
        ft_l = -(th_l + sh_l) * 0.50 - max(0.0, -s) * 0.12

        th_r = 0.26 - s * 0.74
        sh_r = -0.40 - max(0.0, c) * 0.92
        ft_r = -(th_r + sh_r) * 0.50 - max(0.0, s) * 0.12

        pel_z = max(monster_leg_drop_z(th_l, sh_l), monster_leg_drop_z(th_r, sh_r)) + 0.100
        set_pelvis_world_offset(s * 0.028, 0.03 + abs(c) * 0.03, pel_z)
        pb["Pelvis"].rotation_euler = (0.06, -s * 0.14, s * 0.05)

        # Predatory 35-40 deg hunched forward lunge + asymmetric bounding spine twist
        pb["SpineLow"].rotation_euler = (0.24 + s2 * 0.03, s * 0.12, -s * 0.06)
        pb["SpineMid"].rotation_euler = (0.22 + s2 * 0.04, -s * 0.18, s * 0.06)
        pb["SpineUpper"].rotation_euler = (0.18 - s2 * 0.03, -s * 0.22, 0.03 - s * 0.05)

        # Craned forward neck, erratic side-to-side snapping/twitching head, wide screaming jaw!
        pb["Neck"].rotation_euler = (0.22 + s2 * 0.04, s * 0.16 + c2 * 0.08, s * 0.05)
        pb["Head"].rotation_euler = (-0.74 - s2 * 0.05, s * 0.10 - s2 * 0.12 + s3 * 0.09, -s * 0.12 + s3 * 0.12)
        pb["Jaw"].rotation_euler = (0.18 + abs(s2) * 0.18, 0.0, 0.0)

        # Outstretched reaching & violently slashing/flailing clawed arms toward the prey!
        # Note: spine forward pitch (~0.70 rad) tilts rest arms back, so UpperArm.x ~ 1.6..2.40
        # thrusts arms straight forward at chest/face height; when raised, -Z abducts L outward (-X) and +Z abducts R outward (+X).
        pb["Shoulder.L"].rotation_euler = (0.0, -0.08 * s, 0.10 - s * 0.12)
        pb["Shoulder.R"].rotation_euler = (0.0, -0.08 * s, -0.10 - s * 0.12)

        pb["UpperArm.L"].rotation_euler = (1.98 - s * 0.40 + c2 * 0.08, -0.08 + s * 0.20, -0.44 - max(0.0, s) * 0.44 - s2 * 0.10)
        pb["Forearm.L"].rotation_euler = (0.12 + max(0.0, s) * 0.40 + max(0.0, -s2) * 0.14, 0.0, -0.04)
        pb["Hand.L"].rotation_euler = (-0.24 + s * 0.34 + s2 * 0.20, s * 0.16, 0.12)

        pb["UpperArm.R"].rotation_euler = (1.96 + s * 0.42 - c2 * 0.08, 0.08 + s * 0.20, 0.44 + max(0.0, -s) * 0.46 + s2 * 0.10)
        pb["Forearm.R"].rotation_euler = (0.14 + max(0.0, -s) * 0.42 + max(0.0, s2) * 0.14, 0.0, 0.04)
        pb["Hand.R"].rotation_euler = (-0.24 - s * 0.34 - s2 * 0.20, s * 0.16, -0.12)

        pb["Thigh.L"].rotation_euler = (th_l, 0.0, -0.09)
        pb["Shin.L"].rotation_euler = (sh_l, 0.0, 0.0)
        pb["Foot.L"].rotation_euler = (ft_l, 0.0, 0.0)
        pb["Thigh.R"].rotation_euler = (th_r, 0.0, 0.09)
        pb["Shin.R"].rotation_euler = (sh_r, 0.0, 0.0)
        pb["Foot.R"].rotation_euler = (ft_r, 0.0, 0.0)
        key_all(f, linear=False)
    push_nla_action(arm_obj, "Run")

    # -----------------------------------------------------------------------
    # ACTION 4: Attack (24 frames: frames 1..25)
    # Dead-Center First-Person Jumpscare & Melee Lunge:
    # Head & split-fanged Jaw stay horizontally centered (X ~ 0) & vertically
    # stable (Z ~ 1.68..1.79) while lunging straight forward & snapping;
    # both clawed hands frame left/right camera edges (Y ~ 0.72..0.88, X ~ +-0.26..0.44)
    # without clipping behind the ~1.05m camera and slash inward!
    # -----------------------------------------------------------------------
    act = bpy.data.actions.new("Attack")
    arm_obj.animation_data.action = act
    # (frame, pel_dy, sp_x, hd_x, hd_yaw, hd_roll, jaw_x, arm_lx, arm_la, arm_ly, arm_rx, arm_ra, arm_ry, fore_lx, fore_rx, hand_x, th_x, sh_x)
    # Note: when arms are raised forward, -Z abducts Left outward (-X) and +Z abducts Right outward (+X).
    # Jaw rest pose is already open; +0.26..+0.34 opens maximally, -0.38..-0.42 clamps fangs shut!
    atk_poses = [
        (1,  0.00, 0.12, -0.18,  0.00,  0.02,  0.14, 1.24, -0.34, -0.06, 1.24, 0.34,  0.06, 1.46, 1.46, -0.18, 0.26, -0.46),
        (4, -0.02, 0.09, -0.14, -0.02, -0.04,  0.32, 1.12, -0.44, -0.10, 1.12, 0.44,  0.10, 1.50, 1.50, -0.26, 0.28, -0.50),  # Coiled wide-claw flare + roaring jaw!
        (8,  0.08, 0.17, -0.25,  0.02,  0.03,  0.34, 1.42, -0.26, -0.04, 1.42, 0.26,  0.04, 1.44, 1.44, -0.16, 0.24, -0.44),  # Explosive lunge: claws framing camera edges!
        (11, 0.09, 0.18, -0.27, -0.02,  0.04, -0.40, 1.46, -0.16,  0.04, 1.46, 0.16, -0.04, 1.50, 1.50,  0.14, 0.24, -0.44),  # JAW SLAMS SHUT + inward claw grab!
        (14, 0.06, 0.15, -0.21,  0.02, -0.05,  0.32, 1.34, -0.36, -0.06, 1.38, 0.34,  0.06, 1.48, 1.44, -0.20, 0.26, -0.47),  # Second rabid snarl & wide re-cock
        (18, 0.08, 0.17, -0.25, -0.02,  0.03, -0.38, 1.44, -0.18,  0.04, 1.42, 0.18, -0.04, 1.50, 1.50,  0.12, 0.25, -0.45),  # Second bite snap!
        (21, 0.04, 0.14, -0.20,  0.01, -0.02,  0.22, 1.34, -0.32, -0.04, 1.34, 0.32,  0.04, 1.46, 1.46, -0.14, 0.26, -0.46),  # Vibrating snap hold
        (25, 0.00, 0.12, -0.18,  0.00,  0.02,  0.14, 1.24, -0.34, -0.06, 1.24, 0.34,  0.06, 1.46, 1.46, -0.18, 0.26, -0.46),
    ]
    for f, pel_dy, sp_x, hd_x, hd_yaw, hd_roll, jaw_x, arm_lx, arm_la, arm_ly, arm_rx, arm_ra, arm_ry, fore_lx, fore_rx, hand_x, th_x, sh_x in atk_poses:
        reset_pose()
        pel_z = monster_leg_drop_z(th_x, sh_x) + 0.015
        set_pelvis_world_offset(0.0, pel_dy, pel_z)
        pb["Pelvis"].rotation_euler = (sp_x * 0.30, 0.0, 0.0)
        pb["SpineLow"].rotation_euler = (sp_x * 0.65, 0.0, 0.0)
        pb["SpineMid"].rotation_euler = (sp_x * 0.85, 0.0, 0.0)
        pb["SpineUpper"].rotation_euler = (sp_x * 0.75, 0.0, 0.0)
        pb["Neck"].rotation_euler = (sp_x * 0.40, hd_yaw * 0.3, -hd_roll * 0.25)
        pb["Head"].rotation_euler = (hd_x, hd_yaw, hd_roll)
        pb["Jaw"].rotation_euler = (jaw_x, 0.0, 0.0)

        pb["Shoulder.L"].rotation_euler = (0.0, 0.0, 0.04)
        pb["Shoulder.R"].rotation_euler = (0.0, 0.0, -0.04)
        pb["UpperArm.L"].rotation_euler = (arm_lx, arm_ly, arm_la)
        pb["Forearm.L"].rotation_euler = (fore_lx, 0.0, -0.04)
        pb["Hand.L"].rotation_euler = (hand_x, 0.0, 0.10)
        pb["UpperArm.R"].rotation_euler = (arm_rx, arm_ry, arm_ra)
        pb["Forearm.R"].rotation_euler = (fore_rx, 0.0, 0.04)
        pb["Hand.R"].rotation_euler = (hand_x, 0.0, -0.10)

        pb["Thigh.L"].rotation_euler = (th_x, 0.0, -0.08)
        pb["Shin.L"].rotation_euler = (sh_x, 0.0, 0.0)
        pb["Foot.L"].rotation_euler = (-(th_x + sh_x) * 0.85, 0.0, 0.0)
        pb["Thigh.R"].rotation_euler = (th_x + 0.04, 0.0, 0.08)
        pb["Shin.R"].rotation_euler = (sh_x - 0.06, 0.0, 0.0)
        pb["Foot.R"].rotation_euler = (-(th_x + sh_x) * 0.85, 0.0, 0.0)
        key_all(f, linear=True)
    push_nla_action(arm_obj, "Attack")

    out_path = os.path.join(MODEL_DIR, "monster_stalker.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_materials="EXPORT",
    )
    print("EXPORTED SKINNED MONSTER:", out_path, os.path.getsize(out_path))


# ===========================================================================
# 2. RE-SCULPTED CO-OP SURVIVOR: SOVIET BIO-HAZMAT LIQUIDATOR
# ===========================================================================
def build_sculpted_survivor() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)

    mat_suit = make_uv_pbr_mat(
        "HazmatSuit",
        "hazmat_fabric.png",
        "hazmat_fabric_n.png",
        base_col=(0.88, 0.86, 0.80, 1.0),
        roughness=0.72,
        metallic=0.02,
        normal_strength=0.95,
    )
    mat_rubber = make_uv_pbr_mat(
        "HazmatRubber",
        "",
        "",
        base_col=(0.016, 0.018, 0.019, 1.0),
        roughness=0.52,
        metallic=0.05,
    )
    mat_metal = make_uv_pbr_mat(
        "HazmatMetal",
        "concrete_wall.png",
        "concrete_wall_n.png",
        base_col=(0.14, 0.17, 0.15, 1.0),
        roughness=0.40,
        metallic=0.76,
    )
    # Dark smoked reflective glass visor (#141A1C) — ZERO emission so it NEVER glows white!
    mat_visor = make_uv_pbr_mat(
        "HazmatVisor",
        "",
        "",
        base_col=(0.010, 0.016, 0.018, 1.0),
        roughness=0.07,
        metallic=0.48,
        specular_ior=0.95,
    )
    mat_patch = make_uv_pbr_mat(
        "HazmatPatch",
        "",
        "",
        base_col=(0.68, 0.36, 0.08, 1.0),
        roughness=0.52,
        metallic=0.05,
    )
    palette = [mat_suit, mat_rubber, mat_metal, mat_visor, mat_patch]

    # 1. Articulated Humanoid Suit Graph (~1.80m tall, +Y forward, +Z up)
    mesh = bpy.data.meshes.new("SurvivorGraph")
    body_obj = bpy.data.objects.new("SurvivorBody", mesh)
    bpy.context.collection.objects.link(body_obj)

    nodes_spec = {
        "pelvis": ((0.0, 0.0, 0.90), 0.145, 0.112),
        "waist": ((0.0, 0.0, 1.06), 0.132, 0.104),
        "chest_low": ((0.0, 0.01, 1.24), 0.158, 0.118),
        "chest_up": ((0.0, 0.01, 1.40), 0.180, 0.128),
        "collar": ((0.0, 0.01, 1.52), 0.102, 0.102),
        "head": ((0.0, 0.02, 1.66), 0.118, 0.126),
        "head_top": ((0.0, 0.01, 1.79), 0.098, 0.106),
    }
    edges_spec = [
        ("pelvis", "waist"),
        ("waist", "chest_low"),
        ("chest_low", "chest_up"),
        ("chest_up", "collar"),
        ("collar", "head"),
        ("head", "head_top"),
    ]
    for side, s in ((-1, "L"), (1, "R")):
        nodes_spec.update({
            f"sh_{s}": ((side * 0.205, 0.0, 1.385), 0.084, 0.086),
            f"elb_{s}": ((side * 0.252, 0.01, 1.14), 0.066, 0.066),
            f"wrs_{s}": ((side * 0.245, 0.08, 0.90), 0.052, 0.052),
            f"hand_{s}": ((side * 0.240, 0.11, 0.82), 0.048, 0.040),
            f"hip_{s}": ((side * 0.108, 0.0, 0.85), 0.102, 0.102),
            f"thigh_mid_{s}": ((side * 0.111, 0.01, 0.66), 0.090, 0.092),
            f"knee_{s}": ((side * 0.114, 0.02, 0.47), 0.076, 0.080),
            f"shin_mid_{s}": ((side * 0.114, 0.005, 0.28), 0.058, 0.060),
            f"ank_{s}": ((side * 0.114, -0.01, 0.10), 0.048, 0.052),
            f"foot_{s}": ((side * 0.116, 0.12, 0.042), 0.048, 0.036),
        })
        edges_spec.extend([
            ("chest_up", f"sh_{s}"),
            (f"sh_{s}", f"elb_{s}"),
            (f"elb_{s}", f"wrs_{s}"),
            (f"wrs_{s}", f"hand_{s}"),
            ("pelvis", f"hip_{s}"),
            (f"hip_{s}", f"thigh_mid_{s}"),
            (f"thigh_mid_{s}", f"knee_{s}"),
            (f"knee_{s}", f"shin_mid_{s}"),
            (f"shin_mid_{s}", f"ank_{s}"),
            (f"ank_{s}", f"foot_{s}"),
        ])

    keys = list(nodes_spec.keys())
    idx_map = {k: i for i, k in enumerate(keys)}
    mesh.from_pydata([nodes_spec[k][0] for k in keys], [(idx_map[a], idx_map[b]) for a, b in edges_spec], [])
    mesh.update()

    sk = body_obj.modifiers.new("Skin", "SKIN")
    sk.use_smooth_shade = True
    for i, k in enumerate(keys):
        _, rx, ry = nodes_spec[k]
        body_obj.data.skin_vertices[0].data[i].radius = (rx, ry)
    body_obj.data.skin_vertices[0].data[idx_map["pelvis"]].use_root = True

    sub = body_obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    apply_modifiers_and_uv(body_obj, mat_suit, tex_repeat=2.2)

    # 2. Build Multi-Material Soviet Liquidator Equipment & Protective Gear
    detail_items = []

    def push_ex(name: str, bm_p: bmesh.types.BMesh, mt, tex_rep: float = 2.0):
        obj = create_detail_obj(name, bm_p, tex_repeat=tex_rep)
        detail_items.append((obj, mt))
        return obj

    # A) Flared Hazmat Hood Collar Rim (`HazmatSuit`)
    bm_hood = bmesh.new()
    add_curved_visor_band(bm_hood, Vector((0.0, 0.02, 1.56)), 0.115, 0.122, 0.0, math.tau, 1.50, 1.56, 0.022, arc_steps=20)
    # Hood ridge framing face opening
    hood_arc = []
    for k in range(13):
        t = k / 12.0
        a = -math.pi * 0.42 + t * math.pi * 0.84
        px = math.sin(a) * 0.118
        pz = 1.66 + math.cos(a) * 0.128
        py = 0.095 - abs(math.sin(a)) * 0.025
        hood_arc.append((Vector((px, py, pz)), 0.020, 0.022))
    add_tube_along_points(bm_hood, hood_arc, segs=8)
    push_ex("HoodRim", bm_hood, mat_suit, 2.2)

    # B) Dark Smoked Reflective Panoramic Visor (`HazmatVisor`)
    bm_visor = bmesh.new()
    visor_c = Vector((0.0, 0.045, 1.675))
    add_curved_visor_band(bm_visor, visor_c, 0.096, 0.106, -0.82, 0.82, 1.640, 1.715, 0.012, arc_steps=16)
    push_ex("GasMaskVisor", bm_visor, mat_visor, 1.0)

    # C) Dark Vulcanized Rubber Gear: Mask Frame, Snout, Corrugated Hose, Boots, Gloves, Belt & Harness
    bm_rub = bmesh.new()
    # Mask facepiece frame & raised bezel around smoked visor (keeps visor recessed & realistic!)
    add_curved_visor_band(bm_rub, visor_c, 0.098, 0.108, -0.92, 0.92, 1.712, 1.734, 0.018, arc_steps=16)
    add_curved_visor_band(bm_rub, visor_c, 0.098, 0.108, -0.92, 0.92, 1.615, 1.642, 0.018, arc_steps=16)
    for side in (-1, 1):
        add_box_bm(bm_rub, (0.020, 0.032, 0.105), (side * 0.090, 0.115, 1.675), Euler((0, 0, side * 0.45)))
    # Respirator nose/chin snout housing
    add_cyl_bm(bm_rub, 0.044, 0.036, 0.065, Vector((0.0, 0.155, 1.602)), Euler((1.35, 0, 0)), segs=12)

    # Corrugated breathing hose from lower snout down to chest regulator unit!
    hose_pts = [
        (Vector((0.0, 0.172, 1.572)), 0.022, 0.022),
        (Vector((0.015, 0.185, 1.505)), 0.020, 0.020),
        (Vector((0.022, 0.175, 1.430)), 0.020, 0.020),
        (Vector((0.012, 0.155, 1.355)), 0.021, 0.021),
    ]
    add_tube_along_points(bm_rub, hose_pts, segs=10)
    # Corrugation ribs along hose
    for ht in (0.18, 0.34, 0.50, 0.66, 0.82):
        # Linear interpolate along segments roughly
        p = hose_pts[0][0].lerp(hose_pts[-1][0], ht) + Vector((math.sin(ht * math.pi) * 0.018, math.sin(ht * math.pi) * 0.022, 0.0))
        add_cyl_bm(bm_rub, 0.025, 0.025, 0.012, p, Euler((0.25, 0.1, 0)), segs=10)

    # Heavy Knee-High Chemical Rubber Boots (both legs — wide enough to cleanly enclose lower pant leg!)
    for side in (-1, 1):
        bx = side * 0.115
        # Boot shin shaft + top cuff
        add_cyl_bm(bm_rub, 0.076, 0.082, 0.28, Vector((bx, 0.0, 0.20)), segs=14)
        add_cyl_bm(bm_rub, 0.088, 0.088, 0.034, Vector((bx, 0.0, 0.33)), segs=14)
        # Heavy lugged sole + toe box
        add_box_bm(bm_rub, (0.128, 0.248, 0.042), (bx, 0.062, 0.021))
        add_box_bm(bm_rub, (0.122, 0.218, 0.078), (bx, 0.056, 0.068))

    # Protective Rubber Gauntlets & Gloves (separate mesh so belt pouches NEVER cross-bind to Forearm!)
    bm_gloves = bmesh.new()
    for side in (-1, 1):
        add_cyl_bm(bm_gloves, 0.056, 0.064, 0.14, Vector((side * 0.244, 0.082, 0.91)), Euler((-0.24, side * 0.04, 0)), segs=12)
        add_box_bm(bm_gloves, (0.074, 0.095, 0.105), (side * 0.240, 0.108, 0.815), Euler((-0.18, 0, 0)))
    push_ex("HazmatGloves", bm_gloves, mat_rubber, 1.0)

    # Waist Belt, Side Pouches & Snug Shoulder Webbing Straps
    add_curved_visor_band(bm_rub, Vector((0.0, 0.0, 1.04)), 0.136, 0.110, 0.0, math.tau, 1.01, 1.075, 0.016, arc_steps=20)
    for side in (-1, 1):
        add_box_bm(bm_rub, (0.062, 0.115, 0.125), (side * 0.155, 0.01, 1.01))
        strap = [
            (Vector((side * 0.082, 0.120, 1.07)), 0.018, 0.007),
            (Vector((side * 0.088, 0.132, 1.24)), 0.018, 0.007),
            (Vector((side * 0.095, 0.120, 1.40)), 0.018, 0.007),
            (Vector((side * 0.092, 0.035, 1.48)), 0.018, 0.007),
            (Vector((side * 0.092, -0.108, 1.38)), 0.018, 0.007),
            (Vector((side * 0.085, -0.105, 1.07)), 0.018, 0.007),
        ]
        add_tube_along_points(bm_rub, strap, segs=6)
    push_ex("HazmatRubberGear", bm_rub, mat_rubber, 1.0)

    # D) Metal Gear: Twin Soviet Filter Canisters, Chest Regulator Box, Belt Buckle, Twin Oxygen Backpack + Whip Antenna
    bm_met = bmesh.new()
    # Twin angled Soviet GP-7/PMG filter canisters on mask cheeks
    for side in (-1, 1):
        fc = Vector((side * 0.072, 0.145, 1.595))
        f_rot = Euler((1.18, 0, -side * 0.55))
        add_cyl_bm(bm_met, 0.038, 0.038, 0.068, fc, f_rot, segs=14)
        add_cyl_bm(bm_met, 0.041, 0.041, 0.012, fc + Vector((side * 0.015, 0.022, -0.010)), f_rot, segs=14)

    # Chest air-regulator / dosimeter box + belt buckle
    add_box_bm(bm_met, (0.115, 0.055, 0.135), (0.01, 0.142, 1.32))
    add_box_bm(bm_met, (0.068, 0.026, 0.058), (0.0, 0.125, 1.042))

    # Oxygen/Radio Backpack: Frame + Twin Vertical Cylinders + Radio Transceiver + Whip Antenna!
    add_box_bm(bm_met, (0.25, 0.085, 0.34), (0.0, -0.155, 1.29))
    for side in (-1, 1):
        add_cyl_bm(bm_met, 0.055, 0.055, 0.35, Vector((side * 0.065, -0.205, 1.28)), segs=14)
        add_cyl_bm(bm_met, 0.032, 0.055, 0.045, Vector((side * 0.065, -0.205, 1.475)), segs=14)
    # Whip antenna rising above left shoulder!
    add_cyl_bm(bm_met, 0.008, 0.003, 0.44, Vector((-0.105, -0.18, 1.66)), Euler((-0.08, -0.05, 0)), segs=8)
    push_ex("HazmatMetalGear", bm_met, mat_metal, 2.0)

    # E) SODIUM Amber Hazard Arm Patch + Backpack Status Stripe (`HazmatPatch`)
    bm_patch = bmesh.new()
    # Left deltoid shoulder hazard patch
    add_box_bm(bm_patch, (0.016, 0.068, 0.084), (-0.276, 0.01, 1.32), Euler((0, 0.26, 0)))
    # Chest regulator gauge face + backpack caution band
    add_box_bm(bm_patch, (0.068, 0.014, 0.032), (0.01, 0.171, 1.345))
    add_box_bm(bm_patch, (0.22, 0.022, 0.036), (0.0, -0.255, 1.32))
    push_ex("HazmatPatches", bm_patch, mat_patch, 1.0)

    # 3. Articulated Humanoid Rig (`SurvivorArmature`) Bound to Pure Manifold Suit First (Zero Bone-Heat Errors!)
    arm_data = bpy.data.armatures.new("SurvivorArmature")
    arm_obj = bpy.data.objects.new("SurvivorRig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def add_b(n, h, t, p=None, roll_axis=(1.0, 0.0, 0.0)):
        b = eb.new(n)
        b.head = Vector(h)
        b.tail = Vector(t)
        b.align_roll(Vector(roll_axis))
        if p:
            b.parent = eb[p]
        return b

    # align_roll sets bone.z_axis!
    # Align Spine/Head/Limbs z_axis to +Y_world (forward) so +X rotation ALWAYS pitches forward (+Y)!
    # Align Foot z_axis to +Z_world (up) so +X rotation pitches toe UP!
    add_b("Root", (0, 0, 0), (0, 0, 0.30), None, (0.0, 1.0, 0.0))
    add_b("Pelvis", (0, 0, 0.88), (0, 0, 1.10), "Root", (0.0, 1.0, 0.0))
    add_b("Spine", (0, 0, 1.10), (0, 0.01, 1.52), "Pelvis", (0.0, 1.0, 0.0))
    add_b("Head", (0, 0.01, 1.52), (0, 0.02, 1.82), "Spine", (0.0, 1.0, 0.0))
    for side, s in ((-1, "L"), (1, "R")):
        add_b(f"UpperArm.{s}", (side * 0.20, 0, 1.39), (side * 0.252, 0.01, 1.14), "Spine", (0.0, 1.0, 0.0))
        add_b(f"Forearm.{s}", (side * 0.252, 0.01, 1.14), (side * 0.24, 0.11, 0.82), f"UpperArm.{s}", (0.0, 1.0, 0.0))
        add_b(f"Thigh.{s}", (side * 0.108, 0, 0.86), (side * 0.114, 0.02, 0.47), "Pelvis", (0.0, 1.0, 0.0))
        add_b(f"Shin.{s}", (side * 0.114, 0.02, 0.47), (side * 0.115, -0.01, 0.10), f"Thigh.{s}", (0.0, 1.0, 0.0))
        add_b(f"Foot.{s}", (side * 0.115, -0.01, 0.10), (side * 0.116, 0.15, 0.02), f"Shin.{s}", (0.0, 0.0, 1.0))

    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    body_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    # 4. Pre-assign Exact Bone Vertex Groups on Each Equipment Detail Before Joining
    def bind_sobj(obj, weight_fn):
        for v in obj.data.vertices:
            for bname, w in weight_fn(v.co).items():
                vg = obj.vertex_groups.get(bname) or obj.vertex_groups.new(name=bname)
                vg.add([v.index], w, "REPLACE")

    sdet = {o.name: o for o, _ in detail_items}
    bind_sobj(sdet["HoodRim"], lambda co: {"Head": 1.0} if co.z >= 1.55 else {"Spine": 0.65, "Head": 0.35})
    bind_sobj(sdet["GasMaskVisor"], lambda co: {"Head": 1.0})

    def rub_weights(co):
        side_s = "L" if co.x < 0 else "R"
        if co.z >= 1.52:
            return {"Head": 1.0}
        if co.z >= 1.32 and co.y > 0.14:
            # Corrugated breathing hose bridging Head -> Chest
            t = max(0.0, min(1.0, (co.z - 1.32) / 0.20))
            return {"Head": t, "Spine": 1.0 - t}
        if co.z <= 0.095 or (co.z <= 0.135 and co.y > 0.045):
            return {f"Foot.{side_s}": 1.0}
        if co.z <= 0.135:
            t = max(0.0, min(1.0, (co.z - 0.095) / 0.040))
            return {f"Shin.{side_s}": t, f"Foot.{side_s}": 1.0 - t}
        if co.z <= 0.40:
            return {f"Shin.{side_s}": 1.0}
        if co.z <= 1.12:
            return {"Pelvis": 1.0}
        return {"Spine": 1.0}

    bind_sobj(sdet["HazmatGloves"], lambda co: {"Forearm.L" if co.x < 0 else "Forearm.R": 1.0})
    bind_sobj(sdet["HazmatRubberGear"], rub_weights)
    bind_sobj(sdet["HazmatMetalGear"], lambda co: {
        "Head": 1.0} if (co.z >= 1.50 and co.y > -0.05) else ({"Pelvis": 1.0} if co.z <= 1.10 else {"Spine": 1.0})
    )
    bind_sobj(sdet["HazmatPatches"], lambda co: {
        "UpperArm.L": 1.0} if co.x < -0.18 else {"Spine": 1.0}
    )

    join_with_exact_materials(body_obj, mat_suit, detail_items, palette)

    s_sp = body_obj.vertex_groups.get("Spine") or body_obj.vertex_groups.new(name="Spine")
    for v in body_obj.data.vertices:
        if sum(g.weight for g in v.groups) < 0.05:
            s_sp.add([v.index], 1.0, "REPLACE")

    # 5. Bake 5 Articulated NLA Animations (CrouchIdle, CrouchWalk, Downed, Idle, Walk) at 24 FPS
    bpy.context.scene.render.fps = 24
    arm_obj.animation_data_create()
    pb = arm_obj.pose.bones
    for b in pb:
        b.rotation_mode = "XYZ"

    def reset_spose():
        for b in pb:
            b.location = (0, 0, 0)
            b.rotation_euler = (0, 0, 0)

    ALL_SURV_BONES = (
        "Spine", "Head",
        "Thigh.L", "Shin.L", "Foot.L",
        "Thigh.R", "Shin.R", "Foot.R",
        "UpperArm.L", "Forearm.L", "UpperArm.R", "Forearm.R",
    )

    pelvis_inv = arm_obj.data.bones["Pelvis"].matrix_local.to_3x3().inverted()

    def set_pelvis_world_offset(dx: float, dy: float, dz: float) -> None:
        pb["Pelvis"].location = pelvis_inv @ Vector((dx, dy, dz))

    def leg_hip_drop_z(thigh_x: float, shin_x: float) -> float:
        """Exact pelvis Z offset so the lowest ankle remains at rest height (~0.10m, boot sole on z=0)."""
        thigh_len = 0.39
        shin_len = 0.37
        h = thigh_len * math.cos(thigh_x) + shin_len * math.cos(thigh_x + shin_x)
        return h - (thigh_len + shin_len)

    # ACTION 1: CrouchIdle (48 frames: deep knee-bent tactical crouch with subtle breath sway)
    act = bpy.data.actions.new("CrouchIdle")
    arm_obj.animation_data.action = act
    for idx in range(9):
        f = 1 + idx * 6
        ang = (idx / 8.0) * math.tau
        s = math.sin(ang)
        reset_spose()
        th_l = 1.26 + s * 0.02
        sh_l = -2.06 - s * 0.03
        th_r = 1.20 + s * 0.02
        sh_r = -1.98 - s * 0.03
        pel_z = min(-0.38, min(leg_hip_drop_z(th_l, sh_l), leg_hip_drop_z(th_r, sh_r)))
        set_pelvis_world_offset(0.0, -0.02, pel_z)
        pb["Spine"].rotation_euler = (0.34 + s * 0.025, 0, 0)
        pb["Head"].rotation_euler = (-0.26 - s * 0.02, 0, s * 0.06)
        pb["Thigh.L"].rotation_euler = (th_l, 0, -0.10)
        pb["Shin.L"].rotation_euler = (sh_l, 0, 0)
        pb["Foot.L"].rotation_euler = (-(th_l + sh_l), 0, 0)
        pb["Thigh.R"].rotation_euler = (th_r, 0, 0.10)
        pb["Shin.R"].rotation_euler = (sh_r, 0, 0)
        pb["Foot.R"].rotation_euler = (-(th_r + sh_r), 0, 0)
        pb["UpperArm.L"].rotation_euler = (0.14, 0, -0.14)
        pb["Forearm.L"].rotation_euler = (0.82 + s * 0.04, 0, 0.12)
        pb["UpperArm.R"].rotation_euler = (0.18, 0, 0.14)
        pb["Forearm.R"].rotation_euler = (0.86 - s * 0.04, 0, -0.12)
        pb["Pelvis"].keyframe_insert(data_path="location", frame=f)
        for bn in ALL_SURV_BONES:
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "CrouchIdle")

    # ACTION 2: CrouchWalk (32 frames: crouched stealth shuffle maintaining lowered pelvis & bent knees)
    act = bpy.data.actions.new("CrouchWalk")
    arm_obj.animation_data.action = act
    for idx in range(9):
        f = 1 + idx * 4
        ang = (idx / 8.0) * math.tau
        s, c = math.sin(ang), math.cos(ang)
        reset_spose()
        th_l = 1.24 + s * 0.28
        sh_l = -2.02 - max(0.0, -c) * 0.26
        th_r = 1.24 - s * 0.28
        sh_r = -2.02 - max(0.0, c) * 0.26
        drop_l = leg_hip_drop_z(th_l, sh_l)
        drop_r = leg_hip_drop_z(th_r, sh_r)
        pel_z = max(drop_l, drop_r) - 0.015
        set_pelvis_world_offset(0.0, -0.02, pel_z)
        pb["Spine"].rotation_euler = (0.36, s * 0.05, -s * 0.06)
        pb["Head"].rotation_euler = (-0.28, 0, s * 0.05)
        pb["Thigh.L"].rotation_euler = (th_l, 0, -0.10)
        pb["Shin.L"].rotation_euler = (sh_l, 0, 0)
        pb["Foot.L"].rotation_euler = (-(th_l + sh_l) * 0.88, 0, 0)
        pb["Thigh.R"].rotation_euler = (th_r, 0, 0.10)
        pb["Shin.R"].rotation_euler = (sh_r, 0, 0)
        pb["Foot.R"].rotation_euler = (-(th_r + sh_r) * 0.88, 0, 0)
        pb["UpperArm.L"].rotation_euler = (0.16 - s * 0.22, 0, -0.14)
        pb["Forearm.L"].rotation_euler = (0.80 + max(0.0, -s) * 0.14, 0, 0.10)
        pb["UpperArm.R"].rotation_euler = (0.16 + s * 0.22, 0, 0.14)
        pb["Forearm.R"].rotation_euler = (0.80 + max(0.0, s) * 0.14, 0, -0.10)
        pb["Pelvis"].keyframe_insert(data_path="location", frame=f)
        for bn in ALL_SURV_BONES:
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "CrouchWalk")

    # ACTION 3: Downed (40 frames: collapsed/crawling wounded posture near the floor, bracing forward)
    act = bpy.data.actions.new("Downed")
    arm_obj.animation_data.action = act
    for idx in range(9):
        f = 1 + idx * 5
        ang = (idx / 8.0) * math.tau
        s = math.sin(ang)
        reset_spose()
        set_pelvis_world_offset(0.0, -0.06, -0.73 + s * 0.012)
        pb["Spine"].rotation_euler = (1.18 + s * 0.04, s * 0.05, 0)
        pb["Head"].rotation_euler = (-0.82 - s * 0.04, 0, s * 0.08)
        pb["Thigh.L"].rotation_euler = (-1.34 + s * 0.05, 0, -0.14)
        pb["Shin.L"].rotation_euler = (-0.28 - s * 0.05, 0, 0)
        pb["Foot.L"].rotation_euler = (0.35, 0, 0)
        pb["Thigh.R"].rotation_euler = (-1.18 - s * 0.05, 0, 0.16)
        pb["Shin.R"].rotation_euler = (-0.52 + s * 0.05, 0, 0)
        pb["Foot.R"].rotation_euler = (0.42, 0, 0)
        pb["UpperArm.L"].rotation_euler = (0.78 + s * 0.06, 0, -0.20)
        pb["Forearm.L"].rotation_euler = (0.62 - s * 0.05, 0, 0)
        pb["UpperArm.R"].rotation_euler = (0.86 - s * 0.06, 0, 0.20)
        pb["Forearm.R"].rotation_euler = (0.54 + s * 0.05, 0, 0)
        pb["Pelvis"].keyframe_insert(data_path="location", frame=f)
        for bn in ALL_SURV_BONES:
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "Downed")

    # ACTION 4: Idle (48 frames: cautious breathing & subtle head scan, feet flat on z = 0)
    act = bpy.data.actions.new("Idle")
    arm_obj.animation_data.action = act
    for idx in range(9):
        f = 1 + idx * 6
        ang = (idx / 8.0) * math.tau
        s = math.sin(ang)
        reset_spose()
        pb["Spine"].rotation_euler = (0.04 + s * 0.025, 0, 0)
        pb["Head"].rotation_euler = (-0.02, 0, s * 0.12)
        pb["UpperArm.L"].rotation_euler = (0.08, 0, -0.05)
        pb["Forearm.L"].rotation_euler = (0.20 + s * 0.03, 0, 0)
        pb["UpperArm.R"].rotation_euler = (0.10, 0, 0.05)
        pb["Forearm.R"].rotation_euler = (0.24 - s * 0.03, 0, 0)
        for bn in ALL_SURV_BONES:
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "Idle")

    # ACTION 5: Walk (32 frames: natural articulated knee-bending stride + opposite arm swing)
    act = bpy.data.actions.new("Walk")
    arm_obj.animation_data.action = act
    for idx in range(9):
        f = 1 + idx * 4
        ang = (idx / 8.0) * math.tau
        s, c = math.sin(ang), math.cos(ang)
        reset_spose()
        th_l = s * 0.44
        sh_l = -max(0.0, -c) * 0.54
        th_r = -s * 0.44
        sh_r = -max(0.0, c) * 0.54
        pel_z = max(leg_hip_drop_z(th_l, sh_l), leg_hip_drop_z(th_r, sh_r))
        set_pelvis_world_offset(0.0, 0.0, pel_z)
        pb["Spine"].rotation_euler = (0.07, 0, -s * 0.05)
        pb["Head"].rotation_euler = (-0.05, 0, s * 0.04)
        pb["Thigh.L"].rotation_euler = (th_l, 0, 0)
        pb["Shin.L"].rotation_euler = (sh_l, 0, 0)
        pb["Foot.L"].rotation_euler = (-(th_l + sh_l) * 0.45, 0, 0)
        pb["Thigh.R"].rotation_euler = (th_r, 0, 0)
        pb["Shin.R"].rotation_euler = (sh_r, 0, 0)
        pb["Foot.R"].rotation_euler = (-(th_r + sh_r) * 0.45, 0, 0)
        pb["UpperArm.L"].rotation_euler = (-s * 0.36 + 0.06, 0, -0.05)
        pb["Forearm.L"].rotation_euler = (0.28 + max(0.0, -s) * 0.16, 0, 0)
        pb["UpperArm.R"].rotation_euler = (s * 0.36 + 0.06, 0, 0.05)
        pb["Forearm.R"].rotation_euler = (0.28 + max(0.0, s) * 0.16, 0, 0)
        pb["Pelvis"].keyframe_insert(data_path="location", frame=f)
        for bn in ALL_SURV_BONES:
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "Walk")

    out_path = os.path.join(MODEL_DIR, "survivor_hazmat.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_materials="EXPORT",
    )
    print("EXPORTED SKINNED SURVIVOR:", out_path, os.path.getsize(out_path))


if __name__ == "__main__":
    build_sculpted_monster()
    if "--monster-only" not in sys.argv:
        build_sculpted_survivor()
