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


def fine_leaflet(pal, rng, w=6, h=6):
    """Acacia pinnule spray: a midrib with tiny paired leaflets (bipinnate)."""
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    cx = w // 2
    for y in range(h):
        put(px, w, h, cx, y, pal[1])
        if y < h - 1 and y % 2 == 0:
            put(px, w, h, cx - 1, y, pal[2])
            put(px, w, h, cx + 1, y, pal[3] if rng.random() < 0.5 else pal[2])
            if y < h - 2 and rng.random() < 0.7:
                put(px, w, h, cx - 2, y + 1, pal[2])
                put(px, w, h, cx + 2, y + 1, pal[2])
    put(px, w, h, cx, 0, pal[3])
    return im


def footprints():
    """Boot prints (right, left) 10x10 pressed into sand: shadowed hollow
    with a ridged sole, narrower heel, sand pushed up in front of the toe."""
    hollow, deep, rim = (196, 132, 112, 255), (176, 114, 98, 255), (242, 194, 170, 255)
    cells = []
    for flip in (False, True):
        im = Image.new("RGBA", (10, 10), CLEAR)
        px = im.load()
        for y in range(1, 10):
            for x in range(10):
                t = (y - 1) / 8.0
                half = 2.9 - 1.1 * t
                dx = (x - 4.5 - 0.5 * t) / half
                dy = (y - 5.0) / 4.4
                if dx * dx + dy * dy < 1.0:
                    # toe-side edge falls in shadow, sole ridges
                    px[x, y] = deep if (y <= 2 or (y % 3 == 0 and abs(dx) < 0.7)) else hollow
        for x in (3, 4, 5, 6):
            px[x, 0] = rim
        if flip:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        cells.append(im)
    return cells


def palm_boot(pal, rng, w=8, h=10):
    """Persistent leaf base of a date palm: a broad wedge with a frayed fibrous
    top edge, light upper rim, shadowed lower half. Root (attachment) at the
    bottom, the cut petiole end at the top."""
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    for y in range(h):
        t = 1 - y / (h - 1)                    # 0 bottom .. 1 top
        half = 1.2 + 2.6 * t
        for x in range(w):
            dx = abs(x - (w / 2 - 0.5))
            if dx <= half:
                c = pal[2]
                if dx > half - 1.0:
                    c = pal[1]                  # edge
                if y >= h - 3:
                    c = pal[0] if dx > half - 1.5 else pal[1]   # tucked base
                if y <= 1:
                    c = pal[3] if (x + y) % 2 == 0 else pal[2]   # light rim
                if y == 0 and rng.random() < 0.35:
                    continue                    # frayed top
                put(px, w, h, x, y, c)
    # fibre streak
    put(px, w, h, w // 2, h // 2, pal[1])
    put(px, w, h, w // 2, h // 2 + 1, pal[1])
    return im


def date_cluster(pal, w=8, h=12):
    """Hanging bunch of dates: a stalk, then drupes in staggered rows."""
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    for y in range(0, 3):
        put(px, w, h, w // 2, y, pal[0])
    for y in range(3, h):
        t = (y - 3) / (h - 4)
        half = int(1 + 2.2 * math.sin(math.pi * min(1.0, t * 0.9 + 0.1)))
        for x in range(w // 2 - half, w // 2 + half + 1):
            if (x + y) % 2 == 0:
                put(px, w, h, x, y, pal[3] if y < 6 else pal[2])
            else:
                put(px, w, h, x, y, pal[1])
    return im


def reed(pal, rng, w=8, h=32):
    """Clump of rushes: 3-4 stiff upright stems, rust/brown, dark base."""
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    for k in range(rng.randint(6, 8)):
        x0 = rng.randint(1, w - 2)
        top = rng.randint(2, 12)
        lean = rng.choice([-1, 0, 0, 1])
        for y in range(h - 1, top - 1, -1):
            t = (h - 1 - y) / (h - 1)
            x = x0 + int(round(lean * t * t * 2))
            c = pal[0] if y > h - 4 else (pal[3] if t > 0.75 else (pal[2] if k % 2 else pal[1]))
            put(px, w, h, x, y, c)
        if rng.random() < 0.6:                  # seed spike
            x = x0 + int(round(lean * 2))
            for y in range(top, top + 4):
                put(px, w, h, x, y, pal[4])
    return im


def twig_shrub(pal, rng, w=16, h=16):
    """Dead desert shrub: dark forked twigs from a root point (reads as the
    small dry bushes scattered over Garbage Country's dirt)."""
    im = Image.new("RGBA", (w, h), CLEAR)
    px = im.load()
    def branch(x, y, ang, length, depth):
        for i in range(length):
            put(px, w, h, int(round(x)), int(round(y)), pal[1] if depth == 0 else pal[2])
            x += math.sin(ang)
            y -= math.cos(ang)
        if depth < 2:
            for da in (-0.6, 0.55):
                if rng.random() < 0.85:
                    branch(x, y, ang + da + rng.uniform(-0.2, 0.2), max(2, length - 2), depth + 1)
        else:
            put(px, w, h, int(round(x)), int(round(y)), pal[3])
    for ang in (-0.5, 0.05, 0.45):
        branch(w / 2 - 0.5, h - 1, ang + rng.uniform(-0.15, 0.15), rng.randint(4, 6), 0)
    for x in range(w // 2 - 2, w // 2 + 2):
        put(px, w, h, x, h - 1, pal[0])
    return im


def main():
    rng = random.Random(11)
    dry = ramp(hexc("C99A45"), 5, 0.55, 1.18)
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
    # fine acacia sprays 6x6: 3 light, 2 dark (canopy underside), 2 dry, 1 olive
    fine = ([fine_leaflet(ramp(hexc("7D8965"), 5, 0.6, 1.25), rng) for _ in range(3)]
            + [fine_leaflet(ramp(hexc("56614A"), 5, 0.6, 1.15), rng) for _ in range(2)]
            + [fine_leaflet(ramp(hexc("B5A061"), 5, 0.6, 1.15), rng) for _ in range(2)]
            + [fine_leaflet(ramp(hexc("8C9467"), 5, 0.6, 1.2), rng)])
    sheet(fine, 6, 6, 8).save(os.path.join(OUT, "veg_leaf_fine.png"))
    sheet(footprints(), 10, 10, 2).save(os.path.join(OUT, "fx_footprint.png"))
    # date palm leaf bases: ochre, beige, weathered brown, dark old
    boots = [palm_boot(ramp(hexc(c), 4, 0.55, 1.25), rng) for c in ("A97C4E", "C2A27A", "8A6A4E", "6E5546")]
    sheet(boots, 8, 10, 4).save(os.path.join(OUT, "veg_palm_boot.png"))
    dates = [date_cluster(ramp(hexc(c), 4, 0.55, 1.3)) for c in ("B86A2E", "8C4A2A")]
    sheet(dates, 8, 12, 2).save(os.path.join(OUT, "veg_dates.png"))
    reeds = [reed(ramp(hexc(c), 5, 0.5, 1.2), rng) for c in ("8E5A3A", "9A6A3E", "7A6A40")]
    sheet(reeds, 8, 32, 3).save(os.path.join(OUT, "veg_reed.png"))
    twigs = [twig_shrub(ramp(hexc(c), 4, 0.5, 1.3), rng) for c in ("4A3630", "56403A", "3E3434")]
    sheet(twigs, 16, 16, 3).save(os.path.join(OUT, "veg_twig.png"))
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
    files = ["veg_grass", "veg_leaf", "veg_leaf_fine", "fx_footprint", "veg_palm_boot", "veg_dates", "veg_reed", "veg_twig", "veg_palm_leaflet", "veg_flower", "veg_bark_palm", "veg_bark_acacia"]
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
