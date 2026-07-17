#!/usr/bin/env python3
"""Procedural pixel-art sprite generator for Orbfall Arena.

Regenerate all sprites:      python3 tools/make_sprites.py
Output:                      assets/sprites/*.png  (+ sheet_preview.png)

Style: gritty 16-bit. Enemies are angular slabs with glowing slit eyes
under heavy brows; the five playables are PEOPLE on one shared 48px human
rig — capsule/curve silhouettes instead of slabs, multi-pixel faces (iris,
brows, nose, mouth), gendered builds, class outfits and weapons, kept
tasteful. All original designs, deterministic, upscaled x4
nearest-neighbour. Colors track src/balance.gd. Replace any PNG with
hand-made art (same filename) and the game picks it up automatically;
missing files fall back to vector shapes in-game.
"""

import math
import os

from PIL import Image, ImageDraw

SCALE = 4
OUTDIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
OUTLINE = (20, 16, 28, 255)
SKIN = (222, 178, 138)
DARK = (26, 22, 36)
STEEL = (168, 176, 192)
PALE = (226, 234, 248)


def clamp(v):
    return max(0, min(255, int(v)))


def tint(c, f):
    return (clamp(c[0] * f), clamp(c[1] * f), clamp(c[2] * f))


def mix(a, b, t):
    return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(3))


def desat(c, t=0.2):
    g = clamp(0.3 * c[0] + 0.55 * c[1] + 0.15 * c[2])
    return mix(c, (g, g, g), t)


class Px:
    def __init__(self, size):
        self.s = size
        self.img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        self.p = self.img.load()

    def set(self, x, y, c, a=255):
        if 0 <= x < self.s and 0 <= y < self.s:
            self.p[int(x), int(y)] = (c[0], c[1], c[2], a)

    def get_a(self, x, y):
        if 0 <= x < self.s and 0 <= y < self.s:
            return self.p[x, y][3]
        return 0

    def mask_pixels(self, inside):
        return [(x, y) for y in range(self.s) for x in range(self.s) if inside(x, y)]

    def glow(self, inside, color, spread=2, alpha=60):
        pts = self.mask_pixels(inside)
        for d in range(spread, 0, -1):
            a = int(alpha * (1.0 - (d - 1) / spread))
            for (x, y) in pts:
                for dx in range(-d, d + 1):
                    for dy in range(-d, d + 1):
                        if abs(dx) + abs(dy) <= d and self.get_a(x + dx, y + dy) == 0:
                            self.set(x + dx, y + dy, color, a)

    def fill(self, inside, base, rim=True):
        pts = self.mask_pixels(inside)
        if not pts:
            return
        ys = [y for (_, y) in pts]
        y0, y1 = min(ys), max(ys)
        h = max(1, y1 - y0)
        for (x, y) in pts:
            t = (y - y0) / h
            if t < 0.2:
                f = 1.16
            elif t < 0.52:
                f = 1.04
            elif t < 0.82:
                f = 0.92
            else:
                f = 0.62
            self.set(x, y, tint(base, f))
        if rim:
            for (x, y) in pts:
                if not inside(x - 1, y) and (y - y0) / h < 0.45:
                    self.set(x, y, tint(base, 1.26))

    def paint(self, inside, c):
        for (x, y) in self.mask_pixels(inside):
            self.set(x, y, c)

    def outline(self, color=OUTLINE):
        add = []
        for y in range(self.s):
            for x in range(self.s):
                if self.p[x, y][3] >= 200:
                    continue
                if any(
                    self.get_a(x + dx, y + dy) >= 200
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                ):
                    add.append((x, y))
        for (x, y) in add:
            self.p[x, y] = color

    def dots(self, pts, c, a=255):
        for (x, y) in pts:
            self.set(x, y, c, a)

    def hline(self, x0, x1, y, c):
        for x in range(int(x0), int(x1) + 1):
            self.set(x, y, c)

    def vline(self, x, y0, y1, c):
        for y in range(int(y0), int(y1) + 1):
            self.set(x, y, c)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            self.hline(x0, x1, y, c)

    def save(self, name):
        img = self.img.resize((self.s * SCALE, self.s * SCALE), Image.NEAREST)
        img.save(os.path.join(OUTDIR, name + ".png"))
        return img


def circle(cx, cy, r):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def ellipse(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def trap(cx, top, wt, wb, h):
    """Trapezoid slab: width wt at the top edge tapering to wb at the bottom."""

    def inside(x, y):
        if y < top or y > top + h:
            return False
        t = (y - top) / max(1.0, h)
        return abs(x - cx) <= (wt + (wb - wt) * t) / 2.0

    return inside


def capsule(x0, y0, x1, y1, r):
    """Rounded limb: every point within r of the segment (x0,y0)-(x1,y1)."""

    def inside(x, y):
        dx, dy = x1 - x0, y1 - y0
        l2 = dx * dx + dy * dy
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / l2))
        qx, qy = x0 + t * dx, y0 + t * dy
        return (x - qx) ** 2 + (y - qy) ** 2 <= r * r

    return inside


def profile(cx, y0, y1, half_widths):
    """Smooth vertical silhouette: half-width control points spread evenly
    over y0..y1 and cosine-eased between them — curves instead of slabs."""
    n = len(half_widths)

    def inside(x, y):
        if y < y0 or y > y1:
            return False
        t = (y - y0) / max(1e-6, float(y1 - y0)) * (n - 1)
        i = min(int(t), n - 2)
        f = (1.0 - math.cos((t - i) * math.pi)) * 0.5
        hw = half_widths[i] + (half_widths[i + 1] - half_widths[i]) * f
        return abs(x - cx) <= hw

    return inside


def star(cx, cy, r, points=8, inner=0.62):
    def inside(x, y):
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        if d < 0.001:
            return True
        wob = (math.cos(math.atan2(dy, dx) * points) + 1) / 2
        return d <= r * (inner + (1 - inner) * wob)

    return inside


def union(*fns):
    return lambda x, y: any(f(x, y) for f in fns)


# ---------------------------------------------------------------- face kit


def slit_eyes(px, cx, ey, gap, glow=(255, 84, 70), w=2):
    """Glowing slits under a heavy dark brow — the standard hostile face."""
    for s in (-1, 1):
        x = cx + s * gap
        px.hline(x - w // 2, x + (w - 1) // 2, ey, glow)
        px.hline(x - w // 2 - 1, x + (w - 1) // 2 + 1, ey - 1, DARK)


# ---------------------------------------------------------------- palette

C = {
    "scrapper": (255, 115, 77),
    "sparker": (255, 204, 77),
    "sentry": (242, 140, 64),
    "crusher": (255, 153, 64),
    "forgemaster": (217, 191, 166),
    "sporeling": (140, 230, 102),
    "mite": (179, 255, 140),
    "croaker": (89, 179, 89),
    "spitter": (179, 140, 242),
    "broodmother": (128, 204, 89),
    "wisp": (153, 204, 255),
    "blinker": (191, 140, 255),
    "husk": (115, 102, 179),
    "detonant": (255, 102, 191),
    "oracle": (128, 179, 255),
    "ranger": (89, 217, 255),
    "blitz": (255, 210, 62),
    "bastion": (154, 167, 192),
    "jinx": (255, 143, 208),
    "volt": (125, 242, 255),
    "boss": (177, 107, 255),
}


# ---------------------------------------------------------------- characters
# The five playables are PEOPLE and share one 48px rig — identical head
# size, eye line, shoulder line, stance and boot line — so the roster reads
# as a uniform cast. Silhouettes come from capsules and eased width
# profiles instead of slabs, and faces get multi-pixel eyes (white + iris
# column), lids, brows, a nose and a mouth so they read at arena zoom.

HERO_CX = 24

BUILDS = {  # torso half-widths, top to bottom: shoulders, chest, waist, hips
    "m": (8.4, 7.4, 5.8, 6.6),
    "f": (7.0, 6.0, 4.4, 6.9),
    "n": (7.6, 6.6, 5.2, 6.2),
}


def _person(skin, build, shirt, sleeves=None, gloves=None, legs=(52, 46, 66),
            hips=None, boots=(44, 38, 54), crop_y=31, back=None):
    """Shared 48px human rig; returns (px, cx, head_mask).

    Draw order: back layer (ponytails/scarf tails), legs, boots, hip
    garment, torso (down to crop_y), arms + hands, neck, head. Callers add
    outfit detail, hair and the face on top, so every character keeps the
    same proportions. sleeves/gloves default to bare skin.
    """
    px = Px(48)
    cx = HERO_CX
    bw = BUILDS[build] if isinstance(build, str) else tuple(build)
    if back:
        back(px)
    for s in (-1, 1):
        px.fill(capsule(cx + s * 3.2, 31.5, cx + s * 3.4, 42.0, 2.2), legs)
    for s in (-1, 1):
        bx = cx + s * 3.4
        px.rect(bx - 2, 42, bx + 2, 45, boots)
        px.hline(bx - 2, bx + 2, 42, tint(boots, 1.3))
        px.hline(bx - 2, bx + 2, 46, tint(boots, 0.6))
    px.fill(profile(cx, 29, 34, (bw[3] - 0.4, bw[3] + 0.2, bw[3] - 1.2)), hips or legs)
    pts = bw if crop_y >= 30 else (bw[0], bw[1], bw[2] + 0.6)
    px.fill(profile(cx, 19, crop_y, pts), shirt)
    for s in (-1, 1):
        px.fill(
            capsule(cx + s * (bw[0] - 0.5), 20.5, cx + s * (bw[0] + 1.1), 29.5, 1.7),
            sleeves or skin,
        )
        px.fill(circle(cx + s * (bw[0] + 1.5), 31.5, 1.9), gloves or skin)
    px.fill(capsule(cx, 15.0, cx, 17.5, 1.9), tint(skin, 0.84))  # neck
    head = ellipse(cx, 10, 5.9, 6.8)
    px.paint(head, skin)
    px.paint(lambda x, y: head(x, y) and y <= 6, tint(skin, 1.08))
    px.paint(lambda x, y: head(x, y) and y >= 14, tint(skin, 0.9))
    return px, cx, head


def _grip(px, x, y, c):
    """Repaint a hand over a just-drawn weapon so the fist holds it."""
    px.fill(circle(x, y, 1.9), c)


def _face48(px, cx, skin, eye=(84, 64, 52), brows=DARK, lash=False,
            heavy=False, mouth="soft", blush=None):
    """Readable face: 2x2 eyes with an iris column, lids, brows, nose, mouth."""
    lid = mix(brows, DARK, 0.5)
    for s in (-1, 1):
        ex = cx - 4 if s < 0 else cx + 2
        px.rect(ex, 10, ex + 1, 11, PALE)
        px.vline(ex + (1 if s < 0 else 0), 10, 11, eye)  # iris toward the nose
        px.hline(ex - 1, ex + 2, 9, lid)  # upper lid
        px.hline(ex, ex + 1, 7, brows)  # brow
        if heavy:
            px.hline(ex - 1, ex + 2, 8, brows)
        if lash:
            px.set(ex - 1 if s < 0 else ex + 2, 10, brows)
    px.set(cx, 13, tint(skin, 0.8))  # nose
    dark = tint(skin, 0.58)
    if mouth == "soft":
        px.hline(cx - 1, cx + 1, 15, dark)
    elif mouth == "smile":
        px.hline(cx - 1, cx + 1, 15, dark)
        px.dots([(cx - 2, 14), (cx + 2, 14)], dark)
    elif mouth == "smirk":
        px.hline(cx - 1, cx + 1, 15, dark)
        px.set(cx + 2, 14, dark)
    elif mouth == "grin":
        px.hline(cx - 2, cx + 2, 14, dark)
        px.hline(cx - 1, cx + 1, 15, (238, 238, 244))
    if blush:
        px.dots([(cx - 4, 13), (cx + 4, 13)], blush, 110)


def char_ranger():
    # Scout captain. Teal ponytail, cropped field jacket over a bare
    # midriff, fingerless gloves, long precision rifle.
    skin = (226, 178, 136)
    hair = (40, 160, 180)
    c = desat(C["ranger"], 0.12)

    def back(px):
        px.fill(capsule(HERO_CX - 6.5, 7, HERO_CX - 9, 20, 2.2), tint(hair, 0.78))
        px.fill(capsule(HERO_CX - 9, 20, HERO_CX - 7.5, 27, 1.4), tint(hair, 0.6))

    px, cx, head = _person(skin, "f", c, sleeves=tint(c, 0.9),
                           gloves=(58, 50, 68), crop_y=24, back=back)
    px.fill(profile(cx, 25, 29, (5.0, 4.7, 5.6)), skin)  # bare midriff
    px.set(cx, 28, tint(skin, 0.72))  # navel
    px.hline(cx - 6, cx + 6, 29, (48, 40, 56))  # low belt
    px.set(cx, 29, (216, 186, 96))
    px.hline(cx - 5, cx + 5, 19, tint(c, 1.22))  # collar
    px.vline(cx, 20, 24, tint(c, 0.68))  # zip
    px.dots([(cx - 3, 22), (cx + 3, 22)], tint(c, 0.8))  # pocket studs
    px.paint(lambda x, y: head(x, y) and y <= 6, hair)
    px.paint(lambda x, y: head(x, y) and y <= 8 and abs(x - cx) >= 4, hair)  # framing
    px.paint(lambda x, y: head(x, y) and y <= 9 and x >= cx + 4, hair)  # side sweep
    px.fill(circle(cx - 6.5, 6, 1.8), hair)  # ponytail knot
    px.dots([(cx - 3, 7), (cx + 3, 7)], hair)  # loose fringe
    px.dots([(cx - 1, 4), (cx, 4), (cx + 1, 5)], tint(hair, 1.24))  # shine
    _face48(px, cx, skin, eye=(96, 66, 44), lash=True, mouth="smile",
            blush=(232, 130, 110))
    px.vline(cx + 11, 5, 28, STEEL)  # rifle barrel
    px.vline(cx + 12, 8, 26, tint(STEEL, 0.72))
    px.set(cx + 11, 4, PALE)  # muzzle glint
    px.hline(cx + 10, cx + 12, 14, tint(STEEL, 0.6))  # sight block
    px.rect(cx + 10, 26, cx + 12, 31, (108, 80, 56))  # stock
    px.dots([(cx + 8, 21), (cx + 5, 23), (cx + 2, 25)], (70, 58, 62))  # sling
    _grip(px, cx + 8.5, 31.5, (58, 50, 68))
    px.outline()
    return px


def char_blitz():
    # Duelist. Spiked blond hair, red scarf, sleeveless vest, bare arms,
    # twin daggers held low.
    skin = (238, 196, 158)
    hair = (230, 196, 90)
    c = desat(C["blitz"], 0.12)

    def back(px):
        px.fill(capsule(HERO_CX - 7, 18, HERO_CX - 12, 14.5, 1.5), (198, 72, 58))
        px.dots([(HERO_CX - 13, 13), (HERO_CX - 13, 14)], (172, 60, 50))

    px, cx, head = _person(skin, "m", c, legs=(54, 48, 66), back=back)
    px.paint(lambda x, y: 19 <= y <= 21 and abs(x - cx) <= 21 - y, skin)  # V-neck
    px.vline(cx - 4, 20, 28, tint(c, 0.66))  # vest edges
    px.vline(cx + 4, 20, 28, tint(c, 0.66))
    px.hline(cx - 6, cx + 6, 30, (48, 40, 56))  # belt
    px.set(cx, 30, (216, 186, 96))
    px.dots([(cx - 8, 20), (cx + 8, 20)], tint(skin, 1.14))  # deltoid light
    for s in (-1, 1):  # forearm wraps
        ax = cx + s * 9
        px.rect(ax - 1, 26, ax + 1, 28, (76, 66, 86))
    px.hline(cx - 4, cx + 4, 17, (222, 88, 70))  # scarf
    px.hline(cx - 4, cx + 4, 18, (198, 72, 58))
    px.paint(lambda x, y: head(x, y) and y <= 6, hair)
    for dx, top in ((-5, 5), (-3, 3), (-1, 2), (1, 1), (3, 2), (5, 4)):  # spikes
        px.vline(cx + dx, top, 6, hair)
    px.dots([(cx - 3, 4), (cx, 3), (cx + 1, 2)], tint(hair, 1.22))
    px.hline(cx - 4, cx + 4, 6, tint(hair, 0.82))  # under-shade
    _face48(px, cx, skin, eye=(74, 108, 66), mouth="grin")
    for s in (-1, 1):  # daggers angled down-out
        hx = cx + s * 9.9
        _grip(px, hx, 31.5, skin)
        px.set(int(hx + s * 2), 31, (216, 186, 96))  # guard
        for i in range(4):
            px.set(int(hx + s * (2 + i)), 32 + i, (218, 226, 238))
        px.set(int(hx + s * 6), 36, PALE)  # tip
    px.outline()
    return px


def char_bastion():
    # Veteran wall. Dark-skinned and bald with a grey beard and a scarred
    # brow; plate cuirass, round pauldrons, tower shield and arming sword.
    skin = (150, 104, 72)
    beard = (192, 188, 182)
    c = desat(C["bastion"], 0.12)
    px, cx, head = _person(skin, (9.0, 8.0, 6.2, 7.0), c, sleeves=tint(c, 0.8),
                           gloves=tint(c, 0.94), legs=(58, 56, 66), boots=(52, 50, 62))
    px.vline(cx, 19, 28, tint(c, 1.14))  # cuirass ridge
    px.hline(cx - 6, cx + 6, 26, tint(c, 0.62))  # waist plates
    px.hline(cx - 5, cx + 5, 29, tint(c, 0.62))
    px.dots([(cx - 4, 21), (cx + 4, 21), (cx - 5, 24), (cx + 5, 24)], tint(c, 0.55))
    for s in (-1, 1):  # round pauldrons
        px.fill(circle(cx + s * 8.8, 20.5, 2.7), tint(c, 1.1))
        px.set(int(cx + s * 8.8), 23, tint(c, 0.6))
    px.dots([(cx - 2, 4), (cx - 1, 4), (cx, 4), (cx - 3, 5)], tint(skin, 1.2))  # shine
    px.paint(lambda x, y: head(x, y) and y >= 14, beard)
    px.fill(ellipse(cx, 16.5, 3.4, 2.2), beard)  # full jaw
    px.hline(cx - 2, cx + 2, 18, tint(beard, 0.8))
    _face48(px, cx, skin, eye=(58, 50, 46), brows=(126, 122, 118), heavy=True,
            mouth="hidden")
    px.hline(cx - 1, cx + 1, 14, tint(beard, 1.12))  # mustache
    px.dots([(cx + 3, 6), (cx + 3, 8)], tint(skin, 1.35))  # brow scar
    sh = profile(cx - 12.5, 13, 33, (2.4, 3.1, 3.1, 2.5))  # tower shield
    px.fill(sh, tint(c, 1.06))
    px.paint(
        lambda x, y: sh(x, y) and 15 <= y <= 31 and abs(x - (cx - 12.5)) <= 1.6,
        tint(c, 0.8),
    )
    px.dots(
        [(cx - 14, 19), (cx - 13, 20), (cx - 12, 21), (cx - 11, 20), (cx - 10, 19)],
        tint(c, 1.24),
    )  # chevron
    px.vline(cx + 11, 8, 27, (216, 224, 236))  # sword
    px.vline(cx + 12, 9, 26, (166, 174, 188))
    px.set(cx + 11, 7, PALE)
    px.hline(cx + 9, cx + 13, 28, (216, 186, 96))  # crossguard
    _grip(px, cx + 10.5, 31.5, tint(c, 0.94))
    px.set(cx + 11, 34, (216, 186, 96))  # pommel
    px.outline()
    return px


def char_jinx():
    # Trickster gambler. Long magenta waves over one eye, off-shoulder top,
    # flared gold-trimmed skirt, spinning coin and a palmed card.
    skin = (240, 190, 150)
    hair = (218, 74, 142)
    c = desat(C["jinx"], 0.12)

    def back(px):
        for s, y1 in ((-1, 27), (1, 25)):  # waves down both sides
            px.fill(
                capsule(HERO_CX + s * 6, 8, HERO_CX + s * 7.5, y1, 2.0),
                tint(hair, 0.76),
            )
            px.dots(
                [(HERO_CX + s * 9, y1 - 2), (HERO_CX + s * 8, y1 + 1)], tint(hair, 0.6)
            )

    px, cx, head = _person(skin, "f", c, legs=skin, hips=tint(c, 0.7),
                           boots=(60, 40, 72), back=back)
    px.paint(lambda x, y: 19 <= y <= 20 and -7 <= x - cx <= -2, skin)  # bare shoulder
    px.hline(cx - 7, cx - 2, 21, tint(c, 1.24))  # slanted neckline
    px.hline(cx - 2, cx + 6, 19, tint(c, 1.24))
    px.fill(profile(cx, 29, 35, (6.6, 7.6, 8.8)), tint(c, 0.7))  # flared skirt
    px.hline(cx - 8, cx + 8, 35, (232, 196, 100))  # gold hem
    px.hline(cx - 6, cx + 6, 29, tint(c, 0.5))  # waistband
    px.hline(cx + 2, cx + 5, 37, (120, 60, 100))  # thigh band
    for s in (-1, 1):  # bracelets
        px.set(int(cx + s * 8.5), 29, (232, 196, 100))
    _face48(px, cx, skin, eye=(128, 60, 132), lash=True, mouth="smirk",
            blush=(236, 122, 112))
    px.set(cx + 4, 14, tint(skin, 0.62))  # beauty mark
    px.paint(lambda x, y: head(x, y) and y <= 6, hair)  # crown
    px.paint(lambda x, y: head(x, y) and x <= cx - 1 and y <= 12, hair)  # deep bang
    px.dots([(cx, 8), (cx + 1, 7), (cx - 1, 10)], hair)  # bang sweep
    px.dots([(cx - 5, 13), (cx - 4, 14), (cx - 2, 13)], tint(hair, 0.84))  # bang tips
    px.dots([(cx - 2, 4), (cx - 1, 3)], tint(hair, 1.24))  # shine
    px.fill(circle(cx + 10, 26, 1.6), (240, 202, 96))  # coin
    px.set(cx + 10, 26, (255, 240, 180))
    px.dots([(cx + 10, 23), (cx + 12, 26), (cx + 8, 26)], (255, 240, 180), 150)
    px.rect(cx - 13, 27, cx - 11, 30, PALE)  # thrown card
    px.set(cx - 12, 28, (204, 64, 64))
    px.outline()
    return px


def char_volt():
    # Arcanist. White undercut over shaved sides, high-collared storm coat
    # with lit seams, orb staff. Deliberately androgynous.
    skin = (216, 208, 214)
    hair = (240, 246, 252)
    c = desat(C["volt"], 0.12)
    glow = mix(c, PALE, 0.55)
    px, cx, head = _person(skin, "n", tint(c, 0.72), sleeves=tint(c, 0.62),
                           gloves=(58, 52, 72), legs=(50, 46, 64), hips=tint(c, 0.66))
    px.fill(profile(cx, 30, 40, (6.4, 6.0, 5.0)), tint(c, 0.66))  # coat skirt
    px.vline(cx, 32, 40, (46, 42, 60))  # center split
    for s in (-1, 1):  # lit seams
        px.vline(cx + s * 3, 21, 37, glow)
    px.dots([(cx, 22), (cx - 1, 23), (cx, 24), (cx - 1, 25)], (255, 250, 190))  # bolt
    px.hline(cx - 4, cx + 4, 17, tint(c, 0.9))  # high collar
    px.hline(cx - 3, cx + 3, 18, tint(c, 0.9))
    px.paint(lambda x, y: head(x, y) and y <= 6, (94, 102, 118))  # shaved sides
    px.paint(lambda x, y: head(x, y) and y <= 6 and x <= cx + 1, hair)  # swept top
    px.dots([(cx - 5, 7), (cx - 6, 8), (cx - 4, 7)], hair)  # falling lock
    _face48(px, cx, skin, eye=(120, 235, 255), brows=(96, 104, 118), mouth="soft")
    px.vline(cx - 11, 6, 33, (104, 80, 58))  # staff
    px.vline(cx - 11, 13, 20, (124, 98, 72))  # grain light
    px.dots([(cx - 12, 5), (cx - 10, 5)], (104, 80, 58))  # fork
    px.glow(circle(cx - 11, 3, 1.4), glow, 2, 90)
    px.fill(circle(cx - 11, 3, 1.6), glow)  # orb
    px.set(cx - 11, 3, PALE)
    px.dots([(cx - 13, 2), (cx - 9, 1)], glow, 150)  # static
    _grip(px, cx - 9.1, 31.5, (58, 52, 72))
    px.outline()
    return px


# ---------------------------------------------------------------- enemies


def enemy_scrapper():
    px, c = Px(24), desat(C["scrapper"])
    px.fill(trap(12, 6, 17, 13, 10), c)  # angular hull
    px.hline(6, 18, 10, tint(c, 0.55))  # plate seam
    px.rect(4, 17, 19, 20, tint(c, 0.42))  # tracked base
    px.dots([(6, 20), (10, 20), (14, 20), (18, 20)], DARK)
    px.hline(10, 14, 8, DARK)  # single sensor slit
    px.dots([(12, 8)], (255, 96, 70))
    px.vline(12, 2, 4, tint(c, 0.7))
    px.set(12, 1, (255, 120, 80))
    px.outline()
    return px


def enemy_sparker():
    px, c = Px(22), desat(C["sparker"])
    px.fill(trap(11, 6, 13, 5, 12), c)  # arc drone, tapering down
    for sx in (7, 15):  # tesla prongs
        px.vline(sx, 2, 5, tint(c, 0.7))
        px.set(sx, 1, PALE)
    px.set(11, 3, mix(c, PALE, 0.6))  # arc between prongs
    slit_eyes(px, 11, 9, 3, (255, 240, 160))
    px.dots([(11, 19), (9, 18), (13, 18)], tint(c, 0.6))  # exhaust
    px.outline()
    return px


def enemy_sentry():
    px, c = Px(24), desat(C["sentry"])
    px.fill(trap(12, 8, 18, 14, 9), c)  # pillbox
    px.hline(4, 20, 11, tint(c, 0.55))
    px.hline(8, 16, 7, DARK)
    px.dots([(12, 7)], (255, 96, 70))  # targeting slit
    px.rect(17, 12, 22, 13, tint(c, 0.5))  # side cannon
    px.set(23, 12, DARK)
    for sx in (6, 12, 18):  # bolted legs
        px.vline(sx, 17, 20, tint(c, 0.45))
    px.outline()
    return px


def enemy_crusher():
    px, c = Px(30), desat(C["crusher"])
    px.fill(trap(15, 6, 25, 13, 16), c)  # hulking chassis
    px.hline(4, 26, 10, tint(c, 0.55))  # shoulder seam
    px.hline(8, 22, 16, tint(c, 0.55))
    slit_eyes(px, 15, 8, 3, (255, 84, 60))
    for sx in (3, 24):  # square fists
        px.rect(sx, 16, sx + 3, 20, tint(c, 0.85))
        px.hline(sx, sx + 3, 17, tint(c, 1.1))
    for sx in (9, 19):  # legs
        px.rect(sx, 23, sx + 2, 26, tint(c, 0.45))
    px.dots([(8, 3), (22, 3), (7, 4), (23, 4)], tint(c, 1.2))  # antenna horns
    px.outline()
    return px


def enemy_forgemaster():
    px, c = Px(30), desat(C["forgemaster"])
    px.fill(trap(15, 11, 21, 13, 11), c)  # plated bulk
    px.hline(6, 24, 15, tint(c, 0.55))
    px.dots([(9, 13), (15, 13), (21, 13)], tint(c, 0.5))  # rivets
    head = circle(15, 7, 4)
    px.fill(head, tint(c, 1.0))
    px.rect(11, 1, 19, 3, tint(c, 0.55))  # anvil crest
    px.hline(12, 18, 8, DARK)
    px.dots([(13, 8), (17, 8)], (150, 235, 255))  # cold visor glow
    px.vline(26, 6, 20, (96, 74, 52))  # war hammer
    px.rect(24, 4, 28, 7, (150, 156, 172))
    for sx in (11, 18):
        px.rect(sx, 23, sx + 1, 26, tint(c, 0.45))
    px.outline()
    return px


def enemy_sporeling():
    px, c = Px(24), desat(C["sporeling"])
    # drooping, asymmetric cap
    px.fill(trap(12, 3, 10, 20, 6), c)
    px.hline(2, 21, 9, tint(c, 0.5))
    px.dots([(6, 5), (15, 4), (18, 7)], tint(c, 0.55))  # dull spots
    px.fill(trap(12, 10, 9, 7, 9), mix(SKIN, c, 0.35))  # gnarled stem
    slit_eyes(px, 12, 14, 2, (190, 255, 130))
    px.dots([(3, 2), (20, 3), (9, 1)], tint(c, 0.8), 160)  # drifting spores
    for sx in (9, 14):  # root feet
        px.rect(sx, 19, sx + 1, 21, tint(c, 0.4))
    px.outline()
    return px


def enemy_mite():
    px, c = Px(16), desat(C["mite"])
    px.fill(trap(8, 5, 11, 8, 7), c)
    px.dots([(4, 3), (8, 2), (12, 3)], tint(c, 1.2))  # dorsal spikes
    for sx in (2, 4, 11, 13):
        px.set(sx, 13, tint(c, 0.5))
    slit_eyes(px, 8, 8, 2, (255, 96, 70), 1)
    px.outline()
    return px


def enemy_croaker():
    px, c = Px(26), desat(C["croaker"])
    px.fill(trap(13, 8, 20, 16, 12), c)  # war-toad bulk
    px.hline(4, 22, 7, tint(c, 0.6))  # heavy brow ridge
    slit_eyes(px, 13, 9, 5, (255, 196, 90))
    px.hline(9, 17, 15, tint(c, 0.45))  # grim mouth
    px.dots([(6, 12), (19, 11), (16, 13)], tint(c, 0.6))  # warts
    for sx in (3, 20):  # haunches
        px.rect(sx, 16, sx + 2, 21, tint(c, 0.8))
        px.rect(sx, 21, sx + 3, 22, tint(c, 0.5))
    px.outline()
    return px


def enemy_spitter():
    px, c = Px(26), desat(C["spitter"])
    px.fill(trap(13, 3, 16, 8, 12), c)  # flared cobra hood
    px.fill(trap(13, 15, 10, 14, 7), tint(c, 0.8))  # coiled base
    px.hline(9, 17, 6, tint(c, 0.55))
    slit_eyes(px, 13, 8, 3, (255, 196, 90))
    for sx in (11, 15):  # long fangs
        px.vline(sx, 11, 13, PALE)
    px.dots([(13, 12)], tint(c, 0.4))
    px.outline()
    return px


def enemy_broodmother():
    px, c = Px(32), desat(C["broodmother"])
    # segmented chitin dome
    px.fill(trap(16, 4, 14, 24, 7), c)
    px.fill(trap(16, 11, 26, 22, 8), tint(c, 0.92))
    px.fill(trap(16, 19, 22, 16, 7), tint(c, 0.8))
    px.dots([(8, 3), (16, 2), (24, 3)], tint(c, 1.2))  # ridge spikes
    px.hline(5, 27, 11, tint(c, 0.5))
    px.hline(6, 26, 19, tint(c, 0.5))
    slit_eyes(px, 16, 15, 4, (216, 255, 140))
    for (ex, ey) in ((8, 27), (16, 29), (24, 27)):  # dull egg sacs
        px.fill(circle(ex, ey, 2), mix(c, (70, 80, 60), 0.35))
    px.outline()
    return px


def enemy_wisp():
    px, c = Px(22), desat(C["wisp"], 0.1)
    shroud = trap(11, 4, 7, 17, 14)
    px.glow(shroud, c, 2, 60)
    px.fill(shroud, c)
    for i, sx in enumerate((5, 8, 11, 14, 17)):  # tattered hem
        px.vline(sx, 18, 19 + (i % 2), tint(c, 0.7))
    px.dots([(8, 9), (14, 9)], (40, 60, 110))  # hollow sockets
    px.dots([(8, 10), (14, 10)], PALE)
    px.outline((40, 60, 110, 255))
    return px


def enemy_blinker():
    px, c = Px(24), desat(C["blinker"], 0.1)
    body = trap(12, 6, 18, 8, 12)
    px.glow(body, c, 2, 60)
    px.fill(body, c)
    px.hline(6, 18, 9, tint(c, 0.5))  # eyelid line
    px.fill(circle(12, 12, 3), (232, 236, 248))  # single eye
    px.vline(12, 10, 13, (48, 24, 84))  # slit pupil
    for s in (-1, 1):  # wing barbs
        px.dots([(12 + s * 10, 7), (12 + s * 11, 5)], tint(c, 0.8))
    px.outline((50, 30, 90, 255))
    return px


def enemy_husk():
    px, c = Px(26), desat(C["husk"])
    px.fill(trap(13, 4, 17, 13, 14), c)  # obsidian torso
    for sx in (7, 15):
        px.rect(sx, 19, sx + 3, 23, tint(c, 0.6))  # slab legs
    crack = [(13, 5), (12, 7), (13, 9), (14, 11), (13, 13), (12, 15)]
    px.dots(crack, tint(c, 0.35))
    px.dots([(9, 8), (17, 8)], DARK)  # deep sockets
    px.dots([(9, 9), (17, 9)], (140, 230, 255))
    px.outline()
    return px


def enemy_detonant():
    px, c = Px(26), desat(C["detonant"], 0.1)
    px.glow(circle(13, 12, 8), c, 2, 80)
    px.fill(star(13, 12, 12, 8, 0.68), c)
    px.hline(8, 18, 15, tint(c, 0.45))  # hazard band
    px.dots([(10, 15), (13, 15), (16, 15)], (60, 50, 40))
    slit_eyes(px, 13, 10, 3, (255, 240, 160))
    px.dots([(13, 13)], (255, 230, 150))  # armed core
    for sx in (10, 16):
        px.rect(sx - 1, 21, sx, 23, tint(c, 0.55))
    px.outline((90, 24, 60, 255))
    return px


def enemy_oracle():
    px, c = Px(26), desat(C["oracle"], 0.1)
    robe = trap(13, 3, 9, 19, 20)
    px.glow(robe, c, 2, 55)
    px.fill(robe, c)
    px.dots([(7, 8), (19, 8)], tint(c, 1.15))  # shoulder points
    px.paint(lambda x, y: trap(13, 4, 7, 9, 6)(x, y) and y >= 5, (24, 28, 48))  # hood void
    px.dots([(13, 8)], (200, 230, 255))  # single seer light
    px.hline(9, 17, 17, tint(c, 0.6))  # rope belt
    for sx in (8, 13, 18):  # ragged hem
        px.vline(sx, 22, 23, tint(c, 0.6))
    px.dots([(3, 6), (23, 6)], mix(c, PALE, 0.5))  # floating runes
    px.outline((40, 50, 100, 255))
    return px


def boss_sprite():
    px, c = Px(56), desat(C["boss"], 0.12)
    px.glow(circle(28, 28, 20), c, 3, 50)
    px.fill(trap(28, 18, 44, 22, 28), c)  # warlord bulk
    px.hline(10, 46, 26, tint(c, 0.55))  # plate lines
    px.hline(14, 42, 34, tint(c, 0.55))
    for sx in (6, 44):  # spiked pauldrons
        px.rect(sx, 16, sx + 6, 21, tint(c, 1.1))
        px.dots([(sx + 1, 15), (sx + 4, 14)], tint(c, 1.25))
    head = trap(28, 6, 16, 12, 10)
    px.fill(head, tint(c, 1.05))
    px.paint(lambda x, y: trap(28, 9, 12, 9, 6)(x, y), (30, 22, 44))  # skull shadow
    slit_eyes(px, 28, 11, 3, (255, 84, 84), 3)
    for i, tx in enumerate(range(24, 33, 2)):  # jagged jaw
        px.set(tx, 14 + (i % 2), PALE)
    for s in (-1, 1):  # tall stepped horns
        hx = 28 + s * 10
        px.vline(hx, 2, 6, tint(c, 1.2))
        px.vline(hx + s * 2, 0, 3, tint(c, 1.35))
    for sx in (4, 47):  # clawed fists
        px.rect(sx, 36, sx + 4, 41, tint(c, 0.85))
        px.dots([(sx, 35), (sx + 2, 34), (sx + 4, 35)], PALE)
    for (x, y) in px.mask_pixels(trap(28, 30, 6, 6, 6)):  # chest core
        px.set(x, y, mix(c, PALE, 0.5))
    px.set(28, 31, PALE)
    for sx in (20, 33):
        px.rect(sx, 46, sx + 3, 50, tint(c, 0.5))  # legs
    px.outline((36, 20, 60, 255))
    return px


# ---------------------------------------------------------------- props


def bullet(c):
    px = Px(12)
    px.glow(circle(6, 6, 3), c, 2, 110)
    px.fill(circle(6, 6, 4), c)
    px.dots([(5, 5)], PALE)
    px.outline(tuple(tint(c, 0.3)) + (255,))
    return px


def ball_sprite():
    px, c = Px(14), (255, 214, 77)
    px.glow(circle(7, 7, 4), c, 2, 100)
    px.fill(circle(7, 7, 5), c)
    px.dots([(5, 5), (6, 4)], (255, 250, 220))
    px.outline((120, 80, 20, 255))
    return px


def gate_frame():
    w, h = 88, 30
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = (235, 235, 245, 255)
    dim = (150, 150, 170, 255)
    d.rounded_rectangle([1, 1, w - 2, h - 2], radius=6, outline=base, width=2)
    d.rounded_rectangle([3, 3, w - 4, h - 4], radius=5, outline=(90, 90, 110, 120), width=1)
    for (x0, x1) in [(0, 5), (w - 6, w - 1)]:
        d.rectangle([x0, 2, x1, h - 3], fill=dim)
        d.rectangle([x0, 2, x1, 6], fill=base)
    img = img.resize((w * SCALE, h * SCALE), Image.NEAREST)
    img.save(os.path.join(OUTDIR, "gate_frame.png"))
    return img


ENEMIES = {
    "scrapper": enemy_scrapper,
    "sparker": enemy_sparker,
    "sentry": enemy_sentry,
    "crusher": enemy_crusher,
    "forgemaster": enemy_forgemaster,
    "sporeling": enemy_sporeling,
    "mite": enemy_mite,
    "croaker": enemy_croaker,
    "spitter": enemy_spitter,
    "broodmother": enemy_broodmother,
    "wisp": enemy_wisp,
    "blinker": enemy_blinker,
    "husk": enemy_husk,
    "detonant": enemy_detonant,
    "oracle": enemy_oracle,
}

CHARS = {
    "ranger": char_ranger,
    "blitz": char_blitz,
    "bastion": char_bastion,
    "jinx": char_jinx,
    "volt": char_volt,
}


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    made = {}
    for kind, fn in ENEMIES.items():
        made["enemy_" + kind] = fn().save("enemy_" + kind)
    for cid, fn in CHARS.items():
        made["char_" + cid] = fn().save("char_" + cid)
    made["boss"] = boss_sprite().save("boss")
    made["bullet_player"] = bullet((255, 237, 140)).save("bullet_player")
    made["bullet_enemy"] = bullet((255, 115, 140)).save("bullet_enemy")
    made["ball"] = ball_sprite().save("ball")
    made["gate_frame"] = gate_frame()

    names = sorted(made.keys())
    cols, cell = 6, 130
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell + 10), (11, 14, 26, 255))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        img = made[name]
        cx = (i % cols) * cell + cell // 2
        cy = (i // cols) * cell + 52
        f = min(1.0, 96 / max(img.size))
        if f < 1.0:
            img = img.resize((int(img.width * f), int(img.height * f)), Image.NEAREST)
        sheet.alpha_composite(img, (cx - img.width // 2, cy - img.height // 2))
        d.text((cx, cy + 58), name, fill=(200, 210, 235), anchor="mm")
    sheet.save(os.path.join(OUTDIR, "sheet_preview.png"))
    print("wrote %d sprites -> %s" % (len(made) + 1, os.path.normpath(OUTDIR)))


if __name__ == "__main__":
    main()
