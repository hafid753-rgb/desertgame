"""Quick orthographic views of every shape key in daraa_source.blend."""
import sys
import bpy
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/drape.png"
bpy.ops.wm.open_mainfile(filepath=sys.argv[2] if len(sys.argv) > 2 else "tools/garment/daraa_source.blend")
me = bpy.data.objects["Daraa"].data
faces = [list(p.vertices) for p in me.polygons]
keys = me.shape_keys.key_blocks
L = np.array([0.4, -0.6, 0.7]); L /= np.linalg.norm(L)
fig, axs = plt.subplots(3, len(keys), figsize=(4 * len(keys), 12))
for c, k in enumerate(keys):
    P = np.array([v.co[:] for v in k.data])
    for r, (ai, depth, sgn, flip, name) in enumerate([(0, 1, 1, 1, "front"), (1, 0, -1, 1, "side"), (0, 1, -1, -1, "back")]):
        ax = axs[r][c]
        d = P[:, depth] * sgn
        order = sorted(range(len(faces)), key=lambda f: -np.mean(d[faces[f]]))
        polys, cols = [], []
        for f in order:
            q = P[faces[f]]
            polys.append(np.stack([q[:, ai] * flip, q[:, 2]], 1))
            n = np.cross(q[1] - q[0], q[2] - q[0]); n /= np.linalg.norm(n) + 1e-9
            l = abs(np.dot(n, L))
            cols.append((0.2 + 0.6 * l, 0.35 + 0.5 * l, 0.7 + 0.3 * l))
        ax.add_collection(PolyCollection(polys, facecolors=cols, edgecolors="none"))
        ax.set_xlim(-0.9, 0.9); ax.set_ylim(0, 1.4); ax.set_aspect("equal"); ax.set_title(k.name + " " + name)
plt.tight_layout(); plt.savefig(out, dpi=55)
