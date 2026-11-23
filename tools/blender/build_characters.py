"""Build Hafid's stylised characters with Blender's Python API (bpy).

Run:  python tools/blender/build_characters.py   (needs `pip install bpy`, Blender 5.x)
Writes game/art/characters/{cat,fennec,lizard,jinn,equipment}.glb

Every character is a set of separate parts (Body, Head, HandR, HandL, FootR,
FootL, Tail) so the game animates them procedurally with floating hands and
feet (no skinning). Colour lives in vertex colours, so one material and one
draw call per part. Geometry is written in Godot coordinates (x right, y up,
forward = -z) and converted to Blender's Z-up on output; glTF converts back.
"""
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils
import bmesh  # noqa: E402
from mathutils import Matrix, Vector

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "game", "art", "characters"))
META_RES = 0.045  # metaball resolution: lower = more triangles
# With stiffness 2 and threshold 0.6 a metaball's visible surface sits at
# r * sqrt(1 - sqrt(0.6 / 2)) ~= 0.67 r. Scale radii so `radius` means the
# visible radius, which is what the part layout below assumes.
META_RADIUS_SCALE = 1.0 / math.sqrt(1.0 - math.sqrt(0.6 / 2.0))


# --- helpers ----------------------------------------------------------------

def g2b(v):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.metaballs, bpy.data.materials):
        for d in list(coll):
            coll.remove(d)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(a, b, t) for a, b in zip(c1, c2))


def hash3(x, y, z):
    h = math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453
    return h - math.floor(h)


class Part:
    """Accumulates pieces (in Godot coords, relative to the part origin)."""

    def __init__(self):
        self.verts = []
        self.normals = []
        self.faces = []
        self.colors = []

    def add_mesh(self, me, color_fn, matrix=Matrix.Identity(4)):
        off = len(self.verts)
        nmat = matrix.to_3x3()
        for v in me.vertices:
            co = matrix @ v.co
            n = (nmat @ v.normal).normalized()
            self.verts.append(co)
            self.normals.append(n)
            self.colors.append(color_fn(co, n))
        for p in me.polygons:
            self.faces.append([off + i for i in p.vertices])


def meta_mesh(name, elements, threshold=0.6, resolution=None):
    """elements: list of (type, center, radius, size(x,y,z) or None).
    Coordinates in Godot space. Returns a bpy Mesh in Godot space."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution or META_RES
    mb.render_resolution = resolution or META_RES
    mb.threshold = threshold
    obj = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(obj)
    for typ, c, r, size in elements:
        el = mb.elements.new(type=typ)
        el.co = Vector(c)  # Godot space; metaball has no up-axis meaning
        el.radius = r * META_RADIUS_SCALE
        el.stiffness = 2.0
        if size:
            el.size_x, el.size_y, el.size_z = size
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj, do_unlink=True)
    return me


def prim(kind, **kw):
    bm = bmesh.new()
    if kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=kw.get("u", 16), v_segments=kw.get("v", 10), radius=kw.get("r", 1.0))
    elif kind == "cone":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=kw.get("seg", 10),
                              radius1=kw.get("r1", 1.0), radius2=kw.get("r2", 0.0), depth=kw.get("h", 1.0))
    elif kind == "cube":
        bmesh.ops.create_cube(bm, size=1.0)
    elif kind == "grid":
        bmesh.ops.create_grid(bm, x_segments=kw.get("xs", 8), y_segments=kw.get("ys", 8), size=0.5)
    me = bpy.data.meshes.new(kind)
    bm.to_mesh(me)
    bm.free()
    return me


def T(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Transform in Godot space. Cones/cylinders from bmesh point along +Z (Blender
    local) which we treat as Godot +Z too; rotate with rot (x, y, z) radians."""
    m = Matrix.Translation(Vector(loc))
    m = m @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X") @ Matrix.Rotation(rot[2], 4, "Z")
    m = m @ Matrix.Diagonal(Vector((scale[0], scale[1], scale[2], 1.0)))
    return m


UP_CONE = Matrix.Rotation(-math.pi / 2, 4, "X")  # cone axis +Z -> +Y


def emit(name, part, pivot, smooth=True):
    """Create a Blender object from a Part at Godot-space `pivot`."""
    verts = [g2b(v) for v in part.verts]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], part.faces)
    me.update()
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    flat = []
    for c in part.colors:
        flat.extend((c[0], c[1], c[2], 1.0))
    attr.data.foreach_set("color", flat)
    me.color_attributes.active_color_name = "Col"
    if smooth:
        me.shade_smooth()
    obj = bpy.data.objects.new(name, me)
    obj.location = g2b(pivot)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.get("toon") or bpy.data.materials.new("toon")
    me.materials.append(mat)
    return obj, len(part.faces)


def export(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_apply=True,
        export_vertex_color="ACTIVE", export_normals=True, export_materials="PLACEHOLDER",
        export_yup=True,
    )


# --- species ----------------------------------------------------------------

SPECIES = {
    "cat": {
        "fur": (0.95, 0.55, 0.2), "fur_dark": (0.7, 0.4, 0.2), "accent": (0.97, 0.87, 0.74),
        "inner_ear": (0.98, 0.62, 0.62), "eye": (0.07, 0.05, 0.09), "nose": (0.85, 0.42, 0.45),
        "robe": (0.42, 0.66, 0.92), "robe_dark": (0.3, 0.5, 0.78), "embroidery": (1.0, 0.83, 0.35),
        "ears": "cat", "head": "round", "tail": "cat",
    },
    "fennec": {
        "fur": (0.92, 0.76, 0.52), "fur_dark": (0.76, 0.58, 0.36), "accent": (0.96, 0.9, 0.8),
        "inner_ear": (1.0, 0.86, 0.78), "eye": (0.07, 0.05, 0.09), "nose": (0.12, 0.08, 0.08),
        "robe": (0.9, 0.9, 0.88), "robe_dark": (0.74, 0.76, 0.8), "embroidery": (0.2, 0.3, 0.62),
        "ears": "fennec", "head": "fox", "tail": "fennec",
    },
    "lizard": {
        "fur": (0.36, 0.66, 0.36), "fur_dark": (0.22, 0.46, 0.26), "accent": (0.9, 0.88, 0.5),
        "inner_ear": (0.9, 0.5, 0.3), "eye": (0.98, 0.82, 0.2), "nose": (0.18, 0.3, 0.18),
        "robe": (0.2, 0.26, 0.55), "robe_dark": (0.14, 0.18, 0.42), "embroidery": (0.98, 0.95, 0.88),
        "ears": "none", "head": "lizard", "tail": "lizard",
    },
}


def build_head(s):
    p = Part()
    fur, dark, acc = s["fur"], s["fur_dark"], s["accent"]
    if s["head"] == "lizard":
        elems = [("ELLIPSOID", (0, 0.02, 0), 0.34, (0.95, 0.85, 1.05)),
                 ("ELLIPSOID", (0, -0.05, -0.3), 0.24, (0.85, 0.65, 1.2)),
                 ("BALL", (0.16, 0.12, -0.08), 0.15, None), ("BALL", (-0.16, 0.12, -0.08), 0.15, None)]
    elif s["head"] == "fox":
        elems = [("ELLIPSOID", (0, 0, 0), 0.36, (1.05, 0.95, 1.0)),
                 ("BALL", (0.18, -0.1, -0.1), 0.15, None), ("BALL", (-0.18, -0.1, -0.1), 0.15, None),
                 ("ELLIPSOID", (0, -0.1, -0.3), 0.14, (0.9, 0.8, 1.5))]
    else:
        elems = [("ELLIPSOID", (0, 0, 0), 0.37, (1.1, 0.95, 1.0)),
                 ("BALL", (0.17, -0.11, -0.13), 0.16, None), ("BALL", (-0.17, -0.11, -0.13), 0.16, None),
                 ("BALL", (0, -0.1, -0.25), 0.13, None)]
    head = meta_mesh("head_" + s["head"], elems)

    def head_col(co, n):
        x, y, z = co
        if s["head"] == "lizard":
            if y < -0.08 and z < -0.05:
                return acc  # pale jaw
            if hash3(round(x * 14), round(y * 14), round(z * 14)) > 0.72 and y > 0.0:
                return dark  # spots
            return fur
        if z < -0.16 and y < -0.02:
            return acc  # muzzle / cheeks
        if s["head"] == "round" and y > 0.14 and abs(x) < 0.2 and math.sin(x * 34) > 0.45:
            return dark  # forehead stripes (cat)
        return fur
    p.add_mesh(head, head_col)

    # Eyes: big glossy ovals with a white glint (Tunic-like readability).
    if s["head"] == "lizard":
        for sx in (-1, 1):
            p.add_mesh(prim("sphere", r=0.085, u=14, v=8), lambda c, n: s["eye"], T((0.22 * sx, 0.14, -0.15), scale=(0.7, 1, 1)))
            p.add_mesh(prim("sphere", r=0.04, u=10, v=6), lambda c, n: (0.05, 0.05, 0.05), T((0.275 * sx, 0.14, -0.17), scale=(0.4, 1.4, 0.5)))
    else:
        for sx in (-1, 1):
            p.add_mesh(prim("sphere", r=0.07, u=14, v=8), lambda c, n: s["eye"], T((0.135 * sx, 0.03, -0.315), scale=(1.0, 1.35, 0.55)))
            p.add_mesh(prim("sphere", r=0.022, u=8, v=6), lambda c, n: (1, 1, 1), T((0.135 * sx + 0.025, 0.07, -0.35)))
    # Nose.
    nose_pos = (0, -0.06, -0.5) if s["head"] == "lizard" else ((0, -0.05, -0.47) if s["head"] == "fox" else (0, -0.05, -0.375))
    p.add_mesh(prim("sphere", r=0.04, u=10, v=6), lambda c, n: s["nose"], T(nose_pos, scale=(1.2, 0.8, 0.8)))

    # Ears.
    if s["ears"] in ("cat", "fennec"):
        big = s["ears"] == "fennec"
        r, h = (0.17, 0.5) if big else (0.12, 0.28)
        for sx in (-1, 1):
            m = T((0.2 * sx if big else 0.19 * sx, 0.3 if big else 0.28, 0.02), rot=(0, 0, -(0.42 if big else 0.32) * sx)) @ UP_CONE
            ear = prim("cone", r1=r, r2=0.0, h=h, seg=10)
            p.add_mesh(ear, lambda c, n: s["fur"], m @ Matrix.Translation((0, 0, h * 0.5)) @ Matrix.Diagonal((1, 0.45, 1, 1)))
            inner = prim("cone", r1=r * 0.6, r2=0.0, h=h * 0.75, seg=8)
            p.add_mesh(inner, lambda c, n: s["inner_ear"], m @ Matrix.Translation((0, -0.03, h * 0.42)) @ Matrix.Diagonal((1, 0.3, 1, 1)))
    elif s["ears"] == "none":
        for i, zz in enumerate([0.12, 0.0, -0.12]):  # crest
            m = T((0, 0.31 - i * 0.02, zz)) @ UP_CONE
            p.add_mesh(prim("cone", r1=0.05, r2=0.0, h=0.14, seg=6), lambda c, n: s["inner_ear"], m @ Matrix.Translation((0, 0, 0.06)) @ Matrix.Diagonal((0.5, 1, 1, 1)))
    return p


def build_body(s):
    """Torso wearing a daraa (Mauritanian robe) with an embroidered chest pocket."""
    p = Part()
    body = meta_mesh("body_robe", [
        ("ELLIPSOID", (0, 0.05, 0), 0.32, (1.0, 1.2, 0.92)),
        ("ELLIPSOID", (0, -0.24, 0), 0.36, (1.08, 0.6, 1.0)),
        ("BALL", (0, 0.3, 0), 0.16, None),
    ], resolution=0.03)
    robe, robe_dark, emb, fur = s["robe"], s["robe_dark"], s["embroidery"], s["fur"]

    def col(co, n):
        x, y, z = co
        if y > 0.34:
            return fur  # neck
        if y < -0.38:
            return robe_dark  # hem
        if -0.38 <= y < -0.33:
            return emb  # hem trim
        # Embroidered chest pocket (front, left of centre like a real daraa):
        # a frame with a chain of three diamonds, and a V-neck trim.
        if z < -0.16:
            px, py = x - 0.075, y - 0.11
            if abs(px) < 0.085 and abs(py) < 0.16:
                if abs(px) > 0.06 or abs(py) > 0.135:
                    return emb
                for cy in (-0.07, 0.0, 0.07):
                    if abs(px) / 0.04 + abs(py - cy) / 0.035 < 1.0:
                        return emb
                return robe
            if y > 0.2 and abs(abs(x) - (0.3 - y) * 0.5) < 0.012:
                return emb
        return robe
    p.add_mesh(body, col)
    return p


def build_tail(s):
    p = Part()
    kind = s["tail"]
    pts = []
    n = 7 if kind != "lizard" else 9
    for i in range(n):
        t = i / (n - 1)
        if kind == "lizard":
            pos = (0, -0.25 + 0.15 * math.sin(t * 2.2), 0.05 + t * 0.85)
            r = lerp(0.13, 0.035, t)
        elif kind == "fennec":
            pos = (0, t * 0.45, 0.05 + t * 0.32)
            r = lerp(0.07, 0.12, math.sin(t * math.pi * 0.85))
        else:
            pos = (0, t * 0.55, 0.05 + math.sin(t * 2.0) * 0.28)
            r = lerp(0.07, 0.055, t)
        pts.append((pos, r, t))
    me = meta_mesh("tail_" + kind, [("BALL", pp, r, None) for pp, r, _ in pts])

    def col(co, nrm):
        # nearest sample along the chain
        best = min(pts, key=lambda q: (Vector(q[0]) - co).length)
        t = best[2]
        if kind == "fennec" and t > 0.8:
            return (0.12, 0.08, 0.07)  # dark tail tip
        if kind == "cat" and math.sin(t * 22) > 0.4:
            return s["fur_dark"]
        if kind == "lizard" and nrm.y > 0.6 and hash3(co.x * 9, co.y * 9, co.z * 9) > 0.6:
            return s["fur_dark"]
        return s["fur"]
    p.add_mesh(me, col)
    if kind == "lizard":
        for i in range(4):
            t = 0.15 + i * 0.18
            pos = Vector((0, -0.25 + 0.15 * math.sin(t * 2.2) + lerp(0.12, 0.04, t), 0.05 + t * 0.85))
            p.add_mesh(prim("cone", r1=0.035, r2=0.0, h=0.09, seg=6), lambda c, n: s["inner_ear"],
                       Matrix.Translation(pos) @ UP_CONE @ Matrix.Translation((0, 0, 0.04)) @ Matrix.Diagonal((0.5, 1, 1, 1)))
    return p


def build_paw(s, foot=False):
    p = Part()
    if foot:
        p.add_mesh(prim("sphere", r=0.115, u=14, v=8), lambda c, n: s["fur_dark"] if c.y < -0.04 else s["accent"],
                   T((0, 0, -0.04), scale=(1.0, 0.75, 1.4)))
    else:
        p.add_mesh(prim("sphere", r=0.1, u=14, v=8), lambda c, n: s["accent"])
        p.add_mesh(prim("sphere", r=0.045, u=8, v=6), lambda c, n: s["accent"], T((0.0, 0.03, -0.08)))  # thumb
    return p


def build_daraa_wing(s, sx):
    """The robe's wide sleeve opened as a sail for gliding. Folds are baked in."""
    part = Part()
    grid = prim("grid", xs=10, ys=6)
    for v in grid.vertices:
        u = v.co.x + 0.5  # 0 at the body, 1 at the tip
        w = v.co.y + 0.5  # 0 front, 1 back
        v.co = Vector((sx * (0.12 + u * 0.95), math.sin(w * math.pi * 4) * 0.025 * u - 0.05 * u * u, (w - 0.5) * lerp(0.55, 0.8, u)))

    def col(c, n):
        u = (abs(c.x) - 0.12) / 0.95
        w = c.z
        if u > 0.92:
            return s["embroidery"]
        if 0.55 < u < 0.6 and math.sin(w * 60) > 0:
            return s["embroidery"]
        return s["robe"]
    part.add_mesh(grid, col)
    return part


def build_species(name):
    clear_scene()
    s = SPECIES[name]
    tris = 0
    for pname, part, pivot in [
        ("Body", build_body(s), (0, 0.62, 0)),
        ("Head", build_head(s), (0, 1.15, 0)),
        ("Tail", build_tail(s), (0, 0.4, 0.26)),
        ("HandR", build_paw(s), (0.45, 0.62, -0.08)),
        ("HandL", build_paw(s), (-0.45, 0.62, -0.08)),
        ("FootR", build_paw(s, True), (0.17, 0.09, 0)),
        ("FootL", build_paw(s, True), (-0.17, 0.09, 0)),
        ("DaraaR", build_daraa_wing(s, 1), (0, 0.95, 0.05)),
        ("DaraaL", build_daraa_wing(s, -1), (0, 0.95, 0.05)),
    ]:
        _, f = emit(pname, part, pivot)
        tris += f
    export(os.path.join(OUT, name + ".glb"))
    return tris


# --- equipment --------------------------------------------------------------

def box_part(part, center, size, color, taper_tip=None):
    m = T(center, scale=size)
    part.add_mesh(prim("cube"), lambda c, n: color, m)


def build_equipment():
    clear_scene()
    # Takouba-style straight sword: grip at origin, blade toward -Z.
    sword = Part()
    steel, steel_edge = (0.82, 0.85, 0.9), (0.95, 0.97, 1.0)
    blade = bmesh.new()
    L, W, Tk = 0.8, 0.065, 0.016
    vs = [(-W / 2, 0, -0.1), (W / 2, 0, -0.1), (W / 2, 0, -0.1 - L + 0.08), (0, 0, -0.1 - L), (-W / 2, 0, -0.1 - L + 0.08)]
    top = [blade.verts.new((x, Tk / 2, z)) for x, _, z in vs]
    bot = [blade.verts.new((x, -Tk / 2, z)) for x, _, z in vs]
    blade.faces.new(top)
    blade.faces.new(list(reversed(bot)))
    for i in range(len(vs)):
        j = (i + 1) % len(vs)
        blade.faces.new([top[i], top[j], bot[j], bot[i]])
    bmesh.ops.recalc_face_normals(blade, faces=blade.faces)
    bme = bpy.data.meshes.new("blade")
    blade.to_mesh(bme)
    sword.add_mesh(bme, lambda c, n: steel_edge if abs(c.x) > 0.022 else steel)
    box_part(sword, (0, 0, -0.08), (0.26, 0.035, 0.04), (0.85, 0.65, 0.25))   # brass cross-guard
    box_part(sword, (0, 0, 0.03), (0.04, 0.04, 0.18), (0.32, 0.18, 0.1))      # leather grip
    sword.add_mesh(prim("sphere", r=0.038, u=10, v=6), lambda c, n: (0.85, 0.65, 0.25), T((0, 0, 0.13)))
    emit("Sword", sword, (0, 0, 0), smooth=False)

    # Round leather shield with a painted geometric ring and a brass boss; faces -X.
    shield = Part()
    disc = prim("sphere", r=0.27, u=28, v=14)

    def shield_col(c, n):
        r = math.hypot(c.y, c.z)
        ang = math.atan2(c.y, c.z)
        if r < 0.06:
            return (0.85, 0.65, 0.25)
        if 0.15 < r < 0.21:
            return (0.55, 0.12, 0.08) if math.sin(ang * 12) > 0 else (0.12, 0.08, 0.06)
        if r > 0.245:
            return (0.3, 0.17, 0.08)
        return (0.72, 0.52, 0.3)
    shield.add_mesh(disc, shield_col, T(scale=(0.12, 1, 1)))
    emit("Shield", shield, (0, 0, 0))

    export(os.path.join(OUT, "equipment.glb"))


# --- jinn -------------------------------------------------------------------

def build_jinn():
    clear_scene()
    body = Part()
    elems = [("ELLIPSOID", (0, 1.15, 0), 0.5, (1.0, 1.25, 0.9)),
             ("BALL", (0.3, 1.38, 0.02), 0.26, None), ("BALL", (-0.3, 1.38, 0.02), 0.26, None)]
    for i, (y, r, z) in enumerate([(0.75, 0.36, 0.04), (0.5, 0.26, 0.08), (0.3, 0.17, 0.12), (0.14, 0.09, 0.16)]):
        elems.append(("BALL", (0, y, z), r, None))
    body.add_mesh(meta_mesh("jinn_body", elems), lambda c, n: (0.05, 0.03, 0.08))
    emit("Body", body, (0, 0, 0))

    for name, sx in (("ArmR", 1), ("ArmL", -1)):
        arm = Part()
        chain = []
        for i in range(6):
            t = i / 5
            chain.append(("BALL", (sx * (0.0 + t * 0.32), -t * 0.62, -t * 0.12), lerp(0.13, 0.07, t), None))
        for k in (-1, 0, 1):  # three long claws
            chain.append(("ELLIPSOID", (sx * 0.34 + k * 0.04, -0.75, -0.16), 0.05, (0.6, 2.2, 0.6)))
        arm.add_mesh(meta_mesh("jinn_arm_" + name, chain), lambda c, n: (0.05, 0.03, 0.08))
        emit(name, arm, (sx * 0.5, 1.35, 0))

    # Carved bone mask with ochre triangle band: fictional, not tied to any real tradition.
    mask = Part()
    sph = prim("sphere", r=1.0, u=36, v=18)
    bone, ochre, dark = (0.93, 0.88, 0.78), (0.72, 0.3, 0.14), (0.06, 0.04, 0.06)

    def mcol(c, n):
        x, y = c.x, c.y
        for ex in (-0.11, 0.11):  # eye holes (dark), the game puts glowing eyes in front
            if ((x - ex) / 0.07) ** 2 + ((y - 0.05) / 0.05) ** 2 < 1.0:
                return dark
        if y > 0.17 and (abs((x * 18) % 2 - 1) < (y - 0.17) * 9):
            return ochre  # triangle band on the brow
        if abs(x) < 0.018 and -0.3 < y < -0.02:
            return ochre  # vertical line below the eyes
        if -0.24 < y < -0.2 and abs(x) < 0.1:
            return dark  # mouth slit
        return bone
    # Front half of a flattened sphere only (a shell), curved like a face.
    m = T(scale=(0.27, 0.36, 0.11))
    tmp = Part()
    tmp.add_mesh(sph, mcol, m)
    keep = {i for i, v in enumerate(tmp.verts) if v.z <= 0.01}
    remap = {}
    for i in sorted(keep):
        remap[i] = len(mask.verts)
        mask.verts.append(tmp.verts[i])
        mask.normals.append(tmp.normals[i])
        mask.colors.append(tmp.colors[i])
    for f in tmp.faces:
        if all(i in keep for i in f):
            mask.faces.append([remap[i] for i in f])
    emit("Mask", mask, (0, 1.36, -0.42))
    export(os.path.join(OUT, "jinn.glb"))


def main():
    report = {}
    for sp in SPECIES:
        report[sp] = build_species(sp)
    build_equipment()
    build_jinn()
    for k, v in report.items():
        print(f"{k}: {v} faces")
    print("wrote", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
