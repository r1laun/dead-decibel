import os
import math
import random
import bpy
import bmesh
from mathutils import Vector, Matrix, Euler, noise

BASE_GAME = "/Users/nuralynuriden/Desktop/Хоррор игра/game"
TEX_DIR = os.path.join(BASE_GAME, "assets", "textures")
MODEL_DIR = os.path.join(BASE_GAME, "assets", "models")
os.makedirs(MODEL_DIR, exist_ok=True)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_img(filename: str, non_color: bool = False):
    path = os.path.join(TEX_DIR, filename)
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def make_pbr_mat(
    name: str,
    tex_file: str = "",
    norm_file: str = "",
    base_col=(0.5, 0.5, 0.5, 1.0),
    roughness: float = 0.78,
    metallic: float = 0.0,
    emission_col=None,
    emission_strength: float = 0.0,
    uv_scale: float = 1.0,
):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Base Color"].default_value = base_col

    if emission_col is not None and emission_strength > 0.0:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emission_col[:3], 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission_strength

    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if tex_file:
        tex_coord = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, uv_scale)
        links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])

        tex_node = nodes.new("ShaderNodeTexImage")
        tex_node.image = load_img(tex_file, non_color=False)
        links.new(mapping.outputs["Vector"], tex_node.inputs["Vector"])

        if base_col[:3] != (1.0, 1.0, 1.0):
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 0.85
            mix.inputs[6].default_value = tex_node.image and (1, 1, 1, 1)
            links.new(tex_node.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = base_col
            links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])

        if norm_file:
            n_tex = nodes.new("ShaderNodeTexImage")
            n_tex.image = load_img(norm_file, non_color=True)
            links.new(mapping.outputs["Vector"], n_tex.inputs["Vector"])
            n_map = nodes.new("ShaderNodeNormalMap")
            n_map.inputs["Strength"].default_value = 0.9
            links.new(n_tex.outputs["Color"], n_map.inputs["Color"])
            links.new(n_map.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def make_empty(name: str, loc=(0.0, 0.0, 0.0), parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.location = loc
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def finalize_mesh_obj(
    name: str,
    bm: bmesh.types.BMesh,
    mat,
    loc=(0.0, 0.0, 0.0),
    rot=(0.0, 0.0, 0.0),
    parent=None,
    smooth: bool = True,
    bevel_width: float = 0.0,
    subsurf_levels: int = 0,
):
    mesh = bpy.data.meshes.new(name + "_mesh")
    # Ensure UV layer exists with cubic projection based on bounding box / world scale
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x, co.y
            elif ax >= ay and ax >= az:
                u, v = co.y, co.z
            else:
                u, v = co.x, co.z
            loop[uv_layer].uv = (u * 1.4 + 0.5, v * 1.4 + 0.5)

    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()

    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    obj.location = loc
    obj.rotation_euler = rot
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    if mat is not None:
        obj.data.materials.append(mat)

    if bevel_width > 0.0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel_width
        bev.segments = 2
        bev.limit_method = "ANGLE"

    if subsurf_levels > 0:
        sub = obj.modifiers.new(name="Subsurf", type="SUBSURF")
        sub.levels = subsurf_levels
        sub.render_levels = subsurf_levels

    return obj


def add_box_obj(
    name: str,
    size=(1.0, 1.0, 1.0),
    offset=(0.0, 0.0, 0.0),
    mat=None,
    loc=(0.0, 0.0, 0.0),
    rot=(0.0, 0.0, 0.0),
    parent=None,
    bevel: float = 0.008,
    smooth: bool = False,
):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if offset != (0.0, 0.0, 0.0):
        bmesh.ops.translate(bm, vec=offset, verts=bm.verts)
    return finalize_mesh_obj(name, bm, mat, loc=loc, rot=rot, parent=parent, smooth=smooth, bevel_width=bevel)


def add_cyl_obj(
    name: str,
    r1: float,
    r2: float,
    depth: float,
    segs: int = 16,
    offset=(0.0, 0.0, 0.0),
    rot_mesh=(0.0, 0.0, 0.0),
    mat=None,
    loc=(0.0, 0.0, 0.0),
    rot=(0.0, 0.0, 0.0),
    parent=None,
    smooth: bool = True,
):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
    if rot_mesh != (0.0, 0.0, 0.0):
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Euler(rot_mesh).to_matrix(), verts=bm.verts)
    if offset != (0.0, 0.0, 0.0):
        bmesh.ops.translate(bm, vec=offset, verts=bm.verts)
    return finalize_mesh_obj(name, bm, mat, loc=loc, rot=rot, parent=parent, smooth=smooth)


def add_sculpted_limb(
    name: str,
    length: float,
    r_start: float,
    r_mid: float,
    r_end: float,
    offset_dir=(0.0, 0.0, -1.0),
    noise_amp: float = 0.012,
    mat=None,
    loc=(0.0, 0.0, 0.0),
    rot=(0.0, 0.0, 0.0),
    parent=None,
):
    """Create organic tapered multi-ring muscular limb segment from origin along offset_dir."""
    bm = bmesh.new()
    rings = 9
    segs = 14
    d_vec = Vector(offset_dir).normalized()
    # Orthonormal basis around d_vec
    up_ref = Vector((0, 1, 0)) if abs(d_vec.y) < 0.9 else Vector((1, 0, 0))
    u_vec = d_vec.cross(up_ref).normalized()
    v_vec = d_vec.cross(u_vec).normalized()

    ring_verts = []
    for ri in range(rings):
        t = ri / (rings - 1)
        # Smooth anatomical profile (bulge at muscle belly)
        if t < 0.5:
            st = t * 2.0
            rad = r_start * (1.0 - st) + r_mid * st
        else:
            st = (t - 0.5) * 2.0
            rad = r_mid * (1.0 - st) + r_end * st
        # Pinch slightly at ends for rounded caps
        if ri == 0 or ri == rings - 1:
            rad *= 0.68
        center = d_vec * (t * length)
        cur = []
        for si in range(segs):
            ang = (si / segs) * math.tau
            p = center + (u_vec * math.cos(ang) + v_vec * math.sin(ang)) * rad
            if noise_amp > 0.0 and 0 < ri < rings - 1:
                n = noise.noise(p * 11.0) * noise_amp
                p += (u_vec * math.cos(ang) + v_vec * math.sin(ang)) * n
            cur.append(bm.verts.new(p))
        ring_verts.append(cur)

    for ri in range(rings - 1):
        for si in range(segs):
            sn = (si + 1) % segs
            bm.faces.new([
                ring_verts[ri][si],
                ring_verts[ri][sn],
                ring_verts[ri + 1][sn],
                ring_verts[ri + 1][si],
            ])
    bm.faces.new(list(reversed(ring_verts[0])))
    bm.faces.new(ring_verts[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finalize_mesh_obj(name, bm, mat, loc=loc, rot=rot, parent=parent, smooth=True, subsurf_levels=1)


def export_glb(filename: str) -> None:
    filepath = os.path.join(MODEL_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print("EXPORTED:", filename, os.path.getsize(filepath), "bytes")


# ===========================================================================
# 1. MONSTER: SPECIMEN-07 ("ОБЪЕКТ-07 / СЛЕПОЙ ХИРУРГ")
# ===========================================================================
def build_monster_stalker() -> None:
    reset_scene()
    mat_flesh = make_pbr_mat(
        "MutantFlesh", "flesh_mutant.png", "flesh_mutant_n.png",
        base_col=(0.88, 0.78, 0.76, 1.0), roughness=0.58, metallic=0.0, uv_scale=1.5
    )
    mat_blood = make_pbr_mat(
        "DriedBloodFlesh", "flesh_mutant.png", "flesh_mutant_n.png",
        base_col=(0.42, 0.09, 0.09, 1.0), roughness=0.38, metallic=0.05, uv_scale=2.0
    )
    mat_iron = make_pbr_mat(
        "BlindfoldIron", "rusted_metal.png", "rusted_metal_n.png",
        base_col=(0.55, 0.50, 0.48, 1.0), roughness=0.52, metallic=0.82
    )
    mat_apron = make_pbr_mat(
        "BloodiedApron", "hazmat_fabric.png", "hazmat_fabric_n.png",
        base_col=(0.18, 0.13, 0.13, 1.0), roughness=0.88, metallic=0.0
    )
    mat_bone = make_pbr_mat(
        "BoneTeeth", "", "", base_col=(0.78, 0.72, 0.58, 1.0), roughness=0.42, metallic=0.0
    )

    # Facing +Y in Blender -> -Z in Godot! Floor Z = 0.0 -> Y = 0.0 in Godot!
    root = make_empty("StalkerRoot", (0, 0, 0))
    pelvis = make_empty("Pelvis", (0, 0.0, 1.06), parent=root)

    # Gaunt pelvis & tattered dark surgical apron
    add_sculpted_limb("PelvisCore", 0.24, 0.16, 0.19, 0.15, (0, 0, 1), 0.012, mat_flesh, (0, 0, -0.06), parent=pelvis)
    add_box_obj("TatteredApronFront", (0.34, 0.04, 0.52), (0, 0.14, -0.24), mat_apron, parent=pelvis, bevel=0.015, smooth=True)
    add_box_obj("TatteredApronBack", (0.32, 0.04, 0.44), (0, -0.14, -0.20), mat_apron, parent=pelvis, bevel=0.015, smooth=True)

    # Hunched Spine & Ribcage
    spine = make_empty("Spine", (0, 0.02, 0.18), parent=pelvis)
    add_sculpted_limb("TorsoMesh", 0.58, 0.15, 0.23, 0.19, (0, 0.14, 0.98), 0.018, mat_flesh, (0, 0, 0), parent=spine)

    # Exposed protruding ribs & dorsal spine vertebrae
    for ri in range(5):
        rz = 0.12 + ri * 0.085
        rw = 0.17 + math.sin(ri * 0.65) * 0.045
        for side in (-1, 1):
            add_cyl_obj(
                f"Rib_{ri}_{side}", 0.016, 0.011, 0.18, 10,
                offset=(side * rw * 0.65, 0.11 + ri * 0.01, rz),
                rot_mesh=(0.2, side * 1.15, side * 0.35),
                mat=mat_bone, parent=spine
            )
        # Dorsal spine spike
        add_cyl_obj(
            f"SpineKnob_{ri}", 0.022, 0.005, 0.08, 8,
            offset=(0, -0.15 + ri * 0.012, rz),
            rot_mesh=(-1.25, 0, 0),
            mat=mat_bone, parent=spine
        )

    # Iron chest harness strap
    add_box_obj("ChestStrap", (0.42, 0.34, 0.05), (0, 0.04, 0.36), mat_iron, parent=spine, bevel=0.01)

    # Neck & Sculpted Blindfolded Horror Skull
    neck_head = make_empty("NeckHead", (0, 0.10, 0.56), parent=spine)
    add_sculpted_limb("Neck", 0.16, 0.085, 0.075, 0.08, (0, 0.25, 0.96), 0.01, mat_flesh, (0, 0, 0), parent=neck_head)

    # Sculpted Cranium
    bm_head = bmesh.new()
    bmesh.ops.create_icosphere(bm_head, subdivisions=3, radius=0.145)
    for v in bm_head.verts:
        # Elongate skull front-to-back (+Y is face), gaunt cheekbones
        v.co.y *= 1.24
        v.co.z *= 1.18
        v.co.x *= 0.86
        if v.co.z < -0.02 and v.co.y > 0.02:
            v.co.x *= 0.75  # Hollow gaunt cheeks
        v.co += Vector((0, 0.05, 0.22))
        v.co += Vector((noise.noise(v.co * 14.0) * 0.008, 0, noise.noise(v.co * 12.0) * 0.008))
    finalize_mesh_obj("Cranium", bm_head, mat_flesh, parent=neck_head, smooth=True)

    # Rusted Iron Blindfold Visor bolted into skull (+Y front)
    add_box_obj("IronBlindfold", (0.25, 0.16, 0.075), (0, 0.11, 0.24), mat_iron, parent=neck_head, bevel=0.012, smooth=True)
    for sx in (-0.095, 0.095):
        add_cyl_obj(f"VisorBolt_{sx}", 0.016, 0.016, 0.04, 8, offset=(sx, 0.19, 0.24), rot_mesh=(1.57, 0, 0), mat=mat_iron, parent=neck_head)

    # Hinged Gaping Lower Jaw with Jagged Teeth
    jaw = make_empty("JawPivot", (0, 0.04, 0.14), parent=neck_head)
    add_sculpted_limb("LowerJaw", 0.15, 0.075, 0.068, 0.045, (0, 0.92, -0.38), 0.006, mat_blood, (0, 0, 0), parent=jaw)
    for ti in range(-2, 3):
        tx = ti * 0.022
        ty = 0.11 - abs(ti) * 0.012
        # Lower teeth
        add_cyl_obj(f"ToothLow_{ti}", 0.008, 0.001, 0.032, 6, offset=(tx, ty, -0.01), rot_mesh=(0.15, 0, 0), mat=mat_bone, parent=jaw)
        # Upper teeth on cranium
        add_cyl_obj(f"ToothUp_{ti}", 0.008, 0.001, 0.034, 6, offset=(tx, ty + 0.04, 0.15), rot_mesh=(3.0, 0, 0), mat=mat_bone, parent=neck_head)

    # Long Sinewy Arms & Bloody Claws (Left = -X, Right = +X)
    for side, sname in ((-1, "L"), (1, "R")):
        sh = make_empty(f"Shoulder{sname}", (side * 0.24, 0.06, 0.48), parent=spine)
        add_sculpted_limb(f"UpperArm{sname}", 0.44, 0.078, 0.068, 0.055, (side * 0.14, 0.08, -0.98), 0.01, mat_flesh, parent=sh)

        elb = make_empty(f"Elbow{sname}", (side * 0.06, 0.04, -0.43), parent=sh)
        add_sculpted_limb(f"Forearm{sname}", 0.48, 0.058, 0.052, 0.042, (0.0, 0.28, -0.96), 0.01, mat_blood, parent=elb)
        # Iron wrist cuff
        add_cyl_obj(f"WristShackle{sname}", 0.055, 0.055, 0.06, 12, offset=(0, 0.11, -0.38), rot_mesh=(0.28, 0, 0), mat=mat_iron, parent=elb)

        # 4 Elongated Curved Claws
        for fi in range(4):
            fx = (fi - 1.5) * 0.022
            add_cyl_obj(
                f"Claw{sname}_{fi}", 0.012, 0.002, 0.16, 7,
                offset=(fx, 0.16, -0.52),
                rot_mesh=(0.55, 0, (fi - 1.5) * 0.08),
                mat=mat_bone, parent=elb
            )

    # Legs & Rusted Ankle Shackle (Hip at z=1.06 above ground)
    for side, sname in ((-1, "L"), (1, "R")):
        hip = make_empty(f"Hip{sname}", (side * 0.13, 0.0, 0.0), parent=pelvis)
        add_sculpted_limb(f"Thigh{sname}", 0.52, 0.105, 0.088, 0.068, (0, 0.05, -1.0), 0.01, mat_flesh, parent=hip)

        knee = make_empty(f"Knee{sname}", (0, 0.025, -0.51), parent=hip)
        add_sculpted_limb(f"Shin{sname}", 0.52, 0.068, 0.055, 0.045, (0, -0.05, -1.0), 0.008, mat_blood, parent=knee)
        add_box_obj(f"Foot{sname}", (0.10, 0.23, 0.06), (0, 0.06, -0.52), mat_blood, parent=knee, bevel=0.02, smooth=True)
        if sname == "R":
            add_cyl_obj("AnkleIron", 0.062, 0.062, 0.065, 12, offset=(0, -0.02, -0.42), mat=mat_iron, parent=knee)

    export_glb("monster_stalker.glb")


# ===========================================================================
# 2. CO-OP SURVIVOR: HAZMAT TECHNICIAN
# ===========================================================================
def build_survivor_hazmat() -> None:
    reset_scene()
    mat_suit = make_pbr_mat("HazmatSuit", "hazmat_fabric.png", "hazmat_fabric_n.png", base_col=(0.95, 0.88, 0.72, 1.0), roughness=0.82)
    mat_dark = make_pbr_mat("BootsGear", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.30, 0.32, 0.35, 1.0), roughness=0.62, metallic=0.45)
    mat_visor = make_pbr_mat("MaskVisor", "", "", base_col=(0.95, 0.68, 0.18, 1.0), roughness=0.18, metallic=0.2, emission_col=(1.0, 0.65, 0.15), emission_strength=1.4)

    root = make_empty("SurvivorRoot", (0, 0, 0))
    pelvis = make_empty("Pelvis", (0, 0, 0.92), parent=root)
    torso = make_empty("Torso", (0, 0, 0.06), parent=pelvis)

    add_box_obj("ChestSuit", (0.38, 0.24, 0.50), (0, 0, 0.24), mat_suit, parent=torso, bevel=0.05, smooth=True)
    add_box_obj("RadioBackpack", (0.28, 0.14, 0.34), (0, -0.17, 0.26), mat_dark, parent=torso, bevel=0.02)

    head = make_empty("Head", (0, 0, 0.54), parent=torso)
    add_cyl_obj("HoodHead", 0.125, 0.135, 0.26, 16, offset=(0, 0, 0.13), mat=mat_suit, parent=head)
    add_box_obj("GasMaskVisor", (0.17, 0.06, 0.085), (0, 0.11, 0.15), mat_visor, parent=head, bevel=0.015, smooth=True)
    for sx in (-0.065, 0.065):
        add_cyl_obj(f"Filter_{sx}", 0.038, 0.038, 0.065, 12, offset=(sx, 0.13, 0.07), rot_mesh=(1.2, 0, sx * 2.5), mat=mat_dark, parent=head)

    for side, sname in ((-1, "L"), (1, "R")):
        arm = make_empty(f"Arm{sname}", (side * 0.24, 0, 0.44), parent=torso)
        add_sculpted_limb(f"Sleeve{sname}", 0.56, 0.072, 0.068, 0.052, (0, 0.06, -1.0), 0.004, mat_suit, parent=arm)
        add_box_obj(f"Glove{sname}", (0.08, 0.10, 0.10), (0, 0.04, -0.58), mat_dark, parent=arm, bevel=0.02, smooth=True)

        leg = make_empty(f"Leg{sname}", (side * 0.11, 0, 0), parent=pelvis)
        add_sculpted_limb(f"Pant{sname}", 0.84, 0.095, 0.085, 0.070, (0, 0, -1.0), 0.004, mat_suit, parent=leg)
        add_box_obj(f"Boot{sname}", (0.11, 0.22, 0.11), (0, 0.04, -0.86), mat_dark, parent=leg, bevel=0.02, smooth=True)

    export_glb("survivor_hazmat.glb")


# ===========================================================================
# 3. HIDING LOCKER (WITH REAL CUT-OUT PEEK SLITS!)
# ===========================================================================
def build_locker_metal() -> None:
    reset_scene()
    mat_steel = make_pbr_mat("LockerSteel", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.68, 0.74, 0.72, 1.0), roughness=0.58, metallic=0.68)
    mat_dark = make_pbr_mat("LockerInner", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.25, 0.26, 0.28, 1.0), roughness=0.75, metallic=0.5)

    root = make_empty("LockerRoot")
    W, D, H, T = 0.92, 0.86, 2.15, 0.045
    # Hollow cabinet shell (open on +Y front -> -Z in Godot)
    add_box_obj("BackWall", (W, T, H), (0, -D * 0.5 + T * 0.5, H * 0.5), mat_steel, parent=root, bevel=0.006)
    add_box_obj("LeftWall", (T, D, H), (-W * 0.5 + T * 0.5, 0, H * 0.5), mat_steel, parent=root, bevel=0.006)
    add_box_obj("RightWall", (T, D, H), (W * 0.5 - T * 0.5, 0, H * 0.5), mat_steel, parent=root, bevel=0.006)
    add_box_obj("BottomFloor", (W, D, 0.06), (0, 0, 0.03), mat_dark, parent=root, bevel=0.006)
    add_box_obj("TopRoof", (W + 0.02, D + 0.02, 0.06), (0, 0, H - 0.03), mat_steel, parent=root, bevel=0.008)

    # Hinged Door with clear eye-level horizontal louver viewing window (z = 1.34 .. 1.84)
    # Player camera inside locker sits at y ~ 1.59m, aligned with the unobstructed center band (1.56..1.66)!
    door_piv = make_empty("DoorPivot", (-W * 0.5 + 0.03, D * 0.5 - 0.02, 0.0), parent=root)
    dw = W - 0.06
    cx = dw * 0.5
    # Lower solid panel (0.05 .. 1.34)
    add_box_obj("DoorLow", (dw, 0.035, 1.29), (cx, 0, 0.695), mat_steel, parent=door_piv, bevel=0.006)
    # Slim side stiles around eye-level viewing aperture (z = 1.34 .. 1.84)
    stile_w = 0.08
    add_box_obj("DoorStileL", (stile_w, 0.035, 0.50), (stile_w * 0.5, 0, 1.59), mat_steel, parent=door_piv, bevel=0.004)
    add_box_obj("DoorStileR", (stile_w, 0.035, 0.50), (dw - stile_w * 0.5, 0, 1.59), mat_steel, parent=door_piv, bevel=0.004)
    # 3 ultra-thin horizontal iron louvers (thickness 0.014m, gently tilted, 0.13m spacing)
    # Leaves a wide unobstructed eye-level center band around z = 1.56 .. 1.66!
    slat_w = dw - stile_w * 2.0
    for si, sz in enumerate((1.42, 1.55, 1.68)):
        add_box_obj(
            f"VentSlat_{si}",
            (slat_w, 0.030, 0.014),
            offset=(0.0, 0.0, 0.0),
            mat=mat_steel,
            loc=(cx, 0.003, sz),
            rot=(0.14, 0, 0),
            parent=door_piv,
            bevel=0.002,
        )
    # Top solid header (1.84 .. 2.10)
    add_box_obj("DoorTop", (dw, 0.035, 0.26), (cx, 0, 1.97), mat_steel, parent=door_piv, bevel=0.006)
    # Door hinges & recessed handle
    for hz in (0.36, 1.05, 1.88):
        add_cyl_obj(f"DoorHinge_{hz}", 0.014, 0.014, 0.08, 10, offset=(0.01, 0.02, hz), mat=mat_dark, parent=door_piv)
    add_box_obj("DoorHandle", (0.04, 0.07, 0.18), (dw - 0.07, 0.035, 1.08), mat_dark, parent=door_piv, bevel=0.008)

    export_glb("locker_metal.glb")


# ===========================================================================
# 4. HEAVY LAB TABLE (CROUCH-UNDER HIDING SPOT)
# ===========================================================================
def build_desk_hide() -> None:
    reset_scene()
    mat_wood = make_pbr_mat("DeskTopWood", "dirty_wood.png", "dirty_wood_n.png", base_col=(0.82, 0.74, 0.66, 1.0), roughness=0.84)
    mat_metal = make_pbr_mat("DeskLegs", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.55, 0.55, 0.58, 1.0), roughness=0.62, metallic=0.7)
    mat_cloth = make_pbr_mat("DeskCloth", "hazmat_fabric.png", "hazmat_fabric_n.png", base_col=(0.28, 0.22, 0.22, 1.0), roughness=0.92)

    root = make_empty("DeskRoot")
    W, D, H = 1.90, 0.96, 1.02
    add_box_obj("TableTop", (W, D, 0.07), (0, 0, H - 0.035), mat_wood, parent=root, bevel=0.012)
    # Drape cloth hanging halfway down back & sides for cozy hiding visual
    add_box_obj("BackDrape", (W - 0.12, 0.025, 0.58), (0, -D * 0.44, H - 0.34), mat_cloth, parent=root, bevel=0.01)
    for lx in (-W * 0.44, W * 0.44):
        for ly in (-D * 0.42, D * 0.42):
            add_box_obj(f"Leg_{lx}_{ly}", (0.07, 0.07, H - 0.06), (lx, ly, (H - 0.06) * 0.5), mat_metal, parent=root, bevel=0.008)
    export_glb("desk_hide.glb")


# ===========================================================================
# 5. INTERACTIVE ROOM DOOR
# ===========================================================================
def build_door_heavy() -> None:
    reset_scene()
    mat_frame = make_pbr_mat("DoorFrame", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.38, 0.40, 0.42, 1.0), roughness=0.68, metallic=0.72)
    mat_leaf = make_pbr_mat("DoorLeaf", "dirty_wood.png", "dirty_wood_n.png", base_col=(0.68, 0.56, 0.48, 1.0), roughness=0.78, metallic=0.1)

    root = make_empty("DoorRoot")
    W, H = 1.32, 2.45
    add_box_obj("JambL", (0.10, 0.30, H), (-W * 0.5 - 0.04, 0, H * 0.5), mat_frame, parent=root)
    add_box_obj("JambR", (0.10, 0.30, H), (W * 0.5 + 0.04, 0, H * 0.5), mat_frame, parent=root)
    add_box_obj("Lintel", (W + 0.20, 0.30, 0.12), (0, 0, H + 0.05), mat_frame, parent=root)

    piv = make_empty("DoorPivot", (-W * 0.5, 0, 0), parent=root)
    # Solid lower & upper panels + barred inspection window
    add_box_obj("LeafLow", (W, 0.07, 1.48), (W * 0.5, 0, 0.74), mat_leaf, parent=piv, bevel=0.01)
    add_box_obj("LeafTop", (W, 0.07, 0.44), (W * 0.5, 0, 2.22), mat_leaf, parent=piv, bevel=0.01)
    add_box_obj("LeafStileL", (0.36, 0.07, 0.54), (0.18, 0, 1.74), mat_leaf, parent=piv, bevel=0.008)
    add_box_obj("LeafStileR", (0.36, 0.07, 0.54), (W - 0.18, 0, 1.74), mat_leaf, parent=piv, bevel=0.008)
    for bi in range(3):
        bx = 0.48 + bi * 0.18
        add_cyl_obj(f"WindowBar_{bi}", 0.012, 0.012, 0.54, 8, offset=(bx, 0, 1.74), mat=mat_frame, parent=piv)
    # Lever handle both sides
    add_box_obj("HandlePlate", (0.06, 0.13, 0.22), (W - 0.14, 0, 1.05), mat_frame, parent=piv, bevel=0.008)
    add_box_obj("HandleLeverF", (0.14, 0.03, 0.03), (W - 0.19, 0.08, 1.05), mat_frame, parent=piv, bevel=0.006)
    add_box_obj("HandleLeverB", (0.14, 0.03, 0.03), (W - 0.19, -0.08, 1.05), mat_frame, parent=piv, bevel=0.006)
    export_glb("door_heavy.glb")


# ===========================================================================
# 6. MAIN ESCAPE BLAST GATE ("EXIT AIRLOCK" WITH 4 VISIBLE LOCKS!)
# ===========================================================================
def build_exit_airlock() -> None:
    reset_scene()
    mat_steel = make_pbr_mat("BlastSteel", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.56, 0.60, 0.64, 1.0), roughness=0.52, metallic=0.78)
    mat_hazard = make_pbr_mat("HazardTrim", "hazard_stripes.png", "", base_col=(1, 1, 1, 1), roughness=0.65)
    mat_wood = make_pbr_mat("BoardWood", "dirty_wood.png", "dirty_wood_n.png", base_col=(0.88, 0.72, 0.54, 1.0), roughness=0.85)
    mat_brass = make_pbr_mat("PadlockBrass", "rusted_metal.png", "", base_col=(0.92, 0.72, 0.24, 1.0), roughness=0.38, metallic=0.85)
    mat_wire = make_pbr_mat("RedCable", "", "", base_col=(0.90, 0.12, 0.12, 1.0), roughness=0.42, emission_col=(0.8, 0.08, 0.08), emission_strength=0.45)
    mat_red = make_pbr_mat("LampRed", "", "", base_col=(1.0, 0.1, 0.1, 1.0), roughness=0.2, emission_col=(1.0, 0.12, 0.12), emission_strength=3.2)
    mat_grn = make_pbr_mat("LampGreen", "", "", base_col=(0.15, 1.0, 0.35, 1.0), roughness=0.2, emission_col=(0.15, 1.0, 0.35), emission_strength=3.2)

    root = make_empty("ExitGateRoot")
    W, H = 2.4, 2.8
    # Heavy Frame + Hazard Threshold
    add_box_obj("GateFrameL", (0.24, 0.38, H), (-W * 0.5 - 0.10, 0, H * 0.5), mat_steel, parent=root)
    add_box_obj("GateFrameR", (0.24, 0.38, H), (W * 0.5 + 0.10, 0, H * 0.5), mat_steel, parent=root)
    add_box_obj("GateHeader", (W + 0.48, 0.42, 0.32), (0, 0, H + 0.14), mat_hazard, parent=root)
    add_box_obj("Threshold", (W + 0.40, 0.44, 0.08), (0, 0.04, 0.04), mat_hazard, parent=root)

    # Sliding Blast Doors
    dl = make_empty("DoorLeft", (0, 0, 0), parent=root)
    dr = make_empty("DoorRight", (0, 0, 0), parent=root)
    add_box_obj("BlastLeafL", (W * 0.5, 0.14, H), (-W * 0.25, 0, H * 0.5), mat_steel, parent=dl, bevel=0.015)
    add_box_obj("BlastLeafR", (W * 0.5, 0.14, H), (W * 0.25, 0, H * 0.5), mat_steel, parent=dr, bevel=0.015)

    # LOCK 1: Nailed Wooden Planks (Crowbar removes!)
    planks = make_empty("LockPlanks", (0, 0.12, 0), parent=root)
    add_box_obj("Plank1", (2.35, 0.06, 0.22), (0, 0, 1.62), mat_wood, rot=(0, 0.07, 0), parent=planks, bevel=0.008)
    add_box_obj("Plank2", (2.30, 0.06, 0.22), (0, 0.02, 0.96), mat_wood, rot=(0, -0.06, 0), parent=planks, bevel=0.008)

    # LOCK 2: Heavy Chain & Master Padlock (Master Key removes!)
    padlock = make_empty("LockPadlock", (0, 0.16, 1.28), parent=root)
    add_box_obj("ChainBar", (0.62, 0.05, 0.07), (0, 0, 0.04), mat_steel, parent=padlock, bevel=0.01)
    add_box_obj("PadlockBody", (0.16, 0.07, 0.20), (0, 0.04, -0.08), mat_brass, parent=padlock, bevel=0.018)
    add_cyl_obj("PadlockShackle", 0.055, 0.055, 0.12, 10, offset=(0, 0.04, 0.04), mat=mat_steel, parent=padlock)

    # LOCK 3: High-Voltage Security Cable (Wire Cutters snip!)
    cable = make_empty("LockCable", (0.86, 0.14, 1.32), parent=root)
    add_box_obj("JunctionBox", (0.28, 0.12, 0.36), (0.28, 0, 0.15), mat_steel, parent=cable, bevel=0.01)
    add_cyl_obj("RedSecurityWire", 0.024, 0.024, 0.85, 10, offset=(-0.12, 0.02, 0.0), rot_mesh=(0, 1.15, 0), mat=mat_wire, parent=cable)

    # LOCK 4: Generator Power Status Beacon
    add_cyl_obj("StatusRed", 0.08, 0.08, 0.08, 12, offset=(0, 0.24, H + 0.14), rot_mesh=(1.57, 0, 0), mat=mat_red, parent=root)
    grn_lamp = add_cyl_obj("StatusGreen", 0.08, 0.08, 0.08, 12, offset=(0, 0.24, H + 0.14), rot_mesh=(1.57, 0, 0), mat=mat_grn, parent=root)
    grn_lamp.scale = (0.01, 0.01, 0.01)

    export_glb("exit_airlock.glb")


# ===========================================================================
# 7. SEARCHABLE DRAWER CABINET, WALL SAFE & FUSE GENERATOR
# ===========================================================================
def build_containers_and_puzzles() -> None:
    # A) Searchable Cabinet
    reset_scene()
    mat_cab = make_pbr_mat("CabSteel", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.52, 0.58, 0.56, 1.0), roughness=0.60, metallic=0.65)
    mat_dark = make_pbr_mat("CabDark", "rusted_metal.png", "", base_col=(0.22, 0.24, 0.26, 1.0), roughness=0.75, metallic=0.5)
    root = make_empty("CabinetRoot")
    add_box_obj("CabBody", (0.86, 0.62, 0.92), (0, 0, 0.46), mat_cab, parent=root, bevel=0.012)
    drw = make_empty("DrawerPivot", (0, 0.28, 0.64), parent=root)
    add_box_obj("DrawerTray", (0.74, 0.50, 0.24), (0, -0.20, 0), mat_dark, parent=drw, bevel=0.008)
    add_box_obj("DrawerFront", (0.78, 0.04, 0.28), (0, 0.05, 0), mat_cab, parent=drw, bevel=0.01)
    add_box_obj("DrawerPull", (0.20, 0.04, 0.03), (0, 0.09, 0), mat_dark, parent=drw, bevel=0.006)
    export_glb("cabinet_search.glb")

    # B) Wall Safe with Keypad
    reset_scene()
    mat_safe = make_pbr_mat("SafeIron", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.36, 0.38, 0.42, 1.0), roughness=0.48, metallic=0.82)
    mat_gold = make_pbr_mat("SafeDial", "", "", base_col=(0.85, 0.68, 0.24, 1.0), roughness=0.35, metallic=0.85)
    mat_led = make_pbr_mat("KeypadGlow", "", "", base_col=(1.0, 0.25, 0.15, 1.0), roughness=0.2, emission_col=(1.0, 0.2, 0.1), emission_strength=2.2)
    root = make_empty("SafeRoot")
    # Recessed box mounted on wall or pedestal (z=0 bottom of safe)
    add_box_obj("SafeShellBack", (0.62, 0.06, 0.62), (0, -0.22, 0.31), mat_safe, parent=root)
    add_box_obj("SafeShellL", (0.06, 0.46, 0.62), (-0.28, 0, 0.31), mat_safe, parent=root)
    add_box_obj("SafeShellR", (0.06, 0.46, 0.62), (0.28, 0, 0.31), mat_safe, parent=root)
    add_box_obj("SafeShellBot", (0.62, 0.46, 0.06), (0, 0, 0.03), mat_safe, parent=root)
    add_box_obj("SafeShellTop", (0.62, 0.46, 0.06), (0, 0, 0.59), mat_safe, parent=root)

    sdoor = make_empty("SafeDoorPivot", (-0.25, 0.21, 0.31), parent=root)
    add_box_obj("SafeDoor", (0.50, 0.05, 0.50), (0.25, 0, 0), mat_safe, parent=sdoor, bevel=0.012)
    add_box_obj("KeypadPanel", (0.16, 0.03, 0.22), (0.34, 0.035, 0.02), mat_gold, parent=sdoor, bevel=0.006)
    add_box_obj("KeypadLED", (0.10, 0.02, 0.035), (0.34, 0.05, 0.09), mat_led, parent=sdoor)
    add_cyl_obj("WheelHandle", 0.065, 0.065, 0.05, 12, offset=(0.14, 0.04, 0), rot_mesh=(1.57, 0, 0), mat=mat_gold, parent=sdoor)
    export_glb("safe_wall.glb")

    # C) Basement Fuse Generator
    reset_scene()
    mat_gen = make_pbr_mat("GenSteel", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.45, 0.52, 0.48, 1.0), roughness=0.58, metallic=0.72)
    mat_haz = make_pbr_mat("GenHazard", "hazard_stripes.png", "", base_col=(1, 1, 1, 1), roughness=0.65)
    mat_glow = make_pbr_mat("FuseGlow", "", "", base_col=(1.0, 0.72, 0.2, 1.0), roughness=0.2, emission_col=(1.0, 0.68, 0.15), emission_strength=3.0)
    root = make_empty("GeneratorRoot")
    add_box_obj("GenBase", (1.10, 0.72, 1.35), (0, 0, 0.675), mat_gen, parent=root, bevel=0.018)
    add_box_obj("GenStripe", (1.12, 0.74, 0.18), (0, 0, 0.14), mat_haz, parent=root, bevel=0.008)
    add_box_obj("FuseRecess", (0.28, 0.08, 0.36), (-0.18, 0.35, 0.92), mat_haz, parent=root)
    fuse_mesh = add_cyl_obj("FuseInstalled", 0.048, 0.048, 0.24, 12, offset=(-0.18, 0.40, 0.92), mat=mat_glow, parent=root)
    fuse_mesh.scale = (0.01, 0.01, 0.01)

    lev = make_empty("LeverPivot", (0.26, 0.36, 0.92), parent=root)
    add_cyl_obj("LeverArm", 0.02, 0.02, 0.28, 8, offset=(0, 0.10, 0.10), rot_mesh=(0.75, 0, 0), mat=mat_gen, parent=lev)
    add_box_obj("LeverGrip", (0.14, 0.05, 0.05), (0, 0.20, 0.20), mat_glow, parent=lev, bevel=0.01)
    export_glb("generator_panel.glb")


# ===========================================================================
# 8. PICKUP & HANDHELD 3D TOOLS + ATMOSPHERIC PROPS
# ===========================================================================
def build_items_and_props() -> None:
    # 1. Crowbar
    reset_scene()
    m_red = make_pbr_mat("CrowRed", "rusted_metal.png", "", base_col=(0.88, 0.18, 0.16, 1.0), roughness=0.45, metallic=0.65)
    m_stl = make_pbr_mat("CrowSteel", "rusted_metal.png", "", base_col=(0.78, 0.82, 0.86, 1.0), roughness=0.38, metallic=0.88)
    r = make_empty("CrowbarRoot")
    add_cyl_obj("Shaft", 0.018, 0.018, 0.56, 8, offset=(0, 0, 0.03), rot_mesh=(0, 1.57, 0), mat=m_red, parent=r)
    add_box_obj("CurvedHook", (0.14, 0.036, 0.11), (0.31, 0, 0.07), m_stl, rot=(0, -0.55, 0), parent=r, bevel=0.008)
    add_box_obj("PryChisel", (0.11, 0.042, 0.016), (-0.31, 0, 0.02), m_stl, rot=(0, 0.22, 0), parent=r, bevel=0.004)
    export_glb("item_crowbar.glb")

    # 2. Wire Cutters
    reset_scene()
    m_yel = make_pbr_mat("GripYel", "", "", base_col=(0.95, 0.68, 0.12, 1.0), roughness=0.62)
    m_jaw = make_pbr_mat("JawSteel", "rusted_metal.png", "", base_col=(0.72, 0.76, 0.80, 1.0), roughness=0.38, metallic=0.88)
    r = make_empty("CuttersRoot")
    add_cyl_obj("GripL", 0.018, 0.015, 0.26, 10, offset=(-0.10, -0.06, 0.03), rot_mesh=(0.22, 1.57, 0), mat=m_yel, parent=r)
    add_cyl_obj("GripR", 0.018, 0.015, 0.26, 10, offset=(-0.10, 0.06, 0.03), rot_mesh=(-0.22, 1.57, 0), mat=m_yel, parent=r)
    add_cyl_obj("PivotBolt", 0.038, 0.038, 0.035, 12, offset=(0.05, 0, 0.03), mat=m_jaw, parent=r)
    add_box_obj("JawL", (0.13, 0.028, 0.028), (0.13, -0.02, 0.03), m_jaw, rot=(0, 0, 0.16), parent=r, bevel=0.005)
    add_box_obj("JawR", (0.13, 0.028, 0.028), (0.13, 0.02, 0.03), m_jaw, rot=(0, 0, -0.16), parent=r, bevel=0.005)
    export_glb("item_cutters.glb")

    # 3. High-Voltage Fuse
    reset_scene()
    m_br = make_pbr_mat("CapBrass", "rusted_metal.png", "", base_col=(0.88, 0.68, 0.26, 1.0), roughness=0.35, metallic=0.88)
    m_gl = make_pbr_mat("CoreAmber", "", "", base_col=(1.0, 0.72, 0.18, 1.0), roughness=0.2, emission_col=(1.0, 0.68, 0.15), emission_strength=2.5)
    r = make_empty("FuseRoot")
    add_cyl_obj("CoreTube", 0.038, 0.038, 0.22, 14, offset=(0, 0, 0.05), rot_mesh=(0, 1.57, 0), mat=m_gl, parent=r)
    add_cyl_obj("CapA", 0.045, 0.045, 0.05, 14, offset=(-0.11, 0, 0.05), rot_mesh=(0, 1.57, 0), mat=m_br, parent=r)
    add_cyl_obj("CapB", 0.045, 0.045, 0.05, 14, offset=(0.11, 0, 0.05), rot_mesh=(0, 1.57, 0), mat=m_br, parent=r)
    export_glb("item_fuse.glb")

    # 4. Master Key
    reset_scene()
    m_key = make_pbr_mat("MasterBrass", "rusted_metal.png", "", base_col=(0.94, 0.76, 0.28, 1.0), roughness=0.32, metallic=0.90)
    m_tag = make_pbr_mat("KeyTag", "", "", base_col=(0.82, 0.16, 0.14, 1.0), roughness=0.55)
    r = make_empty("KeyRoot")
    add_cyl_obj("KeyBow", 0.055, 0.055, 0.018, 14, offset=(-0.09, 0, 0.02), mat=m_key, parent=r)
    add_box_obj("KeyShaft", (0.18, 0.018, 0.016), (0.02, 0, 0.02), m_key, parent=r, bevel=0.003)
    add_box_obj("KeyTeeth1", (0.025, 0.04, 0.014), (0.07, -0.025, 0.02), m_key, parent=r)
    add_box_obj("KeyTeeth2", (0.022, 0.032, 0.014), (0.10, -0.020, 0.02), m_key, parent=r)
    add_box_obj("RedKeyTag", (0.08, 0.05, 0.012), (-0.17, 0.02, 0.02), m_tag, parent=r, bevel=0.004)
    export_glb("item_key.glb")

    # 5. Bloody Safe Code Clipboard Note
    reset_scene()
    m_bd = make_pbr_mat("ClipWood", "dirty_wood.png", "", base_col=(0.75, 0.58, 0.42, 1.0), roughness=0.8)
    m_pg = make_pbr_mat("NotePaper", "", "", base_col=(0.90, 0.85, 0.72, 1.0), roughness=0.88, emission_col=(0.25, 0.22, 0.18), emission_strength=0.25)
    m_ink = make_pbr_mat("BloodInk", "", "", base_col=(0.68, 0.08, 0.08, 1.0), roughness=0.5)
    r = make_empty("NoteRoot")
    add_box_obj("Board", (0.24, 0.32, 0.016), (0, 0, 0.01), m_bd, parent=r, bevel=0.004)
    add_box_obj("Sheet", (0.20, 0.26, 0.006), (0, -0.01, 0.02), m_pg, parent=r)
    add_box_obj("Scrawl1", (0.13, 0.022, 0.004), (0, 0.04, 0.025), m_ink, parent=r)
    add_box_obj("Scrawl2", (0.11, 0.022, 0.004), (-0.01, -0.03, 0.025), m_ink, parent=r)
    export_glb("item_code_note.glb")

    # 6. Glass Decoy Bottle
    reset_scene()
    m_bt = make_pbr_mat("BottleGlass", "", "", base_col=(0.22, 0.48, 0.30, 1.0), roughness=0.16, metallic=0.1)
    r = make_empty("BottleRoot")
    add_cyl_obj("BottleBody", 0.048, 0.048, 0.18, 14, offset=(0, 0, 0.09), mat=m_bt, parent=r)
    add_cyl_obj("BottleShoulder", 0.048, 0.018, 0.06, 14, offset=(0, 0, 0.21), mat=m_bt, parent=r)
    add_cyl_obj("BottleNeck", 0.018, 0.020, 0.08, 12, offset=(0, 0, 0.27), mat=m_bt, parent=r)
    export_glb("item_bottle.glb")

    # 7. Adrenaline Syringe
    reset_scene()
    m_syr = make_pbr_mat("SyringeBody", "", "", base_col=(0.82, 0.88, 0.92, 1.0), roughness=0.25, metallic=0.4)
    m_ser = make_pbr_mat("GreenSerum", "", "", base_col=(0.2, 0.95, 0.45, 1.0), roughness=0.2, emission_col=(0.15, 0.9, 0.4), emission_strength=1.6)
    r = make_empty("SyringeRoot")
    add_cyl_obj("Barrel", 0.022, 0.022, 0.16, 12, offset=(0, 0, 0.03), rot_mesh=(0, 1.57, 0), mat=m_ser, parent=r)
    add_cyl_obj("Collar", 0.028, 0.028, 0.03, 12, offset=(-0.08, 0, 0.03), rot_mesh=(0, 1.57, 0), mat=m_syr, parent=r)
    add_cyl_obj("Needle", 0.004, 0.002, 0.09, 8, offset=(0.12, 0, 0.03), rot_mesh=(0, 1.57, 0), mat=m_syr, parent=r)
    export_glb("item_syringe.glb")

    # 8. Flashlight Battery
    reset_scene()
    m_b1 = make_pbr_mat("BatCase", "", "", base_col=(0.18, 0.20, 0.24, 1.0), roughness=0.45, metallic=0.6)
    m_b2 = make_pbr_mat("BatTop", "", "", base_col=(0.92, 0.62, 0.14, 1.0), roughness=0.42, metallic=0.5)
    r = make_empty("BatteryRoot")
    add_cyl_obj("CellMain", 0.042, 0.042, 0.12, 14, offset=(0, 0, 0.06), mat=m_b1, parent=r)
    add_cyl_obj("CellBand", 0.043, 0.043, 0.04, 14, offset=(0, 0, 0.12), mat=m_b2, parent=r)
    add_cyl_obj("CellTerm", 0.016, 0.016, 0.02, 10, offset=(0, 0, 0.15), mat=m_b2, parent=r)
    export_glb("item_battery.glb")

    # 9. Prop: Hospital Gurney Bed
    reset_scene()
    m_fr = make_pbr_mat("GurneySteel", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.62, 0.64, 0.66, 1.0), roughness=0.55, metallic=0.75)
    m_mt = make_pbr_mat("StainedMattress", "flesh_mutant.png", "", base_col=(0.62, 0.58, 0.54, 1.0), roughness=0.88)
    r = make_empty("GurneyRoot")
    add_box_obj("Mattress", (0.86, 1.92, 0.14), (0, 0, 0.78), m_mt, parent=r, bevel=0.03, smooth=True)
    add_box_obj("HeadRail", (0.88, 0.05, 0.34), (0, -0.96, 0.88), m_fr, parent=r, bevel=0.01)
    add_box_obj("FootRail", (0.88, 0.05, 0.26), (0, 0.96, 0.84), m_fr, parent=r, bevel=0.01)
    for lx in (-0.38, 0.38):
        for ly in (-0.86, 0.86):
            add_cyl_obj(f"GLeg_{lx}_{ly}", 0.026, 0.026, 0.72, 10, offset=(lx, ly, 0.36), mat=m_fr, parent=r)
    export_glb("prop_gurney.glb")

    # 10. Prop: Rusted Industrial Barrel
    reset_scene()
    m_br = make_pbr_mat("BarrelRust", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.56, 0.36, 0.28, 1.0), roughness=0.68, metallic=0.65)
    r = make_empty("BarrelRoot")
    add_cyl_obj("Drum", 0.31, 0.31, 0.94, 18, offset=(0, 0, 0.47), mat=m_br, parent=r)
    for rz in (0.06, 0.34, 0.62, 0.90):
        add_cyl_obj(f"Rim_{rz}", 0.325, 0.325, 0.03, 18, offset=(0, 0, rz), mat=m_br, parent=r)
    export_glb("prop_barrel.glb")

    # 11. Prop: Caged Ceiling Light Fixture
    reset_scene()
    m_cg = make_pbr_mat("CageIron", "rusted_metal.png", "", base_col=(0.32, 0.34, 0.36, 1.0), roughness=0.6, metallic=0.8)
    m_blb = make_pbr_mat("WarmBulb", "", "", base_col=(1.0, 0.88, 0.65, 1.0), roughness=0.15, emission_col=(1.0, 0.82, 0.52), emission_strength=3.5)
    r = make_empty("LampRoot")
    add_cyl_obj("MountPlate", 0.14, 0.16, 0.06, 14, offset=(0, 0, -0.03), mat=m_cg, parent=r)
    add_cyl_obj("BulbGlass", 0.065, 0.045, 0.16, 12, offset=(0, 0, -0.13), mat=m_blb, parent=r)
    export_glb("prop_ceiling_lamp.glb")

    # 12. Prop: Wall Pipe Cluster + Red Valve
    reset_scene()
    m_pp = make_pbr_mat("PipeRust", "rusted_metal.png", "rusted_metal_n.png", base_col=(0.52, 0.46, 0.42, 1.0), roughness=0.62, metallic=0.75)
    m_vl = make_pbr_mat("ValveRed", "", "", base_col=(0.78, 0.15, 0.14, 1.0), roughness=0.45, metallic=0.6)
    r = make_empty("PipesRoot")
    add_cyl_obj("PipeA", 0.065, 0.065, 2.8, 12, offset=(-0.12, 0, 1.4), mat=m_pp, parent=r)
    add_cyl_obj("PipeB", 0.045, 0.045, 2.8, 12, offset=(0.08, 0, 1.4), mat=m_pp, parent=r)
    add_cyl_obj("ValveWheel", 0.15, 0.15, 0.03, 14, offset=(-0.12, 0.11, 1.35), rot_mesh=(1.57, 0, 0), mat=m_vl, parent=r)
    export_glb("prop_pipes.glb")


if __name__ == "__main__":
    build_locker_metal()
    print("LOCKER_METAL_GLB_COMPLETE")
