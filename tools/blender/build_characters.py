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
        self.ao = None  # per-vertex ambient occlusion (1 = open), set by bake_depth()

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
    ao = part.ao or [1.0] * len(part.colors)
    for c, o in zip(part.colors, ao):
        flat.extend((c[0], c[1], c[2], o))
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
    # Saharan sand cat (Felis margarita margarita): pale yellow-sand fur,
    # broad head, very large black-tipped ears set wide and low, green-yellow
    # eyes ringed with white, black nose, reddish streak from the eye across
    # the cheek, white chin/throat, ringed tail with a black tip.
    "cat": {
        "fur": (0.8, 0.7, 0.55), "fur_dark": (0.36, 0.26, 0.18), "accent": (0.97, 0.95, 0.88),
        "inner_ear": (0.86, 0.62, 0.48), "eye": (0.07, 0.05, 0.09), "nose": (0.1, 0.08, 0.08),
        "pad": (0.3, 0.22, 0.16), "iris": (0.74, 0.82, 0.32), "streak": (0.78, 0.44, 0.22),
        "robe": (0.36, 0.6, 0.88), "robe_dark": (0.24, 0.44, 0.72), "embroidery": (1.0, 0.84, 0.38),
        "inner": (0.96, 0.95, 0.92), "hawli": (0.1, 0.1, 0.12), "hawli_dark": (0.05, 0.05, 0.07), "hawli_on": "neck",
        "ears": "cat", "head": "round", "tail": "cat",
    },
    # Fennec (Vulpes zerda): cream fur, white underparts, enormous ears,
    # tiny face with a pointed snout, black eyes and nose, black tail tip.
    "fennec": {
        "fur": (0.9, 0.81, 0.66), "fur_dark": (0.55, 0.4, 0.28), "accent": (0.98, 0.97, 0.93),
        "inner_ear": (0.98, 0.88, 0.8), "eye": (0.07, 0.05, 0.09), "nose": (0.06, 0.05, 0.05),
        "pad": (0.3, 0.22, 0.18), "iris": (0.12, 0.08, 0.06), "streak": (0.5, 0.36, 0.26),
        "robe": (0.93, 0.93, 0.9), "robe_dark": (0.76, 0.78, 0.82), "embroidery": (0.22, 0.34, 0.7),
        "inner": (0.2, 0.3, 0.6), "hawli": (0.16, 0.22, 0.52), "hawli_dark": (0.1, 0.14, 0.38), "hawli_on": "head",
        "ears": "fennec", "head": "fox", "tail": "fennec",
    },
    # Spiny-tailed lizard / dabb (Uromastyx dispar, found in Mauritania):
    # blunt round head, males bright yellow with mottled black, short thick
    # tail ringed with spiny scales.
    "lizard": {
        "fur": (0.86, 0.7, 0.26), "fur_dark": (0.14, 0.11, 0.08), "accent": (0.96, 0.9, 0.62),
        "inner_ear": (0.62, 0.46, 0.26), "eye": (0.07, 0.05, 0.09), "nose": (0.3, 0.22, 0.12),
        "pad": (0.6, 0.48, 0.2), "iris": (0.55, 0.32, 0.12), "streak": (0.6, 0.45, 0.28),
        "robe": (0.16, 0.2, 0.42), "robe_dark": (0.1, 0.13, 0.3), "embroidery": (0.98, 0.95, 0.86),
        "inner": (0.95, 0.93, 0.88), "hawli": (0.13, 0.2, 0.5), "hawli_dark": (0.08, 0.12, 0.34), "hawli_on": "both",
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


def project_poly(target, polys, offset=0.005, cuts=3):
    """Project flat 2D polygons (lists of (x, y) in the part's space, with a
    colour) onto the front of `target` along +Z. Polygons are triangulated and
    subdivided so they hug the curved cloth; edges stay perfectly straight."""
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromPolygons([Vector(v) for v in target.verts], target.faces)
    out = Part()
    for pts, col in polys:
        bm = bmesh.new()
        vs = [bm.verts.new((x, y, 0.0)) for x, y in pts]
        bm.faces.new(vs)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        off = len(out.verts)
        ok = True
        for v in bm.verts:
            hit = bvh.ray_cast(Vector((v.co.x, v.co.y, -2.0)), Vector((0, 0, 1)))
            if hit[0] is None:
                ok = False
                break
            out.verts.append(hit[0] + Vector((0, 0, -offset)))
            out.normals.append(Vector((0, 0, -1)))
            out.colors.append(col)
        if not ok:
            del out.verts[off:], out.normals[off:], out.colors[off:]
            bm.free()
            continue
        bm.verts.index_update()
        for f in bm.faces:
            ids = [off + v.index for v in f.verts]
            a, b, c = (v.co.copy() for v in f.verts[:3])
            if (b - a).cross(c - a).z > 0:  # face toward -Z (the viewer)
                ids.reverse()
            out.faces.append(ids)
        bm.free()
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
HAND_C = (0.56, 0.92, -0.05)
FOOT_C = (0.13, 0.07, 0.0)


def superellipse(a, hw, hd, n=2.6):
    c, s_ = math.cos(a), math.sin(a)
    x = hw * math.copysign(abs(c) ** (2.0 / n), c)
    z = hd * math.copysign(abs(s_) ** (2.0 / n), s_)
    return x, z


def loft(sections, segs, color_fn, fold_fn=None, cap_top=True, cap_bottom=True, squareness=2.6):
    """sections: [(y, half_width, half_depth, z_offset)], bottom to top.
    Returns a Part whose rings are superellipses with optional folds."""
    p = Part()
    rings = []
    for (y, hw, hd, zo) in sections:
        ring = []
        for i in range(segs):
            a = i / segs * math.tau
            x, z = superellipse(a, hw, hd, squareness)
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
        return depth * (0.035 * side * math.sin(a * 6 + 0.4) + 0.012 * math.sin(a * 13 + 1.1))

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
    p = loft(sections, 56, col, folds, squareness=4.5)

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


# ===========================================================================
# Boxy style (v0.6): everything built from rounded boxes (bevelled cubes),
# Rayman-style floating hands and shoes, five hand poses per side.
# ===========================================================================
HAND_POSES = ["open", "fist", "grip", "thumbs_up", "peace"]
HAND_SCALE = 1.6  # big, expressive Rayman-style paws


def rbox(size, r=0.03, seg=2, taper=None):
    """Rounded box centred at the origin. taper=(sx, sz) scales the top face
    (y > 0) to make wedges such as ears."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if taper and v.co.y > 0:
            v.co.x *= taper[0]
            v.co.z *= taper[1]
    r = min(r, min(size) * 0.45)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=r, offset_type="OFFSET", segments=seg,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("rbox")
    bm.to_mesh(me)
    bm.free()
    return me


def add_box(part, size, loc, color, r=0.03, rot=(0, 0, 0), taper=None, seg=2):
    c = color if callable(color) else (lambda co, n, col=color: col)
    part.add_mesh(rbox(size, r, seg, taper), c, T(loc, rot=rot))


def mirrored(part):
    """Mirror a Part across X (left from right), fixing face winding."""
    m = Part()
    m.verts = [Vector((-v.x, v.y, v.z)) for v in part.verts]
    m.normals = [Vector((-n.x, n.y, n.z)) for n in part.normals]
    m.colors = list(part.colors)
    m.faces = [list(reversed(f)) for f in part.faces]
    return m


def build_head(s):
    p = Part()
    fur, fur_dark, acc = s["fur"], s["fur_dark"], s["accent"]
    kind = s["head"]
    if kind == "lizard":
        add_box(p, (0.36, 0.3, 0.4), (0, 0.0, 0.02), fur, r=0.09)
        add_box(p, (0.28, 0.15, 0.24), (0, -0.05, -0.25), fur, r=0.06)
        add_box(p, (0.26, 0.06, 0.22), (0, -0.115, -0.24), acc, r=0.03)  # pale jaw
        for i, zz in enumerate([0.12, 0.03, -0.06]):  # crest
            add_box(p, (0.035, 0.09, 0.07), (0, 0.18 - i * 0.008, zz), s["inner_ear"], r=0.015, taper=(0.5, 0.4))
        for sx in (-1, 1):  # scale spots
            add_box(p, (0.05, 0.012, 0.05), (0.09 * sx, 0.152, 0.06), dark, r=0.008)
        add_box(p, (0.04, 0.02, 0.025), (0, -0.02, -0.37), s["nose"], r=0.008)
        return p
    if kind == "fox":
        add_box(p, (0.4, 0.34, 0.36), (0, 0.0, 0.0), fur, r=0.1)
        add_box(p, (0.16, 0.11, 0.2), (0, -0.075, -0.24), acc, r=0.045)
        add_box(p, (0.3, 0.08, 0.2), (0, -0.14, -0.04), acc, r=0.035)   # pale cheeks/throat
        add_box(p, (0.05, 0.12, 0.02), (0, 0.06, -0.181), mix(fur, acc, 0.6), r=0.01)  # blaze
        add_box(p, (0.05, 0.03, 0.03), (0, -0.045, -0.345), s["nose"], r=0.01)
    else:
        add_box(p, (0.42, 0.36, 0.38), (0, 0.0, 0.0), fur, r=0.1)
        add_box(p, (0.21, 0.12, 0.12), (0, -0.075, -0.2), acc, r=0.05)
        for x in (-0.06, 0.0, 0.06):  # forehead stripes
            add_box(p, (0.03, 0.012, 0.13), (x, 0.181, -0.03), dark, r=0.005)
        add_box(p, (0.055, 0.03, 0.03), (0, -0.03, -0.268), s["nose"], r=0.01)
    # Cheek tufts and determined brows.
    for sx in (-1, 1):
        add_box(p, (0.07, 0.08, 0.09), (0.215 * sx, -0.07, 0.0), fur, r=0.025, rot=(0, 0, 0.5 * sx), taper=(0.4, 0.8))
        add_box(p, (0.11, 0.026, 0.035), (0.085 * sx, 0.075, -0.188), s["fur_dark"], r=0.01, rot=(0, 0, 0.15 * sx))
    return p


EYE_Y = {"round": 0.0, "fox": 0.0, "lizard": 0.04}


def build_eyes(s):
    """Rounded-rectangle eyes: sclera, iris, pupil, glint. One part so the
    game blinks it by scaling Y."""
    p = Part()
    kind = s["head"]
    iris = s["iris"]
    if kind == "lizard":
        for sx in (-1, 1):
            add_box(p, (0.03, 0.08, 0.1), (0.185 * sx, 0.0, -0.06), iris, r=0.02)
            add_box(p, (0.012, 0.06, 0.02), (0.2 * sx, 0.0, -0.065), (0.04, 0.04, 0.04), r=0.005)
            add_box(p, (0.008, 0.015, 0.015), (0.203 * sx, 0.02, -0.09), (1, 1, 1), r=0.004)
        return p
    slit = kind == "round"
    for sx in (-1, 1):
        x = 0.085 * sx
        add_box(p, (0.1, 0.075, 0.02), (x, 0.0, -0.19), (0.97, 0.96, 0.92), r=0.022)
        add_box(p, (0.055, 0.058, 0.012), (x - 0.006 * sx, -0.003, -0.2), iris, r=0.016)
        add_box(p, (0.016 if slit else 0.028, 0.044 if slit else 0.03, 0.008), (x - 0.006 * sx, -0.003, -0.205), (0.03, 0.02, 0.03), r=0.006)
        add_box(p, (0.012, 0.012, 0.006), (x + 0.012 * sx, 0.016, -0.209), (1, 1, 1), r=0.004)
    return p


def ear_layout(s):
    if s["ears"] == "fennec":
        return (0.17, 0.32, 0.06), (0.12, 0.17, 0.02), 0.45
    return (0.12, 0.17, 0.05), (0.12, 0.17, 0.0), 0.32


def build_ear(s, sx):
    p = Part()
    size, _, tilt = ear_layout(s)
    rot = (0, 0, -tilt * sx)
    w, h, d = size
    p.add_mesh(rbox(size, 0.02, 3, taper=(0.15, 0.6)), lambda c, n: s["fur"], T((0, h * 0.5, 0), rot=rot) if False else
               Matrix.Rotation(-tilt * sx, 4, "Z") @ Matrix.Translation((0, h * 0.5, 0)))
    p.add_mesh(rbox((w * 0.6, h * 0.75, d * 0.4), 0.012, 2, taper=(0.15, 0.6)), lambda c, n: s["inner_ear"],
               Matrix.Rotation(-tilt * sx, 4, "Z") @ Matrix.Translation((0, h * 0.42, -d * 0.4)))
    if s["ears"] == "cat":
        p.add_mesh(rbox((w * 0.35, h * 0.28, d * 1.05), 0.008, 2, taper=(0.2, 0.7)), lambda c, n: s["fur_dark"],
                   Matrix.Rotation(-tilt * sx, 4, "Z") @ Matrix.Translation((0, h * 0.86, 0)))
    return p


def build_tail(s):
    """Chain of rounded boxes following the tail curve."""
    p = Part()
    kind = s["tail"]
    pts = []
    n = 8
    for i in range(n + 1):
        t = i / n
        if kind == "lizard":
            pos, r = Vector((0, -0.45 + 0.08 * math.sin(t * 3.0), 0.05 + t * 0.95)), lerp(0.1, 0.03, t)
        elif kind == "fennec":
            pos, r = Vector((0, -0.15 + t * 0.25, 0.05 + t * 0.55)), lerp(0.06, 0.12, math.sin(t * math.pi * 0.85))
        else:
            pos, r = Vector((0, -0.1 + t * 0.55, 0.05 + math.sin(t * 2.2) * 0.4)), lerp(0.05, 0.04, t)
        pts.append((pos, r, t))
    for i in range(n):
        a, b = pts[i], pts[i + 1]
        d = b[0] - a[0]
        mid = (a[0] + b[0]) * 0.5
        r = (a[1] + b[1]) * 0.5
        t = a[2]
        if kind == "fennec" and t > 0.8:
            col = (0.12, 0.08, 0.07)
        elif kind == "cat" and i % 2 == 1:
            col = s["fur_dark"]
        elif kind == "lizard" and i % 3 == 1:
            col = s["fur_dark"]
        else:
            col = s["fur"]
        rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        p.add_mesh(rbox((r * 2, d.length * 1.25, r * 2), r * 0.45, 2), lambda c, nn, col=col: col,
                   Matrix.Translation(mid) @ rot)
    return p


def build_hand(s, pose):
    """Right paw, palm down, fingers toward -Z, thumb on the inner (-X) side.
    Poses: open (walking), fist (running/punching), grip (holding the sword),
    thumbs_up, peace."""
    p = Part()
    fur, pad = s["fur"], s.get("pad", (0.95, 0.62, 0.62))
    claw = s["head"] == "lizard"
    tip = (0.95, 0.95, 0.85) if claw else fur

    def palm_col(co, n):
        return pad if co.y < -0.03 else fur
    add_box(p, (0.15, 0.08, 0.13), (0, 0, 0), palm_col, r=0.035)
    fx = [0.05, 0.017, -0.017, -0.05]

    def straight(x, length=0.1, rot=(0, 0, 0), y=0.0):
        add_box(p, (0.034, 0.034, length), (x, y, -0.065 - length * 0.5), fur, r=0.014, rot=rot)
        if claw:
            add_box(p, (0.02, 0.02, 0.025), (x, y, -0.065 - length - 0.008), tip, r=0.008)

    def curled(xs):
        for x in xs:
            add_box(p, (0.036, 0.05, 0.05), (x, -0.012, -0.085), fur, r=0.016)

    if pose == "open":
        for x in fx:
            straight(x)
        add_box(p, (0.036, 0.036, 0.085), (-0.095, 0.0, -0.035), fur, r=0.015, rot=(0, 0.55, 0))
    elif pose == "fist":
        curled(fx)
        add_box(p, (0.08, 0.034, 0.036), (-0.03, 0.03, -0.095), fur, r=0.014)  # thumb across the knuckles
    elif pose == "grip":
        for x in fx:  # fingers wrapped under the hilt
            add_box(p, (0.036, 0.03, 0.06), (x, -0.045, -0.09), fur, r=0.012)
        add_box(p, (0.036, 0.034, 0.075), (-0.07, 0.035, -0.09), fur, r=0.014)  # thumb along the top
    elif pose == "thumbs_up":
        curled(fx)
        add_box(p, (0.038, 0.1, 0.038), (-0.07, 0.085, -0.045), fur, r=0.016)
    elif pose == "peace":
        curled(fx[:2])
        straight(fx[2], 0.13, rot=(0, -0.34, 0))
        straight(fx[3], 0.13, rot=(0, 0.4, 0))
        add_box(p, (0.07, 0.034, 0.036), (0.02, 0.03, -0.095), fur, r=0.014)
    p.verts = [v * HAND_SCALE for v in p.verts]
    return p


def build_shoe(s):
    """Chunky leather boot with a toe cap and a coloured strap."""
    p = Part()
    leather, sole = (0.55, 0.32, 0.16), (0.3, 0.18, 0.1)
    add_box(p, (0.17, 0.11, 0.27), (0, 0.0, -0.04), leather, r=0.05)
    add_box(p, (0.175, 0.03, 0.28), (0, -0.055, -0.04), sole, r=0.012)
    add_box(p, (0.15, 0.06, 0.08), (0, 0.02, -0.15), mix(leather, (1, 1, 1), 0.12), r=0.025)
    add_box(p, (0.178, 0.03, 0.05), (0, 0.035, -0.02), s["embroidery"], r=0.01)
    add_box(p, (0.12, 0.07, 0.11), (0, 0.075, 0.02), s["fur"], r=0.035)  # ankle tuft
    return p


def build_daraa_wing(s, sx):
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
        ("FootR", build_shoe(s), FOOT_C),
        ("FootL", mirrored(build_shoe(s)), (-FOOT_C[0], FOOT_C[1], FOOT_C[2])),
        ("DaraaR", build_daraa_wing(s, 1), (0, 1.3, 0.02)),
        ("DaraaL", build_daraa_wing(s, -1), (0, 1.3, 0.02)),
    ]
    for pose in HAND_POSES:
        hand = build_hand(s, pose)
        rows.append(("HandR_" + pose, hand, HAND_C))
        rows.append(("HandL_" + pose, mirrored(hand), (-HAND_C[0], HAND_C[1], HAND_C[2])))
    if s["ears"] != "none":
        _, base, _ = ear_layout(s)
        rows.append(("EarR", build_ear(s, 1), (base[0], HEAD_C[1] + base[1], base[2])))
        rows.append(("EarL", build_ear(s, -1), (-base[0], HEAD_C[1] + base[1], base[2])))
    tris = 0
    for pname, part, pivot in rows:
        _, f = emit(pname, part, pivot)
        if not pname.startswith("Hand") or pname.endswith("_open"):
            tris += f
    export(os.path.join(OUT, name + ".glb"))
    return tris


def build_equipment():
    clear_scene()
    # Takoba: the straight, double-edged broadsword of the Sahara and Sahel.
    # Long, gently tapering blade with three fullers and a rounded tip; flat
    # cross-guard with langets; leather-wrapped grip with brass bands; disc
    # pommel. Grip at origin, blade toward -Z.
    sword = Part()
    steel, steel_edge, fuller = (0.78, 0.81, 0.86), (0.97, 0.98, 1.0), (0.52, 0.56, 0.62)
    brass, red, black = (0.86, 0.66, 0.26), (0.58, 0.13, 0.08), (0.1, 0.07, 0.06)
    L, z0 = 0.9, -0.1
    bm = bmesh.new()
    rings = []
    steps = 22
    for i in range(steps + 1):
        t = i / steps
        z = z0 - t * L
        w = lerp(0.074, 0.058, t)
        if t > 0.9:  # rounded tip
            k = (t - 0.9) / 0.1
            w *= math.sqrt(max(0.0, 1 - k * k)) * 0.92 + 0.08
        th = lerp(0.02, 0.012, t)
        prof = [(-w / 2, 0), (-w * 0.32, th / 2), (w * 0.32, th / 2), (w / 2, 0), (w * 0.32, -th / 2), (-w * 0.32, -th / 2)]
        rings.append([bm.verts.new((x, y, z)) for x, y in prof])
    for i in range(steps):
        for j in range(6):
            bm.faces.new([rings[i][j], rings[i][(j + 1) % 6], rings[i + 1][(j + 1) % 6], rings[i + 1][j]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bme = bpy.data.meshes.new("blade")
    bm.to_mesh(bme)
    bm.free()
    sword.add_mesh(bme, lambda c, n: steel_edge if abs(n.y) < 0.5 else steel)
    for side in (1, -1):  # three fullers on each face
        for fx, fl in ((-0.016, 0.62), (0.0, 0.7), (0.016, 0.62)):
            add_box(sword, (0.006, 0.003, L * fl), (fx, side * 0.0085, z0 - 0.03 - L * fl / 2), fuller, r=0.001)
    add_box(sword, (0.25, 0.03, 0.035), (0, 0, -0.085), brass, r=0.008)            # cross-guard
    add_box(sword, (0.05, 0.034, 0.08), (0, 0, -0.12), brass, r=0.008, taper=(0.6, 1.0))  # langets
    for i in range(7):  # leather wrap, alternating red / black, brass end bands
        z = -0.05 + i * 0.024
        col = brass if i in (0, 6) else (red if i % 2 else black)
        add_box(sword, (0.044, 0.04, 0.024), (0, 0, z), col, r=0.01)
    add_box(sword, (0.11, 0.028, 0.11), (0, 0, 0.13), brass, r=0.03)               # disc pommel
    add_box(sword, (0.035, 0.035, 0.04), (0, 0, 0.19), brass, r=0.014)
    sword.verts = [v * 0.78 for v in sword.verts]
    emit("Sword", sword, (0, 0, 0), smooth=False)

    # Takoba scabbard: tooled leather with red / green / black bands and a
    # flared diamond chape. Same axis as the blade so the sheathed sword sits in it.
    sc = Part()
    tan, green = (0.7, 0.5, 0.3), (0.2, 0.42, 0.28)
    n = 10
    for i in range(n):
        t = (i + 0.5) / n
        z = -0.11 - t * 0.88
        col = tan
        if i % 3 == 1:
            col = red
        elif i % 3 == 2 and i > 2:
            col = green
        add_box(sc, (lerp(0.1, 0.085, t), 0.04, 0.088), (0, 0, z), col, r=0.014)
        add_box(sc, (0.02, 0.043, 0.06), (0, 0, z), black if col != tan else red, r=0.006, rot=(0, 0.785, 0))
    add_box(sc, (0.16, 0.036, 0.16), (0, 0, -1.04), tan, r=0.02, rot=(0, 0.785, 0))     # diamond chape
    add_box(sc, (0.1, 0.04, 0.1), (0, 0, -1.04), red, r=0.015, rot=(0, 0.785, 0))
    add_box(sc, (0.12, 0.05, 0.04), (0, 0, -0.12), brass, r=0.012)                       # throat
    sc.verts = [v * 0.78 for v in sc.verts]
    emit("Scabbard", sc, (0, 0, 0))

    # Rectangular leather shield (aghar-inspired): rounded box, painted
    # cross and triangle pattern projected as crisp geometry, brass boss.
    shield = Part()
    leather, red, dark, brass = (0.74, 0.55, 0.32), (0.58, 0.14, 0.08), (0.14, 0.09, 0.06), (0.85, 0.65, 0.25)
    add_box(shield, (0.05, 0.5, 0.36), (0, 0, 0), leather, r=0.02)
    add_box(shield, (0.03, 0.04, 0.04), (-0.035, 0, 0), brass, r=0.01)

    def pattern(u, v):
        x, y = (u - 0.5) * 0.36, (v - 0.5) * 0.5
        if abs(x) < 0.012 or abs(y) < 0.012:
            return dark
        if abs(abs(x) - 0.15) < 0.01 or abs(abs(y) - 0.225) < 0.01:
            return red
        tri = abs(((y * 20) % 2) - 1)
        if abs(x) > 0.11 and abs(x) - 0.11 < 0.035 * tri:
            return red
        return None
    # Project onto the outer face (-X): rotate a temporary copy so the face
    # points at the projector, then rotate the decal back.
    rot_in = Matrix.Rotation(-math.pi / 2, 4, "Y")
    tmp = Part()
    tmp.verts = [rot_in @ v for v in shield.verts]
    tmp.faces = shield.faces
    decal = project_patch(tmp, (0, 0), (0.36, 0.5), (40, 56), pattern, offset=0.003)
    rot_out = Matrix.Rotation(math.pi / 2, 4, "Y")
    decal.verts = [rot_out @ v for v in decal.verts]
    merge(shield, decal)
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


# ===========================================================================
# v0.7: species-accurate heads, a true daraa, the hawli/tagelmust, and
# baked depth (ambient occlusion + edge curvature + height gradient).
# Appended last so these definitions replace the earlier ones.
# ===========================================================================


def torus(major, minor, seg=28, tube=8):
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = i / seg * math.tau
        ring = []
        for j in range(tube):
            b = j / tube * math.tau
            r = major + minor * math.cos(b)
            ring.append(bm.verts.new((r * math.cos(a), minor * math.sin(b), r * math.sin(a))))
        rings.append(ring)
    for i in range(seg):
        for j in range(tube):
            a0, a1 = rings[i], rings[(i + 1) % seg]
            bm.faces.new([a0[j], a0[(j + 1) % tube], a1[(j + 1) % tube], a1[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("torus")
    bm.to_mesh(me)
    bm.free()
    return me


def build_head(s):
    p = Part()
    fur, fur_dark, acc = s["fur"], s["fur_dark"], s["accent"]
    kind = s["head"]
    if kind == "lizard":
        # Dabb: blunt, rounded head, brownish with pale spots, short snout.
        head_col = (0.8, 0.62, 0.3)
        add_box(p, (0.38, 0.3, 0.4), (0, 0.0, 0.02), head_col, r=0.13, seg=6)
        add_box(p, (0.3, 0.17, 0.16), (0, -0.04, -0.21), head_col, r=0.075)
        add_box(p, (0.28, 0.06, 0.2), (0, -0.115, -0.18), acc, r=0.03)
        for i, (x, z) in enumerate([(-0.1, 0.06), (0.08, 0.1), (0.0, -0.05), (-0.06, -0.12), (0.11, -0.08), (0.03, 0.15)]):
            add_box(p, (0.045, 0.012, 0.04), (x, 0.152, z), (0.95, 0.88, 0.62) if i % 2 else fur_dark, r=0.01)
        for sx in (-1, 1):  # heavy brow scales over the eyes
            add_box(p, (0.09, 0.05, 0.1), (0.15 * sx, 0.1, -0.05), head_col, r=0.025)
            add_box(p, (0.02, 0.015, 0.02), (0.06 * sx, -0.03, -0.295), (0.08, 0.06, 0.05), r=0.006)  # nostril
        return p
    if kind == "fox":
        # Fennec: small rounded skull, tiny face, slim pointed snout, white cheeks.
        add_box(p, (0.36, 0.31, 0.33), (0, 0.0, 0.0), fur, r=0.13, seg=6)
        add_box(p, (0.12, 0.09, 0.2), (0, -0.07, -0.22), fur, r=0.04, taper=(0.75, 1.0))
        add_box(p, (0.11, 0.045, 0.18), (0, -0.1, -0.21), acc, r=0.02)
        add_box(p, (0.3, 0.1, 0.22), (0, -0.12, -0.05), acc, r=0.045)
        add_box(p, (0.045, 0.035, 0.03), (0, -0.05, -0.33), s["nose"], r=0.012)
        for sx in (-1, 1):  # dark tear line from the inner eye down the snout
            add_box(p, (0.018, 0.05, 0.012), (0.04 * sx, -0.03, -0.172), s["streak"], r=0.006, rot=(0, 0, 0.35 * sx))
        return p
    # Sand cat: broad, low head; white lower face; reddish cheek streaks.
    add_box(p, (0.46, 0.33, 0.38), (0, 0.0, 0.0), fur, r=0.13, seg=6)
    add_box(p, (0.24, 0.12, 0.12), (0, -0.08, -0.2), acc, r=0.05)
    add_box(p, (0.34, 0.08, 0.24), (0, -0.14, -0.05), acc, r=0.035)
    for x in (-0.05, 0.0, 0.05):  # faint crown striations
        add_box(p, (0.022, 0.01, 0.12), (x, 0.166, -0.02), s["fur_dark"], r=0.004)
    for sx in (-1, 1):
        add_box(p, (0.1, 0.016, 0.012), (0.16 * sx, -0.035, -0.18), s["streak"], r=0.006, rot=(0, 0, -0.45 * sx))
        add_box(p, (0.075, 0.09, 0.08), (0.24 * sx, -0.08, 0.0), fur, r=0.025, rot=(0, 0, 0.6 * sx), taper=(0.4, 0.8))
    add_box(p, (0.06, 0.035, 0.03), (0, -0.035, -0.268), s["nose"], r=0.012)
    return p


def build_eyes(s):
    p = Part()
    kind = s["head"]
    iris = s["iris"]
    if kind == "lizard":
        for sx in (-1, 1):
            add_box(p, (0.03, 0.065, 0.085), (0.19 * sx, 0.0, -0.06), (0.18, 0.12, 0.06), r=0.02)
            add_box(p, (0.012, 0.05, 0.06), (0.204 * sx, 0.0, -0.06), iris, r=0.01)
            add_box(p, (0.008, 0.014, 0.014), (0.21 * sx, 0.018, -0.08), (1, 1, 1), r=0.004)
        return p
    ring = kind == "round"  # sand cat: eyes ringed with white
    for sx in (-1, 1):
        x = 0.09 * sx
        if ring:  # pale lower rim instead of a full white frame
            add_box(p, (0.07, 0.016, 0.012), (x, -0.04, -0.188), (0.98, 0.97, 0.92), r=0.007)
        base = iris if ring else ((0.12, 0.08, 0.06) if kind == "fox" else (0.97, 0.96, 0.9))
        add_box(p, (0.084, 0.07, 0.02), (x, 0.0, -0.19), base, r=0.032, seg=3, rot=(0, 0, -0.12 * sx))
        add_box(p, (0.055, 0.058, 0.012), (x - 0.005 * sx, -0.002, -0.2), iris, r=0.016)
        add_box(p, (0.014 if ring else 0.03, 0.044 if ring else 0.032, 0.008), (x - 0.005 * sx, -0.002, -0.205), (0.03, 0.02, 0.03), r=0.006)
        add_box(p, (0.013, 0.013, 0.006), (x + 0.013 * sx, 0.017, -0.209), (1, 1, 1), r=0.004)
    return p


def ear_layout(s):
    if s["ears"] == "fennec":
        return (0.2, 0.4, 0.06), (0.11, 0.12, 0.02), 0.42
    return (0.19, 0.22, 0.05), (0.19, 0.07, 0.0), 0.75  # sand cat: very large, wide and low


def build_ear(s, sx):
    p = Part()
    size, _, tilt = ear_layout(s)
    w, h, d = size
    rot = Matrix.Rotation(-tilt * sx, 4, "Z")
    p.add_mesh(rbox(size, 0.025, 2, taper=(0.18, 0.6)), lambda c, n: s["fur"], rot @ Matrix.Translation((0, h * 0.5, 0)))
    p.add_mesh(rbox((w * 0.62, h * 0.78, d * 0.4), 0.015, 2, taper=(0.15, 0.6)), lambda c, n: s["inner_ear"],
               rot @ Matrix.Translation((0, h * 0.42, -d * 0.4)))
    p.add_mesh(rbox((w * 0.5, h * 0.35, d * 0.25), 0.01, 2, taper=(0.3, 0.6)), lambda c, n: s["accent"],
               rot @ Matrix.Translation((0, h * 0.2, -d * 0.52)))  # pale inner fur
    if s["ears"] == "cat":  # black tips
        p.add_mesh(rbox((w * 0.34, h * 0.3, d * 1.06), 0.008, 2, taper=(0.2, 0.7)), lambda c, n: (0.08, 0.07, 0.07),
                   rot @ Matrix.Translation((0, h * 0.86, 0)))
    return p


def build_tail(s):
    p = Part()
    kind = s["tail"]
    n = 9
    pts = []
    for i in range(n + 1):
        t = i / n
        if kind == "lizard":  # short, thick, ringed with spines
            pos, r = Vector((0, -0.42 + 0.05 * math.sin(t * 3.0), 0.05 + t * 0.62)), lerp(0.13, 0.05, t)
        elif kind == "fennec":
            pos, r = Vector((0, -0.15 + t * 0.25, 0.05 + t * 0.55)), lerp(0.06, 0.12, math.sin(t * math.pi * 0.85))
        else:
            pos, r = Vector((0, -0.1 + t * 0.5, 0.05 + math.sin(t * 2.2) * 0.42)), lerp(0.055, 0.045, t)
        pts.append((pos, r, t))
    for i in range(n):
        a, b = pts[i], pts[i + 1]
        d = b[0] - a[0]
        mid = (a[0] + b[0]) * 0.5
        r = (a[1] + b[1]) * 0.5
        t = a[2]
        if kind == "fennec":
            col = (0.1, 0.07, 0.06) if t > 0.75 else s["fur"]
        elif kind == "cat":
            col = (0.08, 0.07, 0.07) if t > 0.85 or (t > 0.45 and i % 2 == 0) else s["fur"]
        else:
            col = s["fur_dark"] if i % 2 == 1 else s["fur"]
        rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        p.add_mesh(rbox((r * 2, d.length * 1.25, r * 2), r * 0.45, 2), lambda c, nn, col=col: col, Matrix.Translation(mid) @ rot)
        if kind == "lizard":  # whorl of spiny scales
            for k in range(6):
                ang = k / 6 * math.tau
                outward = Vector((math.cos(ang), 0.0, math.sin(ang)))
                loc = Vector((0, 0, 0)) + outward * r * 0.95
                spike_rot = Vector((0, 1, 0)).rotation_difference(outward).to_matrix().to_4x4()
                p.add_mesh(rbox((0.035, 0.06, 0.035), 0.01, 1, taper=(0.15, 0.15)), lambda c, nn: (0.86, 0.72, 0.3),
                           Matrix.Translation(mid) @ rot @ Matrix.Translation(loc) @ spike_rot)
    return p


_old_build_hand = build_hand


def build_hand(s, pose):
    p = _old_build_hand(s, pose)
    if s["head"] == "round":  # sand cat: dark bars around the wrist
        for z in (0.05, 0.085):
            add_box(p, (0.16 * HAND_SCALE, 0.088 * HAND_SCALE, 0.016 * HAND_SCALE), (0, 0, z * HAND_SCALE), s["fur_dark"], r=0.03)
    return p


def build_robe(s):
    """A true daraa: one wide rectangle folded at the shoulders, sides sewn
    only halfway so the upper sides open into huge sleeves. Front view is a
    wide, squarish block falling from shoulder line to shins; deep vertical
    drape folds hang from the arms. Long V-neck ending in a five-sided
    embroidered pocket, an inner tunic showing in the V, gold/white hem."""
    robe, robe_dark, emb, fur = s["robe"], s["robe_dark"], s["embroidery"], s["fur"]
    oy = BODY_C[1]
    prof = [  # (world y, half width, half depth, z offset)
        (0.22, 0.44, 0.25, 0.02), (0.3, 0.44, 0.245, 0.02), (0.5, 0.425, 0.24, 0.01),
        (0.7, 0.405, 0.23, 0.0), (0.9, 0.385, 0.22, 0.0), (1.08, 0.37, 0.21, 0.0),
        (1.2, 0.35, 0.2, 0.0), (1.28, 0.31, 0.185, 0.0), (1.34, 0.25, 0.16, 0.0),
        (1.39, 0.18, 0.13, 0.0), (1.43, 0.11, 0.09, 0.0),
    ]
    dense = []
    for i in range(len(prof) - 1):
        a, b = prof[i], prof[i + 1]
        for t in (0.0, 0.34, 0.67):
            dense.append(tuple(lerp(a[k], b[k], t) for k in range(4)))
    dense.append(prof[-1])
    sections = [(y - oy, hw, hd, zo) for (y, hw, hd, zo) in dense]

    def folds(y, a):
        wy = y + oy
        depth = max(0.0, min(1.0, (1.25 - wy) / 0.9))
        # Main drape: big folds where the cloth falls off the arms (sides),
        # smaller pleats front and back.
        side = abs(math.cos(a)) ** 3
        return depth * (0.035 * side * math.sin(a * 6 + 0.4) + 0.012 * math.sin(a * 13 + 1.1))

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
    p = loft(sections, 56, col, folds, squareness=4.5)

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


# ===========================================================================
# Boxy style (v0.6): everything built from rounded boxes (bevelled cubes),
# Rayman-style floating hands and shoes, five hand poses per side.
# ===========================================================================
HAND_POSES = ["open", "fist", "grip", "thumbs_up", "peace"]
HAND_SCALE = 1.6  # big, expressive Rayman-style paws


def rbox(size, r=0.03, seg=2, taper=None):
    """Rounded box centred at the origin. taper=(sx, sz) scales the top face
    (y > 0) to make wedges such as ears."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if taper and v.co.y > 0:
            v.co.x *= taper[0]
            v.co.z *= taper[1]
    r = min(r, min(size) * 0.45)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=r, offset_type="OFFSET", segments=seg,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("rbox")
    bm.to_mesh(me)
    bm.free()
    return me


def add_box(part, size, loc, color, r=0.03, rot=(0, 0, 0), taper=None, seg=2):
    c = color if callable(color) else (lambda co, n, col=color: col)
    part.add_mesh(rbox(size, r, seg, taper), c, T(loc, rot=rot))


def mirrored(part):
    """Mirror a Part across X (left from right), fixing face winding."""
    m = Part()
    m.verts = [Vector((-v.x, v.y, v.z)) for v in part.verts]
    m.normals = [Vector((-n.x, n.y, n.z)) for n in part.normals]
    m.colors = list(part.colors)
    m.faces = [list(reversed(f)) for f in part.faces]
    return m


def build_head(s):
    p = Part()
    fur, fur_dark, acc = s["fur"], s["fur_dark"], s["accent"]
    kind = s["head"]
    if kind == "lizard":
        add_box(p, (0.36, 0.3, 0.4), (0, 0.0, 0.02), fur, r=0.09)
        add_box(p, (0.28, 0.15, 0.24), (0, -0.05, -0.25), fur, r=0.06)
        add_box(p, (0.26, 0.06, 0.22), (0, -0.115, -0.24), acc, r=0.03)  # pale jaw
        for i, zz in enumerate([0.12, 0.03, -0.06]):  # crest
            add_box(p, (0.035, 0.09, 0.07), (0, 0.18 - i * 0.008, zz), s["inner_ear"], r=0.015, taper=(0.5, 0.4))
        for sx in (-1, 1):  # scale spots
            add_box(p, (0.05, 0.012, 0.05), (0.09 * sx, 0.152, 0.06), dark, r=0.008)
        add_box(p, (0.04, 0.02, 0.025), (0, -0.02, -0.37), s["nose"], r=0.008)
        return p
    if kind == "fox":
        add_box(p, (0.4, 0.34, 0.36), (0, 0.0, 0.0), fur, r=0.1)
        add_box(p, (0.16, 0.11, 0.2), (0, -0.075, -0.24), acc, r=0.045)
        add_box(p, (0.3, 0.08, 0.2), (0, -0.14, -0.04), acc, r=0.035)   # pale cheeks/throat
        add_box(p, (0.05, 0.12, 0.02), (0, 0.06, -0.181), mix(fur, acc, 0.6), r=0.01)  # blaze
        add_box(p, (0.05, 0.03, 0.03), (0, -0.045, -0.345), s["nose"], r=0.01)
    else:
        add_box(p, (0.42, 0.36, 0.38), (0, 0.0, 0.0), fur, r=0.1)
        add_box(p, (0.21, 0.12, 0.12), (0, -0.075, -0.2), acc, r=0.05)
        for x in (-0.06, 0.0, 0.06):  # forehead stripes
            add_box(p, (0.03, 0.012, 0.13), (x, 0.181, -0.03), dark, r=0.005)
        add_box(p, (0.055, 0.03, 0.03), (0, -0.03, -0.268), s["nose"], r=0.01)
    # Cheek tufts and determined brows.
    for sx in (-1, 1):
        add_box(p, (0.07, 0.08, 0.09), (0.215 * sx, -0.07, 0.0), fur, r=0.025, rot=(0, 0, 0.5 * sx), taper=(0.4, 0.8))
        add_box(p, (0.11, 0.026, 0.035), (0.085 * sx, 0.075, -0.188), s["fur_dark"], r=0.01, rot=(0, 0, 0.15 * sx))
    return p


EYE_Y = {"round": 0.0, "fox": 0.0, "lizard": 0.04}


def build_eyes(s):
    """Rounded-rectangle eyes: sclera, iris, pupil, glint. One part so the
    game blinks it by scaling Y."""
    p = Part()
    kind = s["head"]
    iris = s["iris"]
    if kind == "lizard":
        for sx in (-1, 1):
            add_box(p, (0.03, 0.08, 0.1), (0.185 * sx, 0.0, -0.06), iris, r=0.02)
            add_box(p, (0.012, 0.06, 0.02), (0.2 * sx, 0.0, -0.065), (0.04, 0.04, 0.04), r=0.005)
            add_box(p, (0.008, 0.015, 0.015), (0.203 * sx, 0.02, -0.09), (1, 1, 1), r=0.004)
        return p
    slit = kind == "round"
    for sx in (-1, 1):
        x = 0.085 * sx
        add_box(p, (0.1, 0.075, 0.02), (x, 0.0, -0.19), (0.97, 0.96, 0.92), r=0.022)
        add_box(p, (0.055, 0.058, 0.012), (x - 0.006 * sx, -0.003, -0.2), iris, r=0.016)
        add_box(p, (0.016 if slit else 0.028, 0.044 if slit else 0.03, 0.008), (x - 0.006 * sx, -0.003, -0.205), (0.03, 0.02, 0.03), r=0.006)
        add_box(p, (0.012, 0.012, 0.006), (x + 0.012 * sx, 0.016, -0.209), (1, 1, 1), r=0.004)
    return p


def ear_layout(s):
    if s["ears"] == "fennec":
        return (0.17, 0.32, 0.06), (0.12, 0.17, 0.02), 0.45
    return (0.12, 0.17, 0.05), (0.12, 0.17, 0.0), 0.32


def build_ear(s, sx):
    p = Part()
    size, _, tilt = ear_layout(s)
    rot = (0, 0, -tilt * sx)
    w, h, d = size
    p.add_mesh(rbox(size, 0.02, 3, taper=(0.15, 0.6)), lambda c, n: s["fur"], T((0, h * 0.5, 0), rot=rot) if False else
               Matrix.Rotation(-tilt * sx, 4, "Z") @ Matrix.Translation((0, h * 0.5, 0)))
    p.add_mesh(rbox((w * 0.6, h * 0.75, d * 0.4), 0.012, 2, taper=(0.15, 0.6)), lambda c, n: s["inner_ear"],
               Matrix.Rotation(-tilt * sx, 4, "Z") @ Matrix.Translation((0, h * 0.42, -d * 0.4)))
    if s["ears"] == "cat":
        p.add_mesh(rbox((w * 0.35, h * 0.28, d * 1.05), 0.008, 2, taper=(0.2, 0.7)), lambda c, n: s["fur_dark"],
                   Matrix.Rotation(-tilt * sx, 4, "Z") @ Matrix.Translation((0, h * 0.86, 0)))
    return p


def build_tail(s):
    """Chain of rounded boxes following the tail curve."""
    p = Part()
    kind = s["tail"]
    pts = []
    n = 8
    for i in range(n + 1):
        t = i / n
        if kind == "lizard":
            pos, r = Vector((0, -0.45 + 0.08 * math.sin(t * 3.0), 0.05 + t * 0.95)), lerp(0.1, 0.03, t)
        elif kind == "fennec":
            pos, r = Vector((0, -0.15 + t * 0.25, 0.05 + t * 0.55)), lerp(0.06, 0.12, math.sin(t * math.pi * 0.85))
        else:
            pos, r = Vector((0, -0.1 + t * 0.55, 0.05 + math.sin(t * 2.2) * 0.4)), lerp(0.05, 0.04, t)
        pts.append((pos, r, t))
    for i in range(n):
        a, b = pts[i], pts[i + 1]
        d = b[0] - a[0]
        mid = (a[0] + b[0]) * 0.5
        r = (a[1] + b[1]) * 0.5
        t = a[2]
        if kind == "fennec" and t > 0.8:
            col = (0.12, 0.08, 0.07)
        elif kind == "cat" and i % 2 == 1:
            col = s["fur_dark"]
        elif kind == "lizard" and i % 3 == 1:
            col = s["fur_dark"]
        else:
            col = s["fur"]
        rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        p.add_mesh(rbox((r * 2, d.length * 1.25, r * 2), r * 0.45, 2), lambda c, nn, col=col: col,
                   Matrix.Translation(mid) @ rot)
    return p


def build_hand(s, pose):
    """Right paw, palm down, fingers toward -Z, thumb on the inner (-X) side.
    Poses: open (walking), fist (running/punching), grip (holding the sword),
    thumbs_up, peace."""
    p = Part()
    fur, pad = s["fur"], s.get("pad", (0.95, 0.62, 0.62))
    claw = s["head"] == "lizard"
    tip = (0.95, 0.95, 0.85) if claw else fur

    def palm_col(co, n):
        return pad if co.y < -0.03 else fur
    add_box(p, (0.15, 0.08, 0.13), (0, 0, 0), palm_col, r=0.035)
    fx = [0.05, 0.017, -0.017, -0.05]

    def straight(x, length=0.1, rot=(0, 0, 0), y=0.0):
        add_box(p, (0.034, 0.034, length), (x, y, -0.065 - length * 0.5), fur, r=0.014, rot=rot)
        if claw:
            add_box(p, (0.02, 0.02, 0.025), (x, y, -0.065 - length - 0.008), tip, r=0.008)

    def curled(xs):
        for x in xs:
            add_box(p, (0.036, 0.05, 0.05), (x, -0.012, -0.085), fur, r=0.016)

    if pose == "open":
        for x in fx:
            straight(x)
        add_box(p, (0.036, 0.036, 0.085), (-0.095, 0.0, -0.035), fur, r=0.015, rot=(0, 0.55, 0))
    elif pose == "fist":
        curled(fx)
        add_box(p, (0.08, 0.034, 0.036), (-0.03, 0.03, -0.095), fur, r=0.014)  # thumb across the knuckles
    elif pose == "grip":
        for x in fx:  # fingers wrapped under the hilt
            add_box(p, (0.036, 0.03, 0.06), (x, -0.045, -0.09), fur, r=0.012)
        add_box(p, (0.036, 0.034, 0.075), (-0.07, 0.035, -0.09), fur, r=0.014)  # thumb along the top
    elif pose == "thumbs_up":
        curled(fx)
        add_box(p, (0.038, 0.1, 0.038), (-0.07, 0.085, -0.045), fur, r=0.016)
    elif pose == "peace":
        curled(fx[:2])
        straight(fx[2], 0.13, rot=(0, -0.34, 0))
        straight(fx[3], 0.13, rot=(0, 0.4, 0))
        add_box(p, (0.07, 0.034, 0.036), (0.02, 0.03, -0.095), fur, r=0.014)
    p.verts = [v * HAND_SCALE for v in p.verts]
    return p


def build_shoe(s):
    """Chunky leather boot with a toe cap and a coloured strap."""
    p = Part()
    leather, sole = (0.55, 0.32, 0.16), (0.3, 0.18, 0.1)
    add_box(p, (0.17, 0.11, 0.27), (0, 0.0, -0.04), leather, r=0.05)
    add_box(p, (0.175, 0.03, 0.28), (0, -0.055, -0.04), sole, r=0.012)
    add_box(p, (0.15, 0.06, 0.08), (0, 0.02, -0.15), mix(leather, (1, 1, 1), 0.12), r=0.025)
    add_box(p, (0.178, 0.03, 0.05), (0, 0.035, -0.02), s["embroidery"], r=0.01)
    add_box(p, (0.12, 0.07, 0.11), (0, 0.075, 0.02), s["fur"], r=0.035)  # ankle tuft
    return p


def build_daraa_wing(s, sx):
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
        ("FootR", build_shoe(s), FOOT_C),
        ("FootL", mirrored(build_shoe(s)), (-FOOT_C[0], FOOT_C[1], FOOT_C[2])),
        ("DaraaR", build_daraa_wing(s, 1), (0, 1.3, 0.02)),
        ("DaraaL", build_daraa_wing(s, -1), (0, 1.3, 0.02)),
    ]
    for pose in HAND_POSES:
        hand = build_hand(s, pose)
        rows.append(("HandR_" + pose, hand, HAND_C))
        rows.append(("HandL_" + pose, mirrored(hand), (-HAND_C[0], HAND_C[1], HAND_C[2])))
    if s["ears"] != "none":
        _, base, _ = ear_layout(s)
        rows.append(("EarR", build_ear(s, 1), (base[0], HEAD_C[1] + base[1], base[2])))
        rows.append(("EarL", build_ear(s, -1), (-base[0], HEAD_C[1] + base[1], base[2])))
    tris = 0
    for pname, part, pivot in rows:
        _, f = emit(pname, part, pivot)
        if not pname.startswith("Hand") or pname.endswith("_open"):
            tris += f
    export(os.path.join(OUT, name + ".glb"))
    return tris


def build_equipment():
    clear_scene()
    # Takoba: the straight, double-edged broadsword of the Sahara and Sahel.
    # Long, gently tapering blade with three fullers and a rounded tip; flat
    # cross-guard with langets; leather-wrapped grip with brass bands; disc
    # pommel. Grip at origin, blade toward -Z.
    sword = Part()
    steel, steel_edge, fuller = (0.78, 0.81, 0.86), (0.97, 0.98, 1.0), (0.52, 0.56, 0.62)
    brass, red, black = (0.86, 0.66, 0.26), (0.58, 0.13, 0.08), (0.1, 0.07, 0.06)
    L, z0 = 0.9, -0.1
    bm = bmesh.new()
    rings = []
    steps = 22
    for i in range(steps + 1):
        t = i / steps
        z = z0 - t * L
        w = lerp(0.074, 0.058, t)
        if t > 0.9:  # rounded tip
            k = (t - 0.9) / 0.1
            w *= math.sqrt(max(0.0, 1 - k * k)) * 0.92 + 0.08
        th = lerp(0.02, 0.012, t)
        prof = [(-w / 2, 0), (-w * 0.32, th / 2), (w * 0.32, th / 2), (w / 2, 0), (w * 0.32, -th / 2), (-w * 0.32, -th / 2)]
        rings.append([bm.verts.new((x, y, z)) for x, y in prof])
    for i in range(steps):
        for j in range(6):
            bm.faces.new([rings[i][j], rings[i][(j + 1) % 6], rings[i + 1][(j + 1) % 6], rings[i + 1][j]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bme = bpy.data.meshes.new("blade")
    bm.to_mesh(bme)
    bm.free()
    sword.add_mesh(bme, lambda c, n: steel_edge if abs(n.y) < 0.5 else steel)
    for side in (1, -1):  # three fullers on each face
        for fx, fl in ((-0.016, 0.62), (0.0, 0.7), (0.016, 0.62)):
            add_box(sword, (0.006, 0.003, L * fl), (fx, side * 0.0085, z0 - 0.03 - L * fl / 2), fuller, r=0.001)
    add_box(sword, (0.25, 0.03, 0.035), (0, 0, -0.085), brass, r=0.008)            # cross-guard
    add_box(sword, (0.05, 0.034, 0.08), (0, 0, -0.12), brass, r=0.008, taper=(0.6, 1.0))  # langets
    for i in range(7):  # leather wrap, alternating red / black, brass end bands
        z = -0.05 + i * 0.024
        col = brass if i in (0, 6) else (red if i % 2 else black)
        add_box(sword, (0.044, 0.04, 0.024), (0, 0, z), col, r=0.01)
    add_box(sword, (0.11, 0.028, 0.11), (0, 0, 0.13), brass, r=0.03)               # disc pommel
    add_box(sword, (0.035, 0.035, 0.04), (0, 0, 0.19), brass, r=0.014)
    sword.verts = [v * 0.78 for v in sword.verts]
    emit("Sword", sword, (0, 0, 0), smooth=False)

    # Takoba scabbard: tooled leather with red / green / black bands and a
    # flared diamond chape. Same axis as the blade so the sheathed sword sits in it.
    sc = Part()
    tan, green = (0.7, 0.5, 0.3), (0.2, 0.42, 0.28)
    n = 10
    for i in range(n):
        t = (i + 0.5) / n
        z = -0.11 - t * 0.88
        col = tan
        if i % 3 == 1:
            col = red
        elif i % 3 == 2 and i > 2:
            col = green
        add_box(sc, (lerp(0.1, 0.085, t), 0.04, 0.088), (0, 0, z), col, r=0.014)
        add_box(sc, (0.02, 0.043, 0.06), (0, 0, z), black if col != tan else red, r=0.006, rot=(0, 0.785, 0))
    add_box(sc, (0.16, 0.036, 0.16), (0, 0, -1.04), tan, r=0.02, rot=(0, 0.785, 0))     # diamond chape
    add_box(sc, (0.1, 0.04, 0.1), (0, 0, -1.04), red, r=0.015, rot=(0, 0.785, 0))
    add_box(sc, (0.12, 0.05, 0.04), (0, 0, -0.12), brass, r=0.012)                       # throat
    sc.verts = [v * 0.78 for v in sc.verts]
    emit("Scabbard", sc, (0, 0, 0))

    # Rectangular leather shield (aghar-inspired): rounded box, painted
    # cross and triangle pattern projected as crisp geometry, brass boss.
    shield = Part()
    leather, red, dark, brass = (0.74, 0.55, 0.32), (0.58, 0.14, 0.08), (0.14, 0.09, 0.06), (0.85, 0.65, 0.25)
    add_box(shield, (0.05, 0.5, 0.36), (0, 0, 0), leather, r=0.02)
    add_box(shield, (0.03, 0.04, 0.04), (-0.035, 0, 0), brass, r=0.01)

    def pattern(u, v):
        x, y = (u - 0.5) * 0.36, (v - 0.5) * 0.5
        if abs(x) < 0.012 or abs(y) < 0.012:
            return dark
        if abs(abs(x) - 0.15) < 0.01 or abs(abs(y) - 0.225) < 0.01:
            return red
        tri = abs(((y * 20) % 2) - 1)
        if abs(x) > 0.11 and abs(x) - 0.11 < 0.035 * tri:
            return red
        return None
    # Project onto the outer face (-X): rotate a temporary copy so the face
    # points at the projector, then rotate the decal back.
    rot_in = Matrix.Rotation(-math.pi / 2, 4, "Y")
    tmp = Part()
    tmp.verts = [rot_in @ v for v in shield.verts]
    tmp.faces = shield.faces
    decal = project_patch(tmp, (0, 0), (0.36, 0.5), (40, 56), pattern, offset=0.003)
    rot_out = Matrix.Rotation(math.pi / 2, 4, "Y")
    decal.verts = [rot_out @ v for v in decal.verts]
    merge(shield, decal)
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


# ===========================================================================
# v0.7: species-accurate heads, a true daraa, the hawli/tagelmust, and
# baked depth (ambient occlusion + edge curvature + height gradient).
# Appended last so these definitions replace the earlier ones.
# ===========================================================================


def torus(major, minor, seg=28, tube=8):
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = i / seg * math.tau
        ring = []
        for j in range(tube):
            b = j / tube * math.tau
            r = major + minor * math.cos(b)
            ring.append(bm.verts.new((r * math.cos(a), minor * math.sin(b), r * math.sin(a))))
        rings.append(ring)
    for i in range(seg):
        for j in range(tube):
            a0, a1 = rings[i], rings[(i + 1) % seg]
            bm.faces.new([a0[j], a0[(j + 1) % tube], a1[(j + 1) % tube], a1[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("torus")
    bm.to_mesh(me)
    bm.free()
    return me


def build_head(s):
    p = Part()
    fur, fur_dark, acc = s["fur"], s["fur_dark"], s["accent"]
    kind = s["head"]
    if kind == "lizard":
        # Dabb: blunt, rounded head, brownish with pale spots, short snout.
        head_col = (0.8, 0.62, 0.3)
        add_box(p, (0.38, 0.3, 0.4), (0, 0.0, 0.02), head_col, r=0.13, seg=6)
        add_box(p, (0.3, 0.17, 0.16), (0, -0.04, -0.21), head_col, r=0.075)
        add_box(p, (0.28, 0.06, 0.2), (0, -0.115, -0.18), acc, r=0.03)
        for i, (x, z) in enumerate([(-0.1, 0.06), (0.08, 0.1), (0.0, -0.05), (-0.06, -0.12), (0.11, -0.08), (0.03, 0.15)]):
            add_box(p, (0.045, 0.012, 0.04), (x, 0.152, z), (0.95, 0.88, 0.62) if i % 2 else fur_dark, r=0.01)
        for sx in (-1, 1):  # heavy brow scales over the eyes
            add_box(p, (0.09, 0.05, 0.1), (0.15 * sx, 0.1, -0.05), head_col, r=0.025)
            add_box(p, (0.02, 0.015, 0.02), (0.06 * sx, -0.03, -0.295), (0.08, 0.06, 0.05), r=0.006)  # nostril
        return p
    if kind == "fox":
        # Fennec: small rounded skull, tiny face, slim pointed snout, white cheeks.
        add_box(p, (0.36, 0.31, 0.33), (0, 0.0, 0.0), fur, r=0.13, seg=6)
        add_box(p, (0.12, 0.09, 0.2), (0, -0.07, -0.22), fur, r=0.04, taper=(0.75, 1.0))
        add_box(p, (0.11, 0.045, 0.18), (0, -0.1, -0.21), acc, r=0.02)
        add_box(p, (0.3, 0.1, 0.22), (0, -0.12, -0.05), acc, r=0.045)
        add_box(p, (0.045, 0.035, 0.03), (0, -0.05, -0.33), s["nose"], r=0.012)
        for sx in (-1, 1):  # dark tear line from the inner eye down the snout
            add_box(p, (0.018, 0.05, 0.012), (0.04 * sx, -0.03, -0.172), s["streak"], r=0.006, rot=(0, 0, 0.35 * sx))
        return p
    # Sand cat: broad, low head; white lower face; reddish cheek streaks.
    add_box(p, (0.46, 0.33, 0.38), (0, 0.0, 0.0), fur, r=0.13, seg=6)
    add_box(p, (0.24, 0.12, 0.12), (0, -0.08, -0.2), acc, r=0.05)
    add_box(p, (0.34, 0.08, 0.24), (0, -0.14, -0.05), acc, r=0.035)
    for x in (-0.05, 0.0, 0.05):  # faint crown striations
        add_box(p, (0.022, 0.01, 0.12), (x, 0.166, -0.02), s["fur_dark"], r=0.004)
    for sx in (-1, 1):
        add_box(p, (0.1, 0.016, 0.012), (0.16 * sx, -0.035, -0.18), s["streak"], r=0.006, rot=(0, 0, -0.45 * sx))
        add_box(p, (0.075, 0.09, 0.08), (0.24 * sx, -0.08, 0.0), fur, r=0.025, rot=(0, 0, 0.6 * sx), taper=(0.4, 0.8))
    add_box(p, (0.06, 0.035, 0.03), (0, -0.035, -0.268), s["nose"], r=0.012)
    return p


def build_eyes(s):
    p = Part()
    kind = s["head"]
    iris = s["iris"]
    if kind == "lizard":
        for sx in (-1, 1):
            add_box(p, (0.03, 0.065, 0.085), (0.19 * sx, 0.0, -0.06), (0.18, 0.12, 0.06), r=0.02)
            add_box(p, (0.012, 0.05, 0.06), (0.204 * sx, 0.0, -0.06), iris, r=0.01)
            add_box(p, (0.008, 0.014, 0.014), (0.21 * sx, 0.018, -0.08), (1, 1, 1), r=0.004)
        return p
    cat = kind == "round"

    def blob(r, loc, scale, col, u=16, v=10):
        p.add_mesh(prim("sphere", r=r, u=u, v=v), lambda c, n, col=col: col, T(loc, scale=scale))
    for sx in (-1, 1):
        x = 0.09 * sx
        base = iris if cat else (0.1, 0.07, 0.06)
        blob(0.046, (x, 0.0, -0.183), (1.0, 0.86, 0.45), base)
        if cat:
            blob(0.03, (x, -0.036, -0.187), (1.25, 0.32, 0.4), (0.98, 0.97, 0.92))   # pale lower rim
            blob(0.032, (x - 0.004 * sx, 0.0, -0.194), (0.28, 0.95, 0.3), (0.04, 0.03, 0.04))  # slit pupil
        else:
            blob(0.026, (x, 0.0, -0.197), (1.0, 1.0, 0.3), (0.02, 0.02, 0.03))
        blob(0.011, (x + 0.016 * sx, 0.018, -0.203), (1.0, 1.0, 0.5), (1, 1, 1), 8, 6)
        blob(0.006, (x - 0.012 * sx, -0.016, -0.203), (1.0, 1.0, 0.5), (1, 1, 1), 6, 4)
    return p

def ear_layout(s):
    if s["ears"] == "fennec":
        return (0.2, 0.4, 0.06), (0.11, 0.12, 0.02), 0.42
    return (0.19, 0.22, 0.05), (0.19, 0.07, 0.0), 0.75  # sand cat: very large, wide and low


def build_ear(s, sx):
    p = Part()
    size, _, tilt = ear_layout(s)
    w, h, d = size
    rot = Matrix.Rotation(-tilt * sx, 4, "Z")
    p.add_mesh(rbox(size, 0.025, 2, taper=(0.18, 0.6)), lambda c, n: s["fur"], rot @ Matrix.Translation((0, h * 0.5, 0)))
    p.add_mesh(rbox((w * 0.62, h * 0.78, d * 0.4), 0.015, 2, taper=(0.15, 0.6)), lambda c, n: s["inner_ear"],
               rot @ Matrix.Translation((0, h * 0.42, -d * 0.4)))
    p.add_mesh(rbox((w * 0.5, h * 0.35, d * 0.25), 0.01, 2, taper=(0.3, 0.6)), lambda c, n: s["accent"],
               rot @ Matrix.Translation((0, h * 0.2, -d * 0.52)))  # pale inner fur
    if s["ears"] == "cat":  # black tips
        p.add_mesh(rbox((w * 0.34, h * 0.3, d * 1.06), 0.008, 2, taper=(0.2, 0.7)), lambda c, n: (0.08, 0.07, 0.07),
                   rot @ Matrix.Translation((0, h * 0.86, 0)))
    return p


def build_tail(s):
    p = Part()
    kind = s["tail"]
    n = 9
    pts = []
    for i in range(n + 1):
        t = i / n
        if kind == "lizard":  # short, thick, ringed with spines
            pos, r = Vector((0, -0.42 + 0.05 * math.sin(t * 3.0), 0.05 + t * 0.62)), lerp(0.13, 0.05, t)
        elif kind == "fennec":
            pos, r = Vector((0, -0.15 + t * 0.25, 0.05 + t * 0.55)), lerp(0.06, 0.12, math.sin(t * math.pi * 0.85))
        else:
            pos, r = Vector((0, -0.1 + t * 0.5, 0.05 + math.sin(t * 2.2) * 0.42)), lerp(0.055, 0.045, t)
        pts.append((pos, r, t))
    for i in range(n):
        a, b = pts[i], pts[i + 1]
        d = b[0] - a[0]
        mid = (a[0] + b[0]) * 0.5
        r = (a[1] + b[1]) * 0.5
        t = a[2]
        if kind == "fennec":
            col = (0.1, 0.07, 0.06) if t > 0.75 else s["fur"]
        elif kind == "cat":
            col = (0.08, 0.07, 0.07) if t > 0.85 or (t > 0.45 and i % 2 == 0) else s["fur"]
        else:
            col = s["fur_dark"] if i % 2 == 1 else s["fur"]
        rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        p.add_mesh(rbox((r * 2, d.length * 1.25, r * 2), r * 0.45, 2), lambda c, nn, col=col: col, Matrix.Translation(mid) @ rot)
        if kind == "lizard":  # whorl of spiny scales
            for k in range(6):
                ang = k / 6 * math.tau
                outward = Vector((math.cos(ang), 0.0, math.sin(ang)))
                loc = Vector((0, 0, 0)) + outward * r * 0.95
                spike_rot = Vector((0, 1, 0)).rotation_difference(outward).to_matrix().to_4x4()
                p.add_mesh(rbox((0.035, 0.06, 0.035), 0.01, 1, taper=(0.15, 0.15)), lambda c, nn: (0.86, 0.72, 0.3),
                           Matrix.Translation(mid) @ rot @ Matrix.Translation(loc) @ spike_rot)
    return p


_old_build_hand = build_hand


def build_hand(s, pose):
    p = _old_build_hand(s, pose)
    if s["head"] == "round":  # sand cat: dark bars around the wrist
        for z in (0.05, 0.085):
            add_box(p, (0.16 * HAND_SCALE, 0.088 * HAND_SCALE, 0.016 * HAND_SCALE), (0, 0, z * HAND_SCALE), s["fur_dark"], r=0.03)
    return p


def build_robe(s):
    """A true daraa: one wide rectangle folded at the shoulders, sides sewn
    only halfway so the upper sides open into huge sleeves. Front view is a
    wide, squarish block falling from shoulder line to shins; deep vertical
    drape folds hang from the arms. Long V-neck ending in a five-sided
    embroidered pocket, an inner tunic showing in the V, gold/white hem."""
    robe, robe_dark, emb, fur = s["robe"], s["robe_dark"], s["embroidery"], s["fur"]
    oy = BODY_C[1]
    prof = [  # (world y, half width, half depth, z offset)
        (0.22, 0.52, 0.24, 0.02), (0.3, 0.53, 0.24, 0.02), (0.5, 0.54, 0.235, 0.01),
        (0.7, 0.55, 0.23, 0.0), (0.9, 0.56, 0.22, 0.0), (1.08, 0.57, 0.21, 0.0),
        (1.2, 0.56, 0.2, 0.0), (1.28, 0.5, 0.18, 0.0), (1.34, 0.36, 0.16, 0.0),
        (1.39, 0.2, 0.13, 0.0), (1.43, 0.1, 0.09, 0.0),
    ]
    dense = []
    for i in range(len(prof) - 1):
        a, b = prof[i], prof[i + 1]
        for t in (0.0, 0.34, 0.67):
            dense.append(tuple(lerp(a[k], b[k], t) for k in range(4)))
    dense.append(prof[-1])
    sections = [(y - oy, hw, hd, zo) for (y, hw, hd, zo) in dense]

    def folds(y, a):
        wy = y + oy
        drape = max(0.0, min(1.0, (1.3 - wy) / 0.5))
        side = abs(math.cos(a)) ** 4          # cloth hanging off the arms
        front = 1.0 - side
        return drape * (0.035 * side * math.sin(a * 10 + 0.7) + 0.012 * front * math.sin(a * 16 + 0.3))

    def col(co, a):
        wy = co.y + oy
        if wy > 1.41:
            return fur
        if wy < 0.27:
            return emb
        if wy < 0.3:
            return robe_dark
        side = abs(math.cos(a)) ** 4
        shade = 0.5 + 0.5 * math.sin(a * 10 + 0.7)
        return mix(robe, robe_dark, 0.45 * shade * side)
    p = loft(sections, 72, col, folds, squareness=5.0)

    # Long V-neck (inner tunic showing, embroidered border) ending in the
    # five-sided pocket that cuts off the tip of the V.
    top, tip = 1.395 - oy, 1.02 - oy
    polys = [
        ([(-0.15, top), (0.15, top), (0.0, tip)], emb),
        ([(-0.115, top), (0.115, top), (0.0, tip + 0.05)], s["inner"]),
    ]
    pk_top, pk_bot = 1.08 - oy, 0.86 - oy
    def pent(hw, t, b):
        return [(-hw, t), (hw, t), (hw, b + hw * 0.9), (0.0, b), (-hw, b + hw * 0.9)]
    polys += [
        (pent(0.1, pk_top, pk_bot), emb),
        (pent(0.08, pk_top - 0.018, pk_bot + 0.026), robe),
        ([(-0.006, pk_top - 0.018), (0.006, pk_top - 0.018), (0.006, pk_bot + 0.03), (-0.006, pk_bot + 0.03)], emb),
    ]
    for k in range(3):  # stacked lozenges either side of the spine
        cy = pk_top - 0.05 - k * 0.045
        for cx in (-0.04, 0.04):
            polys.append(([(cx, cy + 0.02), (cx + 0.022, cy), (cx, cy - 0.02), (cx - 0.022, cy)], emb))
    for k in range(9):  # stitched dots along the hem band
        x = -0.36 + k * 0.09
        polys.append(([(x - 0.018, 0.31 - oy), (x, 0.33 - oy), (x + 0.018, 0.31 - oy), (x, 0.29 - oy)], emb))
    sub = project_poly(p, polys[:2], offset=0.004)
    merge(p, sub)
    merge(p, project_poly(p, polys[2:3], offset=0.0055))
    merge(p, project_poly(p, polys[3:4], offset=0.007))
    merge(p, project_poly(p, polys[4:], offset=0.01, cuts=1))

    # Huge sleeves: the folded rectangle's open sides hang from the shoulder
    # line almost to the knees, inside shown in a darker shade, gold hem.
    for sx in (-1, 1):
        def sleeve_col(c, n, sx=sx):
            return robe_dark if n.x * sx < -0.3 else robe
        p.add_mesh(rbox((0.05, 0.64, 0.44), 0.022, 2, taper=(1.0, 0.7)), sleeve_col,
                   T((0.43 * sx, 0.95 - oy, 0.0), rot=(0, 0, 0.16 * sx)))
        add_box(p, (0.058, 0.04, 0.44), (0.48 * sx, 0.645 - oy, 0.0), emb, r=0.012, rot=(0, 0, 0.16 * sx))
    # Gold trim down the open side edges of the sleeves.
    return p


def build_hawli_neck(s):
    """Hawli wrapped around the neck: three thick turns and a hanging end."""
    p = Part()
    c1, c2 = s["hawli"], s["hawli_dark"]
    for i, (y, R, tilt) in enumerate([(0.0, 0.2, 0.12), (0.05, 0.19, -0.1), (0.095, 0.17, 0.16)]):
        p.add_mesh(torus(R, 0.05, 24, 8), lambda c, n, col=(c1 if i % 2 == 0 else c2): col,
                   Matrix.Translation((0, y, 0.0)) @ Matrix.Rotation(tilt, 4, "X"))
    # Loose end falling over the chest, slightly to one side.
    for k in range(4):
        add_box(p, (0.12, 0.1, 0.035), (0.2 + k * 0.012, -0.06 - k * 0.09, -0.15 - k * 0.006), c1 if k % 2 == 0 else c2,
                r=0.02, rot=(0.15, 0, 0.12))
    return p


def build_hawli_head(s):
    """Tagelmust worn as a turban: stacked turns around the crown, ears out."""
    p = Part()
    c1, c2 = s["hawli"], s["hawli_dark"]
    lizard = s["head"] == "lizard"
    turns = [(0.09, 0.2, 0.1), (0.13, 0.19, -0.08), (0.17, 0.16, 0.12)] if lizard else [(0.1, 0.185, 0.08), (0.14, 0.17, -0.1)]
    for i, (y, R, tilt) in enumerate(turns):
        p.add_mesh(torus(R, 0.04, 26, 8), lambda c, n, col=(c1 if i % 2 == 0 else c2): col,
                   Matrix.Translation((0, y, 0.02)) @ Matrix.Rotation(tilt, 4, "X") @ Matrix.Diagonal((1.1, 1.0, 1.0, 1.0)))
    if lizard:
        add_box(p, (0.24, 0.1, 0.26), (0, 0.2, 0.03), c2, r=0.05)  # crown fold
        for k in range(3):  # tail of cloth down the back
            add_box(p, (0.12, 0.12, 0.03), (0.05, 0.02 - k * 0.11, 0.2 + k * 0.01), c1 if k % 2 == 0 else c2, r=0.015, rot=(-0.2, 0, 0.1))
    return p


def bake_depth(rows):
    """Bake per-vertex ambient occlusion (into vertex alpha) and darken
    concave / brighten convex edges plus a soft top-down gradient (into RGB).
    Occluders: every visible part of the character in world space."""
    from mathutils.bvhtree import BVHTree
    occluders = [(part, Vector(pivot)) for name, part, pivot in rows
                 if not name.startswith("Daraa") and (not name.startswith("Hand") or name.endswith("_open"))]
    verts, faces = [], []
    for part, piv in occluders:
        off = len(verts)
        verts += [v + piv for v in part.verts]
        faces += [[i + off for i in f] for f in part.faces]
    bvh = BVHTree.FromPolygons(verts, faces)
    # Fixed hemisphere sample set (cosine-weighted), 14 rays.
    dirs = []
    for i in range(24):
        u, v = (i + 0.5) / 24, (i * 0.618034) % 1.0
        r = math.sqrt(u)
        th = v * math.tau
        dirs.append((r * math.cos(th), math.sqrt(max(0.0, 1 - u)), r * math.sin(th)))
    for name, part, pivot in rows:
        piv = Vector(pivot)
        n_v = len(part.verts)
        # neighbours for curvature
        nb = [set() for _ in range(n_v)]
        for f in part.faces:
            for k in range(len(f)):
                nb[f[k]].add(f[k - 1])
                nb[f[k]].add(f[(k + 1) % len(f)])
        ao = []
        cols = []
        for i in range(n_v):
            vw = part.verts[i] + piv
            n = part.normals[i].normalized() if part.normals[i].length > 0 else Vector((0, 1, 0))
            t1 = n.orthogonal().normalized()
            t2 = n.cross(t1)
            hits = 0
            for dx, dy, dz in dirs:
                d = (t1 * dx + n * dy + t2 * dz).normalized()
                loc, _, _, dist = bvh.ray_cast(vw + n * 0.004, d, 0.22)
                if loc is not None:
                    hits += 1.0 - (dist / 0.22) * 0.6
            occ = min(1.0, hits / len(dirs) * 1.6)
            ao.append(1.0 - occ * 0.85)
            curv = 0.0
            if nb[i]:
                for j in nb[i]:
                    e = part.verts[j] - part.verts[i]
                    if e.length > 1e-6:
                        curv += -n.dot(e.normalized())
                curv /= len(nb[i])
            edge = max(-1.0, min(1.0, curv * 3.0))
            height = max(0.0, min(1.0, vw.y / 1.8))
            k = (0.86 + 0.14 * height) * (1.0 + 0.16 * edge)
            c = part.colors[i]
            cols.append((min(1.0, c[0] * k), min(1.0, c[1] * k), min(1.0, c[2] * k)))
        part.ao = ao
        part.colors = cols


def build_species(name):
    clear_scene()
    s = SPECIES[name]
    eye_y = EYE_Y[s["head"]]
    rows = [
        ("Body", build_robe(s), BODY_C),
        ("Head", build_head(s), HEAD_C),
        ("Eyes", build_eyes(s), (0, HEAD_C[1] + eye_y, 0)),
        ("Tail", build_tail(s), TAIL_C),
        ("FootR", build_shoe(s), FOOT_C),
        ("FootL", mirrored(build_shoe(s)), (-FOOT_C[0], FOOT_C[1], FOOT_C[2])),
        ("DaraaR", build_daraa_wing(s, 1), (0, 1.3, 0.02)),
        ("DaraaL", build_daraa_wing(s, -1), (0, 1.3, 0.02)),
    ]
    if s["hawli_on"] in ("neck", "both"):
        rows.append(("Hawli", build_hawli_neck(s), (0, 1.42, 0.0)))
    if s["hawli_on"] in ("head", "both"):
        rows.append(("Turban", build_hawli_head(s), HEAD_C))
    for pose in HAND_POSES:
        hand = build_hand(s, pose)
        rows.append(("HandR_" + pose, hand, HAND_C))
        rows.append(("HandL_" + pose, mirrored(hand), (-HAND_C[0], HAND_C[1], HAND_C[2])))
    if s["ears"] != "none":
        _, base, _ = ear_layout(s)
        rows.append(("EarR", build_ear(s, 1), (base[0], HEAD_C[1] + base[1], base[2])))
        rows.append(("EarL", build_ear(s, -1), (-base[0], HEAD_C[1] + base[1], base[2])))
    rows = chibi(rows, s)
    bake_depth(rows)
    tris = 0
    for pname, part, pivot in rows:
        _, f = emit(pname, part, pivot)
        if not pname.startswith("Hand") or pname.endswith("_open"):
            tris += f
    export(os.path.join(OUT, name + ".glb"))
    return tris


# ===========================================================================
# v0.8 sculpt pass: cloth with real pipe folds (round crests, sharp creases),
# fanned from the shoulders, a wavy thick hem, hanging sleeve panels, and the
# hawli / turban as swept cloth bands with a knot and hanging tails.
# ===========================================================================


def _ss(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0))) if e1 != e0 else 0.0
    return t * t * (3 - 2 * t)


def _pipe(u):
    """Cloth fold profile: rounded crest (+1), sharp crease (-1)."""
    return 2.0 * abs(math.cos(u * 0.5)) - 1.0


def _angdiff(a, b):
    d = (a - b) % math.tau
    return min(d, math.tau - d)


def sweep(path, width_fn, thick_fn, color_fn, sides=12, twist_fn=None, ripple_fn=None):
    """Sweep a flattened cloth section along `path` (list of Vector).
    width_fn/thick_fn/twist_fn/ripple_fn take t in [0, 1]."""
    p = Part()
    n = len(path)
    T = [(path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized() for i in range(n)]
    up = Vector((0, 1, 0)) if abs(T[0].y) < 0.9 else Vector((1, 0, 0))
    N = (up - T[0] * up.dot(T[0])).normalized()
    rings = []
    for i in range(n):
        t = i / (n - 1)
        N = (N - T[i] * N.dot(T[i])).normalized()
        B = T[i].cross(N)
        tw = twist_fn(t) if twist_fn else 0.0
        Nn = N * math.cos(tw) + B * math.sin(tw)
        Bn = T[i].cross(Nn)
        w, th = width_fn(t), thick_fn(t)
        rip = ripple_fn(t) if ripple_fn else 0.0
        ring = []
        for k in range(sides):
            a = k / sides * math.tau
            ca, sa = math.cos(a), math.sin(a)
            # flattened band, with cloth ripples across its width
            off = Nn * (ca * w) + Bn * (sa * th + rip * math.sin(ca * 7.0 + t * 3.0) * w * 0.12)
            co = path[i] + off
            ring.append(len(p.verts))
            p.verts.append(co)
            p.normals.append((Nn * ca * th + Bn * sa * w).normalized())
            p.colors.append(color_fn(t, a))
        rings.append(ring)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(sides):
            j = (k + 1) % sides
            f = [a[k], a[j], b[j], b[k]]
            c = sum((p.verts[x] for x in f), Vector()) / 4
            ctr = (path[i] + path[i + 1]) * 0.5
            nrm = (p.verts[f[1]] - p.verts[f[0]]).cross(p.verts[f[3]] - p.verts[f[0]])
            if nrm.dot(c - ctr) < 0:
                f.reverse()
            p.faces.append(f)
    for ring, idx in ((rings[0], 0), (rings[-1], n - 1)):  # caps
        c = len(p.verts)
        p.verts.append(path[idx].copy())
        p.normals.append(T[idx] * (-1 if idx == 0 else 1))
        p.colors.append(p.colors[ring[0]])
        for k in range(sides):
            j = (k + 1) % sides
            f = [ring[k], ring[j], c]
            nrm = (p.verts[f[1]] - p.verts[f[0]]).cross(p.verts[f[2]] - p.verts[f[0]])
            if nrm.dot(T[idx] * (-1 if idx == 0 else 1)) < 0:
                f.reverse()
            p.faces.append(f)
    return p


def _helix(center, rx, rz, y0, y1, turns, steps, tilt=0.0, start=-math.pi / 2, wobble=0.0):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a = start + t * turns * math.tau
        y = lerp(y0, y1, t) + math.sin(a) * tilt + math.sin(a * 2 + t * 5) * wobble
        pts.append(Vector((center[0] + math.cos(a) * rx, y, center[2] + math.sin(a) * rz)))
    return pts


def _band_col(c1, c2, stripes=0.0, stripe_col=None):
    def f(t, a):
        if stripe_col and t > 1.0 - stripes and int(t * 90) % 3 == 0:
            return stripe_col
        return mix(c1, c2, 0.5 + 0.5 * math.sin(a * 2.0))
    return f


def build_robe(s):
    robe, robe_dark, emb, fur = s["robe"], s["robe_dark"], s["embroidery"], s["fur"]
    oy = BODY_C[1]
    prof = [
        (0.24, 0.45, 0.255, 0.02), (0.32, 0.445, 0.25, 0.02), (0.5, 0.43, 0.24, 0.01),
        (0.7, 0.41, 0.23, 0.0), (0.9, 0.39, 0.22, 0.0), (1.08, 0.37, 0.21, 0.0),
        (1.2, 0.35, 0.2, 0.0), (1.28, 0.31, 0.185, 0.0), (1.34, 0.25, 0.16, 0.0),
        (1.39, 0.18, 0.13, 0.0), (1.43, 0.115, 0.095, 0.0),
    ]
    rings_n = 40
    sections = []
    for j in range(rings_n + 1):
        y = lerp(prof[0][0], prof[-1][0], (j / rings_n) ** 0.92)
        for k in range(len(prof) - 1):
            if prof[k][0] <= y <= prof[k + 1][0]:
                t = (y - prof[k][0]) / (prof[k + 1][0] - prof[k][0])
                t = t * t * (3 - 2 * t) * 0.5 + t * 0.5
                sections.append((y - oy,) + tuple(lerp(prof[k][m], prof[k + 1][m], t) for m in (1, 2, 3)))
                break

    def col(co, a):
        wy = co.y + oy
        if wy > 1.415:
            return emb
        if 0.27 < wy < 0.31:
            return emb
        return robe
    segs = 120
    p = loft(sections, segs, col, None, squareness=4.0)

    front_a = 1.5 * math.pi
    bottom_y = sections[0][0]

    def disp(co):
        wy = co.y + oy
        a = math.atan2(co.z, co.x) % math.tau
        g = _ss(1.34, 0.92, wy)
        hem = _ss(0.6, 0.24, wy)
        side = abs(math.cos(a)) ** 2
        front = _angdiff(a, front_a)
        flat = 1.0 - 0.8 * _ss(0.42, 0.05, front) * _ss(0.78, 0.95, wy)
        u1 = a * 9 + 0.9 * math.sin(a * 2 + 1.0) * (1.34 - wy) + 0.35 * math.sin(wy * 4.0 + a * 3)
        u2 = a * 23 + 1.6 * math.sin(wy * 6.0 + a * 5)
        amp = (0.024 * g + 0.018 * hem) * (1.0 + 0.6 * side) * flat
        return amp * _pipe(u1) + amp * 0.3 * _pipe(u2), _pipe(u1)

    top_ring_start = len(p.verts) - 2 - segs  # before caps: last ring
    for i, co in enumerate(p.verts):
        if co.x == 0 and co.z == sum(v.z for v in p.verts[:1]) * 0:  # cap centres are fine untouched
            pass
        r = Vector((co.x, 0, co.z))
        if r.length < 1e-5:
            continue
        d, prof_v = disp(co)
        co += r.normalized() * d
        if abs(co.y - bottom_y) < 1e-6:  # wavy hem: crests hang lower
            co.y -= 0.022 * (prof_v * 0.5 + 0.5)
        p.colors[i] = mix(p.colors[i], robe_dark, max(0.0, -prof_v) * 0.35 * _ss(1.3, 0.9, co.y + oy))

    # Thick hem: the bottom cap is raised inside so the robe reads as cloth.
    for i, co in enumerate(p.verts):
        if abs(co.y - bottom_y) < 0.03 and Vector((co.x, 0, co.z)).length < 1e-5:
            co.y += 0.09
            p.colors[i] = mix(robe_dark, (0.05, 0.04, 0.05), 0.5)

    # Rolled neck edge.
    collar = _helix((0, 0, 0), 0.118, 0.1, 1.418 - oy, 1.418 - oy, 1.0, 40)
    merge(p, sweep(collar, lambda t: 0.016, lambda t: 0.016, lambda t, a: emb, sides=8))

    # V-neck + five-sided pocket + hem stitches, crisp and hugging the folds.
    top, tip = 1.40 - oy, 1.02 - oy
    merge(p, project_poly(p, [([(-0.15, top), (0.15, top), (0.0, tip)], emb)], offset=0.004))
    merge(p, project_poly(p, [([(-0.115, top), (0.115, top), (0.0, tip + 0.05)], s["inner"])], offset=0.007))
    pk_top, pk_bot = 1.08 - oy, 0.86 - oy

    def pent(hw, t, b):
        return [(-hw, t), (hw, t), (hw, b + hw * 0.9), (0.0, b), (-hw, b + hw * 0.9)]
    merge(p, project_poly(p, [(pent(0.1, pk_top, pk_bot), emb)], offset=0.009))
    merge(p, project_poly(p, [(pent(0.08, pk_top - 0.018, pk_bot + 0.026), robe)], offset=0.012))
    orn = [([(-0.006, pk_top - 0.018), (0.006, pk_top - 0.018), (0.006, pk_bot + 0.03), (-0.006, pk_bot + 0.03)], emb)]
    for k in range(3):
        cy = pk_top - 0.05 - k * 0.045
        for cx in (-0.04, 0.04):
            orn.append(([(cx, cy + 0.02), (cx + 0.022, cy), (cx, cy - 0.02), (cx - 0.022, cy)], emb))
    merge(p, project_poly(p, orn, offset=0.015, cuts=1))

    # Hanging sleeves: thin cloth panels with folds across their width.
    for sx in (-1, 1):
        sl_sections = []
        for j in range(17):
            t = j / 16
            y = lerp(0.62, 1.3, t)
            sl_sections.append((y, 0.026, lerp(0.27, 0.15, t ** 1.3), 0.0))
        sl = loft(sl_sections, 32, lambda co, a: robe, None, squareness=2.2)
        for i, co in enumerate(sl.verts):
            t = (co.y - 0.62) / 0.68
            amp = 0.035 * (1 - t) ** 1.2 + 0.004
            u = co.z * 34 + 0.8 * math.sin(co.y * 5)
            pv = _pipe(u)
            co.x += amp * pv
            if co.y < 0.625:
                co.y -= 0.025 * (pv * 0.5 + 0.5)
            inner = co.x < 0.0
            c = robe_dark if inner else robe
            if co.y < 0.69:
                c = emb
            sl.colors[i] = mix(c, robe_dark, max(0.0, -pv) * 0.3)
        m = T((0.455 * sx, -oy, 0.0), rot=(0, 0, 0.16 * sx))
        for i, co in enumerate(sl.verts):
            v = co.copy()
            if sx < 0:
                v.x = -v.x
            sl.verts[i] = m @ v
            nn = sl.normals[i].copy()
            if sx < 0:
                nn.x = -nn.x
            sl.normals[i] = (m.to_3x3() @ nn).normalized()
        if sx < 0:
            sl.faces = [list(reversed(f)) for f in sl.faces]
        merge(p, sl)
    return p


def build_hawli_neck(s):
    """Hawli wound round the neck, knotted at the front, tails hanging."""
    c1, c2 = s["hawli"], s["hawli_dark"]
    p = Part()
    wrap = _helix((0, 0, 0), 0.2, 0.17, -0.01, 0.1, 2.4, 110, tilt=0.025, wobble=0.006)
    merge(p, sweep(wrap, lambda t: 0.048, lambda t: 0.02, _band_col(c1, c2), sides=12,
                   twist_fn=lambda t: math.sin(t * 9) * 0.5, ripple_fn=lambda t: 0.6))
    # knot at the front-right
    kc = Vector((0.08, 0.02, -0.18))
    knot = [kc + Vector((math.cos(a) * 0.045, math.sin(a) * 0.04, -0.015 * math.sin(a * 2))) for a in
            [i / 24 * math.tau * 1.3 for i in range(25)]]
    merge(p, sweep(knot, lambda t: 0.034, lambda t: 0.018, _band_col(c2, c1), sides=10))
    # two tails falling over the chest, widening, with fringed ends
    for k, (dx, ln, ph) in enumerate(((0.0, 0.2, 0.0), (0.05, 0.15, 1.4))):
        tail = []
        for i in range(24):
            t = i / 23
            tail.append(kc + Vector((dx + 0.03 * math.sin(t * 3 + ph) + 0.04 * t, -0.02 - t * ln,
                                     -0.03 - 0.05 * math.sin(t * 2.2) - 0.02 * t)))
        merge(p, sweep(tail, lambda t: lerp(0.03, 0.058, t), lambda t: 0.012,
                       _band_col(c1 if k == 0 else c2, c2, 0.12, s["embroidery"]), sides=10,
                       twist_fn=lambda t, ph=ph: 0.35 * math.sin(t * 4 + ph) + 1.3, ripple_fn=lambda t: 1.2 * t))
    return p


def build_hawli_head(s):
    """Tagelmust worn as a turban: crossed wraps, a crown, a tail behind."""
    c1, c2 = s["hawli"], s["hawli_dark"]
    lizard = s["head"] == "lizard"
    fox = s["head"] == "fox"
    rx, rz = (0.215, 0.225) if lizard else ((0.19, 0.18) if fox else (0.24, 0.2))
    y0, y1 = (0.13, 0.24) if lizard else (0.125, 0.175)
    p = Part()
    wrap = _helix((0, 0, 0.02), rx, rz, y0, y1, 3.2 if lizard else 2.2, 150, tilt=0.03, wobble=0.008)
    merge(p, sweep(wrap, lambda t: lerp(0.05, 0.042, t), lambda t: 0.022, _band_col(c1, c2), sides=12,
                   twist_fn=lambda t: 0.6 * math.sin(t * 13), ripple_fn=lambda t: 0.7))
    if lizard:
        cap = loft([(0.17, rx * 0.88, rz * 0.88, 0.02), (0.22, rx * 0.8, rz * 0.8, 0.02), (0.26, rx * 0.55, rz * 0.55, 0.02),
                    (0.28, rx * 0.2, rz * 0.2, 0.02)], 24, lambda co, a: c2, None, squareness=2.2)
        merge(p, cap)
    # tail falling behind the head onto the shoulders
    start = Vector((0.06, y0, 0.02 + rz))
    tail = [start + Vector((0.03 * math.sin(t * 3), -t * (0.3 if lizard else 0.2), 0.05 * math.sin(t * 2.5) + 0.02 * t))
            for t in [i / 17 for i in range(18)]]
    merge(p, sweep(tail, lambda t: lerp(0.045, 0.065, t), lambda t: 0.012,
                   _band_col(c1, c2, 0.15, s["embroidery"]), sides=10,
                   twist_fn=lambda t: 1.4 + 0.3 * math.sin(t * 5), ripple_fn=lambda t: t))
    return p


# ===========================================================================
# Chibi proportions (reference sheet): head ~1/3 of the height, short stocky
# body, chunky boots under baggy sarouel cuffs, big mitten hands at the hips.
# Limbs stay disconnected (floating). Built in the old frame, then remapped.
# ===========================================================================
HEAD_SCALE = 1.55
ROBE_Y0, ROBE_SY = 0.44, 0.52           # robe world y = ROBE_Y0 + (old - 0.24) * ROBE_SY
NEW_HEAD_C = (0.0, 1.28, 0.0)
NEW_BODY_C = (0.0, ROBE_Y0 + (0.8 - 0.24) * ROBE_SY, 0.0)
NEW_TAIL_C = (0.0, 0.5, 0.24)
NEW_HAND_C = (0.5, 0.66, -0.1)
NEW_FOOT_C = (0.15, 0.0, 0.0)
NEW_WING_C = (0.0, ROBE_Y0 + (1.3 - 0.24) * ROBE_SY, 0.02)
NEW_NECK_Y = ROBE_Y0 + (1.42 - 0.24) * ROBE_SY


def _remap(part, pivot, fn):
    """Apply fn(world Vector) -> world Vector to every vertex; return new pivot."""
    piv = Vector(pivot)
    new_piv = fn(piv.copy())
    for i, v in enumerate(part.verts):
        part.verts[i] = fn(v + piv) - new_piv
    return tuple(new_piv)


def build_boot(s):
    """Chunky leather boot with a baggy sarouel cuff above (floating leg)."""
    p = Part()
    leather, sole, lace = (0.42, 0.25, 0.14), (0.16, 0.11, 0.08), (0.86, 0.66, 0.26)
    sar = s.get("sarouel", mix(s["robe_dark"], (0.25, 0.25, 0.27), 0.5))
    add_box(p, (0.2, 0.06, 0.32), (0, 0.03, -0.03), sole, r=0.025, seg=3)
    add_box(p, (0.19, 0.12, 0.3), (0, 0.11, -0.03), leather, r=0.05, seg=3)
    add_box(p, (0.18, 0.1, 0.13), (0, 0.1, -0.14), leather, r=0.05, seg=3)        # round toe cap
    add_box(p, (0.17, 0.12, 0.17), (0, 0.22, 0.02), leather, r=0.05, seg=3)        # shaft
    add_box(p, (0.185, 0.03, 0.185), (0, 0.285, 0.02), lace, r=0.012)              # tooled brass band
    for k in range(3):  # laces / tooled stitches down the front
        add_box(p, (0.07, 0.012, 0.012), (0, 0.15 + k * 0.04, -0.07 - k * 0.006), lace, r=0.005)
    # baggy sarouel cuff: gathered cloth puff with pipe folds
    secs = [(0.28 + j * 0.02, lerp(0.1, 0.125, math.sin(j / 7 * math.pi)), lerp(0.1, 0.125, math.sin(j / 7 * math.pi)), 0.02)
            for j in range(8)]
    cuff = loft(secs, 28, lambda co, a: sar, None, squareness=2.0)
    for i, co in enumerate(cuff.verts):
        r = Vector((co.x, 0, co.z - 0.02))
        if r.length < 1e-5:
            continue
        a = math.atan2(r.z, r.x)
        pv = _pipe(a * 8 + co.y * 10)
        cuff.verts[i] = co + r.normalized() * 0.012 * pv
        cuff.colors[i] = mix(sar, (0.08, 0.08, 0.1), max(0.0, -pv) * 0.35)
    merge(p, cuff)
    return p


def chibi(rows, s):
    out = []
    hs = HEAD_SCALE
    hold, hnew = Vector(HEAD_C), Vector(NEW_HEAD_C)

    def head_fn(w):
        return hnew + (w - hold) * hs

    def robe_fn(w):
        return Vector((w.x * 0.96, ROBE_Y0 + (w.y - 0.24) * ROBE_SY, w.z))
    for name, part, pivot in rows:
        if name in ("Head", "Eyes", "Turban") or name.startswith("Ear"):
            pivot = _remap(part, pivot, head_fn)
            if name.startswith("Ear") and s["ears"] == "fennec":
                part.verts = [v * 0.8 for v in part.verts]
        elif name == "Body":
            pivot = _remap(part, pivot, robe_fn)
            # keep the pivot where the game expects it
            d = Vector(NEW_BODY_C) - Vector(pivot)
            part.verts = [v - d for v in part.verts]
            pivot = NEW_BODY_C
        elif name == "Hawli":
            sc = 1.2
            part.verts = [Vector((v.x * sc, v.y, v.z * sc)) for v in part.verts]
            pivot = (0.0, NEW_NECK_Y, 0.0)
        elif name == "Tail":
            part.verts = [v * 0.8 for v in part.verts]
            pivot = NEW_TAIL_C
        elif name.startswith("Daraa"):
            part.verts = [v * 0.75 for v in part.verts]
            pivot = NEW_WING_C
        elif name.startswith("HandR"):
            pivot = NEW_HAND_C
        elif name.startswith("HandL"):
            pivot = (-NEW_HAND_C[0], NEW_HAND_C[1], NEW_HAND_C[2])
        elif name == "FootR":
            part = build_boot(s)
            pivot = NEW_FOOT_C
        elif name == "FootL":
            part = mirrored(build_boot(s))
            pivot = (-NEW_FOOT_C[0], NEW_FOOT_C[1], NEW_FOOT_C[2])
        out.append((name, part, pivot))
    return out


# ===========================================================================
# Shell fur meshes (sand cat, fennec): N copies of the furry faces of a part,
# UV2 = (shell height, length multiplier). Rendered by fur_shell.gdshader.
# ===========================================================================
FUR_SHELLS = 8
FUR_SPECIES = {"cat": {"tail": 1.1}, "fennec": {"tail": 1.9}}


def _near(c, ref, tol=0.06):
    return abs(c[0] - ref[0]) + abs(c[1] - ref[1]) + abs(c[2] - ref[2]) < tol


def fur_mask(name, part, s):
    """Per-vertex fur length multiplier (0 = bald), from pre-bake colours."""
    bald = [s["nose"], s["eye"], s["iris"], s["pad"], s["inner_ear"], (1, 1, 1), s.get("hawli", (9, 9, 9))]
    out = []
    for v, c in zip(part.verts, part.colors):
        if any(_near(c, b) for b in bald):
            out.append(0.0)
            continue
        if name == "Head":
            lv = v / HEAD_SCALE
            m = 1.0
            if lv.z < -0.13:
                m = 0.22          # short fur on the face keeps the expression clean
            elif abs(lv.x) > 0.2 and lv.y < 0.02:
                m = 1.35          # cheek ruff
            if lv.y > 0.14:
                m *= 0.8
            out.append(m)
        elif name.startswith("Ear"):
            out.append(0.55)
        elif name == "Tail":
            out.append(FUR_SPECIES[s["_key"]]["tail"])
        elif name.startswith("Hand"):
            out.append(0.3)
        else:
            out.append(0.0)
    return out


def emit_fur(name, part, pivot, mask):
    keep = [f for f in part.faces if all(mask[i] > 0.0 for i in f)]
    if not keep:
        return 0
    used = sorted({i for f in keep for i in f})
    remap = {old: k for k, old in enumerate(used)}
    n = len(used)
    verts, faces, cols, uv2 = [], [], [], []
    for sh in range(1, FUR_SHELLS + 1):
        h = sh / FUR_SHELLS
        for old in used:
            verts.append(g2b(part.verts[old]))
            c = part.colors[old]
            a = part.ao[old] if part.ao else 1.0
            cols.extend((c[0], c[1], c[2], a))
            uv2.append((h, mask[old]))
        base = (sh - 1) * n
        for f in keep:
            faces.append([base + remap[i] for i in f])
    me = bpy.data.meshes.new(name + "_fur")
    me.from_pydata(verts, [], faces)
    me.update()
    # Normals must match the base mesh so shells extrude straight out: copy the
    # smooth normals of the source vertices via custom split normals.
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    attr.data.foreach_set("color", cols)
    me.color_attributes.active_color_name = "Col"
    uv_a = me.uv_layers.new(name="UVMap")
    uv_b = me.uv_layers.new(name="UV2")
    for li, loop in enumerate(me.loops):
        h, m = uv2[loop.vertex_index]
        uv_a.data[li].uv = (0.0, 0.0)
        uv_b.data[li].uv = (h, m)
    me.shade_smooth()
    obj = bpy.data.objects.new(name + "_fur", me)
    obj.location = g2b(pivot)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.get("fur") or bpy.data.materials.new("fur")
    me.materials.append(mat)
    return len(faces) // FUR_SHELLS


def build_species(name):
    clear_scene()
    s = dict(SPECIES[name])
    s["_key"] = name
    eye_y = EYE_Y[s["head"]]
    rows = [
        ("Body", build_robe(s), BODY_C),
        ("Head", build_head(s), HEAD_C),
        ("Eyes", build_eyes(s), (0, HEAD_C[1] + eye_y, 0)),
        ("Tail", build_tail(s), TAIL_C),
        ("FootR", build_shoe(s), FOOT_C),
        ("FootL", mirrored(build_shoe(s)), (-FOOT_C[0], FOOT_C[1], FOOT_C[2])),
        ("DaraaR", build_daraa_wing(s, 1), (0, 1.3, 0.02)),
        ("DaraaL", build_daraa_wing(s, -1), (0, 1.3, 0.02)),
    ]
    if s["hawli_on"] in ("neck", "both"):
        rows.append(("Hawli", build_hawli_neck(s), (0, 1.42, 0.0)))
    if s["hawli_on"] in ("head", "both"):
        rows.append(("Turban", build_hawli_head(s), HEAD_C))
    for pose in HAND_POSES:
        hand = build_hand(s, pose)
        rows.append(("HandR_" + pose, hand, HAND_C))
        rows.append(("HandL_" + pose, mirrored(hand), (-HAND_C[0], HAND_C[1], HAND_C[2])))
    if s["ears"] != "none":
        _, base, _ = ear_layout(s)
        rows.append(("EarR", build_ear(s, 1), (base[0], HEAD_C[1] + base[1], base[2])))
        rows.append(("EarL", build_ear(s, -1), (-base[0], HEAD_C[1] + base[1], base[2])))
    rows = chibi(rows, s)
    furry = name in FUR_SPECIES
    masks = {}
    if furry:
        for pname, part, pivot in rows:
            if pname in ("Head", "Tail") or pname.startswith("Ear") or pname.startswith("Hand"):
                masks[pname] = fur_mask(pname, part, s)
    bake_depth(rows)
    tris = 0
    fur_tris = 0
    for pname, part, pivot in rows:
        _, f = emit(pname, part, pivot)
        visible = not pname.startswith("Hand") or pname.endswith("_open")
        if visible:
            tris += f
        if pname in masks:
            ft = emit_fur(pname, part, pivot, masks[pname])
            if visible:
                fur_tris += ft
    export(os.path.join(OUT, name + ".glb"))
    print(f"  {name}: fur faces per shell {fur_tris} x {FUR_SHELLS}")
    return tris


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
