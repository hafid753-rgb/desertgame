"""Count self-intersecting face pairs of the daraa (base + every shape key).
Adjacent faces (sharing a vertex) are ignored."""
import sys
import bpy
from mathutils.bvhtree import BVHTree

path = sys.argv[sys.argv.index("--blend") + 1] if "--blend" in sys.argv else "tools/garment/daraa_source.blend"
bpy.ops.wm.open_mainfile(filepath=path)
me = bpy.data.objects["Daraa"].data
polys = [tuple(p.vertices) for p in me.polygons]
vsets = [set(p) for p in polys]
for k in me.shape_keys.key_blocks:
    co = [v.co.copy() for v in k.data]
    t = BVHTree.FromPolygons(co, polys, all_triangles=False, epsilon=0.0)
    pairs = [(a, b) for a, b in t.overlap(t) if a < b and not (vsets[a] & vsets[b])]
    print("INTERSECT %-11s %d" % (k.name, len(pairs)))
