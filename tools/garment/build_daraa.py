"""Build the Hafid daraa from its flat pattern and drape it with Blender
cloth (bpy module), then bake the wearing configurations as shape keys.

  python3 tools/garment/build_daraa.py [--res 0.02]

Output:
  game/art/garment/daraa.glb       mesh + UVs + rig weights (COLOR_0) +
                                   shape keys GatherL, GatherR, GatherBoth, Spread
  tools/garment/daraa_source.blend the draped garment, proxies, shape keys
Coordinates are written in Godot model space (y up, front = -z) and
converted to Blender (x, -z, y) internally.
"""
import math
import os
import sys
import time

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import daraa_pattern as P  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_GLB = os.path.join(ROOT, "game", "art", "garment", "daraa.glb")
OUT_BLEND = os.path.join(HERE, "daraa_source.blend")
RES = float(sys.argv[sys.argv.index("--res") + 1]) if "--res" in sys.argv else P.DX
if "--out" in sys.argv:
    OUT_GLB = os.path.join(ROOT, sys.argv[sys.argv.index("--out") + 1])
    OUT_BLEND = os.path.splitext(OUT_BLEND)[0] + "_" + os.path.splitext(os.path.basename(OUT_GLB))[0] + ".blend"
FPS_STEPS = 24


def g2b(v):
    return Vector((v[0], -v[2], v[1]))


def b2g(v):
    return (v.x, v.z, -v.y)


# --- flat pattern -> initial 3D placement ------------------------------------

def initial_pos(x, s):
    """Fold region flat across the top of the shoulders, then straight down
    in front (s<0) and behind (s>0). Piecewise flat => edge rest lengths
    equal the pattern's."""
    zt = P.YOKE_Z
    if abs(s) <= zt:
        return (x, P.SHOULDER_Y, s)
    sign = -1.0 if s < 0 else 1.0
    return (x, P.SHOULDER_Y - (abs(s) - zt), sign * zt)


def build_grid():
    nx = int(round(P.W / RES))
    ns = int(round(2 * P.L / RES))
    verts, uvs, cols, flat = [], [], [], []
    index = {}
    for j in range(ns + 1):
        s = -P.L + 2 * P.L * j / ns
        for i in range(nx + 1):
            x = -P.W / 2 + P.W * i / nx
            index[(i, j)] = len(verts)
            verts.append(initial_pos(x, s))
            uvs.append(P.uv(x, s))
            cols.append(P.weights(x, s))
            flat.append((x, s))
    faces = []
    for j in range(ns):
        for i in range(nx):
            xs = [flat[index[(i + a, j + b)]] for a in (0, 1) for b in (0, 1)]
            cx = sum(p[0] for p in xs) / 4
            cs = sum(p[1] for p in xs) / 4
            if P.in_neck(cx, cs):
                continue
            a, b, c, d = index[(i, j)], index[(i + 1, j)], index[(i + 1, j + 1)], index[(i, j + 1)]
            faces.append((a, d, c, b))   # outward normals
    # lower side seams: pair front s with back -s on both side edges
    seam_rows = int(round(P.SEAM_FRAC * P.L / (2 * P.L / ns)))
    seams = []
    for i in (0, nx):
        for k in range(seam_rows + 1):
            seams.append((index[(i, k)], index[(i, ns - k)]))
    # drop the vertices cut out by the neck opening (no faces) and reindex
    used = sorted({v for f in faces for v in f})
    remap = {o: n for n, o in enumerate(used)}
    verts = [verts[o] for o in used]
    uvs = [uvs[o] for o in used]
    cols = [cols[o] for o in used]
    flat = [flat[o] for o in used]
    faces = [tuple(remap[v] for v in f) for f in faces]
    seams = [(remap[a], remap[b]) for a, b in seams]
    index = {k: remap[v] for k, v in index.items() if v in remap}
    return verts, faces, uvs, cols, flat, seams, (nx, ns, index)


# --- Blender helpers ----------------------------------------------------------

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS_STEPS
    sc.gravity = (0, 0, -9.81)


def ellipsoid(name, centre, radii, rot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1.0, location=g2b(centre))
    o = bpy.context.active_object
    o.name = name
    o.scale = (radii[0], radii[2], radii[1])
    if rot is not None:
        o.rotation_euler = rot
    m = o.modifiers.new("Collision", "COLLISION")
    o.collision.thickness_outer = 0.012
    o.collision.cloth_friction = 3.0
    o.hide_render = True
    return o


def capsule_between(name, a, b, r):
    a, b = g2b(a), g2b(b)
    mid = (a + b) / 2
    d = b - a
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=1.0, location=mid)
    o = bpy.context.active_object
    o.name = name
    o.scale = (r, r, d.length / 2 + r)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.modifiers.new("Collision", "COLLISION")
    o.collision.thickness_outer = 0.01
    o.collision.cloth_friction = 3.0
    return o


def body_proxies():
    """Collision proxies in the character's proportions (rig rest pose):
    torso, shoulders, hidden arm supports, invisible legs/skirt support,
    ground. The chibi head sits over the yoke and is not a collider."""
    ellipsoid("proxy_torso", (0, 0.72, 0), (0.2, 0.36, 0.155))
    for sx in (-1, 1):
        ellipsoid("proxy_shoulder", (0.2 * sx, 0.99, 0), (0.1, 0.09, 0.1))
        # hidden arm support: shoulder to just short of the floating hand's
        # rest (idle hands float at ~(0.52, 0.8, -0.42)); the lateral
        # openings hang from these like sleeves from a real wearer's arms
        capsule_between("proxy_arm", (0.22 * sx, 0.99, -0.02), (0.44 * sx, 0.8, -0.3), 0.05)
    capsule_between("proxy_legs", (0, 0.42, 0), (0, 0.12, 0), 0.17)
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0.0))
    g = bpy.context.active_object
    g.name = "proxy_ground"
    g.modifiers.new("Collision", "COLLISION")


def garment_object(verts, faces, uvs, cols, seams, name="Daraa"):
    me = bpy.data.meshes.new(name)
    bverts = [g2b(v) for v in verts]
    edges = [s for s in seams]
    me.from_pydata(bverts, edges, faces)
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            u, v = uvs[vi]
            uvl.data[li].uv = (u, 1.0 - v)        # glTF flips V on export
    ca = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    for i, c in enumerate(cols):
        ca.data[i].color = c
    me.color_attributes.active_color = ca
    for p in me.polygons:
        p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o


def add_cloth(o, pin_group, frames, sew=True):
    m = o.modifiers.new("Cloth", "CLOTH")
    st = m.settings
    st.quality = 10
    st.mass = 0.25                     # bazin: light but stiff
    st.air_damping = 1.5
    st.tension_stiffness = 20
    st.compression_stiffness = 20
    st.shear_stiffness = 8
    st.bending_stiffness = 3.0
    st.tension_damping = 5
    st.bending_damping = 0.5
    st.vertex_group_mass = pin_group
    st.pin_stiffness = 1.0
    st.use_sewing_springs = sew
    st.sewing_force_max = 0.0
    cs = m.collision_settings
    cs.collision_quality = 4
    cs.distance_min = 0.006
    cs.use_self_collision = True
    cs.self_distance_min = 0.004
    cs.self_friction = 1.5
    m.point_cache.frame_start = 1
    m.point_cache.frame_end = frames
    return m


def run_sim(o, frames):
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, frames
    t0 = time.time()
    for f in range(1, frames + 1):
        sc.frame_set(f)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    pos = [b2g(v.co) for v in me.vertices]
    ev.to_mesh_clear()
    print("  sim %d frames %.1fs" % (frames, time.time() - t0))
    return pos


def snap_seams(pos, seams):
    for a, b in seams:
        m = tuple((pos[a][k] + pos[b][k]) / 2 for k in range(3))
        pos[a] = m
        pos[b] = m
    return pos


def taubin(pos, faces, iters=3, lam=0.5, mu=-0.53):
    """Taubin smoothing: removes the small crumples the coarse sim leaves
    (they alias into pixel noise in the toon shading) while keeping the big
    folds and the volume (no shrinkage)."""
    nb = [set() for _ in pos]
    for f in faces:
        for i in range(len(f)):
            a, b = f[i], f[(i + 1) % len(f)]
            nb[a].add(b)
            nb[b].add(a)
    p = [list(v) for v in pos]
    for _ in range(iters):
        for k in (lam, mu):
            q = []
            for i, v in enumerate(p):
                if not nb[i]:
                    q.append(v)
                    continue
                avg = [sum(p[j][c] for j in nb[i]) / len(nb[i]) for c in range(3)]
                q.append([v[c] + k * (avg[c] - v[c]) for c in range(3)])
            p = q
    return [tuple(v) for v in p]


def set_group(o, name, weights):
    vg = o.vertex_groups.new(name=name)
    for i, w in enumerate(weights):
        if w > 0.0:
            vg.add([i], w, "REPLACE")
    return vg


# --- configurations -----------------------------------------------------------

def side_edge(flat, nx_index, side):
    """Open (unsewn) part of one lateral edge: (vertex, |s| param t)."""
    nx, ns, index = nx_index
    i = 0 if side < 0 else nx
    lo = 0.05
    hi = P.L * (1.0 - P.SEAM_FRAC)
    out = []
    for j in range(ns + 1):
        vi = index[(i, j)]
        s = flat[vi][1]
        if lo <= abs(s) <= hi:
            out.append((vi, (abs(s) - lo) / (hi - lo), 1.0 if s > 0 else -1.0))
    return out


def gather_targets(edge, side):
    """Sleeve gathered onto the shoulder (how a daraa is worn for work):
    the lower part of the lateral opening, front and back, is lifted and
    thrown over the top of the shoulder. Returns {vertex: (waypoint, target)}:
    the waypoint swings the cloth out and around the arm instead of
    dragging it through the body."""
    t = {}
    for vi, u, fb in edge:
        if u < 0.55:
            continue
        k = (u - 0.55) / 0.45
        target = (side * (0.27 + 0.15 * k), P.SHOULDER_Y + 0.05 - 0.28 * k * k, fb * (0.05 + 0.08 * k))
        way = (side * 0.78, 0.95, fb * (0.14 + 0.06 * k))
        t[vi] = (way, target)
    return t


def spread_targets(edge, side):
    """Glide: the open edges held out like wings at shoulder height."""
    t = {}
    for vi, u, fb in edge:
        p = (side * 0.84, 1.0 - 0.3 * u, fb * 0.035)
        t[vi] = (p, p)
    return t


def sim_config(base_pos, faces, uvs, cols, seams, flat, yoke, targets, frames=150, ramp=40):
    clear_scene()
    body_proxies()
    o = garment_object(base_pos, faces, uvs, cols, seams, "DaraaCfg")
    pins = list(yoke)
    for vi in targets:
        pins[vi] = 1.0
    set_group(o, "pin", pins)
    o.shape_key_add(name="Basis")
    kw = o.shape_key_add(name="Way")
    kt = o.shape_key_add(name="Target")
    for vi, (w, p) in targets.items():
        kw.data[vi].co = g2b(w)
        kt.data[vi].co = g2b(p)
    half = ramp // 2
    for key, frames_vals in ((kw, ((1, 0.0), (half, 1.0), (ramp, 0.0))), (kt, ((1, 0.0), (half, 0.0), (ramp, 1.0)))):
        for f, v in frames_vals:
            key.value = v
            key.keyframe_insert("value", frame=f)
    add_cloth(o, "pin", frames)
    pos = run_sim(o, frames)
    return snap_seams(pos, seams)


def main():
    verts, faces, uvs, cols, flat, seams, nxi = build_grid()
    print("pattern: %d verts, %d quads, %d seam pairs, res %.3f" % (len(verts), len(faces), len(seams), RES))
    # shoulder anchors: the yoke around the neck rests on the shoulders
    yoke = []
    for (x, s) in flat:
        yoke.append(1.0 if (abs(x) < 0.2 and abs(s) < 0.2) else 0.0)
    # 1) drape from the flat pattern (sewing springs close the lower seams)
    clear_scene()
    body_proxies()
    o = garment_object(verts, faces, uvs, cols, seams)
    set_group(o, "pin", yoke)
    add_cloth(o, "pin", 120)
    base = snap_seams(run_sim(o, 120), seams)
    # 2) wearing configurations, each simulated from the draped state
    left = side_edge(flat, nxi, -1)
    right = side_edge(flat, nxi, 1)
    cfg = {}
    cfg["GatherL"] = sim_config(base, faces, uvs, cols, seams, flat, yoke, gather_targets(left, -1))
    cfg["GatherR"] = sim_config(base, faces, uvs, cols, seams, flat, yoke, gather_targets(right, 1))
    both = gather_targets(left, -1)
    both.update(gather_targets(right, 1))
    cfg["GatherBoth"] = sim_config(base, faces, uvs, cols, seams, flat, yoke, both)
    sp = spread_targets(left, -1)
    sp.update(spread_targets(right, 1))
    cfg["Spread"] = sim_config(base, faces, uvs, cols, seams, flat, yoke, sp, frames=60, ramp=24)
    # 3) smooth out sim crumples, then the final object: draped base +
    #    shape keys, no loose seam edges
    base = snap_seams(taubin(base, faces), seams)
    for name in cfg:
        cfg[name] = snap_seams(taubin(cfg[name], faces), seams)
    clear_scene()
    body_proxies()
    o = garment_object(base, faces, uvs, cols, [], "Daraa")
    o.shape_key_add(name="Basis")
    for name, pos in cfg.items():
        k = o.shape_key_add(name=name)
        for i, p in enumerate(pos):
            k.data[i].co = g2b(p)
    for ob in list(bpy.data.objects):
        ob.select_set(ob.name == "Daraa")
    bpy.context.view_layer.objects.active = o
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                              export_morph=True, export_morph_normal=True, export_normals=True,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_active_vertex_color_when_no_material=True,
                              export_materials="NONE", export_apply=False, export_yup=True)
    print("wrote", OUT_GLB)


if __name__ == "__main__":
    main()
