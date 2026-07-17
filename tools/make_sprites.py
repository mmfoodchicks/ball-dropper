#!/usr/bin/env python3
"""Procedural pixel-art sprite generator for Orbfall Arena.

Regenerate all sprites:      python3 tools/make_sprites.py
Output:                      assets/sprites/*.png  (+ sheet_preview.png)

Style: enemies are gritty angular slabs with glowing slit eyes under
heavy brows; the five playables are chunky 3/4-view heroes on one shared
48px rig — big bold hair masses with a top-light band, simple dark-pixel
eyes on a lit face, action stances with oversized weapons, kept tasteful.
All original designs, deterministic, upscaled x4
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
# Chunky-hero style (the direction the user picked): 3/4-view figures
# facing right in an action stance, big bold hair masses with a bright
# top-light band, compact bodies, simple dark-pixel eyes on a lit face,
# oversized weapons. One shared rig — same head, eye line, torso and leg
# stance — keeps the five reading as a uniform cast. In-game the hero
# sprite flips horizontally to face the aim direction.

CHK_CX = 22  # body/head axis; weapons and poses extend to the right


def _chunk(skin, shirt, pants, boots, torso_hw=(6.0, 5.6, 4.8, 5.6), crop_y=30):
    """Shared chunky rig; returns (px, head_mask).

    Draw order: back leg + boot (darkened), pelvis, front leg + boot,
    torso (to crop_y), neck shadow, big head with a profile nose. Callers
    layer outfit, arms, hair and face on top in that order.
    """
    px = Px(48)
    px.fill(capsule(19, 29.5, 18, 35, 2.1), tint(pants, 0.72))
    px.rect(15, 35, 20, 38, tint(boots, 0.75))
    px.set(21, 37, tint(boots, 0.75))  # toe
    px.hline(15, 21, 38, tint(boots, 0.5))  # sole
    px.fill(profile(CHK_CX, 28, 32, (5.4, 5.2, 4.2)), pants)
    px.fill(capsule(25, 29.5, 26, 36, 2.1), pants)
    px.rect(23, 36, 28, 39, boots)
    px.set(29, 38, boots)  # toe
    px.hline(23, 29, 39, tint(boots, 0.55))  # sole
    px.fill(profile(CHK_CX, 19, crop_y, torso_hw), shirt)
    px.fill(capsule(CHK_CX, 17.0, CHK_CX, 19.5, 2.0), tint(skin, 0.8))  # neck
    head = ellipse(CHK_CX, 12, 7.2, 7.0)
    px.paint(head, skin)
    px.paint(lambda x, y: head(x, y) and y >= 16, tint(skin, 0.9))
    px.set(29, 14, skin)  # profile nose
    px.set(29, 15, tint(skin, 0.84))
    return px, head


def _eyes(px, c=(24, 20, 34), one=False):
    """Simple 1x2 dark eyes at the shared eye line; `one` for a bang-covered
    back eye."""
    px.vline(27, 12, 13, c)
    if not one:
        px.vline(24, 12, 13, c)


def _mass(px, mask, base, top=True):
    """Punchy hair/cloth shading: flat base, deep 2px bottom shadow, then a
    bright 2px band following the top of the silhouette (skip for masses
    that sit mid-figure, like beards, where a light band reads wrong)."""
    px.paint(mask, base)
    pts = px.mask_pixels(mask)
    for (x, y) in pts:
        if not mask(x, y + 2):
            px.set(x, y, tint(base, 0.6))
    if top:
        for (x, y) in pts:
            if not mask(x, y - 2):
                px.set(x, y, tint(base, 1.35))


def char_ranger():
    # Scout captain: teal bob + ponytail, cropped jacket, bare midriff,
    # levelled precision rifle held in both hands.
    skin = (226, 178, 136)
    hair = (42, 168, 188)
    c = desat(C["ranger"], 0.12)
    px, head = _chunk(skin, c, (50, 46, 64), (40, 62, 74), crop_y=25)
    px.fill(profile(CHK_CX, 25, 28, (4.8, 4.9, 5.2)), skin)  # bare midriff
    px.set(CHK_CX, 27, tint(skin, 0.7))  # navel
    px.hline(17, 27, 28, (48, 40, 56))  # low belt
    px.set(CHK_CX, 28, (216, 186, 96))
    px.hline(18, 26, 19, tint(c, 1.2))  # collar
    px.vline(CHK_CX, 20, 24, tint(c, 0.68))  # zip
    px.fill(capsule(19, 21.5, 25, 24, 1.5), tint(c, 0.62))  # back arm
    hm = union(
        lambda x, y: head(x, y) and (y <= 8 or x <= 18),
        ellipse(15, 8, 4.0, 3.6),  # bob volume
        capsule(13, 9, 11, 21, 2.4),  # ponytail
        capsule(11, 21, 12, 27, 1.5),  # tail tip
    )
    _mass(px, hm, hair)
    px.dots([(21, 9), (24, 9), (26, 9)], hair)  # fringe tips
    px.hline(20, 28, 10, tint(skin, 0.78))  # fringe shadow
    _eyes(px)
    px.dots([(21, 15), (28, 16)], (232, 130, 110), 100)  # blush
    px.hline(26, 41, 22, STEEL)  # rifle, held level
    px.hline(28, 40, 23, tint(STEEL, 0.7))
    px.set(42, 22, PALE)  # muzzle
    px.set(33, 21, tint(STEEL, 0.8))  # sight
    px.rect(22, 21, 25, 24, (108, 80, 56))  # stock
    px.fill(capsule(25, 22, 30, 24.5, 1.5), tint(c, 0.9))  # front arm
    px.fill(circle(31, 24, 1.7), (58, 50, 68))  # gloves on the grip
    px.fill(circle(26, 24.5, 1.6), (58, 50, 68))
    px.outline()
    return px


def char_blitz():
    # Duelist: swept-back blond spikes, scarf streaming behind, gold vest,
    # low lunge with a dagger forward and one reversed behind.
    skin = (238, 196, 158)
    hair = (232, 198, 92)
    c = desat(C["blitz"], 0.12)
    px, head = _chunk(skin, c, (54, 48, 66), (70, 58, 76))
    px.paint(lambda x, y: 19 <= y <= 21 and abs(x - CHK_CX) <= 21 - y, skin)  # V-neck
    px.vline(18, 20, 27, tint(c, 0.66))  # vest edges
    px.vline(26, 20, 27, tint(c, 0.66))
    px.hline(17, 27, 28, (48, 40, 56))  # belt
    px.set(CHK_CX, 28, (216, 186, 96))
    px.fill(capsule(19, 21.5, 14, 26, 1.5), tint(skin, 0.8))  # back arm
    px.fill(circle(13.5, 27, 1.6), tint(skin, 0.8))
    px.set(12, 27, (216, 186, 96))  # reversed dagger behind
    px.dots([(11, 28), (10, 29)], (214, 222, 236))
    sc = union(capsule(18, 18.5, 26, 18.5, 1.4), capsule(17, 18, 10, 14, 2.0))
    _mass(px, sc, (210, 80, 62))  # scarf + streaming tail
    hm = union(
        lambda x, y: head(x, y) and (y <= 8 or x <= 17),
        capsule(16, 5, 11, 2.5, 1.8),  # swept-back spikes
        capsule(15, 8, 10, 6.5, 1.6),
        capsule(15, 11, 11, 11, 1.4),
        capsule(20, 4, 24, 2.5, 1.7),  # front spike
    )
    _mass(px, hm, hair)
    px.dots([(10, 2), (9, 7), (22, 9), (25, 9)], hair)  # spike + fringe tips
    px.hline(20, 28, 10, tint(skin, 0.78))  # fringe shadow
    _eyes(px)
    px.set(25, 16, tint(skin, 0.55))  # grin
    px.set(26, 16, (242, 242, 246))  # tooth glint
    px.fill(capsule(25, 21.5, 30, 26.5, 1.6), skin)  # front arm, lunging low
    px.fill(circle(30.5, 27, 1.7), skin)
    px.set(31, 26, (216, 186, 96))  # guard
    for i in range(4):  # blade forward-down
        px.set(32 + i, 28 + i, (218, 226, 238))
    px.set(36, 32, PALE)  # tip
    px.outline()
    return px


def char_bastion():
    # Veteran wall: bald, grey-bearded, scarred brow; sword shouldered
    # behind, tower shield braced in front.
    skin = (150, 104, 72)
    beard = (196, 192, 186)
    c = desat(C["bastion"], 0.12)
    px, head = _chunk(skin, c, (58, 56, 66), (52, 50, 62),
                      torso_hw=(6.6, 6.2, 5.4, 6.0))
    px.vline(CHK_CX, 19, 27, tint(c, 1.15))  # cuirass ridge
    px.hline(17, 27, 25, tint(c, 0.62))  # waist plate
    px.dots([(19, 21), (25, 21), (18, 24), (26, 24)], tint(c, 0.55))  # rivets
    px.hline(17, 27, 28, (48, 42, 52))
    px.fill(circle(16.5, 20, 2.9), tint(c, 1.08))  # back pauldron
    for i in range(9):  # sword shouldered up-back
        px.set(15 - i, 17 - i, (214, 222, 236))
        px.set(16 - i, 17 - i, (166, 174, 188))
    px.set(6, 8, PALE)  # tip glint
    px.set(15, 18, (216, 186, 96))  # guard
    px.dots([(20, 6), (21, 6), (22, 7)], tint(skin, 1.2))  # crown shine
    bm = union(
        lambda x, y: head(x, y) and y >= 15 and x >= 19,
        ellipse(25, 18, 4.2, 2.6),
    )
    _mass(px, bm, beard, top=False)  # full beard, no light band mid-face
    px.hline(23, 28, 11, (128, 124, 120))  # heavy brow bar
    _eyes(px)
    px.dots([(26, 9), (26, 10)], tint(skin, 1.32))  # brow scar
    px.set(26, 11, skin)  # scar notches the brow
    sh = profile(31, 16, 34, (2.8, 3.5, 3.5, 2.7))  # tower shield, braced
    px.fill(sh, tint(c, 1.05))
    px.paint(
        lambda x, y: sh(x, y) and abs(x - 31) <= 1.6 and 18 <= y <= 32,
        tint(c, 0.8),
    )
    px.dots([(29, 21), (30, 22), (31, 23), (32, 22), (33, 21)], tint(c, 1.24))
    px.fill(capsule(25, 22, 28, 25, 1.6), tint(c, 0.8))  # front arm to shield
    px.outline()
    return px


def char_jinx():
    # Trickster gambler: huge magenta waves with a bang over the back eye,
    # off-shoulder top, flared skirt, tall boots, coin toss mid-flip.
    skin = (240, 190, 150)
    hair = (222, 78, 148)
    c = desat(C["jinx"], 0.12)
    bc = (66, 44, 78)
    px, head = _chunk(skin, c, skin, bc, torso_hw=(5.6, 5.2, 4.4, 5.4))
    px.rect(23, 34, 28, 35, bc)  # tall boot cuffs over bare legs
    px.rect(15, 33, 20, 34, tint(bc, 0.75))
    px.fill(profile(CHK_CX, 26, 30, (5.6, 6.2, 7.0)), tint(c, 0.72))  # skirt
    px.hline(16, 28, 30, (232, 196, 100))  # gold hem
    px.hline(17, 27, 26, tint(c, 0.5))  # waistband
    px.hline(24, 27, 33, (130, 64, 108))  # thigh band
    px.paint(lambda x, y: 19 <= y <= 20 and 16 <= x <= 19, skin)  # bare shoulder
    px.hline(16, 19, 21, tint(c, 1.24))  # slanted neckline
    px.hline(20, 27, 19, tint(c, 1.24))
    px.fill(capsule(19, 21.5, 15.5, 25.5, 1.4), tint(skin, 0.82))  # back arm
    px.fill(circle(15, 26.5, 1.5), tint(skin, 0.82))
    px.rect(12, 24, 14, 27, PALE)  # palmed card
    px.set(13, 25, (204, 64, 64))
    hm = union(
        lambda x, y: head(x, y) and (y <= 9 or x <= 19),
        lambda x, y: 9 <= y <= 13 and 20 <= x <= 21 + (y - 9),  # bang, back eye
        ellipse(15, 11, 4.6, 5.0),  # wave volume
        capsule(13, 16, 11, 27, 2.8),  # falling waves
        capsule(11, 27, 13, 31, 1.8),
    )
    _mass(px, hm, hair)
    px.dots([(12, 20), (13, 24)], tint(hair, 0.55))  # wave notches
    px.hline(25, 28, 10, tint(skin, 0.78))  # fringe shadow
    _eyes(px, one=True)
    px.set(28, 11, (24, 20, 34))  # lash flick
    px.set(26, 16, tint(skin, 0.55))  # smirk
    px.set(27, 15, tint(skin, 0.55))
    px.set(24, 16, tint(skin, 0.62))  # beauty mark
    px.fill(capsule(26.5, 21.5, 30, 18, 1.4), skin)  # front arm raised
    px.fill(circle(30.5, 17, 1.5), skin)
    px.set(30, 19, (232, 196, 100))  # bracelet
    px.fill(circle(33, 12, 1.9), (242, 204, 96))  # lucky coin
    px.set(33, 11, (255, 242, 184))
    px.dots([(33, 8), (36, 12), (30, 10)], (255, 242, 184), 150)  # sparkle
    px.outline()
    return px


def char_volt():
    # Arcanist: white sweep over a shaved side, storm coat with lit seams
    # flaring behind, orb staff planted in front. Androgynous.
    skin = (216, 208, 214)
    hair = (242, 246, 252)
    c = desat(C["volt"], 0.12)
    glow = mix(c, PALE, 0.5)
    px, head = _chunk(skin, tint(c, 0.7), (50, 46, 64), (48, 44, 60),
                      torso_hw=(5.8, 5.4, 4.8, 5.2))
    cm = profile(21, 28, 37, (6.0, 5.6, 4.9))  # coat skirt
    _mass(px, cm, tint(c, 0.62))
    px.vline(24, 29, 37, (46, 42, 60))  # front split
    for s in (-1, 1):  # lit seams
        px.vline(CHK_CX + s * 3, 21, 35, glow)
    px.dots([(22, 22), (21, 23), (22, 24)], (255, 250, 190))  # bolt emblem
    px.hline(16, 18, 18, tint(c, 0.95))  # collar nubs beside the chin
    px.hline(26, 28, 18, tint(c, 0.95))
    px.fill(capsule(19, 21.5, 16, 26, 1.4), tint(c, 0.55))  # back arm
    px.fill(circle(15.5, 27, 1.5), (58, 52, 72))
    px.paint(lambda x, y: head(x, y) and y <= 10 and x <= 18, (96, 104, 120))  # shave
    hm = union(
        lambda x, y: head(x, y) and y <= 6 and x >= 16,
        capsule(17, 5.5, 27, 7.5, 1.7),  # forward sweep hugging the skull
    )
    _mass(px, hm, hair)
    px.dots([(26, 9), (28, 8)], hair)  # sweep tips
    px.hline(20, 28, 10, tint(skin, 0.8))  # fringe shadow
    _eyes(px, (130, 240, 255))  # arc-lit eyes
    px.hline(25, 26, 16, tint(skin, 0.6))  # calm mouth
    px.vline(32, 7, 33, (106, 82, 60))  # staff
    px.vline(32, 14, 22, (126, 100, 74))
    px.dots([(31, 6), (33, 6)], (106, 82, 60))  # fork
    px.glow(circle(32, 4, 1.5), glow, 2, 90)
    px.fill(circle(32, 4, 1.7), glow)  # orb
    px.set(32, 4, PALE)
    px.dots([(30, 2), (34, 3), (35, 6)], glow, 150)  # static
    px.fill(capsule(25, 22, 30, 24.5, 1.5), tint(c, 0.55))  # front arm
    px.fill(circle(31, 25, 1.7), (58, 52, 72))  # grip
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
