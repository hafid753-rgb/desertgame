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
        "inner_ear": (0.98, 0.62, 0.62), "eye": (0.07, 0.05, 0.09), "nose": (0.85, 0.42, 0.45), "pad": (0.96, 0.6, 0.62), "iris": (0.45, 0.75, 0.3),
        "robe": (0.42, 0.66, 0.92), "robe_dark": (0.3, 0.5, 0.78), "embroidery": (1.0, 0.83, 0.35),
        "ears": "cat", "head": "round", "tail": "cat",
    },
    "fennec": {
        "fur": (0.92, 0.76, 0.52), "fur_dark": (0.76, 0.58, 0.36), "accent": (0.96, 0.9, 0.8),
        "inner_ear": (1.0, 0.86, 0.78), "eye": (0.07, 0.05, 0.09), "nose": (0.12, 0.08, 0.08), "pad": (0.35, 0.25, 0.22), "iris": (0.85, 0.55, 0.2),
        "robe": (0.9, 0.9, 0.88), "robe_dark": (0.74, 0.76, 0.8), "embroidery": (0.2, 0.3, 0.62),
        "ears": "fennec", "head": "fox", "tail": "fennec",
    },
    "lizard": {
        "fur": (0.36, 0.66, 0.36), "fur_dark": (0.22, 0.46, 0.26), "accent": (0.9, 0.88, 0.5),
        "inner_ear": (0.9, 0.5, 0.3), "eye": (0.98, 0.82, 0.2), "nose": (0.18, 0.3, 0.18), "pad": (0.85, 0.85, 0.5), "iris": (0.98, 0.82, 0.2),
        "robe": (0.2, 0.26, 0.55), "robe_dark": (0.14, 0.18, 0.42), "embroidery": (0.98, 0.95, 0.88),
        "ears": "none", "head": "lizard", "tail": "lizard",
    },
}


def project_patch(target, center, size, res, pattern, offset=0.004):
    """Crisp surface detail: a dense grid in the XY plane projected onto the
    front of `target` (a Part) along +Z, kept only where pattern(u, v) returns
    a colour. Gives sharp embroidery without a texture."""
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromPolygons([Vector(v) for v in target.verts], target.faces)
    nx, ny = res
    grid = {}
    cols = {}
    for j in range(ny + 1):
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            x = center[0] + (u - 0.5) * size[0]
            y = center[1] + (v - 0.5) * size[1]
            hit = bvh.ray_cast(Vector((x, y, -2.0)), Vector((0, 0, 1)))
            if hit[0] is None:
                continue
            grid[(i, j)] = hit[0] + hit[1].normalized() * offset
            cols[(i, j)] = pattern(u, v)
    out = Part()
    index = {}
    for j in range(ny):
        for i in range(nx):
            quad = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            if not all(q in grid for q in quad):
                continue
            uc, vc = (i + 0.5) / nx, (j + 0.5) / ny
            c = pattern(uc, vc)
            if c is None:
                continue
            ids = []
            for q in quad:
                key = (q, c)
                if key not in index:
                    index[key] = len(out.verts)
                    out.verts.append(grid[q])
                    out.normals.append(Vector((0, 0, -1)))
                    out.colors.append(c)
                ids.append(index[key])
            out.faces.append(list(reversed(ids)))
    return out


def merge(dst, src):
    off = len(dst.verts)
    dst.verts += src.verts
    dst.normals += src.normals
    dst.colors += src.colors
    dst.faces += [[i + off for i in f] for f in src.faces]


def box_part(part, center, size, color, taper_tip=None):
    m = T(center, scale=size)
    part.add_mesh(prim("cube"), lambda c, n: color, m)


# ===========================================================================
# Adventurer proportions (v0.4): ~1.75 m tall, head about 1/6 of the height,
# floating hands and feet kept. Pivots are in Godot space.
# ===========================================================================
HEAD_C = (0, 1.6, 0)     # head pivot
BODY_C = (0, 0.8, 0)     # robe pivot (hips)
TAIL_C = (0, 0.62, 0.22)
HAND_C = (0.5, 0.92, -0.05)
FOOT_C = (0.13, 0.07, 0.0)


def superellipse(a, hw, hd, n=2.6):
    c, s_ = math.cos(a), math.sin(a)
    x = hw * math.copysign(abs(c) ** (2.0 / n), c)
    z = hd * math.copysign(abs(s_) ** (2.0 / n), s_)
    return x, z


def loft(sections, segs, color_fn, fold_fn=None, cap_top=True, cap_bottom=True):
    """sections: [(y, half_width, half_depth, z_offset)], bottom to top.
    Returns a Part whose rings are superellipses with optional folds."""
    p = Part()
    rings = []
    for (y, hw, hd, zo) in sections:
        ring = []
        for i in range(segs):
            a = i / segs * math.tau
            x, z = superellipse(a, hw, hd)
            k = 1.0 + (fold_fn(y, a) if fold_fn else 0.0)
            co = Vector((x * k, y, z * k + zo))
            ring.append(len(p.verts))
            p.verts.append(co)
            n = Vector((x, 0, z)).normalized() if (x or z) else Vector((0, 1, 0))
            p.normals.append(n)
            p.colors.append(color_fn(co, a))
        rings.append(ring)
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        for i in range(segs):
            j = (i + 1) % segs
            p.faces.append([b[i], b[j], a[j], a[i]])
    for cap, ring, flip in ((cap_bottom, rings[0], True), (cap_top, rings[-1], False)):
        if not cap:
            continue
        y = p.verts[ring[0]].y
        zo = sum(p.verts[i].z for i in ring) / len(ring)
        c = len(p.verts)
        p.verts.append(Vector((0, y, zo)))
        p.normals.append(Vector((0, -1 if flip else 1, 0)))
        p.colors.append(p.colors[ring[0]])
        for i in range(segs):
            j = (i + 1) % segs
            p.faces.append([ring[i], ring[j], c] if flip else [ring[j], ring[i], c])
    return p


def build_robe(s):
    """A real daraa: one wide piece of cloth falling from the shoulders over
    the arms to the shins, open at the sides, with deep vertical drape folds,
    gold hem and side trim, and an embroidered chest pocket."""
    robe, robe_dark, emb, fur = s["robe"], s["robe_dark"], s["embroidery"], s["fur"]
    oy = BODY_C[1]
    # (world y, half width, half depth, z offset)
    prof = [
        (0.24, 0.44, 0.27, 0.03), (0.32, 0.43, 0.26, 0.03), (0.5, 0.41, 0.25, 0.02),
        (0.7, 0.38, 0.23, 0.01), (0.9, 0.31, 0.19, 0.0), (1.05, 0.33, 0.19, -0.01),
        (1.17, 0.34, 0.18, -0.01), (1.26, 0.33, 0.16, 0.0), (1.32, 0.3, 0.15, 0.0),
        (1.37, 0.18, 0.12, 0.0), (1.42, 0.1, 0.09, 0.0),
    ]
    # Interpolate extra rings for smooth folds.
    dense = []
    for i in range(len(prof) - 1):
        a, b = prof[i], prof[i + 1]
        for t in (0.0, 0.5):
            dense.append(tuple(lerp(a[k], b[k], t) for k in range(4)))
    dense.append(prof[-1])
    sections = [(y - oy, hw, hd, zo) for (y, hw, hd, zo) in dense]

    def folds(y, a):
        wy = y + oy
        depth = max(0.0, min(1.0, (1.25 - wy) / 0.9))
        # Main drape: big folds where the cloth falls off the arms (sides),
        # smaller pleats front and back.
        side = abs(math.cos(a)) ** 3
        return depth * (0.07 * side * math.sin(a * 6 + 0.4) + 0.025 * math.sin(a * 13 + 1.1))

    def col(co, a):
        wy = co.y + oy
        x = co.x
        if wy > 1.39:
            return fur  # neck
        if wy < 0.31:
            return emb  # gold hem band
        if wy < 0.35:
            return robe_dark
        if 0.86 < wy < 0.95:
            return (0.42, 0.24, 0.12)  # leather belt
        # Side seams of the open daraa: thin gold line down each side.
        shade = 0.5 + 0.5 * math.sin(a * 6 + 0.4)
        depth = max(0.0, min(1.0, (1.2 - wy) / 0.8))
        return mix(robe, robe_dark, 0.35 * shade * depth)
    p = loft(sections, 56, col, folds)

    def pocket(u, v):
        if u < 0.1 or u > 0.9 or v < 0.05 or v > 0.95:
            return emb
        cu = u - 0.5
        for cv in (0.22, 0.5, 0.78):
            d = abs(cu) / 0.28 + abs(v - cv) / 0.1
            if 0.45 < d < 1.0:
                return emb
        if abs(cu) < 0.035 and 0.12 < v < 0.88:
            return emb
        return None
    merge(p, project_patch(p, (0.12, 1.06 - oy), (0.13, 0.18), (22, 34), pocket))
    # Brass belt buckle.
    merge(p, project_patch(p, (0, 0.905 - oy), (0.07, 0.07), (8, 8),
                           lambda u, v: (0.85, 0.65, 0.25) if (abs(u - 0.5) > 0.25 or abs(v - 0.5) > 0.25) else None, offset=0.008))

    def neck(u, v):
        x = (u - 0.5) * 0.22
        y = 1.2 + v * 0.2 - oy
        return emb if abs(abs(x) - (1.4 - oy - y) * 0.45) < 0.01 else None
    merge(p, project_patch(p, (0, 1.3 - oy), (0.22, 0.2), (44, 40), neck))
    return p


def build_head(s):
    p = Part()
    fur, dark, acc = s["fur"], s["fur_dark"], s["accent"]
    kind = s["head"]
    if kind == "lizard":
        elems = [("ELLIPSOID", (0, 0.02, 0.02), 0.2, (0.95, 0.85, 1.05)),
                 ("ELLIPSOID", (0, -0.03, -0.18), 0.14, (0.8, 0.62, 1.35))]
    elif kind == "fox":
        elems = [("ELLIPSOID", (0, 0.01, 0), 0.2, (1.0, 0.92, 1.0)),
                 ("ELLIPSOID", (0, -0.05, -0.17), 0.085, (0.95, 0.75, 1.9)),
                 ("BALL", (0.1, -0.06, -0.06), 0.09, None), ("BALL", (-0.1, -0.06, -0.06), 0.09, None)]
    else:
        elems = [("ELLIPSOID", (0, 0.01, 0), 0.21, (1.05, 0.95, 1.0)),
                 ("ELLIPSOID", (0, -0.06, -0.15), 0.085, (1.15, 0.8, 1.2)),
                 ("BALL", (0.1, -0.07, -0.08), 0.09, None), ("BALL", (-0.1, -0.07, -0.08), 0.09, None)]
    head = meta_mesh("head2_" + kind, elems, resolution=0.026)

    def col(co, n):
        x, y, z = co
        if kind == "lizard":
            if y < -0.06 and z < 0.0:
                return acc
            if hash3(round(x * 22), round(y * 22), round(z * 22)) > 0.75 and y > 0.02:
                return dark
            return fur
        if z < -0.1 and y < -0.04:
            return acc  # muzzle and chin
        if kind == "round" and y > 0.1 and abs(x) < 0.09 and math.sin(x * 70 + 1.57) > 0.55:
            return dark  # forehead stripes
        if kind == "fox" and z < -0.06 and y > -0.02 and abs(x) < 0.035:
            return mix(fur, acc, 0.6)
        if kind == "fox" and y < -0.03:
            return acc  # pale cheeks and throat
        return fur
    p.add_mesh(head, col)
    # Brow ridge gives a determined look instead of a baby face.
    if kind != "lizard":
        for sx in (-1, 1):
            p.add_mesh(prim("sphere", r=0.04, u=10, v=6), lambda c, n: fur,
                       T((0.07 * sx, 0.065, -0.16), rot=(0, 0, 0.18 * sx), scale=(1.4, 0.4, 0.6)))
    nose = {"round": (0, -0.02, -0.262), "fox": (0, -0.05, -0.335), "lizard": (0, -0.02, -0.36)}[kind]
    p.add_mesh(prim("sphere", r=0.022, u=8, v=6), lambda c, n: s["nose"], T(nose, scale=(1.3, 0.8, 0.9)))
    if kind == "lizard":
        for i, zz in enumerate([0.1, 0.03, -0.04, -0.11]):
            m = T((0, 0.19 - abs(zz) * 0.2, zz)) @ UP_CONE
            p.add_mesh(prim("cone", r1=0.03, r2=0.0, h=0.09, seg=6), lambda c, n: s["inner_ear"],
                       m @ Matrix.Translation((0, 0, 0.04)) @ Matrix.Diagonal((0.5, 1, 1, 1)))
    else:
        for sx in (-1, 1):  # cheek ruff
            m = T((0.19 * sx, -0.07, 0.0), rot=(0, 0, -1.1 * sx)) @ UP_CONE
            p.add_mesh(prim("cone", r1=0.035, r2=0.0, h=0.08, seg=6), lambda c, n: fur,
                       m @ Matrix.Translation((0, 0, 0.03)) @ Matrix.Diagonal((1, 0.5, 1, 1)))
    return p


EYE_Y = {"round": 0.03, "fox": 0.03, "lizard": 0.06}


def build_eyes(s):
    """Almond eyes: white sclera, coloured iris, pupil, glint. Separate part
    (pivot at eye height) so the game blinks it by scaling Y."""
    p = Part()
    kind = s["head"]
    iris = s["iris"]
    if kind == "lizard":
        for sx in (-1, 1):
            p.add_mesh(prim("sphere", r=0.05, u=12, v=8), lambda c, n: iris, T((0.13 * sx, 0, -0.07), scale=(0.75, 1, 1)))
            p.add_mesh(prim("sphere", r=0.03, u=8, v=6), lambda c, n: (0.04, 0.04, 0.04), T((0.165 * sx, 0, -0.08), scale=(0.3, 1.4, 0.4)))
            p.add_mesh(prim("sphere", r=0.01, u=6, v=4), lambda c, n: (1, 1, 1), T((0.17 * sx, 0.02, -0.1)))
        return p
    slit = kind == "round"
    for sx in (-1, 1):
        base = Vector((0.075 * sx, 0.0, -0.172))
        p.add_mesh(prim("sphere", r=0.045, u=12, v=8), lambda c, n: (0.97, 0.96, 0.92),
                   T(base, rot=(0, 0, -0.18 * sx), scale=(1.25, 0.82, 0.45)))
        p.add_mesh(prim("sphere", r=0.03, u=10, v=8), lambda c, n: iris, T(base + Vector((-0.004 * sx, -0.002, -0.012)), scale=(1, 1.05, 0.4)))
        p.add_mesh(prim("sphere", r=0.017, u=8, v=6), lambda c, n: (0.03, 0.02, 0.03),
                   T(base + Vector((-0.004 * sx, -0.002, -0.022)), scale=(0.45 if slit else 1.0, 1.25 if slit else 1.0, 0.4)))
        p.add_mesh(prim("sphere", r=0.008, u=6, v=4), lambda c, n: (1, 1, 1), T(base + Vector((0.01 * sx, 0.012, -0.028))))
    return p


def ear_layout(s):
    if s["ears"] == "fennec":
        return 0.12, 0.34, (0.12, 0.13, 0.02), 0.45
    return 0.075, 0.17, (0.12, 0.13, 0.0), 0.35


def build_ear(s, sx):
    p = Part()
    r, h, _, tilt = ear_layout(s)
    m = Matrix.Rotation(-tilt * sx, 4, "Z") @ UP_CONE
    p.add_mesh(prim("cone", r1=r, r2=0.0, h=h, seg=12), lambda c, n: s["fur"],
               m @ Matrix.Translation((0, 0, h * 0.5)) @ Matrix.Diagonal((1, 0.45, 1, 1)))
    p.add_mesh(prim("cone", r1=r * 0.62, r2=0.0, h=h * 0.78, seg=10), lambda c, n: s["inner_ear"],
               m @ Matrix.Translation((0, -0.025, h * 0.43)) @ Matrix.Diagonal((1, 0.3, 1, 1)))
    if s["ears"] == "fennec":
        p.add_mesh(prim("cone", r1=r * 0.3, r2=0.0, h=h * 0.4, seg=6), lambda c, n: s["accent"],
                   m @ Matrix.Translation((0, -0.035, h * 0.22)) @ Matrix.Diagonal((1, 0.4, 1, 1)))
    if s["ears"] == "cat":  # dark ear tips
        p.add_mesh(prim("cone", r1=r * 0.35, r2=0.0, h=h * 0.3, seg=8), lambda c, n: s["fur_dark"],
                   m @ Matrix.Translation((0, 0.003, h * 0.86)) @ Matrix.Diagonal((1, 0.47, 1, 1)))
    return p


def build_tail(s):
    p = Part()
    kind = s["tail"]
    pts = []
    n = 16
    for i in range(n):
        t = i / (n - 1)
        if kind == "lizard":
            pos = (0, -0.45 + 0.08 * math.sin(t * 3.0), 0.05 + t * 0.95)
            r = lerp(0.1, 0.025, t)
        elif kind == "fennec":
            pos = (0, -0.15 + t * 0.25, 0.05 + t * 0.55)
            r = lerp(0.06, 0.11, math.sin(t * math.pi * 0.85))
        else:
            pos = (0, -0.1 + t * 0.55, 0.05 + math.sin(t * 2.2) * 0.4)
            r = lerp(0.05, 0.035, t)
        pts.append((pos, r, t))
    me = meta_mesh("tail2_" + kind, [("BALL", pp, r, None) for pp, r, _ in pts], resolution=0.03)

    def col(co, nrm):
        best = min(pts, key=lambda q: (Vector(q[0]) - co).length)
        t = best[2]
        if kind == "fennec" and t > 0.82:
            return (0.12, 0.08, 0.07)
        if kind == "cat" and math.sin(t * 26) > 0.45:
            return s["fur_dark"]
        if kind == "lizard" and nrm.y > 0.5 and hash3(co.x * 9, co.y * 9, co.z * 9) > 0.6:
            return s["fur_dark"]
        return s["fur"]
    p.add_mesh(me, col)
    return p


def build_paw(s, foot=False):
    p = Part()
    fur, pad = s["fur"], s.get("pad", (0.95, 0.62, 0.62))
    claw = s["head"] == "lizard"
    if foot:
        # Leather sandal (naal) under a furry foot.
        sole, strap = (0.36, 0.22, 0.12), (0.55, 0.3, 0.14)
        p.add_mesh(prim("sphere", r=0.07, u=12, v=8), lambda c, n: fur, T((0, 0.02, -0.03), scale=(0.95, 0.7, 1.5)))
        box_part(p, (0, -0.035, -0.035), (0.13, 0.025, 0.25), sole)
        box_part(p, (0, 0.01, -0.07), (0.14, 0.03, 0.03), strap)
        for k in (-1, 0, 1):
            p.add_mesh(prim("sphere", r=0.025, u=6, v=4), lambda c, n: (0.95, 0.95, 0.85) if claw else fur,
                       T((k * 0.035, -0.005, -0.13), scale=(0.9, 0.8, 1.4 if claw else 1.0)))
    else:
        p.add_mesh(prim("sphere", r=0.065, u=12, v=8), lambda c, n: pad if c.z < -0.035 and c.y < 0.0 else fur,
                   T(scale=(0.9, 1.0, 1.1)))
        for k in (-1, 0, 1):
            p.add_mesh(prim("sphere", r=0.024, u=6, v=4), lambda c, n: (0.95, 0.95, 0.85) if claw else fur,
                       T((k * 0.032, -0.02, -0.065), scale=(0.9, 0.9, 1.6 if claw else 1.3)))
        p.add_mesh(prim("sphere", r=0.024, u=6, v=4), lambda c, n: fur, T((0.055, 0.02, -0.025)))
    return p


def build_daraa_wing(s, sx):
    """The daraa's side panels opened as a sail for gliding."""
    part = Part()
    grid = prim("grid", xs=12, ys=8)
    for v in grid.vertices:
        u = v.co.x + 0.5
        w = v.co.y + 0.5
        v.co = Vector((sx * (0.3 + u * 1.05), math.sin(w * math.pi * 5) * 0.03 * u - 0.06 * u * u - 0.1 * w,
                       (w - 0.5) * lerp(0.5, 0.95, u)))

    def col(c, n):
        u = (abs(c.x) - 0.3) / 1.05
        if u > 0.94 or abs(c.z) > lerp(0.25, 0.475, u) - 0.03:
            return s["embroidery"]
        return s["robe"]
    part.add_mesh(grid, col)
    return part


def build_species(name):
    clear_scene()
    s = SPECIES[name]
    eye_y = EYE_Y[s["head"]]
    rows = [
        ("Body", build_robe(s), BODY_C),
        ("Head", build_head(s), HEAD_C),
        ("Eyes", build_eyes(s), (0, HEAD_C[1] + eye_y, 0)),
        ("Tail", build_tail(s), TAIL_C),
        ("HandR", build_paw(s), HAND_C),
        ("HandL", build_paw(s), (-HAND_C[0], HAND_C[1], HAND_C[2])),
        ("FootR", build_paw(s, True), FOOT_C),
        ("FootL", build_paw(s, True), (-FOOT_C[0], FOOT_C[1], FOOT_C[2])),
        ("DaraaR", build_daraa_wing(s, 1), (0, 1.3, 0.02)),
        ("DaraaL", build_daraa_wing(s, -1), (0, 1.3, 0.02)),
    ]
    if s["ears"] != "none":
        _, _, base, _ = ear_layout(s)
        rows.append(("EarR", build_ear(s, 1), (base[0], HEAD_C[1] + base[1], base[2])))
        rows.append(("EarL", build_ear(s, -1), (-base[0], HEAD_C[1] + base[1], base[2])))
    tris = 0
    for pname, part, pivot in rows:
        _, f = emit(pname, part, pivot)
        tris += f
    export(os.path.join(OUT, name + ".glb"))
    return tris


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
    disc = prim("sphere", r=0.27, u=48, v=24)

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
    body.add_mesh(meta_mesh("jinn_body", elems, resolution=0.065), lambda c, n: (0.05, 0.03, 0.08))
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
    bone, ochre, dark = (0.9, 0.84, 0.72), (0.78, 0.46, 0.2), (0.06, 0.04, 0.06)

    def mask_pattern(x, y):
        for ex in (-0.11, 0.11):  # eye holes; the game puts glowing eyes in front
            if ((x - ex) / 0.068) ** 2 + ((y - 0.05) / 0.045) ** 2 < 1.0:
                return dark
            if ((x - ex) / 0.085) ** 2 + ((y - 0.05) / 0.06) ** 2 < 1.0:
                return ochre  # painted rim around each eye
            for k in (-1, 0, 1):  # three dots under each eye
                if math.hypot(x - ex - k * 0.032, y + 0.035) < 0.011:
                    return ochre
        tri = abs(((x * 14) % 2) - 1)
        if 0.15 < y < 0.15 + 0.06 * (0.3 + 0.7 * tri):  # zigzag brow band
            return ochre
        if 0.245 < y < 0.258:
            return ochre
        if -0.215 < y < -0.195 and abs(x) < 0.085:
            return dark  # mouth slit
        if abs(x) < 0.008 and -0.18 < y < -0.05:
            return ochre  # nose line
        return None

    sph = prim("sphere", r=1.0, u=40, v=20)
    m = T(scale=(0.27, 0.36, 0.11))
    tmp = Part()
    tmp.add_mesh(sph, lambda c, n: bone, m)
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
    W, H = 0.5, 0.66
    merge(mask, project_patch(mask, (0, 0), (W, H), (64, 84),
                              lambda u, v: mask_pattern((u - 0.5) * W, (v - 0.5) * H), offset=0.003))
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
