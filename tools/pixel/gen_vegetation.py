"""Hafid vegetation sprites (editable source of game/art/pixel/veg_*.png).

Each grass blade, leaflet and frond leaflet is its own small sprite with a
transparent background, a limited palette (dark edge, body, light rib, tip)
and a root at the bottom centre, so the game can instance them as separate
deformable surfaces. Run: python3 tools/pixel/gen_vegetation.py
"""
import math
import os
import random

from PIL import Image

from gen_textures import OUT, hexc, ramp, shade

CLEAR = (0, 0, 0, 0)


def put(px, w, h, x, y, c):
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = c + (255,) if len(c) == 3 else c


def blade(w, h, pal, curve, width, rng, seed_head=False, broken=False):
    """One grass blade, root at bottom centre, curving to the side."""
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    top = int(h * (0.55 if broken else 0.0))
    for y in range(h - 1, top - 1, -1):
        t = (h - 1 - y) / (h - 1)          # 0 root .. 1 tip
        cx = w / 2 - 0.5 + curve * (t ** 2) * (w / 2 - 1)
        half = max(0.0, width * (1 - t) ** 0.8)
        x0, x1 = int(round(cx - half)), int(round(cx + half))
        for x in range(x0, x1 + 1):
            edge = x in (x0, x1) and x1 > x0
            c = pal[1] if edge else pal[2]
            if x == int(round(cx)) and x1 - x0 >= 2:
                c = pal[3]                     # light rib
            if t > 0.8:
                c = pal[3] if not edge else pal[2]
            put(px, w, h, x, y, c)
        if y == h - 1:
            for x in range(x0, x1 + 1):
                put(px, w, h, x, y, pal[0])    # root shadow
    if seed_head:
        cx = int(round(w / 2 - 0.5 + curve * (w / 2 - 1)))
        for k in range(5):
            put(px, w, h, cx + (k % 2), top + k, pal[4])
            put(px, w, h, cx - 1 + (k % 2), top + k + 1, pal[3])
    if broken:
        cx = int(round(w / 2 - 0.5 + curve * 0.3 * (w / 2 - 1)))
        put(px, w, h, cx, top, pal[0])
    return im


def leaflet(w, h, pal, rng, shape="oval"):
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    for y in range(h):
        t = y / (h - 1)
        if shape == "oval":
            half = (w / 2) * math.sin(math.pi * (0.08 + 0.92 * t)) ** 0.8
        else:  # long pointed (palm)
            half = (w / 2) * min(1.0, 3.0 * t) * (1 - t) ** 0.6 * 1.6
        cx = w / 2 - 0.5
        x0, x1 = int(round(cx - half)), int(round(cx + half))
        for x in range(x0, x1 + 1):
            c = pal[2]
            if x == x0:
                c = pal[1]
            elif x == x1:
                c = pal[3]
            if x == int(round(cx)) and shape != "oval":
                c = pal[3]
            put(px, w, h, x, y, c)
    return im


def sheet(cells, cw, ch, cols):
    rows = (len(cells) + cols - 1) // cols
    im = Image.new("RGBA", (cw * cols, ch * rows), CLEAR)
    for i, c in enumerate(cells):
        im.paste(c, ((i % cols) * cw, (i // cols) * ch))
    return im


def main():
    rng = random.Random(11)
    dry = ramp(hexc("C2B16A"), 5, 0.62, 1.15)
    green = ramp(hexc("7D8965"), 5, 0.62, 1.2)
    # 6 columns x 2 rows (dry, green) of 16x32 blades
    cells = []
    for pal in (dry, green):
        cells += [
            blade(16, 32, pal, 0.25, 1.6, rng),
            blade(16, 32, pal, -0.6, 1.4, rng),
            blade(16, 32, pal, 0.9, 1.2, rng),
            blade(16, 32, pal, 0.15, 1.5, rng, seed_head=True),
            blade(16, 32, pal, -0.35, 1.8, rng, broken=True),
            blade(16, 32, pal, -0.9, 1.1, rng),
        ]
    sheet(cells, 16, 32, 6).save(os.path.join(OUT, "veg_grass.png"))
    # acacia leaflets 8x8: 4 green + 2 dry
    acacia = ramp(hexc("7D8965"), 5, 0.6, 1.2)
    dryleaf = ramp(hexc("B5A061"), 5, 0.6, 1.15)
    leaves = [leaflet(8, 8, acacia, rng) for _ in range(4)] + [leaflet(8, 8, dryleaf, rng) for _ in range(2)]
    # make variants distinct: rotate / trim
    leaves[1] = leaves[1].transpose(Image.FLIP_LEFT_RIGHT)
    leaves[2] = leaflet(6 + 2, 8, ramp(hexc("6F7E58"), 5, 0.6, 1.2), rng)
    leaves[3] = leaflet(8, 8, ramp(hexc("8C9467"), 5, 0.6, 1.2), rng)
    sheet(leaves, 8, 8, 6).save(os.path.join(OUT, "veg_leaf.png"))
    # palm frond leaflets 8x32: 3 variants
    palm = ramp(hexc("8A9455"), 5, 0.58, 1.2)
    palm_dry = ramp(hexc("B39B5E"), 5, 0.6, 1.15)
    fl = [leaflet(6, 32, palm, rng, "long"), leaflet(6, 32, ramp(hexc("7B8A50"), 5, 0.58, 1.2), rng, "long"),
          leaflet(6, 32, palm_dry, rng, "long")]
    sheet(fl, 6, 32, 3).save(os.path.join(OUT, "veg_palm_leaflet.png"))
    # flowers 16x16: small desert flowers (white, yellow)
    fls = []
    for petal in (hexc("EFE6D2"), hexc("E8C35A")):
        im = Image.new("RGBA", (16, 16), CLEAR)
        px = im.load()
        stem = dry[1]
        for y in range(6, 16):
            put(px, 16, 16, 8 + (1 if y < 9 else 0), y, stem)
        for dx, dy in ((0, -2), (2, 0), (0, 2), (-2, 0), (1, -1), (-1, 1), (1, 1), (-1, -1)):
            put(px, 16, 16, 9 + dx, 4 + dy, petal)
        put(px, 16, 16, 9, 4, hexc("C77A3A"))
        fls.append(im)
    sheet(fls, 16, 16, 2).save(os.path.join(OUT, "veg_flower.png"))
    # bark: palm (diamond leaf-base scars) and acacia (fissured grey-brown)
    pb = ramp(hexc("8C6E4E"), 5, 0.62, 1.15)
    im = Image.new("RGBA", (32, 32))
    px = im.load()
    for y in range(32):
        for x in range(32):
            u = (x + (y // 8) * 4) % 8
            v = y % 8
            d = abs(u - 4) + abs(v - 4)
            c = pb[2]
            if d >= 4:
                c = pb[0] if v in (0, 7) else pb[1]
            elif d <= 1:
                c = pb[3]
            px[x, y] = c + (255,)
    im.save(os.path.join(OUT, "veg_bark_palm.png"))
    ab = ramp(hexc("6E5E50"), 5, 0.6, 1.2)
    im = Image.new("RGBA", (32, 32))
    px = im.load()
    r2 = random.Random(5)
    cols = [r2.randrange(32) for _ in range(6)]
    for y in range(32):
        for x in range(32):
            c = ab[2] if (x // 3 + y // 11) % 2 == 0 else ab[3]
            for cx in cols:
                if abs(x - (cx + int(2 * math.sin(y * 0.4 + cx)))) == 0:
                    c = ab[0]
            px[x, y] = c + (255,)
    im.save(os.path.join(OUT, "veg_bark_acacia.png"))
    # review sheet
    files = ["veg_grass", "veg_leaf", "veg_palm_leaflet", "veg_flower", "veg_bark_palm", "veg_bark_acacia"]
    ims = [Image.open(os.path.join(OUT, f + ".png")) for f in files]
    big = [i.resize((i.size[0] * 6, i.size[1] * 6), Image.NEAREST) for i in ims]
    W = sum(b.size[0] for b in big) + 8 * (len(big) + 1)
    H = max(b.size[1] for b in big) + 16
    sh = Image.new("RGBA", (W, H), (214, 190, 148, 255))
    x = 8
    for b in big:
        sh.paste(b, (x, 8), b)
        x += b.size[0] + 8
    sh.save(os.path.join(OUT, "_veg_sheet.png"))
    print("ok")


if __name__ == "__main__":
    main()
