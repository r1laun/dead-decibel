import os
import math
import bpy
import bmesh
import numpy as np
from mathutils import Euler, Vector

BASE_GAME = "/Users/nuralynuriden/Desktop/Хоррор игра/game"
TEX_DIR = os.path.join(BASE_GAME, "assets", "textures")
MODEL_DIR = os.path.join(BASE_GAME, "assets", "models")
ICON_DIR = os.path.join(BASE_GAME, "assets", "icons")


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_img(filename: str, non_color: bool = False):
    path = os.path.join(TEX_DIR, filename)
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def make_mat(name: str, tex: str = "", norm: str = "", col=(0.5, 0.5, 0.5, 1.0), rough=0.72, metal=0.0, emit_col=None, emit_str=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit_col is not None and emit_str > 0.0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*emit_col[:3], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_str
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if tex:
        ti = nodes.new("ShaderNodeTexImage")
        ti.image = load_img(tex, False)
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.85
        links.new(ti.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = col
        links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        if norm:
            ni = nodes.new("ShaderNodeTexImage")
            ni.image = load_img(norm, True)
            nm = nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 0.9
            links.new(ni.outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_empty(name: str, loc=(0.0, 0.0, 0.0), parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.location = loc
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def finish_obj(name: str, bm: bmesh.types.BMesh, mat, loc=(0, 0, 0), rot=(0, 0, 0), parent=None, bevel: float = 0.0, smooth: bool = False):
    mesh = bpy.data.meshes.new(name + "_m")
    uv_l = bm.loops.layers.uv.verify()
    for f in bm.faces:
        f.smooth = smooth
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for lp in f.loops:
            co = lp.vert.co
            u, v = (co.x, co.y) if (az >= ax and az >= ay) else ((co.y, co.z) if ax >= ay else (co.x, co.z))
            lp[uv_l].uv = (u * 1.4 + 0.5, v * 1.4 + 0.5)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()

    obj = bpy.data.objects.new(name, mesh)
    obj.location = loc
    obj.rotation_euler = rot
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    if mat is not None:
        obj.data.materials.append(mat)
    if bevel > 0.0:
        bv = obj.modifiers.new("Bevel", "BEVEL")
        bv.width = bevel
        bv.segments = 2
    return obj


def box(name: str, sz=(1, 1, 1), ofs=(0, 0, 0), mat=None, loc=(0, 0, 0), rot=(0, 0, 0), parent=None, bevel=0.006, smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=sz, verts=bm.verts)
    if ofs != (0, 0, 0):
        bmesh.ops.translate(bm, vec=ofs, verts=bm.verts)
    return finish_obj(name, bm, mat, loc, rot, parent, bevel, smooth)


def cyl(name: str, r1, r2, depth, segs=14, ofs=(0, 0, 0), rot_m=(0, 0, 0), mat=None, loc=(0, 0, 0), rot=(0, 0, 0), parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    if rot_m != (0, 0, 0):
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Euler(rot_m).to_matrix(), verts=bm.verts)
    if ofs != (0, 0, 0):
        bmesh.ops.translate(bm, vec=ofs, verts=bm.verts)
    return finish_obj(name, bm, mat, loc, rot, parent, 0.0, True)


def export_glb(fname: str) -> None:
    p = os.path.join(MODEL_DIR, fname)
    bpy.ops.export_scene.gltf(filepath=p, export_format="GLB", export_yup=True, export_apply=True, export_materials="EXPORT")
    print("EXPORTED:", fname, os.path.getsize(p))


def build_all_expansion_models() -> None:
    # 1. Industrial Shelving Rack packed with boxes & canisters
    reset_scene()
    m_st = make_mat("RackSteel", "rusted_metal.png", "rusted_metal_n.png", (0.48, 0.52, 0.55, 1), 0.58, 0.75)
    m_wd = make_mat("CrateWood", "dirty_wood.png", "dirty_wood_n.png", (0.76, 0.62, 0.45, 1), 0.85)
    m_cn = make_mat("ChemCan", "", "", (0.26, 0.44, 0.48, 1), 0.35, 0.3)
    r = make_empty("ShelfRoot")
    W, D, H = 1.85, 0.64, 2.22
    for sx in (-W * 0.48, W * 0.48):
        for sy in (-D * 0.46, D * 0.46):
            box(f"Post_{sx}_{sy}", (0.05, 0.05, H), (sx, sy, H * 0.5), m_st, parent=r)
    for sz in (0.18, 0.78, 1.38, 1.98):
        box(f"Shelf_{sz}", (W, D, 0.04), (0, 0, sz), m_st, parent=r)
    # Props on shelves so rooms look rich & lived-in!
    box("Crate1", (0.48, 0.44, 0.36), (-0.45, 0, 0.38), m_wd, rot=(0, 0, 0.08), parent=r, bevel=0.01)
    box("Crate2", (0.52, 0.46, 0.38), (0.38, 0.02, 0.99), m_wd, rot=(0, 0, -0.06), parent=r, bevel=0.01)
    box("BoxTop", (0.44, 0.40, 0.28), (-0.30, -0.04, 1.54), m_wd, parent=r, bevel=0.01)
    cyl("Can1", 0.11, 0.11, 0.36, 12, (0.35, 0, 0.38), mat=m_cn, parent=r)
    cyl("Can2", 0.09, 0.09, 0.32, 12, (0.56, 0.05, 1.56), mat=m_cn, parent=r)
    export_glb("prop_shelving_rack.glb")

    # 2. Bio-Lab Bench with Microscope & Specimen Flasks
    reset_scene()
    m_cab = make_mat("LabBase", "rusted_metal.png", "rusted_metal_n.png", (0.42, 0.48, 0.50, 1), 0.55, 0.6)
    m_top = make_mat("SlateTop", "concrete_wall.png", "", (0.24, 0.26, 0.28, 1), 0.35, 0.2)
    m_glw = make_mat("BioSample", "", "", (0.25, 0.92, 0.58, 1), 0.15, 0.0, (0.2, 0.85, 0.5), 1.8)
    r = make_empty("LabBenchRoot")
    box("CabinetUnder", (2.04, 0.72, 0.86), (0, 0, 0.43), m_cab, parent=r, bevel=0.01)
    box("CounterSlab", (2.16, 0.82, 0.06), (0, 0, 0.89), m_top, parent=r, bevel=0.01)
    # Microscope & flasks
    box("ScopeBase", (0.20, 0.24, 0.04), (-0.52, 0.05, 0.94), m_top, parent=r)
    box("ScopeArm", (0.06, 0.08, 0.28), (-0.52, -0.02, 1.08), m_cab, rot=(0.25, 0, 0), parent=r)
    cyl("ScopeLens", 0.025, 0.02, 0.16, 10, (-0.52, 0.06, 1.15), rot_m=(-0.35, 0, 0), mat=m_cab, parent=r)
    cyl("Flask1", 0.075, 0.03, 0.22, 12, (0.34, 0.04, 1.03), mat=m_glw, parent=r)
    cyl("Flask2", 0.055, 0.055, 0.26, 12, (0.54, -0.08, 1.05), mat=m_glw, parent=r)
    export_glb("prop_lab_bench.glb")

    # 3. Retro Bunker Computer CRT Terminal Desk
    reset_scene()
    m_dsk = make_mat("DeskSteel", "rusted_metal.png", "rusted_metal_n.png", (0.36, 0.38, 0.42, 1), 0.6, 0.65)
    m_crt = make_mat("PlasticBeige", "concrete_wall.png", "", (0.58, 0.55, 0.48, 1), 0.65)
    m_scr = make_mat("PhosphorScreen", "", "", (0.18, 0.85, 0.42, 1), 0.15, 0.0, (0.18, 0.88, 0.45), 2.1)
    r = make_empty("TerminalRoot")
    box("DeskTop", (1.38, 0.76, 0.05), (0, 0, 0.76), m_dsk, parent=r, bevel=0.008)
    box("PedestalL", (0.38, 0.70, 0.74), (-0.46, 0, 0.37), m_dsk, parent=r)
    box("LegR", (0.06, 0.68, 0.74), (0.62, 0, 0.37), m_dsk, parent=r)
    box("CRTBody", (0.46, 0.44, 0.40), (-0.15, -0.06, 0.99), m_crt, parent=r, bevel=0.02)
    box("CRTScreen", (0.36, 0.03, 0.28), (-0.15, 0.155, 1.00), m_scr, parent=r, bevel=0.01)
    box("Keyboard", (0.44, 0.18, 0.03), (-0.14, 0.24, 0.80), m_crt, parent=r, bevel=0.006)
    box("TowerUnit", (0.24, 0.42, 0.36), (0.40, -0.06, 0.96), m_crt, parent=r, bevel=0.01)
    export_glb("prop_computer_terminal.glb")

    # 4. Bloodstained Medical Privacy Curtain
    reset_scene()
    m_frm = make_mat("CurtainSteel", "rusted_metal.png", "", (0.68, 0.70, 0.72, 1), 0.45, 0.8)
    m_clt = make_mat("CurtainCloth", "flesh_mutant.png", "", (0.72, 0.74, 0.68, 1), 0.92)
    r = make_empty("CurtainRoot")
    for sx in (-0.82, 0.82):
        cyl(f"Upright_{sx}", 0.018, 0.018, 1.84, 10, (sx, 0, 0.94), mat=m_frm, parent=r)
        box(f"Foot_{sx}", (0.06, 0.44, 0.04), (sx, 0, 0.02), m_frm, parent=r)
    cyl("TopBar", 0.016, 0.016, 1.66, 10, (0, 0, 1.84), rot_m=(0, 1.57, 0), mat=m_frm, parent=r)
    box("FabricSheet", (1.56, 0.03, 1.42), (0, 0, 1.08), m_clt, parent=r, bevel=0.01, smooth=True)
    export_glb("prop_medical_curtain.glb")

    # 5. Hospital IV Drip Stand
    reset_scene()
    m_pl = make_mat("IVPole", "rusted_metal.png", "", (0.72, 0.75, 0.78, 1), 0.4, 0.85)
    m_bg = make_mat("IVBag", "", "", (0.65, 0.78, 0.82, 1), 0.25, 0.0, (0.2, 0.3, 0.35), 0.3)
    r = make_empty("IVRoot")
    cyl("Pole", 0.014, 0.012, 1.72, 10, (0, 0, 0.88), mat=m_pl, parent=r)
    box("CrossBase1", (0.46, 0.04, 0.03), (0, 0, 0.03), m_pl, parent=r)
    box("CrossBase2", (0.04, 0.46, 0.03), (0, 0, 0.03), m_pl, parent=r)
    box("TopHook", (0.24, 0.018, 0.018), (0, 0, 1.72), m_pl, parent=r)
    box("FluidBag", (0.09, 0.04, 0.18), (-0.09, 0, 1.58), m_bg, parent=r, bevel=0.015, smooth=True)
    export_glb("prop_iv_drip.glb")

    # 6. Abandoned Rusted Wheelchair (Interactive Squeak Hazard!)
    reset_scene()
    m_wc = make_mat("ChairMetal", "rusted_metal.png", "rusted_metal_n.png", (0.48, 0.46, 0.46, 1), 0.55, 0.75)
    m_st = make_mat("LeatherSeat", "hazmat_fabric.png", "", (0.20, 0.16, 0.15, 1), 0.85)
    r = make_empty("WheelchairRoot")
    box("Seat", (0.50, 0.48, 0.05), (0, 0.04, 0.48), m_st, parent=r, bevel=0.01)
    box("Backrest", (0.50, 0.05, 0.46), (0, -0.20, 0.72), m_st, parent=r, bevel=0.01)
    for sx in (-0.28, 0.28):
        cyl(f"BigWheel_{sx}", 0.30, 0.30, 0.04, 20, (sx, -0.06, 0.30), rot_m=(0, 1.57, 0), mat=m_wc, parent=r)
        cyl(f"FrontCaster_{sx}", 0.09, 0.09, 0.035, 12, (sx * 0.82, 0.28, 0.09), rot_m=(0, 1.57, 0), mat=m_wc, parent=r)
        box(f"Armrest_{sx}", (0.04, 0.42, 0.04), (sx * 0.92, 0.02, 0.68), m_wc, parent=r)
    export_glb("prop_wheelchair.glb")

    # 7. Morgue Corpse Bag
    reset_scene()
    m_cb = make_mat("BodyBagVinyl", "hazmat_fabric.png", "hazmat_fabric_n.png", (0.14, 0.15, 0.16, 1), 0.48, 0.1)
    m_sp = make_mat("Strap", "", "", (0.38, 0.12, 0.12, 1), 0.7)
    r = make_empty("CorpseRoot")
    cyl("TorsoLump", 0.22, 0.16, 1.25, 14, (0, 0.05, 0.16), rot_m=(1.57, 0, 0), mat=m_cb, parent=r)
    cyl("HeadLump", 0.13, 0.14, 0.32, 12, (0, -0.72, 0.14), rot_m=(1.57, 0, 0), mat=m_cb, parent=r)
    for sy in (-0.35, 0.25, 0.62):
        box(f"BagStrap_{sy}", (0.44, 0.05, 0.26), (0, sy, 0.15), m_sp, parent=r, bevel=0.01)
    export_glb("prop_corpse_bag.glb")

    # 8. Tall 4-Drawer Archive Filing Cabinet
    reset_scene()
    m_fc = make_mat("ArchiveSteel", "rusted_metal.png", "rusted_metal_n.png", (0.42, 0.46, 0.43, 1), 0.62, 0.68)
    m_pp = make_mat("OldFiles", "", "", (0.82, 0.78, 0.66, 1), 0.9)
    r = make_empty("FilingRoot")
    box("MainTower", (0.58, 0.64, 1.72), (0, 0, 0.86), m_fc, parent=r, bevel=0.01)
    for di, dz in enumerate((0.24, 0.64, 1.04, 1.44)):
        pull_y = 0.22 if di == 2 else 0.02
        box(f"FDrawer_{di}", (0.50, 0.46, 0.34), (0, pull_y + 0.12, dz), m_fc, parent=r, bevel=0.008)
        if di == 2:
            box("Folders", (0.44, 0.26, 0.28), (0, pull_y + 0.14, dz + 0.04), m_pp, parent=r)
    export_glb("prop_filing_tall.glb")

    # 9. Wall Ventilation Crawlspace Hatch (with removable GrateCover!)
    reset_scene()
    m_vh = make_mat("VentGalv", "rusted_metal.png", "rusted_metal_n.png", (0.58, 0.62, 0.65, 1), 0.48, 0.82)
    r = make_empty("VentHatchRoot")
    W, H = 1.08, 1.02
    box("FlangeTop", (W + 0.14, 0.12, 0.08), (0, 0, H), m_vh, parent=r)
    box("FlangeBot", (W + 0.14, 0.12, 0.08), (0, 0, 0.04), m_vh, parent=r)
    box("FlangeL", (0.08, 0.12, H), (-W * 0.5 - 0.03, 0, H * 0.5), m_vh, parent=r)
    box("FlangeR", (0.08, 0.12, H), (W * 0.5 + 0.03, 0, H * 0.5), m_vh, parent=r)
    grate = make_empty("GrateCover", (0, 0.04, 0), parent=r)
    for si in range(6):
        sz = 0.16 + si * 0.145
        box(f"Louver_{si}", (W - 0.06, 0.03, 0.06), (0, 0, sz), m_vh, rot=(0.35, 0, 0), parent=grate)
    export_glb("prop_vent_hatch.glb")

    # 10. Wall PA Intercom Lure Box
    reset_scene()
    m_pa = make_mat("PABox", "rusted_metal.png", "", (0.36, 0.40, 0.38, 1), 0.58, 0.7)
    m_bt = make_mat("PAButtonRed", "", "", (0.92, 0.16, 0.14, 1), 0.3, 0.1, (1.0, 0.2, 0.15), 2.4)
    r = make_empty("PAIntercomRoot")
    box("Housing", (0.38, 0.16, 0.48), (0, 0, 0.24), m_pa, parent=r, bevel=0.01)
    cyl("SpeakerCone", 0.11, 0.06, 0.05, 14, (0, 0.09, 0.32), rot_m=(1.57, 0, 0), mat=m_pa, parent=r)
    cyl("CallBtn", 0.042, 0.042, 0.04, 12, (0, 0.09, 0.13), rot_m=(1.57, 0, 0), mat=m_bt, parent=r)
    export_glb("prop_pa_intercom.glb")

    # 11. Broken Floor Glass Shards (Stealth Crunch Hazard!)
    reset_scene()
    m_gl = make_mat("ShardGlass", "", "", (0.72, 0.88, 0.92, 1), 0.08, 0.25, (0.45, 0.62, 0.68), 0.35)
    r = make_empty("ShardsRoot")
    rng = np.random.default_rng(77)
    for i in range(16):
        ang = rng.uniform(0, math.tau)
        dist = rng.uniform(0.08, 0.68)
        sx = math.cos(ang) * dist
        sy = math.sin(ang) * dist
        w = rng.uniform(0.08, 0.22)
        d = rng.uniform(0.06, 0.16)
        box(f"Shard_{i}", (w, d, 0.012), (sx, sy, 0.008), m_gl, rot=(0, 0, rng.uniform(0, 3.14)), parent=r)
    export_glb("prop_glass_shards.glb")

    # 12. Surgical Holding Cage (3.2m x 3.2m x 2.7m Barred Cell with Hinged Door!)
    reset_scene()
    m_cg = make_mat("CageBars", "rusted_metal.png", "rusted_metal_n.png", (0.38, 0.36, 0.36, 1), 0.58, 0.85)
    r = make_empty("HoldingCageRoot")
    S, H = 3.2, 2.75
    # Roof & Corner Posts (Front is +Y -> -Z in Godot; Back is -Y -> +Z in Godot with vent cutout)
    for cx in (-S * 0.5, S * 0.5):
        for cy in (-S * 0.5, S * 0.5):
            box(f"CPost_{cx}_{cy}", (0.10, 0.10, H), (cx, cy, H * 0.5), m_cg, parent=r)
    box("CRoofFrame", (S + 0.1, S + 0.1, 0.08), (0, 0, H), m_cg, parent=r)
    # Left & Right Barred Walls
    for side in (-1, 1):
        for bi in range(-5, 6):
            cyl(f"SideBar_{side}_{bi}", 0.022, 0.022, H, 8, (side * S * 0.5, bi * 0.26, H * 0.5), mat=m_cg, parent=r)
    # Front Wall Bars leaving 1.2m center doorway + Hinged CageDoorPivot!
    for bx in (-1.35, -1.08, -0.82, 0.82, 1.08, 1.35):
        cyl(f"FrontBar_{bx}", 0.022, 0.022, H, 8, (bx, S * 0.5, H * 0.5), mat=m_cg, parent=r)
    cdoor = make_empty("CageDoorPivot", (-0.62, S * 0.5, 0), parent=r)
    box("CDoorTop", (1.24, 0.06, 0.07), (0.62, 0, H - 0.08), m_cg, parent=cdoor)
    box("CDoorBot", (1.24, 0.06, 0.07), (0.62, 0, 0.08), m_cg, parent=cdoor)
    for dbi in range(6):
        cyl(f"CDoorBar_{dbi}", 0.02, 0.02, H - 0.16, 8, (0.12 + dbi * 0.20, 0, H * 0.5), mat=m_cg, parent=cdoor)
    export_glb("prop_holding_cage.glb")

    # 13. NEW ITEM: Sonic Strobe Flare (item_flare.glb)
    reset_scene()
    m_fl = make_mat("FlareRed", "", "", (0.92, 0.16, 0.14, 1), 0.42, 0.2)
    m_cp = make_mat("FlareCap", "rusted_metal.png", "", (0.25, 0.26, 0.28, 1), 0.5, 0.7, (1.0, 0.35, 0.15), 1.8)
    r = make_empty("FlareRoot")
    cyl("FlareStick", 0.028, 0.028, 0.26, 12, (0, 0, 0.03), rot_m=(0, 1.57, 0), mat=m_fl, parent=r)
    cyl("StrikerCap", 0.032, 0.032, 0.04, 12, (0.13, 0, 0.03), rot_m=(0, 1.57, 0), mat=m_cp, parent=r)
    export_glb("item_flare.glb")

    # 14. NEW ITEM: First-Aid Medkit (item_medkit.glb)
    reset_scene()
    m_mk = make_mat("MedWhite", "concrete_wall.png", "", (0.88, 0.86, 0.82, 1), 0.45, 0.15)
    m_cr = make_mat("MedCross", "", "", (0.84, 0.14, 0.14, 1), 0.4)
    r = make_empty("MedkitRoot")
    box("CaseBody", (0.28, 0.22, 0.11), (0, 0, 0.055), m_mk, parent=r, bevel=0.015)
    box("CrossH", (0.11, 0.035, 0.008), (0, 0, 0.112), m_cr, parent=r)
    box("CrossV", (0.035, 0.11, 0.008), (0, 0, 0.112), m_cr, parent=r)
    export_glb("item_medkit.glb")

    # 15. NEW ITEM: Heavy Screwdriver (item_screwdriver.glb)
    reset_scene()
    m_hd = make_mat("DriverGrip", "", "", (0.92, 0.62, 0.12, 1), 0.35)
    m_sh = make_mat("DriverSteel", "rusted_metal.png", "", (0.78, 0.82, 0.86, 1), 0.3, 0.9)
    r = make_empty("ScrewdriverRoot")
    cyl("Grip", 0.024, 0.022, 0.13, 10, (-0.08, 0, 0.025), rot_m=(0, 1.57, 0), mat=m_hd, parent=r)
    cyl("Shaft", 0.006, 0.005, 0.16, 8, (0.06, 0, 0.025), rot_m=(0, 1.57, 0), mat=m_sh, parent=r)
    box("FlatTip", (0.02, 0.012, 0.003), (0.14, 0, 0.025), m_sh, parent=r)
    export_glb("item_screwdriver.glb")


# --- Generate 5 crisp new 128x128 RGBA icons matching existing set ---
def save_png(filepath: str, rgba_uint8: np.ndarray) -> None:
    h, w, _ = rgba_uint8.shape
    img = bpy.data.images.new(name="tmp_ic", width=w, height=h, alpha=True)
    img.pixels.foreach_set((np.flipud(rgba_uint8).astype(np.float32) / 255.0).ravel())
    img.filepath_raw = filepath
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def sd_seg(px, py, ax, ay, bx, by):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = np.clip((pax * bax + pay * bay) / max(bax * bax + bay * bay, 1e-6), 0.0, 1.0)
    return np.sqrt((pax - bax * h) ** 2 + (pay - bay * h) ** 2)


def sd_bx(px, py, cx, cy, hx, hy, ang=0.0):
    dx, dy = px - cx, py - cy
    if ang != 0.0:
        c, s = math.cos(-ang), math.sin(-ang)
        dx, dy = c * dx - s * dy, s * dx + c * dy
    qx, qy = np.abs(dx) - hx, np.abs(dy) - hy
    return np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0)


def comp(canvas, d, rgb, outline=0.045):
    aa = 0.022
    oa = np.clip((outline - d) / aa, 0, 1)
    fa = np.clip((-d) / aa, 0, 1)
    oc = np.array([0.05, 0.06, 0.08], dtype=np.float32)
    canvas[..., :3] = canvas[..., :3] * (1 - oa[..., None]) + oc * oa[..., None]
    canvas[..., 3] = np.maximum(canvas[..., 3], oa * 0.92)
    gy, gx = np.gradient(d)
    lt = np.clip((-gx * 0.6 - gy * 0.8) * 14.0, -0.2, 0.25)
    col = np.clip(np.array(rgb, dtype=np.float32)[None, None, :] + lt[..., None], 0, 1)
    canvas[..., :3] = canvas[..., :3] * (1 - fa[..., None]) + col * fa[..., None]
    canvas[..., 3] = np.maximum(canvas[..., 3], fa)


def build_new_icons() -> None:
    S = 128
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    nx = (xx / (S - 1)) * 2.0 - 1.0
    ny = (yy / (S - 1)) * 2.0 - 1.0

    # 1. Sonic Flare
    c = np.zeros((S, S, 4), dtype=np.float32)
    stick = sd_bx(nx, ny, -0.10, 0.14, 0.13, 0.44, ang=0.72) - 0.03
    sp1 = sd_seg(nx, ny, 0.22, -0.22, 0.56, -0.56) - 0.04
    sp2 = sd_seg(nx, ny, 0.24, -0.10, 0.62, -0.16) - 0.035
    sp3 = sd_seg(nx, ny, 0.10, -0.24, 0.16, -0.62) - 0.035
    comp(c, stick, (0.86, 0.18, 0.18))
    comp(c, np.minimum(sp1, np.minimum(sp2, sp3)), (1.0, 0.72, 0.24))
    save_png(os.path.join(ICON_DIR, "item_flare.png"), np.clip(c * 255, 0, 255).astype(np.uint8))

    # 2. Medkit
    c = np.zeros((S, S, 4), dtype=np.float32)
    bag = sd_bx(nx, ny, 0.0, 0.06, 0.52, 0.40) - 0.06
    hnd = np.abs(sd_bx(nx, ny, 0.0, -0.40, 0.22, 0.10) - 0.02) - 0.045
    cr1 = sd_bx(nx, ny, 0.0, 0.06, 0.24, 0.08)
    cr2 = sd_bx(nx, ny, 0.0, 0.06, 0.08, 0.24)
    comp(c, np.minimum(bag, hnd), (0.88, 0.86, 0.82))
    comp(c, np.minimum(cr1, cr2), (0.82, 0.16, 0.16), outline=0.015)
    save_png(os.path.join(ICON_DIR, "item_medkit.png"), np.clip(c * 255, 0, 255).astype(np.uint8))

    # 3. Screwdriver
    c = np.zeros((S, S, 4), dtype=np.float32)
    sh = sd_seg(nx, ny, -0.05, 0.05, 0.55, -0.55) - 0.045
    gr = sd_bx(nx, ny, -0.32, 0.32, 0.14, 0.30, ang=0.785) - 0.05
    comp(c, sh, (0.76, 0.80, 0.86))
    comp(c, gr, (0.90, 0.62, 0.14))
    save_png(os.path.join(ICON_DIR, "item_screwdriver.png"), np.clip(c * 255, 0, 255).astype(np.uint8))

    # 4. Hold Breath Icon
    c = np.zeros((S, S, 4), dtype=np.float32)
    l1 = sd_bx(nx, ny, -0.26, 0.08, 0.18, 0.34, ang=0.15) - 0.08
    l2 = sd_bx(nx, ny, 0.26, 0.08, 0.18, 0.34, ang=-0.15) - 0.08
    tr = sd_seg(nx, ny, 0.0, -0.52, 0.0, -0.06) - 0.06
    b1 = sd_seg(nx, ny, 0.0, -0.08, -0.22, 0.06) - 0.05
    b2 = sd_seg(nx, ny, 0.0, -0.08, 0.22, 0.06) - 0.05
    comp(c, np.minimum(np.minimum(l1, l2), np.minimum(tr, np.minimum(b1, b2))), (0.86, 0.88, 0.92))
    save_png(os.path.join(ICON_DIR, "ui_breath.png"), np.clip(c * 255, 0, 255).astype(np.uint8))

    # 5. Field Dossier / Journal Icon
    c = np.zeros((S, S, 4), dtype=np.float32)
    pg = sd_bx(nx, ny, 0.0, 0.0, 0.44, 0.56) - 0.05
    ln1 = sd_seg(nx, ny, -0.24, -0.24, 0.24, -0.24) - 0.035
    ln2 = sd_seg(nx, ny, -0.24, 0.0, 0.24, 0.0) - 0.035
    ln3 = sd_seg(nx, ny, -0.24, 0.24, 0.12, 0.24) - 0.035
    comp(c, pg, (0.86, 0.84, 0.78))
    comp(c, np.minimum(ln1, np.minimum(ln2, ln3)), (0.22, 0.24, 0.28), outline=0.0)
    save_png(os.path.join(ICON_DIR, "ui_journal.png"), np.clip(c * 255, 0, 255).astype(np.uint8))


if __name__ == "__main__":
    build_all_expansion_models()
    build_new_icons()
    print("EXPANSION_ASSETS_COMPLETE")
