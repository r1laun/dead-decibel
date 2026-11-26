import math
import os
from collections import Counter
import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

BASE_GAME = "/Users/nuralynuriden/Desktop/Хоррор игра/game"
TEX_DIR = os.path.join(BASE_GAME, "assets", "textures")
MODEL_DIR = os.path.join(BASE_GAME, "assets", "models")
os.makedirs(MODEL_DIR, exist_ok=True)


def load_img(filename: str, non_color: bool = False):
    path = os.path.join(TEX_DIR, filename)
    img = bpy.data.images.load(path, check_existing=True)
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
        ti.image = load_img(tex_file, False)
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
            ni.image = load_img(norm_file, True)
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


def create_detail_obj(name: str, bm: bmesh.types.BMesh, tex_repeat: float = 2.0):
    m = bpy.data.meshes.new(name + "_mesh")
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
    )
    mat_iron = make_uv_pbr_mat(
        "SpecimenIron",
        "rusted_metal.png",
        "rusted_metal_n.png",
        base_col=(0.48, 0.45, 0.43, 1.0),
        roughness=0.44,
        metallic=0.88,
        normal_strength=1.1,
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
    )
    mat_rag = make_uv_pbr_mat(
        "SpecimenRag",
        "concrete_wall.png",
        "hazmat_fabric_n.png",
        base_col=(0.11, 0.022, 0.020, 1.0),
        roughness=0.95,
        metallic=0.0,
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

    # Elongated sinewy arms (reaching past knees) & bowed stalking legs
    for side, s in ((-1, "L"), (1, "R")):
        asym_z = -0.025 if side == -1 else 0.0
        asym_y = 0.025 if side == 1 else 0.0
        nodes_spec.update({
            f"clav_{s}": ((side * 0.17, 0.12, 1.69 + asym_z * 0.5), 0.082, 0.076),
            f"shld_{s}": ((side * 0.27, 0.09 + asym_y * 0.4, 1.66 + asym_z), 0.095, 0.088),
            f"bicep_{s}": ((side * 0.34, 0.06, 1.44 + asym_z), 0.060, 0.060),
            f"elbow_{s}": ((side * 0.37, 0.03 + asym_y, 1.22 + asym_z), 0.064, 0.066),
            f"fore_{s}": ((side * 0.35, 0.12 + asym_y, 0.99 + asym_z), 0.056, 0.058),
            f"wrist_{s}": ((side * 0.33, 0.22 + asym_y, 0.77 + asym_z), 0.042, 0.044),
            f"palm_{s}": ((side * 0.32, 0.26 + asym_y, 0.67 + asym_z), 0.056, 0.032),
            # 4 articulated splayed finger knuckles & mid-phalanges (talons added separately in bone mat!)
            f"kn1_{s}": ((side * 0.27, 0.29 + asym_y, 0.61 + asym_z), 0.014, 0.014),
            f"mid1_{s}": ((side * 0.25, 0.33 + asym_y, 0.54 + asym_z), 0.010, 0.010),
            f"kn2_{s}": ((side * 0.31, 0.30 + asym_y, 0.60 + asym_z), 0.015, 0.015),
            f"mid2_{s}": ((side * 0.30, 0.34 + asym_y, 0.52 + asym_z), 0.010, 0.010),
            f"kn3_{s}": ((side * 0.35, 0.29 + asym_y, 0.60 + asym_z), 0.014, 0.014),
            f"mid3_{s}": ((side * 0.35, 0.33 + asym_y, 0.53 + asym_z), 0.010, 0.010),
            f"kn4_{s}": ((side * 0.38, 0.26 + asym_y, 0.62 + asym_z), 0.013, 0.013),
            f"mid4_{s}": ((side * 0.40, 0.29 + asym_y, 0.56 + asym_z), 0.009, 0.009),
            # Bowed gaunt legs
            f"hip_{s}": ((side * 0.145, 0.0, 0.98), 0.098, 0.098),
            f"thigh_{s}": ((side * 0.175, 0.04, 0.75), 0.076, 0.080),
            f"knee_{s}": ((side * 0.185, 0.08, 0.52), 0.070, 0.074),
            f"calf_{s}": ((side * 0.165, 0.01, 0.32), 0.062, 0.068),
            f"ankle_{s}": ((side * 0.155, -0.03, 0.09), 0.044, 0.048),
            f"foot_{s}": ((side * 0.165, 0.14, 0.038), 0.056, 0.034),
            f"heel_{s}": ((side * 0.155, -0.09, 0.038), 0.042, 0.034),
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

    # 2. Anatomical Vertex Sculpting Pass on Subdivided Mesh (gaunt waist, sunken cheeks/maw, scapulae)
    for v in body_obj.data.vertices:
        co = v.co
        # Emaciated concave abdominal hollow & protruding lower costal V-arch
        if 1.15 < co.z < 1.46 and co.y > 0.02 and abs(co.x) < 0.14:
            belly_factor = math.sin(((co.z - 1.15) / 0.31) * math.pi)
            center_factor = max(0.0, 1.0 - abs(co.x) / 0.14)
            co.y -= 0.036 * belly_factor * center_factor
        # Sternum furrow between pectoral masses
        if 1.48 < co.z < 1.68 and co.y > 0.12 and abs(co.x) < 0.045:
            co.y -= 0.022 * (1.0 - abs(co.x) / 0.045)
        # Protruding shoulder blades (scapulae) on upper back
        if 1.50 < co.z < 1.72 and co.y < 0.02 and 0.07 < abs(co.x) < 0.21:
            scap = math.sin(((abs(co.x) - 0.07) / 0.14) * math.pi) * math.sin(((co.z - 1.50) / 0.22) * math.pi)
            co.y -= 0.028 * scap
        # Sunken hollow cheeks & dark oral concavity on front lower face (+Y)
        if 1.88 < co.z < 2.02 and co.y > 0.26:
            if 0.045 < abs(co.x) < 0.11:
                co.y -= 0.020 * (1.0 - abs(abs(co.x) - 0.075) / 0.035)
        if 1.84 < co.z < 1.97 and co.y > 0.28 and abs(co.x) < 0.072:
            # Push mouth area backward to carve space for the pitch-black maw abyss
            co.y -= 0.048 * (1.0 - abs(co.x) / 0.072)

    body_obj.data.update()

    # 3. Build Secondary & Tertiary Sculpted Details with EXACT Material Tagging
    detail_items = []

    def push_part(name: str, bm_part: bmesh.types.BMesh, mat_part, tex_rep: float = 2.0):
        obj = create_detail_obj(name, bm_part, tex_repeat=tex_rep)
        detail_items.append((obj, mat_part))
        return obj

    # A) Jutting Anatomical Ribcage Arches (6 pairs hugging thorax sides tightly)
    bm_ribs = bmesh.new()
    for ri in range(6):
        rz = 1.38 + ri * 0.044
        width = 0.122 + math.sin((ri / 5.0) * math.pi * 0.85) * 0.052
        depth = 0.098 + math.sin((ri / 5.0) * math.pi * 0.85) * 0.026
        cy = 0.066 + ri * 0.007
        for side in (-1, 1):
            rib_pts = []
            for k in range(8):
                t = k / 7.0
                ang = -0.10 + t * 2.48
                px = side * math.sin(ang) * width
                py = cy - math.cos(ang) * depth
                pz = rz + (0.012 if t < 0.3 else -t * 0.025)
                rad = 0.0065 + math.sin(t * math.pi) * 0.0055
                rib_pts.append((Vector((px, py, pz)), rad * 0.72, rad * 1.15))
            add_tube_along_points(bm_ribs, rib_pts, segs=8)
    push_part("Ribs", bm_ribs, mat_flesh, 2.4)

    # B) Protruding Dorsal Spine Vertebrae (7 sharp hunched spinous processes)
    bm_spine = bmesh.new()
    spine_pts_z = [1.16, 1.25, 1.35, 1.46, 1.56, 1.66, 1.74]
    spine_pts_y = [-0.08, -0.095, -0.09, -0.065, -0.04, 0.01, 0.08]
    for si, (sy, sz) in enumerate(zip(spine_pts_y, spine_pts_z)):
        ln = 0.052 + (0.026 if 2 <= si <= 5 else 0.0)
        pts = [
            (Vector((0.0, sy + 0.03, sz + 0.01)), 0.018, 0.024),
            (Vector((0.0, sy - ln * 0.55, sz - 0.005)), 0.012, 0.016),
            (Vector((0.0, sy - ln, sz - 0.018)), 0.004, 0.006),
        ]
        add_tube_along_points(bm_spine, pts, segs=7)
    push_part("SpineVertebrae", bm_spine, mat_flesh, 2.4)

    # C) Keratin / Bone Talons on all 8 elongated fingers + 4 toe claws
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
            hook_in = -side * 0.025
            pts = [
                (fb, 0.010, 0.010),
                (fb + Vector((hook_in * 0.4, 0.032, -0.038)), 0.007, 0.008),
                (fb + Vector((hook_in, 0.052, -0.082)), 0.0018, 0.0018),
            ]
            add_tube_along_points(bm_talons, pts, segs=7)
        # Toe talons
        for tx in (side * 0.135, side * 0.19):
            t_base = Vector((tx, 0.18, 0.034))
            add_tube_along_points(bm_talons, [
                (t_base, 0.010, 0.008),
                (t_base + Vector((0.0, 0.045, -0.012)), 0.002, 0.002),
            ], segs=6)
    push_part("Talons", bm_talons, mat_bone, 1.0)

    # D) Soviet Acoustic-Containment Iron Blind-Visor & Bolted Cranial Cage + Recessed Slit
    head_c = Vector((0.0, 0.275, 2.025))
    bm_cage = bmesh.new()
    # Lower and upper visor shield plates leaving a recessed narrow eye-slit channel!
    add_curved_visor_band(bm_cage, head_c, 0.114, 0.134, -1.22, 1.22, 2.044, 2.088, 0.016, arc_steps=18)
    add_curved_visor_band(bm_cage, head_c, 0.114, 0.134, -1.22, 1.22, 1.988, 2.028, 0.016, arc_steps=18)
    # Recessed backplate behind the slit so no hollow gaps show
    add_curved_visor_band(bm_cage, head_c, 0.106, 0.126, -1.18, 1.18, 2.022, 2.050, 0.010, arc_steps=16)
    # Center vertical nose-bridge divider bar splitting the visor into two sinister eye slits
    bmesh.ops.create_cube(bm_cage, size=1.0)
    # Use a clean dedicated mini-box via bmesh for bridge & bolts
    def add_box_bm(bm_target, size_vec, center_vec, rot_eu=Euler((0, 0, 0))):
        ret = bmesh.ops.create_cube(bm_target, size=1.0)
        verts = ret["verts"]
        bmesh.ops.scale(bm_target, vec=size_vec, verts=verts)
        bmesh.ops.rotate(bm_target, cent=(0, 0, 0), matrix=rot_eu.to_matrix(), verts=verts)
        bmesh.ops.translate(bm_target, vec=center_vec, verts=verts)

    # Replace that raw unit cube we created above with clean scaled bridge: wait — clean bm_cage first!
    bm_cage.free()
    bm_cage = bmesh.new()
    add_curved_visor_band(bm_cage, head_c, 0.115, 0.136, -1.25, 1.25, 2.044, 2.090, 0.017, arc_steps=18)
    add_curved_visor_band(bm_cage, head_c, 0.115, 0.136, -1.25, 1.25, 1.986, 2.026, 0.017, arc_steps=18)
    add_curved_visor_band(bm_cage, head_c, 0.106, 0.126, -1.20, 1.20, 2.020, 2.052, 0.010, arc_steps=16)
    # Center iron nose bridge + side hinge plates + temple hex bolts
    add_box_bm(bm_cage, (0.026, 0.022, 0.108), (0.0, 0.422, 2.038))
    for side in (-1, 1):
        add_box_bm(bm_cage, (0.022, 0.052, 0.110), (side * 0.124, 0.312, 2.038), Euler((0, 0, side * 0.28)))
        for bz in (2.005, 2.068):
            ret = bmesh.ops.create_cone(bm_cage, cap_ends=True, segments=6, radius1=0.011, radius2=0.011, depth=0.024)
            bmesh.ops.rotate(bm_cage, cent=(0, 0, 0), matrix=Euler((0, math.pi * 0.5, 0)).to_matrix(), verts=ret["verts"])
            bmesh.ops.translate(bm_cage, vec=(side * 0.134, 0.305, bz), verts=ret["verts"])
    # Crown & occipital skull cage straps
    add_curved_visor_band(bm_cage, Vector((0.0, 0.26, 2.03)), 0.112, 0.132, math.pi * 0.5, math.pi * 1.5, 1.995, 2.040, 0.012, arc_steps=14)
    crown_pts = []
    for k in range(11):
        t = k / 10.0
        a = -0.3 + t * (math.pi + 0.6)
        crown_pts.append((Vector((0.0, 0.26 + math.cos(a) * 0.135, 2.04 + math.sin(a) * 0.155)), 0.012, 0.008))
    add_tube_along_points(bm_cage, crown_pts, segs=6)
    push_part("CranialCage", bm_cage, mat_iron, 2.5)

    # Recessed dual sinister sensor slits inside the visor slot (never blows out white!)
    bm_slit = bmesh.new()
    for side in (-1, 1):
        a0 = 0.14 if side == 1 else -0.82
        a1 = 0.82 if side == 1 else -0.14
        add_curved_visor_band(bm_slit, head_c, 0.112, 0.132, a0, a1, 2.029, 2.041, 0.008, arc_steps=8)
    push_part("VisorSlit", bm_slit, mat_glow, 1.0)

    # E) Pitch-Black Recessed Oral Maw Abyss + Sinewy Cheek Tendons + Distended Split Lower Mandible + Irregular Fangs
    bm_maw = bmesh.new()
    # Recessed deep pitch-black oral throat tucked inside the skull (NEVER a protruding front box!)
    ret = bmesh.ops.create_icosphere(bm_maw, subdivisions=2, radius=0.056)
    bmesh.ops.scale(bm_maw, vec=(1.02, 0.88, 1.12), verts=ret["verts"])
    bmesh.ops.translate(bm_maw, vec=(0.0, 0.278, 1.886), verts=ret["verts"])
    push_part("MawAbyss", bm_maw, mat_maw, 1.0)

    # Split Distended Lower Mandible + Stretched Cheek/Jaw Sinew (left & right jaw rami hinged to a cleft chin!)
    bm_jaw = bmesh.new()
    for side in (-1, 1):
        ramus = [
            (Vector((side * 0.088, 0.255, 1.955)), 0.017, 0.019),
            (Vector((side * 0.074, 0.285, 1.870)), 0.015, 0.018),
            (Vector((side * 0.046, 0.340, 1.805)), 0.014, 0.016),
            (Vector((side * 0.014, 0.368, 1.788)), 0.011, 0.013),
        ]
        add_tube_along_points(bm_jaw, ramus, segs=8)
        # Stretched cheek tendon framing the dark maw mouth corner
        cheek = [
            (Vector((side * 0.082, 0.295, 1.968)), 0.012, 0.014),
            (Vector((side * 0.072, 0.320, 1.905)), 0.010, 0.012),
            (Vector((side * 0.062, 0.325, 1.842)), 0.010, 0.012),
        ]
        add_tube_along_points(bm_jaw, cheek, segs=7)
    push_part("SplitJaw", bm_jaw, mat_flesh, 2.2)

    # Upper & Lower Jagged Crooked Bone Fangs
    bm_teeth = bmesh.new()
    for ti in range(-4, 5):
        ang = ti * 0.20
        ux = math.sin(ang) * 0.070
        uy = 0.300 + math.cos(ang) * 0.076
        flen_u = 0.034 + (0.014 if abs(ti) in (1, 3) else 0.004)
        tilt_u = ti * 0.05
        # Upper fang pointing down & slightly inward
        add_tube_along_points(bm_teeth, [
            (Vector((ux, uy, 1.948)), 0.0075, 0.0075),
            (Vector((ux * 0.96, uy + 0.004, 1.948 - flen_u * 0.55)), 0.0045, 0.0045),
            (Vector((ux * 0.90 + tilt_u * 0.05, uy - 0.004, 1.948 - flen_u)), 0.0012, 0.0012),
        ], segs=6)

        # Lower fang along split jaw pointing up
        if ti == 0:
            continue  # Leave gruesome split cleft gap right at the center!
        split_ofs = 0.007 if ti > 0 else -0.007
        lx = math.sin(ang) * 0.064 + split_ofs
        ly = 0.312 + math.cos(ang) * 0.074
        lz = 1.805 + abs(ti) * 0.009
        flen_l = 0.032 + (0.012 if abs(ti) == 2 else 0.002)
        add_tube_along_points(bm_teeth, [
            (Vector((lx, ly, lz)), 0.0068, 0.0068),
            (Vector((lx * 0.96, ly + 0.002, lz + flen_l * 0.55)), 0.0042, 0.0042),
            (Vector((lx * 0.92, ly - 0.006, lz + flen_l)), 0.0012, 0.0012),
        ], segs=6)
    push_part("Fangs", bm_teeth, mat_bone, 1.0)

    # F) Restraint Hardware: Heavy Neck Collar + Chest Chain, Wrist Manacles + Broken Chains, Surgical Straps & Loincloth Rags
    bm_iron_hw = bmesh.new()
    # Neck Collar (tilted forward with neck)
    neck_c = Vector((0.0, 0.19, 1.795))
    add_curved_visor_band(bm_iron_hw, neck_c, 0.082, 0.088, 0.0, math.tau, 1.775, 1.825, 0.018, arc_steps=18)
    for side in (-1, 1):
        add_box_bm(bm_iron_hw, (0.025, 0.032, 0.054), (side * 0.098, 0.19, 1.80))
    # Chest hanging chain from front collar D-ring
    for ci in range(4):
        c_pos = Vector((0.0, 0.285 - ci * 0.012, 1.75 - ci * 0.044))
        c_rot = Euler((0.25, 0.0, math.pi * 0.5 if ci % 2 == 1 else 0.0))
        add_chain_link(bm_iron_hw, c_pos, c_rot, major_rx=0.018, major_ry=0.028, wire_r=0.0055)

    # Wrist Manacles + 4-link Dangling Broken Chains
    for side in (-1, 1):
        asym_z = -0.025 if side == -1 else 0.0
        asym_y = 0.025 if side == 1 else 0.0
        wc = Vector((side * 0.33, 0.22 + asym_y, 0.77 + asym_z))
        add_curved_visor_band(bm_iron_hw, wc, 0.048, 0.052, 0.0, math.tau, wc.z - 0.026, wc.z + 0.026, 0.014, arc_steps=14)
        for ci in range(4):
            ch_pos = wc + Vector((side * 0.055, 0.015 - ci * 0.008, -0.038 - ci * 0.042))
            ch_rot = Euler((0.08, side * 0.15, math.pi * 0.5 if ci % 2 == 1 else 0.0))
            add_chain_link(bm_iron_hw, ch_pos, ch_rot, major_rx=0.016, major_ry=0.026, wire_r=0.005)
    push_part("RestraintIron", bm_iron_hw, mat_iron, 2.5)

    # Surgical Restraint Leather Harness Straps & Torn Bloodied Hospital Containment Garment Remnants
    bm_straps = bmesh.new()
    # Tight chest containment harness strap hugging the actual thorax curve (no protruding points!)
    chest_band = []
    for k in range(21):
        a = (k / 20.0) * math.tau
        chest_band.append((Vector((math.sin(a) * 0.166, 0.062 + math.cos(a) * 0.116, 1.47)), 0.010, 0.014))
    add_tube_along_points(bm_straps, chest_band, segs=6, cap_start=False, cap_end=False)
    for side in (-1, 1):
        strap_pts = [
            (Vector((side * 0.095, 0.145, 1.46)), 0.015, 0.007),
            (Vector((side * 0.120, 0.135, 1.59)), 0.015, 0.007),
            (Vector((side * 0.130, 0.088, 1.70)), 0.015, 0.007),
            (Vector((side * 0.118, -0.015, 1.65)), 0.015, 0.007),
            (Vector((side * 0.100, -0.046, 1.47)), 0.015, 0.007),
        ]
        add_tube_along_points(bm_straps, strap_pts, segs=6)
    # Waist rope/strap binding the torn garment
    waist_band = []
    for k in range(21):
        a = (k / 20.0) * math.tau
        waist_band.append((Vector((math.sin(a) * 0.142, 0.0 + math.cos(a) * 0.102, 1.03)), 0.011, 0.012))
    add_tube_along_points(bm_straps, waist_band, segs=6, cap_start=False, cap_end=False)
    push_part("SurgicalStraps", bm_straps, mat_strap, 2.2)

    # Torn Bloodied Hospital Garment Wrap & Shredded Strips hugging pelvis/upper thighs
    bm_rags = bmesh.new()
    add_curved_visor_band(bm_rags, Vector((0.0, 0.0, 0.99)), 0.142, 0.102, 0.0, math.tau, 0.94, 1.04, 0.010, arc_steps=18)
    rag_defs = [
        (-0.13, 0.065, 0.28, -0.015, 0.055),
        (-0.04, 0.090, 0.22,  0.005, 0.065),
        ( 0.09, 0.082, 0.30,  0.015, 0.060),
        ( 0.14, 0.010, 0.25,  0.020, 0.015),
        ( 0.10,-0.082, 0.32,  0.010,-0.055),
        (-0.02,-0.092, 0.24, -0.005,-0.060),
        (-0.13,-0.058, 0.30, -0.015,-0.050),
    ]
    for rx, ry, rlen, flare_x, end_y in rag_defs:
        pts = [
            (Vector((rx, ry, 1.01)), 0.042, 0.008),
            (Vector((rx + flare_x * 0.5, (ry + end_y) * 0.55, 1.01 - rlen * 0.45)), 0.032, 0.006),
            (Vector((rx + flare_x, end_y, 1.01 - rlen)), 0.006, 0.004),
        ]
        add_tube_along_points(bm_rags, pts, segs=6)
    push_part("TornGarmentRags", bm_rags, mat_rag, 2.2)

    # 4. Create Articulated Armature & Bind Watertight Manifold Body First (Zero Bone-Heat Errors!)
    arm_data = bpy.data.armatures.new("StalkerArmature")
    arm_obj = bpy.data.objects.new("StalkerRig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def add_bone(bname, head, tail, parent_name=None):
        b = eb.new(bname)
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent_name:
            b.parent = eb[parent_name]
        return b

    add_bone("Root", (0, 0, 0), (0, 0, 0.35))
    add_bone("Pelvis", (0, 0, 1.00), (0, -0.01, 1.24), "Root")
    add_bone("Spine", (0, -0.01, 1.24), (0, 0.08, 1.54), "Pelvis")
    add_bone("Chest", (0, 0.08, 1.54), (0, 0.17, 1.77), "Spine")
    add_bone("Head", (0, 0.17, 1.77), (0, 0.27, 2.15), "Chest")
    add_bone("Jaw", (0, 0.25, 1.94), (0, 0.38, 1.80), "Head")
    for side, s in ((-1, "L"), (1, "R")):
        asym_z = -0.025 if side == -1 else 0.0
        add_bone(f"UpperArm.{s}", (side * 0.24, 0.09, 1.66 + asym_z), (side * 0.37, 0.03, 1.22 + asym_z), "Chest")
        add_bone(f"Forearm.{s}", (side * 0.37, 0.03, 1.22 + asym_z), (side * 0.32, 0.28, 0.56 + asym_z), f"UpperArm.{s}")
        add_bone(f"Thigh.{s}", (side * 0.145, 0.0, 0.98), (side * 0.185, 0.08, 0.52), "Pelvis")
        add_bone(f"Shin.{s}", (side * 0.185, 0.08, 0.52), (side * 0.155, 0.02, 0.04), f"Thigh.{s}")

    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    body_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    # 5. Pre-assign Exact Bone Vertex Groups on Each Detail Object Before Joining!
    def bind_obj_by_fn(obj, weight_fn):
        for v in obj.data.vertices:
            for bname, w in weight_fn(v.co).items():
                vg = obj.vertex_groups.get(bname) or obj.vertex_groups.new(name=bname)
                vg.add([v.index], w, "REPLACE")

    det_map = {o.name: o for o, _ in detail_items}
    bind_obj_by_fn(det_map["Ribs"], lambda co: {"Chest": 1.0} if co.z >= 1.50 else {"Spine": 0.65, "Chest": 0.35})
    bind_obj_by_fn(det_map["SpineVertebrae"], lambda co: {"Chest": 1.0} if co.z >= 1.52 else ({"Spine": 1.0} if co.z >= 1.24 else {"Pelvis": 1.0}))
    bind_obj_by_fn(det_map["Talons"], lambda co: {
        ("Forearm.L" if co.x < 0 else "Forearm.R") if co.z > 0.30 else ("Shin.L" if co.x < 0 else "Shin.R"): 1.0
    })
    for head_det in ("CranialCage", "VisorSlit", "MawAbyss"):
        bind_obj_by_fn(det_map[head_det], lambda co: {"Head": 1.0})
    bind_obj_by_fn(det_map["SplitJaw"], lambda co: {"Head": 0.35, "Jaw": 0.65} if co.z > 1.89 else {"Jaw": 1.0})
    bind_obj_by_fn(det_map["Fangs"], lambda co: {"Head": 1.0} if co.z >= 1.88 else {"Jaw": 1.0})
    bind_obj_by_fn(det_map["RestraintIron"], lambda co: {
        "Chest": 1.0} if co.z > 1.35 else {("Forearm.L" if co.x < 0 else "Forearm.R"): 1.0}
    )
    bind_obj_by_fn(det_map["SurgicalStraps"], lambda co: {"Chest": 1.0} if co.z > 1.30 else {"Pelvis": 1.0})
    bind_obj_by_fn(det_map["TornGarmentRags"], lambda co: {"Pelvis": 1.0})

    # Join all detail parts into rigged body_obj (Blender merges vertex groups & material slots cleanly!)
    join_with_exact_materials(body_obj, mat_flesh, detail_items, palette)

    # Safety check for any zero-weight vertices on main body
    vg_chest = body_obj.vertex_groups.get("Chest") or body_obj.vertex_groups.new(name="Chest")
    vg_head = body_obj.vertex_groups.get("Head") or body_obj.vertex_groups.new(name="Head")
    vg_pelvis = body_obj.vertex_groups.get("Pelvis") or body_obj.vertex_groups.new(name="Pelvis")
    for v in body_obj.data.vertices:
        if sum(g.weight for g in v.groups) < 0.05:
            if v.co.z > 1.76:
                vg_head.add([v.index], 1.0, "REPLACE")
            elif v.co.z > 1.25:
                vg_chest.add([v.index], 1.0, "REPLACE")
            else:
                vg_pelvis.add([v.index], 1.0, "REPLACE")

    # 6. Bake 4 Expressive Horror Animations (Idle, Walk, Run, Attack) at 24 FPS!
    bpy.context.scene.render.fps = 24
    arm_obj.animation_data_create()
    pb = arm_obj.pose.bones
    for b in pb:
        b.rotation_mode = "XYZ"

    def reset_pose():
        for b in pb:
            b.location = (0, 0, 0)
            b.rotation_euler = (0, 0, 0)

    # ACTION 1: Idle (64 frames: ragged breathing heave + sudden creepy acoustic listening head-twitch + jaw tremble)
    act = bpy.data.actions.new("Idle")
    arm_obj.animation_data.action = act
    idle_keys = [
        (1,  0.00,  0.00,  0.00,  0.00, 0.04),
        (16, 0.06,  0.02, -0.05,  0.10, 0.09),
        (24, 0.05,  0.03,  0.18, -0.18, 0.14),  # sharp listening head-cock
        (36, -0.02, -0.02, 0.16, -0.16, 0.06),
        (48, 0.04, -0.03, -0.14,  0.15, 0.12),  # twitch other direction
        (64, 0.00,  0.00,  0.00,  0.00, 0.04),
    ]
    for f, breath, sp_z, hd_y, hd_z, jaw_x in idle_keys:
        reset_pose()
        pb["Spine"].rotation_euler = (0.06 + breath * 0.4, 0.0, sp_z)
        pb["Chest"].rotation_euler = (0.10 + breath * 0.8, 0.0, -sp_z * 0.5)
        pb["Head"].rotation_euler = (-0.06 + breath * 0.5, hd_y, hd_z)
        pb["Jaw"].rotation_euler = (jaw_x, 0.0, 0.0)
        pb["UpperArm.L"].rotation_euler = (0.14 + breath * 0.5, 0.0, -0.07)
        pb["UpperArm.R"].rotation_euler = (0.10 - breath * 0.4, 0.0, 0.08)
        pb["Forearm.L"].rotation_euler = (0.18, 0.0, 0.0)
        pb["Forearm.R"].rotation_euler = (0.22, 0.0, 0.0)
        for bn in ("Spine", "Chest", "Head", "Jaw", "UpperArm.L", "UpperArm.R", "Forearm.L", "Forearm.R"):
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "Idle")

    # ACTION 2: Walk (36 frames: heavy stalking predatory prowl)
    act = bpy.data.actions.new("Walk")
    arm_obj.animation_data.action = act
    for idx in range(10):
        f = 1 + idx * 4  # frames 1..37
        ang = (idx / 9.0) * math.tau
        s, c = math.sin(ang), math.cos(ang)
        reset_pose()
        pb["Pelvis"].location = (0, 0, abs(c) * 0.04 - 0.025)
        pb["Spine"].rotation_euler = (-0.14, s * 0.06, -s * 0.05)
        pb["Chest"].rotation_euler = (-0.10, -s * 0.08, s * 0.07)
        pb["Head"].rotation_euler = (0.18, s * 0.14, -s * 0.10)
        pb["Jaw"].rotation_euler = (0.10 + abs(s) * 0.08, 0, 0)
        pb["Thigh.L"].rotation_euler = (s * 0.50, 0, 0)
        pb["Shin.L"].rotation_euler = (-max(0.0, -c) * 0.58, 0, 0)
        pb["Thigh.R"].rotation_euler = (-s * 0.50, 0, 0)
        pb["Shin.R"].rotation_euler = (-max(0.0, c) * 0.58, 0, 0)
        pb["UpperArm.L"].rotation_euler = (-s * 0.40 + 0.18, 0, -0.08)
        pb["Forearm.L"].rotation_euler = (0.26 + max(0.0, s) * 0.18, 0, 0)
        pb["UpperArm.R"].rotation_euler = (s * 0.40 + 0.18, 0, 0.08)
        pb["Forearm.R"].rotation_euler = (0.26 + max(0.0, -s) * 0.18, 0, 0)
        pb["Pelvis"].keyframe_insert(data_path="location", frame=f)
        for bn in ("Spine", "Chest", "Head", "Jaw", "Thigh.L", "Shin.L", "Thigh.R", "Shin.R", "UpperArm.L", "Forearm.L", "UpperArm.R", "Forearm.R"):
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "Walk")

    # ACTION 3: Run (16 frames: hunched forward predatory sprint, wide jaw, outstretched talons)
    act = bpy.data.actions.new("Run")
    arm_obj.animation_data.action = act
    for idx in range(9):
        f = 1 + idx * 2
        ang = (idx / 8.0) * math.tau
        s, c = math.sin(ang), math.cos(ang)
        reset_pose()
        pb["Pelvis"].location = (0, 0, abs(c) * 0.075 - 0.05)
        pb["Spine"].rotation_euler = (-0.28, s * 0.10, -s * 0.08)
        pb["Chest"].rotation_euler = (-0.22, -s * 0.12, s * 0.08)
        pb["Head"].rotation_euler = (0.38, 0, s * 0.10)
        pb["Jaw"].rotation_euler = (0.34 + abs(s) * 0.10, 0, 0)
        pb["Thigh.L"].rotation_euler = (s * 0.84, 0, 0)
        pb["Shin.L"].rotation_euler = (-max(0.0, -c) * 0.96, 0, 0)
        pb["Thigh.R"].rotation_euler = (-s * 0.84, 0, 0)
        pb["Shin.R"].rotation_euler = (-max(0.0, c) * 0.96, 0, 0)
        pb["UpperArm.L"].rotation_euler = (0.72 - s * 0.56, 0, -0.18)
        pb["Forearm.L"].rotation_euler = (0.48, 0, 0)
        pb["UpperArm.R"].rotation_euler = (0.72 + s * 0.56, 0, 0.18)
        pb["Forearm.R"].rotation_euler = (0.48, 0, 0)
        pb["Pelvis"].keyframe_insert(data_path="location", frame=f)
        for bn in ("Spine", "Chest", "Head", "Jaw", "Thigh.L", "Shin.L", "Thigh.R", "Shin.R", "UpperArm.L", "Forearm.L", "UpperArm.R", "Forearm.R"):
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "Run")

    # ACTION 4: Attack (20 frames: overhead windup + savage double-claw rip & jaw snap)
    act = bpy.data.actions.new("Attack")
    arm_obj.animation_data.action = act
    atk_poses = [
        (1,   0.00,  0.00, 0.10,  0.22,  0.20, -0.10),
        (6,   0.20,  0.18, 0.42,  1.65,  0.65, -0.35),
        (11, -0.32, -0.28, 0.02, -0.62,  0.15,  0.22),
        (15, -0.18, -0.12, 0.05, -0.15,  0.30,  0.10),
        (20,  0.00,  0.00, 0.10,  0.22,  0.20, -0.10),
    ]
    for f, sp_x, ch_x, jaw_x, arm_x, fore_x, hd_x in atk_poses:
        reset_pose()
        pb["Spine"].rotation_euler = (sp_x, 0, 0)
        pb["Chest"].rotation_euler = (ch_x, 0, 0)
        pb["Head"].rotation_euler = (hd_x, 0, 0)
        pb["Jaw"].rotation_euler = (jaw_x, 0, 0)
        pb["UpperArm.L"].rotation_euler = (arm_x, 0, -0.24)
        pb["UpperArm.R"].rotation_euler = (arm_x, 0, 0.24)
        pb["Forearm.L"].rotation_euler = (fore_x, 0, 0)
        pb["Forearm.R"].rotation_euler = (fore_x, 0, 0)
        for bn in ("Spine", "Chest", "Head", "Jaw", "UpperArm.L", "UpperArm.R", "Forearm.L", "Forearm.R"):
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
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
            f"knee_{s}": ((side * 0.114, 0.02, 0.47), 0.078, 0.082),
            f"ank_{s}": ((side * 0.114, -0.01, 0.10), 0.060, 0.064),
            f"foot_{s}": ((side * 0.116, 0.12, 0.042), 0.058, 0.042),
        })
        edges_spec.extend([
            ("chest_up", f"sh_{s}"),
            (f"sh_{s}", f"elb_{s}"),
            (f"elb_{s}", f"wrs_{s}"),
            (f"wrs_{s}", f"hand_{s}"),
            ("pelvis", f"hip_{s}"),
            (f"hip_{s}", f"knee_{s}"),
            (f"knee_{s}", f"ank_{s}"),
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

    # Heavy Knee-High Chemical Rubber Boots (both legs)
    for side in (-1, 1):
        bx = side * 0.115
        # Boot shin shaft + top cuff
        add_cyl_bm(bm_rub, 0.068, 0.074, 0.28, Vector((bx, 0.0, 0.20)), segs=14)
        add_cyl_bm(bm_rub, 0.078, 0.078, 0.032, Vector((bx, 0.0, 0.33)), segs=14)
        # Heavy lugged sole + toe box
        add_box_bm(bm_rub, (0.125, 0.245, 0.042), (bx, 0.062, 0.021))
        add_box_bm(bm_rub, (0.118, 0.215, 0.075), (bx, 0.056, 0.068))

    # Protective Rubber Gauntlets & Gloves
    for side in (-1, 1):
        add_cyl_bm(bm_rub, 0.056, 0.064, 0.14, Vector((side * 0.244, 0.082, 0.91)), Euler((-0.24, side * 0.04, 0)), segs=12)
        add_box_bm(bm_rub, (0.074, 0.095, 0.105), (side * 0.240, 0.108, 0.815), Euler((-0.18, 0, 0)))

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

    # 3. Articulated Humanoid Rig Bound to Pure Manifold Suit First (Zero Bone-Heat Errors!)
    arm_data = bpy.data.armatures.new("SurvivorArmature")
    arm_obj = bpy.data.objects.new("SurvivorRig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def add_b(n, h, t, p=None):
        b = eb.new(n)
        b.head = Vector(h)
        b.tail = Vector(t)
        if p:
            b.parent = eb[p]

    add_b("Root", (0, 0, 0), (0, 0, 0.30))
    add_b("Pelvis", (0, 0, 0.88), (0, 0, 1.12), "Root")
    add_b("Spine", (0, 0, 1.12), (0, 0.01, 1.52), "Pelvis")
    add_b("Head", (0, 0.01, 1.52), (0, 0.02, 1.82), "Spine")
    for side, s in ((-1, "L"), (1, "R")):
        add_b(f"UpperArm.{s}", (side * 0.20, 0, 1.39), (side * 0.252, 0.01, 1.14), "Spine")
        add_b(f"Forearm.{s}", (side * 0.252, 0.01, 1.14), (side * 0.24, 0.11, 0.82), f"UpperArm.{s}")
        add_b(f"Thigh.{s}", (side * 0.108, 0, 0.85), (side * 0.114, 0.02, 0.47), "Pelvis")
        add_b(f"Shin.{s}", (side * 0.114, 0.02, 0.47), (side * 0.116, 0.04, 0.04), f"Thigh.{s}")

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
        if co.z >= 1.52:
            return {"Head": 1.0}
        if co.z >= 1.32 and co.y > 0.14:
            # Corrugated breathing hose bridging Head -> Chest
            t = max(0.0, min(1.0, (co.z - 1.32) / 0.20))
            return {"Head": t, "Spine": 1.0 - t}
        if co.z <= 0.40:
            return {"Shin.L" if co.x < 0 else "Shin.R": 1.0}
        if co.z <= 1.02 and abs(co.x) >= 0.185:
            return {"Forearm.L" if co.x < 0 else "Forearm.R": 1.0}
        if co.z <= 1.10:
            return {"Pelvis": 1.0}
        return {"Spine": 1.0}

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

    # 5. Bake Smooth Idle & Walk NLA Animations (24 FPS)
    bpy.context.scene.render.fps = 24
    arm_obj.animation_data_create()
    pb = arm_obj.pose.bones
    for b in pb:
        b.rotation_mode = "XYZ"

    def reset_spose():
        for b in pb:
            b.location = (0, 0, 0)
            b.rotation_euler = (0, 0, 0)

    # Idle (48 frames: cautious breathing & subtle head scan)
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
        for bn in ("Spine", "Head", "UpperArm.L", "Forearm.L", "UpperArm.R", "Forearm.R"):
            pb[bn].keyframe_insert(data_path="rotation_euler", frame=f)
    push_nla_action(arm_obj, "Idle")

    # Walk (32 frames: natural grounded tactical stride with elbow & knee bend)
    act = bpy.data.actions.new("Walk")
    arm_obj.animation_data.action = act
    for idx in range(9):
        f = 1 + idx * 4
        ang = (idx / 8.0) * math.tau
        s, c = math.sin(ang), math.cos(ang)
        reset_spose()
        pb["Pelvis"].location = (0, 0, abs(c) * 0.025 - 0.015)
        pb["Spine"].rotation_euler = (-0.06, 0, -s * 0.05)
        pb["Head"].rotation_euler = (0.05, 0, s * 0.04)
        pb["Thigh.L"].rotation_euler = (s * 0.44, 0, 0)
        pb["Shin.L"].rotation_euler = (-max(0.0, -c) * 0.52, 0, 0)
        pb["Thigh.R"].rotation_euler = (-s * 0.44, 0, 0)
        pb["Shin.R"].rotation_euler = (-max(0.0, c) * 0.52, 0, 0)
        pb["UpperArm.L"].rotation_euler = (-s * 0.34 + 0.06, 0, -0.04)
        pb["Forearm.L"].rotation_euler = (0.28 + max(0.0, -s) * 0.14, 0, 0)
        pb["UpperArm.R"].rotation_euler = (s * 0.34 + 0.06, 0, 0.04)
        pb["Forearm.R"].rotation_euler = (0.28 + max(0.0, s) * 0.14, 0, 0)
        pb["Pelvis"].keyframe_insert(data_path="location", frame=f)
        for bn in ("Spine", "Head", "Thigh.L", "Shin.L", "Thigh.R", "Shin.R", "UpperArm.L", "Forearm.L", "UpperArm.R", "Forearm.R"):
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
    build_sculpted_survivor()
