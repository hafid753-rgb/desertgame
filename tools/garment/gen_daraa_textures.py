"""Pixel-art textures for the daraa, laid out on the flat pattern UVs
(daraa_pattern.uv): 64 texels per character unit, image row 0 = front hem,
row ~56 = shoulder fold, row ~113 = back hem. Front-only decoration:
embroidered neckline with a short slit band, and the embroidered pocket
(wearer's left). Body cloth: bazin damask woven lozenges, tone on tone.
Three colourways (the species' daraas): royal blue, white, indigo/navy.
"""
import math
import os
from PIL import Image
import daraa_pattern as P

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "art", "garment")
COLOURWAYS = {
    "blue":  {"base": (52, 104, 196), "gold": (236, 186, 64), "gold_d": (160, 108, 36), "accent": (236, 238, 246)},
    "white": {"base": (234, 232, 224), "gold": (214, 160, 52), "gold_d": (140, 96, 40), "accent": (46, 86, 170)},
    "navy":  {"base": (34, 48, 108), "gold": (232, 182, 60), "gold_d": (150, 100, 34), "accent": (230, 226, 214)},
    "green": {"base": (40, 122, 88), "gold": (238, 190, 66), "gold_d": (150, 104, 36), "accent": (240, 236, 222)},
}


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def px_of(x, s):
    return (x + P.W / 2) * P.TEXELS_PER_UNIT, (s + P.L) * P.TEXELS_PER_UNIT


def make(cw):
    base, gold, gold_d, acc = cw["base"], cw["gold"], cw["gold_d"], cw["accent"]
    im = Image.new("RGB", (P.TEX_W, P.TEX_H), base)
    px = im.load()
    pale = sum(base) > 600
    # bazin damask: woven lozenges (8 px), a tone lighter/darker; fine weave
    for y in range(P.TEX_H):
        for x in range(P.TEX_W):
            gx, gy = (x % 8) - 3.5, (y % 8) - 3.5
            d = abs(gx) + abs(gy)
            k = 1.0
            if 2.5 <= d < 3.5:
                k = 1.07 if not pale else 0.965
            elif d < 1.0:
                k = 1.04 if not pale else 0.975
            if (x + y) % 2 == 0:
                k *= 0.985
            px[x, y] = shade(base, k)
    # hems: a faint turned-hem band (front row 0-1, back near the end)
    fold_y = P.L * P.TEXELS_PER_UNIT
    back_hem = int(2 * P.L * P.TEXELS_PER_UNIT) - 1
    for x in range(P.TEX_W):
        for y in (0, 1, back_hem - 1, back_hem):
            if 0 <= y < P.TEX_H:
                px[x, y] = shade(base, 0.86 if not pale else 0.9)
    # side seam stitching (lower side seams), 1 px in from the edge
    seam_rows = int(P.SEAM_FRAC * P.L * P.TEXELS_PER_UNIT)
    for y in list(range(0, seam_rows)) + list(range(back_hem - seam_rows, back_hem)):
        for x in (1, P.TEX_W - 2):
            if y % 2 == 0:
                px[x, y] = shade(base, 0.8 if not pale else 0.88)

    def put(x, y, c):
        if 0 <= x < P.TEX_W and 0 <= y < P.TEX_H:
            px[x, y] = c

    # neckline embroidery (front half only), following the cut ellipse
    cx, _ = px_of(0, 0)
    for y in range(P.TEX_H):
        for x in range(P.TEX_W):
            xx = (x + 0.5) / P.TEXELS_PER_UNIT - P.W / 2
            ss = (y + 0.5) / P.TEXELS_PER_UNIT - P.L
            if ss > 0.012:
                continue
            e = (xx / P.NECK_RX) ** 2 + (ss / P.NECK_FRONT) ** 2
            r = math.sqrt(e)
            # band: rings just outside the cut
            if 1.0 <= r < 1.22:
                put(x, y, gold)
            elif 1.22 <= r < 1.36:
                # little triangles: alternate gold teeth / dark gap
                ang = math.atan2(ss, xx)
                put(x, y, gold_d if int((ang + 4) * 9) % 2 == 0 else shade(base, 0.92))
            elif 1.36 <= r < 1.48:
                put(x, y, acc if int((math.atan2(ss, xx) + 4) * 18) % 3 == 0 else px[x, y])
    # chest band: the embroidered column running down from the V (the part
    # of the neckline embroidery that shows below the hawli knot)
    vy = int((P.L - P.NECK_FRONT) * P.TEXELS_PER_UNIT)
    icx = int(cx)
    for i, y in enumerate(range(vy - 18, vy + 1)):
        put(icx - 2, y, gold_d)
        put(icx + 2, y, gold_d)
        k = i % 4
        put(icx, y, acc if k == 0 else gold)
        put(icx - 1, y, gold if k in (1, 3) else shade(base, 0.85))
        put(icx + 1, y, gold if k in (1, 3) else shade(base, 0.85))
    for dx in range(-2, 3):           # small lozenge finial at the bottom
        put(icx + dx, vy - 19, gold_d if abs(dx) == 2 else gold)
    put(icx - 1, vy - 20, gold)
    put(icx, vy - 20, acc)
    put(icx + 1, vy - 20, gold)
    put(icx, vy - 21, gold)
    # pocket: pentagon (point down), gold outline, lozenge lattice inside,
    # pocket shadow on the lower-right, open top hem in accent thread
    pc_x, top_y = px_of(P.POCKET["cx"], P.POCKET["s0"])
    _, bot_y = px_of(P.POCKET["cx"], P.POCKET["s1"])
    hw = P.POCKET["w"] / 2 * P.TEXELS_PER_UNIT
    shoulder_y = top_y - (top_y - bot_y) * 0.7

    def inside(x, y):
        if y > top_y or y < bot_y:
            return False
        if y >= shoulder_y:
            return abs(x - pc_x) <= hw
        t = (y - bot_y) / max(shoulder_y - bot_y, 1e-3)
        return abs(x - pc_x) <= hw * t

    for y in range(int(bot_y) - 1, int(top_y) + 2):
        for x in range(int(pc_x - hw) - 1, int(pc_x + hw) + 2):
            cxp, cyp = x + 0.5, y + 0.5
            if not inside(cxp, cyp):
                if inside(cxp - 1, cyp + 1):
                    put(x, y, shade(base, 0.72))        # pocket shadow
                continue
            edge = not (inside(cxp + 1, cyp) and inside(cxp - 1, cyp) and inside(cxp, cyp + 1) and inside(cxp, cyp - 1))
            if edge:
                put(x, y, gold)
            else:
                gx, gy = (x - int(pc_x)) % 4, (y - int(bot_y)) % 4
                if (gx + gy) % 4 == 0:
                    put(x, y, gold_d)
                elif gx == 2 and gy == 2:
                    put(x, y, acc)
                else:
                    put(x, y, shade(base, 0.96))
    for x in range(int(pc_x - hw) + 1, int(pc_x + hw)):
        put(x, int(top_y), acc if x % 2 else gold)      # open top hem
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, cw in COLOURWAYS.items():
        im = make(cw)
        im.save(os.path.join(OUT, "daraa_%s.png" % name))
        im.resize((P.TEX_W * 6, P.TEX_H * 6), Image.NEAREST).save("/tmp/daraa_%s_big.png" % name)
    print("ok")


if __name__ == "__main__":
    main()
