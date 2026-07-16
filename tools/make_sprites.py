#!/usr/bin/env python3
"""Procedural pixel-art sprite generator for Orbfall Arena.

Regenerate all sprites:      python3 tools/make_sprites.py
Output:                      assets/sprites/*.png  (+ sheet_preview.png)

Style: chibi character figures — big head, small body, stubby feet, readable
faces and gear — with chunky dark outlines and 3-band shading (think cozy
16-bit critters). All original designs, drawn deterministically on small
pixel grids and upscaled x4 nearest-neighbour. Colors mirror the entity
colors in src/balance.gd. Replace any PNG with hand-made art (same
filename) and the game picks it up automatically.
"""

import math
import os

from PIL import Image, ImageDraw

SCALE = 4
OUTDIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
OUTLINE = (24, 18, 32, 255)
SKIN = (255, 205, 158)
DARK = (30, 24, 40)
WHITE = (250, 250, 255)


def clamp(v):
    return max(0, min(255, int(v)))


def tint(c, f):
    return (clamp(c[0] * f), clamp(c[1] * f), clamp(c[2] * f))


def mix(a, b, t):
    return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(3))


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

    def glow(self, inside, color, spread=3, alpha=70):
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
            if t < 0.22:
                f = 1.32
            elif t < 0.5:
                f = 1.1
            elif t < 0.8:
                f = 0.95
            else:
                f = 0.72
            self.set(x, y, tint(base, f))
        if rim:
            for (x, y) in pts:
                if (not inside(x - 1, y) or not inside(x, y - 1)) and (y - y0) / h < 0.55:
                    self.set(x, y, tint(base, 1.55))

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


def star(cx, cy, r, points=8, inner=0.55):
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


# ---------------------------------------------------------------- figure kit


def eyes(px, cx, ey, gap=3, pupil=DARK, wide=False):
    for sx in (cx - gap, cx + gap):
        px.set(sx, ey, WHITE)
        px.set(sx, ey + 1, pupil)
        if wide:
            px.set(sx + (1 if sx > cx else -1), ey, WHITE)
            px.set(sx + (1 if sx > cx else -1), ey + 1, pupil)


def cyclops(px, cx, ey, c=(140, 240, 255)):
    px.rect(cx - 2, ey, cx + 2, ey + 1, DARK)
    px.set(cx, ey, c)
    px.dots([(cx - 1, ey), (cx + 1, ey)], tint(c, 0.6))


def mouth(px, cx, my, w=2):
    px.hline(cx - w // 2, cx + w // 2, my, tint(DARK, 1.4))


def feet(px, cx, fy, spread, c):
    for sx in (cx - spread, cx + spread):
        px.rect(sx - 1, fy, sx + 1, fy + 1, tint(c, 0.6))


def arms(px, cx, ay, reach, c):
    for sx in (cx - reach, cx + reach):
        px.rect(sx - 1, ay, sx, ay + 2, tint(c, 0.85))


def helmet(px, head, hcy, c, crest_c=None, cx=None, visor=False):
    for (x, y) in px.mask_pixels(head):
        if y <= hcy:
            px.set(x, y, tint(c, 1.15 if y < hcy - 2 else 0.95))
    if crest_c is not None and cx is not None:
        px.vline(cx, hcy - 8, hcy - 5, crest_c)
    if visor and cx is not None:
        px.hline(cx - 3, cx + 3, hcy + 1, DARK)


def body_block(px, cx, top, w, h, c):
    m = ellipse(cx, top + h / 2.0, w / 2.0, h / 2.0 + 0.6)
    px.fill(m, c)
    return m


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
# Chibi adventurers: skin head + helmet/hat in the class color, tunic body,
# stubby feet, and one piece of signature gear each.


def _adventurer(cid, hat="cap"):
    c = C[cid]
    px = Px(30)
    cx = 15
    hcy = 10
    head = circle(cx, hcy, 7)
    body_block(px, cx, 15, 14, 9, c)
    feet(px, cx, 25, 4, c)
    arms(px, cx, 17, 8, c)
    px.fill(head, SKIN)
    if hat == "cap":
        helmet(px, head, hcy - 1, c, crest_c=None)
        px.hline(cx - 7, cx + 7, hcy - 1, tint(c, 0.7))
    elif hat == "full":
        helmet(px, head, hcy + 3, c, cx=cx)
        px.hline(cx - 4, cx + 4, hcy, DARK)  # visor slit
        px.dots([(cx - 2, hcy), (cx + 2, hcy)], (170, 255, 190))
    elif hat == "hood":
        helmet(px, head, hcy + 1, tint(c, 0.85))
    elif hat == "wizard":
        helmet(px, head, hcy - 2, tint(c, 0.9))
        for i, w in enumerate((5, 4, 3, 2, 1)):
            px.hline(cx - w, cx + w, hcy - 3 - i, tint(c, 1.0 + i * 0.08))
    if hat != "full":
        eyes(px, cx, hcy + 1, 3)
        mouth(px, cx, hcy + 4)
    return px, c, cx, hcy


def char_ranger():
    px, c, cx, hcy = _adventurer("ranger", "cap")
    px.vline(cx + 9, 12, 20, (120, 90, 60))  # rifle at the side
    px.dots([(cx + 9, 11)], (220, 230, 255))
    px.set(cx - 7, hcy - 4, mix(c, WHITE, 0.5))  # cap feather
    px.set(cx - 8, hcy - 5, mix(c, WHITE, 0.7))
    px.outline()
    return px


def char_blitz():
    px, c, cx, hcy = _adventurer("blitz", "hood")
    for sx in (cx - 10, cx + 10):  # twin daggers
        px.vline(sx, 16, 19, (220, 230, 240))
        px.set(sx, 20, (120, 90, 60))
    px.dots([(cx + 6, hcy - 5), (cx + 7, hcy - 6)], (255, 140, 60))  # speed tassel
    px.outline()
    return px


def char_bastion():
    px, c, cx, hcy = _adventurer("bastion", "full")
    # tower shield on the left
    px.rect(cx - 12, 12, cx - 8, 23, tint(c, 1.1))
    px.rect(cx - 11, 13, cx - 9, 22, tint(c, 0.8))
    px.dots([(cx - 10, 15), (cx - 10, 19)], mix(c, WHITE, 0.6))
    px.outline()
    return px


def char_jinx():
    px, c, cx, hcy = _adventurer("jinx", "hood")
    px.dots([(cx + 9, 18)], (255, 220, 100))  # lucky coin
    px.dots([(cx + 8, 18), (cx + 10, 18), (cx + 9, 17), (cx + 9, 19)], (200, 160, 60))
    px.dots([(cx - 3, hcy - 6), (cx + 1, hcy - 7)], mix(c, WHITE, 0.6))  # charm sparks
    px.outline()
    return px


def char_volt():
    px, c, cx, hcy = _adventurer("volt", "wizard")
    px.vline(cx - 10, 11, 22, (120, 90, 60))  # staff
    px.dots([(cx - 10, 10)], WHITE)
    px.dots([(cx - 11, 9), (cx - 9, 9), (cx - 10, 8)], mix(c, WHITE, 0.4))  # orb
    px.dots([(cx + 3, hcy - 4), (cx + 2, hcy - 3), (cx + 4, hcy - 3)], (255, 255, 170))  # bolt
    px.outline()
    return px


# ---------------------------------------------------------------- enemies


def enemy_scrapper():
    px, c = Px(24), C["scrapper"]
    body_block(px, 12, 6, 15, 13, c)
    px.rect(5, 19, 18, 21, tint(c, 0.5))  # treads
    px.dots([(6, 19), (9, 21), (12, 19), (15, 21), (17, 19)], tint(c, 0.3))
    cyclops(px, 12, 10)
    px.vline(12, 2, 4, tint(c, 0.8))  # antenna
    px.set(12, 1, (255, 230, 150))
    mouth(px, 12, 15, 4)
    px.dots([(9, 15), (12, 15), (15, 15)], DARK)  # grill
    px.outline()
    return px


def enemy_sparker():
    px, c = Px(22), C["sparker"]
    body_block(px, 11, 7, 11, 10, c)
    for i, sx in enumerate((7, 11, 15)):  # zigzag crest
        px.vline(sx, 3 - (i % 2), 5, mix(c, WHITE, 0.5))
    arms(px, 11, 10, 7, c)
    eyes(px, 11, 10, 2)
    mouth(px, 11, 13)
    px.dots([(11, 18), (8, 17), (14, 17)], tint(c, 0.6))  # hover sparks
    px.outline()
    return px


def enemy_sentry():
    px, c = Px(24), C["sentry"]
    px.fill(ellipse(12, 12, 8, 6.5), c)
    for sx in (5, 12, 19):  # tripod
        px.vline(sx, 17, 20, tint(c, 0.55))
        px.set(sx, 21, tint(c, 0.4))
    cyclops(px, 12, 10, (255, 120, 90))
    px.vline(12, 15, 17, DARK)  # barrel
    px.set(12, 18, (255, 200, 120))
    px.outline()
    return px


def enemy_crusher():
    px, c = Px(30), C["crusher"]
    body_block(px, 15, 8, 22, 15, c)  # huge shouldered torso
    px.fill(circle(15, 7, 5), tint(c, 1.1))  # sunken head
    px.hline(11, 19, 12, tint(c, 0.65))  # shoulder seam
    for sx in (3, 27):  # fists
        px.fill(circle(sx, 18, 3), tint(c, 0.9))
    cyclops(px, 15, 6, (255, 90, 60))
    px.dots([(9, 2), (21, 2), (8, 3), (22, 3)], tint(c, 1.3))  # horns
    feet(px, 15, 24, 5, c)
    px.outline()
    return px


def enemy_forgemaster():
    px, c = Px(30), C["forgemaster"]
    body_block(px, 15, 13, 18, 12, c)
    head = circle(15, 9, 6)
    px.fill(head, SKIN)
    helmet(px, head, 9, tint(c, 0.9), cx=15)
    px.rect(12, 2, 18, 4, tint(c, 0.6))  # anvil crest
    eyes(px, 15, 10, 2, pupil=(90, 60, 30))
    px.vline(26, 8, 20, (120, 90, 60))  # hammer
    px.rect(24, 6, 28, 8, (160, 160, 180))
    px.dots([(10, 18), (15, 20), (20, 18)], mix(c, (90, 200, 255), 0.5))  # studs
    feet(px, 15, 25, 5, c)
    px.outline()
    return px


def enemy_sporeling():
    px, c = Px(24), C["sporeling"]
    cap = ellipse(12, 8, 10, 6)
    px.fill(ellipse(12, 15, 6, 6), SKIN)  # face-stem
    px.fill(cap, c)
    px.dots([(7, 6), (14, 4), (17, 8)], mix(c, WHITE, 0.55))  # cap spots
    eyes(px, 12, 15, 3)
    mouth(px, 12, 18)
    feet(px, 12, 21, 3, c)
    px.outline()
    return px


def enemy_mite():
    px, c = Px(16), C["mite"]
    px.fill(ellipse(8, 9, 5.5, 4.5), c)
    for sx in (3, 5, 11, 13):  # legs
        px.set(sx, 13, tint(c, 0.55))
    px.dots([(5, 3), (11, 3)], tint(c, 1.3))  # antennae
    px.dots([(5, 4), (11, 4)], tint(c, 0.9))
    eyes(px, 8, 8, 2)
    px.outline()
    return px


def enemy_croaker():
    px, c = Px(26), C["croaker"]
    px.fill(ellipse(13, 15, 10, 7), c)
    px.fill(ellipse(13, 18, 5, 3), mix(c, WHITE, 0.45))  # belly
    for (bx) in (7, 19):  # eye bumps
        px.fill(circle(bx, 7, 3), c)
    eyes(px, 13, 6, 6)
    mouth(px, 13, 13, 6)
    for sx in (4, 22):  # splayed legs
        px.rect(sx - 1, 20, sx + 1, 22, tint(c, 0.6))
    px.outline()
    return px


def enemy_spitter():
    px, c = Px(26), C["spitter"]
    px.fill(ellipse(13, 19, 9, 5), tint(c, 0.85))  # coil
    px.fill(ellipse(13, 9, 7, 6), c)  # hooded head
    px.dots([(6, 5), (20, 5), (5, 8), (21, 8)], tint(c, 1.25))  # hood tips
    eyes(px, 13, 8, 3, pupil=(120, 30, 60))
    px.dots([(11, 13), (15, 13)], WHITE)  # fangs
    px.dots([(13, 12)], tint(c, 0.5))
    px.outline()
    return px


def enemy_broodmother():
    px, c = Px(32), C["broodmother"]
    px.fill(ellipse(16, 14, 13, 9), c)  # dome shell
    px.dots([(9, 8), (16, 6), (23, 8), (12, 12), (20, 12)], tint(c, 0.65))  # shell spots
    px.fill(ellipse(16, 23, 8, 4), tint(c, 1.05))  # face band
    eyes(px, 16, 22, 3)
    for (ex, ey) in ((7, 26), (16, 28), (25, 26)):  # egg sacs
        px.fill(circle(ex, ey, 3), mix(c, WHITE, 0.5))
        px.set(ex, ey - 1, mix(c, WHITE, 0.75))
    px.outline()
    return px


def enemy_wisp():
    px, c = Px(22), C["wisp"]
    ghost = union(circle(11, 9, 7), ellipse(11, 14, 7, 5))
    px.glow(ghost, c, 2, 80)
    px.fill(ghost, c)
    for i, sx in enumerate((6, 9, 12, 15)):  # wavy tail
        px.vline(sx, 18, 19 + (i % 2), tint(c, 0.8))
    eyes(px, 11, 8, 3, pupil=(40, 60, 110))
    mouth(px, 11, 12)
    px.outline((40, 60, 110, 255))
    return px


def enemy_blinker():
    px, c = Px(24), C["blinker"]
    px.glow(circle(12, 11, 7), c, 2, 70)
    px.fill(ellipse(12, 11, 8, 7), c)
    for sx in (2, 22):  # wing nubs
        px.dots([(sx, 10), (sx + (1 if sx < 12 else -1), 9)], tint(c, 0.85))
    px.fill(circle(12, 11, 4), WHITE)  # big central eye
    px.fill(circle(12, 11, 2), (60, 30, 100))
    px.set(11, 10, WHITE)
    px.dots([(8, 18), (12, 19), (16, 18)], tint(c, 0.7))  # tail sparks
    px.outline((50, 30, 90, 255))
    return px


def enemy_husk():
    px, c = Px(26), C["husk"]
    px.fill(ellipse(13, 10, 9, 8), c)  # heavy torso
    px.rect(6, 18, 10, 22, tint(c, 0.75))  # stumpy legs
    px.rect(16, 18, 20, 22, tint(c, 0.75))
    crack = [(13, 3), (12, 5), (13, 7), (14, 9), (13, 11)]
    px.dots(crack, tint(c, 0.4))
    px.dots([(9, 9), (17, 9)], (140, 230, 255))  # hollow glowing eyes
    px.dots([(9, 10), (17, 10)], (60, 120, 160))
    px.outline()
    return px


def enemy_detonant():
    px, c = Px(26), C["detonant"]
    px.glow(circle(13, 13, 8), c, 2, 90)
    px.fill(star(13, 12, 11, 8, 0.55), c)
    eyes(px, 13, 10, 3, pupil=(120, 20, 60))
    px.hline(11, 15, 15, DARK)  # gritted mouth
    px.dots([(12, 15), (14, 15)], WHITE)
    for sx in (9, 17):  # little legs
        px.rect(sx - 1, 21, sx, 23, tint(c, 0.6))
    px.dots([(13, 13)], (255, 230, 150))  # lit core
    px.outline((90, 24, 60, 255))
    return px


def enemy_oracle():
    px, c = Px(26), C["oracle"]
    robe = union(ellipse(13, 16, 8, 7), circle(13, 8, 5))
    px.glow(robe, c, 2, 70)
    px.fill(robe, c)
    px.fill(circle(13, 8, 4), tint(c, 0.5))  # hood shadow
    px.fill(circle(13, 8, 2), WHITE)  # single seer eye
    px.set(13, 8, (30, 40, 90))
    for (hx, hy) in ((5, 3), (13, 1), (21, 3)):  # halo dots
        px.set(hx, hy, mix(c, WHITE, 0.6))
    px.hline(9, 17, 22, tint(c, 0.7))  # ragged hem
    px.dots([(9, 23), (13, 23), (17, 23)], tint(c, 0.55))
    px.outline((40, 50, 100, 255))
    return px


def boss_sprite():
    px, c = Px(56), C["boss"]
    px.glow(circle(28, 28, 20), c, 3, 55)
    body_block(px, 28, 20, 38, 26, c)  # armored bulk
    head = circle(28, 14, 9)
    px.fill(head, tint(c, 1.08))
    helmet(px, head, 13, tint(c, 0.8), cx=28)
    px.dots([(16, 4), (40, 4), (15, 6), (41, 6), (28, 2), (28, 3)], tint(c, 1.35))  # crown horns
    eyes(px, 28, 15, 5, pupil=(255, 90, 90), wide=True)
    mouth(px, 28, 20, 6)
    px.dots([(25, 20), (28, 21), (31, 20)], WHITE)  # teeth
    for sx in (7, 49):  # claw fists
        px.fill(circle(sx, 34, 5), tint(c, 0.9))
        px.dots([(sx - 2, 31), (sx, 30), (sx + 2, 31)], tint(c, 1.3))
    for (x, y) in px.mask_pixels(circle(28, 32, 4)):  # chest core
        px.set(x, y, mix(c, WHITE, 0.55))
    px.set(28, 31, WHITE)
    for y in (40, 44):  # plating
        for x in range(18, 39, 4):
            px.set(x, y, tint(c, 0.55))
    feet(px, 28, 46, 8, c)
    px.outline((36, 20, 60, 255))
    return px


# ---------------------------------------------------------------- props


def bullet(c):
    px = Px(12)
    px.glow(circle(6, 6, 3), c, 2, 110)
    px.fill(circle(6, 6, 4), c)
    px.dots([(5, 5)], WHITE)
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
