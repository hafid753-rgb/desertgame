"""Hafid daraa: flat sewing pattern (source of truth for mesh, UVs, textures).

Construction (see docs/garment/DARAA.md for sources and assumptions):
  * ONE broad rectangle of cloth folded over the shoulders: the front and
    back are a single continuous piece (no shoulder seam).
  * Width far beyond the arm span: the outer parts hang from the shoulder
    points and form the large lateral "sleeve" openings.
  * Side seams join front to back ONLY in the lower part (SEAM_FRAC of the
    length from the hem); above them the sides are open.
  * Open hem (no closure), neck opening cut on the fold, deeper at the front.
  * Large embroidered chest pocket, front, slightly to the wearer's left;
    embroidered neckline. Back plain.

Coordinates: character units (Godot model space, metres-like), x across
(wearer's left = -x), s along the length from the shoulder fold
(s < 0 front, s > 0 back). Real-adult equivalents use REAL_SCALE.
"""
import json
import math

W = 1.50              # finished width (x in [-W/2, W/2])
L = 1.22              # fold-to-hem length (over the shoulder, then down to the ankles)
SEAM_FRAC = 0.32      # lower part of each side edge that is sewn
DX = 0.02             # mesh resolution
NECK_RX = 0.085       # neck opening half-width
NECK_FRONT = 0.26     # neck opening depth into the front (V reaches the chest)
NECK_BACK = 0.06      # ... and into the back
POCKET = {"cx": -0.155, "s0": -0.34, "s1": -0.54, "w": 0.17}   # front, wearer's left
TEXELS_PER_UNIT = 64  # garment pixel density (2x the 32 px/m world grid)
TEX_W, TEX_H = 96, 160
REAL_SCALE = 1.45     # 1 character unit ~ 1.45 m of real adult garment
SHOULDER_Y = 1.10     # fold line height in model space (top of the shoulders)
YOKE_Z = 0.19         # half-depth of the shoulder top (fold region)


def in_neck(x, s):
    if s < 0:
        d = (x / NECK_RX) ** 2 + (s / NECK_FRONT) ** 2
    else:
        d = (x / NECK_RX) ** 2 + (s / NECK_BACK) ** 2
    return d < 1.0


def uv(x, s):
    """Texel-consistent UV: pixel (px, py) = ((x+W/2), (s+L)) * density."""
    px = (x + W / 2) * TEXELS_PER_UNIT
    py = (s + L) * TEXELS_PER_UNIT
    return px / TEX_W, py / TEX_H


def weights(x, s):
    """Runtime garment-rig weights (packed into vertex colour RGBA):
    r side chain at -x, g side chain at +x, b freedom (0 yoke .. 1 hem),
    a front (1) / back (0)."""
    def sstep(a, b, v):
        t = min(max((v - a) / (b - a), 0.0), 1.0)
        return t * t * (3 - 2 * t)
    hx = W / 2
    side_neg = sstep(0.16, 0.62, -x / hx * 0.75)
    side_pos = sstep(0.16, 0.62, x / hx * 0.75)
    free = sstep(0.06, L, abs(s)) ** 0.9
    return side_neg, side_pos, free, 1.0 if s < 0 else 0.0


def spec():
    """GarmentCode-style JSON (pattern/panels/stitches), real-size cm."""
    k = REAL_SCALE * 100
    hw, l = W / 2 * k, L * k
    seam = SEAM_FRAC * l
    body = {
        "translation": [0, SHOULDER_Y * k, 0], "rotation": [0, 0, 0],
        # one panel, unfolded: front hem (bottom) -> fold -> back hem (top)
        "vertices": [[-hw, -l], [hw, -l], [hw, l], [-hw, l]],
        "edges": [{"endpoints": [0, 1], "label": "front_hem_open"},
                  {"endpoints": [1, 2], "label": "side_+x"},
                  {"endpoints": [2, 3], "label": "back_hem_open"},
                  {"endpoints": [3, 0], "label": "side_-x"}],
        "fold": {"line": [[-hw, 0], [hw, 0]], "label": "shoulder_fold"},
        "cutouts": [{"label": "neck", "ellipse": {"rx": NECK_RX * k, "front_depth": NECK_FRONT * k,
                                                     "back_depth": NECK_BACK * k}}],
    }
    pocket = {
        "translation": [POCKET["cx"] * k, POCKET["s0"] * k, 0], "rotation": [0, 0, 0],
        "vertices": [[-POCKET["w"] / 2 * k, 0], [POCKET["w"] / 2 * k, 0],
                     [POCKET["w"] / 2 * k, (POCKET["s1"] - POCKET["s0"]) * 0.7 * k],
                     [0, (POCKET["s1"] - POCKET["s0"]) * k],
                     [-POCKET["w"] / 2 * k, (POCKET["s1"] - POCKET["s0"]) * 0.7 * k]],
        "edges": [{"endpoints": [i, (i + 1) % 5]} for i in range(5)],
        "note": "patch pocket, top edge open, embroidered; sewn on the front body",
    }
    stitches = [
        # lower side seams only: front side edge s in [-L, -L+seam] to back [L-seam, L]
        [{"panel": "body", "edge": 1, "range": [0.0, SEAM_FRAC]},
         {"panel": "body", "edge": 1, "range": [1.0 - SEAM_FRAC, 1.0]}],
        [{"panel": "body", "edge": 3, "range": [1.0 - SEAM_FRAC, 1.0]},
         {"panel": "body", "edge": 3, "range": [0.0, SEAM_FRAC]}],
        [{"panel": "pocket", "edges": [1, 2, 3, 4]}, {"panel": "body", "topstitch": True}],
    ]
    return {
        "pattern": {"panels": {"body": body, "pocket": pocket}, "stitches": stitches,
                    "panel_order": ["body", "pocket"]},
        "properties": {"units_in_meter": 100, "garment": "Mauritanian daraa (Hafid)",
                       "character_scale": 1.0 / REAL_SCALE,
                       "fabric": "bazin (damask cotton), stiff, slight sheen",
                       "assumptions": "see docs/garment/DARAA.md"},
    }


if __name__ == "__main__":
    import os
    out = os.path.join(os.path.dirname(__file__), "daraa_specification.json")
    json.dump(spec(), open(out, "w"), indent=1)
    print("wrote", out)
