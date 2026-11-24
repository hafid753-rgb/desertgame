"""Hafid pixel-art texture families (editable source of game/art/pixel/*.png).

Deterministic, palette-limited, cluster-based: every texture is built from
deliberate pixel clusters (blocks, strokes, bands, specks of 1-3 px) using
4-6 shades per material, then cleaned of orphan single pixels so no noise
"dust" remains. Detail textures (fur, fabric, leather, shadow) are grayscale
luminance maps around mid-grey that modulate a mesh's vertex colour; surface
textures (sand, sandstone, earth, wood) are full colour.

Run: python3 tools/pixel/gen_textures.py
"""
import math
import os
import random

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "art", "pixel")


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c)


def hue_shift(c, warm):
    """Shadows cool toward lavender, highlights warm toward sunlight."""
    lav, sun = hexc("82788D"), hexc("F1DDB6")
    t = abs(warm)
    tgt = sun if warm > 0 else lav
    return tuple(int(round(a + (b - a) * t)) for a, b in zip(c, tgt))


def ramp(base, n=5, lo=0.72, hi=1.12):
    """Palette ramp with hue shifting (dark = cooler, light = warmer)."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        k = lo + (hi - lo) * t
        out.append(hue_shift(shade(base, k), (t - 0.5) * 0.5))
    return out


class Grid:
    def __init__(self, w, h, v=0):
        self.w, self.h = w, h
        self.d = [[v] * w for _ in range(h)]

    def get(self, x, y):
        return self.d[y % self.h][x % self.w]

    def set(self, x, y, v):
        self.d[y % self.h][x % self.w] = v

    def clean(self, passes=2):
        """Replace single orphan pixels with their most common neighbour."""
        for _ in range(passes):
            nd = [row[:] for row in self.d]
            for y in range(self.h):
                for x in range(self.w):
                    v = self.d[y][x]
                    nb = [self.get(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
                    if v not in nb:
                        nd[y][x] = max(set(nb), key=nb.count)
            self.d = nd

    def image(self, pal):
        im = Image.new("RGBA", (self.w, self.h))
        px = im.load()
        for y in range(self.h):
            for x in range(self.w):
                c = pal[self.d[y][x]]
                px[x, y] = c if len(c) == 4 else c + (255,)
        return im


def vnoise(rng, w, h, cell):
    """Tileable value noise sampled per pixel (0..1)."""
    gw, gh = w // cell, h // cell
    g = [[rng.random() for _ in range(gw)] for _ in range(gh)]

    def at(x, y):
        fx, fy = x / cell, y / cell
        x0, y0 = int(fx), int(fy)
        tx, ty = fx - x0, fy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = g[y0 % gh][x0 % gw]
        b = g[y0 % gh][(x0 + 1) % gw]
        c = g[(y0 + 1) % gh][x0 % gw]
        d = g[(y0 + 1) % gh][(x0 + 1) % gw]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    return at


# --- Surfaces -----------------------------------------------------------------

def sand(size=128, seed=1):
    rng = random.Random(seed)
    pal = ramp(hexc("D6BE94"), 5, 0.8, 1.08)
    g = Grid(size, size, 2)
    n = vnoise(rng, size, size, 32)
    for y in range(size):
        for x in range(size):
            # wind ripples: wavy diagonal bands, crest (light) / trough (dark)
            ph = (x * 0.42 + y * 0.9 + math.sin(y * 0.11 + x * 0.03) * 3.0) / 6.0
            r = math.sin(ph * math.tau)
            v = 2 + (1 if r > 0.55 else 0) - (1 if r < -0.7 else 0)
            if n(x, y) > 0.68:
                v = min(4, v + 1)
            g.set(x, y, v)
    for _ in range(140):  # grain clusters
        x, y = rng.randrange(size), rng.randrange(size)
        v = rng.choice([0, 1, 4])
        g.set(x, y, v)
        if rng.random() < 0.6:
            g.set(x + 1, y, v)
    g.clean(1)
    return g.image(pal)


def sandstone(size=128, seed=2):
    """Irregular stone courses with mortar, chipped corners, cracks."""
    rng = random.Random(seed)
    pal = ramp(hexc("B49A7B"), 6, 0.68, 1.12)
    g = Grid(size, size, 3)
    y = 0
    while y < size:
        hgt = rng.choice([10, 12, 14, 16])
        if y + hgt > size:
            hgt = size - y
        x = rng.randrange(0, 20)
        while x < size + 20:
            wid = rng.choice([14, 18, 22, 26, 30])
            tone = rng.choice([2, 3, 3, 4])
            for yy in range(y, y + hgt):
                for xx in range(x, x + wid):
                    edge_x = xx in (x, x + wid - 1)
                    edge_y = yy in (y, y + hgt - 1)
                    v = 0 if (edge_x or edge_y) else tone
                    # top-left light edge, bottom-right shadow edge inside the stone
                    if not (edge_x or edge_y):
                        if yy == y + 1 or xx == x + 1:
                            v = min(5, tone + 1)
                        elif yy == y + hgt - 2:
                            v = max(1, tone - 1)
                    g.set(xx, yy, v)
            # chipped corner
            if rng.random() < 0.4:
                cx, cy = x + 1, y + 1
                for dx, dy in ((0, 0), (1, 0), (0, 1)):
                    g.set(cx + dx, cy + dy, 0)
            # crack
            if rng.random() < 0.25:
                cx, cy = x + rng.randrange(3, max(4, wid - 3)), y + 2
                for k in range(hgt - 4):
                    g.set(cx, cy + k, 1)
                    cx += rng.choice([-1, 0, 0, 1])
            # pits
            for _ in range(rng.randrange(0, 3)):
                g.set(x + rng.randrange(2, max(3, wid - 2)), y + rng.randrange(2, max(3, hgt - 2)), max(1, tone - 2))
            x += wid
        y += hgt
    return g.image(pal)


def earth(size=128, seed=3):
    """Packed earth floor: large soft patches, pebbles, faint cracks."""
    rng = random.Random(seed)
    pal = ramp(hexc("B98A68"), 5, 0.86, 1.08)
    g = Grid(size, size, 2)
    n = vnoise(rng, size, size, 16)
    m = vnoise(rng, size, size, 8)
    for y in range(size):
        for x in range(size):
            v = n(x, y) * 0.6 + m(x, y) * 0.4
            g.set(x, y, 1 if v < 0.3 else (3 if v > 0.72 else 2))
    for _ in range(70):
        x, y = rng.randrange(size), rng.randrange(size)
        g.set(x, y, 4)
        g.set(x + 1, y, 4)
        g.set(x, y + 1, 0)
        g.set(x + 1, y + 1, 0)
    for _ in range(6):
        x, y = rng.randrange(size), rng.randrange(size)
        for k in range(rng.randrange(8, 20)):
            g.set(x, y, 0)
            x += rng.choice([1, 1, 0])
            y += rng.choice([-1, 0, 1])
    g.clean(1)
    return g.image(pal)


def wood(size=64, seed=4):
    rng = random.Random(seed)
    pal = ramp(hexc("7A5034"), 5, 0.7, 1.15)
    g = Grid(size, size, 2)
    plank = 16
    for y in range(size):
        for x in range(size):
            px = x % plank
            v = 2
            wob = math.sin(y * 0.19 + (x // plank) * 2.1) * 2.2
            if int(px + wob) % 5 == 0:
                v = 1
            if px == 0:
                v = 0
            elif px == 1:
                v = 3
            g.set(x, y, v)
    for _ in range(5):
        x, y = rng.randrange(size), rng.randrange(size)
        for dy in range(-2, 3):
            for dx in range(-1, 2):
                if abs(dx) + abs(dy) < 3:
                    g.set(x + dx, y + dy, 0 if abs(dx) + abs(dy) < 2 else 1)
    for y in (4, size - 6):  # iron bands / nails
        for x in range(size):
            if x % plank in (6, 10):
                g.set(x, y, 4)
    g.clean(1)
    return g.image(pal)


# --- Detail maps (grayscale, 128 = neutral) ----------------------------------

GRAY5 = [(92, 92, 92), (112, 112, 112), (128, 128, 128), (142, 142, 142), (160, 160, 160)]


def fur(size=32, seed=5):
    """Short directional fur strokes in clumps (2-4 px), lighter tips."""
    rng = random.Random(seed)
    g = Grid(size, size, 2)
    for _ in range(46):
        x, y = rng.randrange(size), rng.randrange(size)
        ln = rng.choice([2, 3, 3, 4])
        dark = rng.random() < 0.5
        for k in range(ln):
            g.set(x + (k // 2 if rng.random() < 0.3 else 0), y + k, 1 if dark else 3)
        g.set(x, y + ln, 0 if dark else 4)
    g.clean(1)
    return g.image(GRAY5)


def fabric(size=32, seed=6):
    """Bazin weave: 2x1 alternating threads + tone-on-tone lozenge motif."""
    g = Grid(size, size, 2)
    for y in range(size):
        for x in range(size):
            v = 2 if ((x // 2) + (y // 2)) % 2 == 0 else 3
            c = abs((x % 16) - 8) + abs((y % 16) - 8)
            if c in (6, 7):
                v = 4
            elif c == 0 or c == 1:
                v = 4
            elif c in (8,) and (x + y) % 2 == 0:
                v = 1
            g.set(x, y, v)
    return g.image(GRAY5)


def leather(size=32, seed=7):
    rng = random.Random(seed)
    g = Grid(size, size, 2)
    n = vnoise(rng, size, size, 8)
    for y in range(size):
        for x in range(size):
            g.set(x, y, 1 if n(x, y) < 0.32 else (3 if n(x, y) > 0.7 else 2))
    for y in range(0, size, 8):  # stitch line
        for x in range(0, size, 3):
            g.set(x, y, 4)
    g.clean(1)
    return g.image(GRAY5)


def shadow_clusters(size=32, seed=8):
    """Jinn body: charcoal clumps with muted purple (#302C3D base)."""
    rng = random.Random(seed)
    base = hexc("302C3D")
    pal = [shade(base, 0.55), shade(base, 0.8), base, (66, 52, 86), (92, 74, 120)]
    g = Grid(size, size, 1)
    n = vnoise(rng, size, size, 8)
    for y in range(size):
        for x in range(size):
            v = n(x, y)
            g.set(x, y, 0 if v < 0.3 else (2 if v > 0.62 else 1))
    for _ in range(14):
        x, y = rng.randrange(size), rng.randrange(size)
        for dx, dy in ((0, 0), (1, 0), (0, 1)):
            g.set(x + dx, y + dy, rng.choice([3, 4]))
    g.clean(1)
    return g.image(pal)


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = {
        "sand_128": sand, "sandstone_128": sandstone, "earth_128": earth, "wood_64": wood,
        "fur_detail_32": fur, "fabric_detail_32": fabric, "leather_detail_32": leather,
        "jinn_shadow_32": shadow_clusters,
    }
    for name, fn in jobs.items():
        im = fn()
        im.save(os.path.join(OUT, name + ".png"))
        print(name, im.size)
    # contact sheet for review (8x nearest)
    ims = [fn() for fn in jobs.values()]
    sheet = Image.new("RGBA", (8 * 128 * 2 + 9 * 8, 128 * 2 + 16), (40, 36, 46, 255))
    x = 8
    for im in ims:
        k = 256 // im.size[0]
        big = im.resize((im.size[0] * k, im.size[1] * k), Image.NEAREST)
        sheet.paste(big, (x, 8))
        x += 256 + 8
    sheet.save(os.path.join(OUT, "_sheet.png"))


if __name__ == "__main__":
    main()
