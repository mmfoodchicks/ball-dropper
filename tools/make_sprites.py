#!/usr/bin/env python3
"""Procedural pixel-art sprite generator for Orbfall Arena.

Regenerate all sprites:      python3 tools/make_sprites.py
Output:                      assets/sprites/*.png  (+ sheet_preview.png)

Style: enemies are gritty angular slabs with glowing slit eyes under
heavy brows (built procedurally); the five playables are hand-drawn 32x32
pixel maps — deliberate per-pixel placement, hue-shifted shadow/highlight
ramps, clean silhouettes and 3/4 action poses, kept tasteful. All original
designs, deterministic, upscaled x4 nearest-neighbour. Colors track
src/balance.gd. Replace any PNG with hand-made art (same filename) and the
game picks it up automatically; missing files fall back to vector shapes
in-game.
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
# The five playables are HAND-DRAWN pixel maps (32x32), not procedural
# shapes: every pixel is placed deliberately, the way the reference packs
# are made. Shared skeleton across the cast — hair cap rows 2-6 with a
# fringe-shadow row, 1x2 eyes on the same eye line (cols 13/16), chin row
# 12, torso rows 14-21, split-stance legs, boots on the same ground line —
# with hue-shifted ramps (shadows go cool, highlights warm) per character.
# Legend: '.' transparent; letters are palette entries per character.


def from_map(rows, pal):
    """Build a Px from an ASCII pixel map. The canvas is len(rows) square;
    short rows are treated as right-padded with transparency, so only the
    painted columns need to be typed out. A row longer than the canvas is
    an authoring error and raises."""
    size = len(rows)
    px = Px(size)
    for y, row in enumerate(rows):
        if len(row) > size:
            raise ValueError("row %d is %d wide, max %d" % (y, len(row), size))
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            px.set(x, y, pal[ch])
    return px


RANGER_PAL = {
    "!": (176, 240, 244), "H": (52, 174, 194), "h": (28, 112, 144),
    "S": (238, 190, 142), "s": (198, 138, 106), "E": (26, 20, 36),
    "J": (64, 126, 150), "j": (40, 86, 114), "+": (112, 178, 196),
    "P": (60, 56, 80), "p": (42, 38, 58),
    "B": (80, 62, 54), "b": (54, 40, 38),
    "G": (56, 48, 66), "O": (232, 194, 102),
    "M": (188, 196, 210), "m": (124, 132, 152),
    "W": (136, 98, 64), "w": (96, 66, 46), "*": (242, 248, 252),
}

# Scout captain: teal bob + ponytail, cropped jacket over a bare midriff,
# both gloved hands on a levelled rifle.
RANGER_MAP = [
    "................................",
    "................................",
    "..........!!!!H.................",
    "........h!!HHHHHH...............",
    ".......hHHHHHHHHHHH.............",
    "......hHhHHHHHHHHHh.............",
    "......hHhHHsssssssh.............",
    "......hHhHsSSSSSSSS.............",
    "......hHhsSSSESSESS.............",
    "......hhhsSSSESSESSS............",
    ".......hhSSSSSSSSSss............",
    "........hsSSSSSssSs.............",
    "......hH...sSSSSs...............",
    "......hh...+ssss+...............",
    ".......h.j++JJJJJJj.....m.......",
    ".......hjJJWWWMMMMMMGMMMMMMMM*..",
    "........jJwwwwGGmmmmGmmmmmm.....",
    ".........JJJJJJJJj..............",
    ".........jJJJJJJjj..............",
    "...........sSSSSs...............",
    "...........sSSsSs...............",
    "..........GGGGOGGG..............",
    "..........pPPPPPPP..............",
    "..........pPP.PPPP..............",
    "..........pPP.PPPP..............",
    "..........ppP.PPPP..............",
    ".........bBBB.PPPP..............",
    ".........bBBB.BBBBB.............",
    ".........bbbb.BBBBB.............",
    "..............bbbbb.............",
    "................................",
    "................................",
]

BLITZ_PAL = {
    "A": (238, 204, 96), "a": (186, 140, 56), "!": (252, 240, 178),
    "S": (242, 198, 158), "s": (204, 148, 110), "E": (26, 20, 36),
    "V": (224, 170, 60), "v": (176, 122, 46), "+": (246, 210, 122),
    "R": (214, 86, 66), "r": (164, 58, 52),
    "P": (58, 52, 72), "p": (40, 36, 54),
    "B": (76, 60, 76), "b": (52, 40, 54),
    "G": (58, 50, 68), "O": (232, 194, 102),
    "M": (210, 218, 232), "m": (142, 150, 168), "*": (244, 248, 252),
}

# Duelist: spiked blond crown, scarf tail streaming behind, gold vest with
# a V-neck, dagger low in the lead hand and one reversed behind.
BLITZ_MAP = [
    "................................",
    ".........A...A...A..............",
    "........AAA.AAA.AAA.............",
    "........aAAAAAAAAAA.............",
    ".......aA!!AAAAAAAA.............",
    ".......aAAAAAAAAAAAa............",
    ".......aAAsssssssss.............",
    ".......aAaSSSSSSSSS.............",
    ".......aAaSSSESSESS.............",
    "........AaSSSESSESSS............",
    ".........aSSSSSSSSss............",
    "..........sSSSs*Sss.............",
    "...........sSSSSs...............",
    "..........RRRRRRRRr.............",
    ".....RRrsS++VVVVVvSs............",
    "....Rr..sSvVSSSVVvSs............",
    "........sSvVVSVVVv.Ss...........",
    "......mmS.vVVVVVVv..SS..........",
    "..........vVVVVVVv..SSO.........",
    "..........vvVVVVvv.....M........",
    "..........GGGGOGGG......M.......",
    "..........pPPPPPPP.......M......",
    "..........pPP.PPPP........*.....",
    "..........pGG.GGGG..............",
    "..........pPP.PPPP..............",
    "..........ppP.PPPP..............",
    ".........bBBB.PPPP..............",
    ".........bBBB.BBBBB.............",
    ".........bbbb.BBBBB.............",
    "..............bbbbb.............",
    "................................",
    "................................",
]

BASTION_PAL = {
    "S": (162, 112, 78), "s": (120, 78, 56), "!": (196, 146, 100),
    "D": (208, 204, 198), "d": (158, 154, 152),
    "w": (92, 86, 82), "E": (26, 20, 36),
    "C": (152, 160, 176), "c": (106, 114, 132), "+": (198, 206, 220),
    "P": (66, 62, 76), "p": (46, 42, 56),
    "B": (92, 98, 112), "b": (62, 66, 78),
    "G": (52, 46, 56), "O": (232, 194, 102),
    "M": (214, 222, 236), "m": (150, 158, 172), "*": (246, 250, 253),
    "T": (172, 180, 194), "t": (120, 128, 144),
}

# Veteran wall: bald crown with a shine, heavy grey brow bar and beard,
# scarred cheek, sword raised behind the shoulder, tower shield braced in
# front with a domed top, gold boss stud and a tapered foot.
BASTION_MAP = [
    "",
    "",
    "...........SSSS",
    "..........S!!SSSS",
    ".........SS!SSSSSS",
    ".........sSSSSSSSSS",
    ".........sSSSSSSSSS",
    "..*......sSSwwwwwwS",
    "..Mm.....sSSSESSESS",
    "...Mm....sSSSESSES!",
    "....Mm...sSDDDDDDDs",
    ".....Mm..sDDDDDDDDd",
    "......Mm..DDDDDDDDd",
    ".......Mm.dDDDDDDd...TTT",
    ".....OOOc++CCCCCCC+cTTTTTt",
    "......GSscCCCCCCCCc.TTTTTTt",
    "........scCCCCCCCCc.TT+O+Tt",
    ".........cCCCCCCCCc.TT+O+Tt",
    ".........ccCCCCCCcc.TT+O+Tt",
    ".........cCCCCCCCCc.TTTTTTt",
    ".........GGGGGOGGGG.TTTTTTt",
    "..........pPPPPPPP..TTTTTTt",
    "..........pPP.PPPP...TTTTTt",
    "..........pPP.PPPP....TTTt",
    "..........ppP.PPPP.....Tt",
    "..........ppP.PPPP",
    ".........bBBB.PPPP",
    ".........bBBB.BBBBB",
    ".........bbbb.BBBBB",
    "..............bbbbb",
    "",
    "",
]

JINX_PAL = {
    "K": (228, 88, 154), "k": (170, 46, 112), "!": (250, 172, 210),
    "S": (242, 196, 152), "s": (206, 144, 110), "E": (26, 20, 36),
    "V": (150, 88, 198), "v": (106, 54, 150), "+": (192, 136, 228),
    "B": (88, 50, 112), "b": (60, 32, 80),
    "O": (234, 198, 104), "*": (255, 246, 200),
    "C": (240, 242, 250), "c": (206, 72, 72),
}

# Trickster gambler: long waves with a bang hiding the back eye, violet
# off-shoulder dress with a gold hem, tall boots, coin tossed above the
# lead hand and a card palmed behind.
JINX_MAP = [
    "................................",
    "................................",
    "..........KKKK..................",
    ".........K!!KKKK................",
    "........KK!KKKKKK...............",
    ".......kKKKKKKKKKKK.............",
    ".......kKKKKKKKKKKKk............",
    ".......kKKKKKKsssss....*........",
    ".......kKKKKKKSSESS..OOO........",
    "........kKKKKSSSESSS.O*O........",
    "........kKKkSSSSSSSs.....*......",
    "........kksSSSSsSsS.SS..........",
    "...........sSSSSs..SS...........",
    ".......kk..ssss..SSS............",
    "......kkSSs+VVVVvVS.............",
    "......kkSsvVVVVVVv..............",
    "....CCCSk.vVVVVVVv..............",
    "....CcCsk.vvVVVVvv..............",
    "....CCC...vvvvvvvv..............",
    ".........vVVVVVVVVv.............",
    "........vVVVVVVVVVVv............",
    "........OOOOOOOOOOOO............",
    "..........sSS.SSSS..............",
    "..........sSS.vvvv..............",
    ".........bBBB.BBBBB.............",
    ".........bBBB.BBBBB.............",
    ".........bBBB.BBBBB.............",
    ".........bBBB.BBBBB.............",
    ".........bbbb.BBBBB.............",
    "..............bbbbb.............",
    "................................",
    "................................",
]

VOLT_PAL = {
    "W": (246, 249, 253), "w": (176, 188, 204), "N": (88, 96, 112),
    "S": (214, 198, 208), "s": (166, 146, 164), "E": (140, 242, 255),
    "C": (64, 150, 162), "c": (40, 106, 122), "+": (198, 248, 252),
    "*": (255, 252, 214),
    "P": (56, 52, 70), "p": (40, 36, 54),
    "B": (50, 46, 62), "b": (36, 32, 46),
    "T": (124, 94, 64), "t": (90, 66, 46), "G": (60, 54, 74),
    "g": (152, 236, 246), "o": (232, 250, 252),
}

# Arcanist: white sweep over a shaved side, storm coat with lit seams and
# a bolt emblem, orb staff planted in the lead hand. Androgynous.
VOLT_MAP = [
    "................................",
    "................................",
    ".......................gg.......",
    "..........WWWW........gog.......",
    ".........WWWWWWWWWW...ttt.......",
    ".........wWWWWWWWWWW....T.......",
    ".........NNwWWWWWWWw....T.......",
    ".........NNNsssssss.....T.......",
    ".........NsSSESSESS.....T.......",
    ".........NsSSESSESSS....T.......",
    "..........sSSSSSSSSs....t.......",
    "..........sSSSSssSS.....t.......",
    "...........sSSSSs.......t.......",
    "..........+ssss++.......T.......",
    "........c+CCCCCCC+cCCCCGT.......",
    "........cCCCCCCCCCc...GGT.......",
    "........cCC+C*C+CCc.....T.......",
    "........cCC+*CC+CCc.....T.......",
    "........cCC+CCC+CCc.....T.......",
    "........ccC+CCC+Ccc.....T.......",
    "........cCC+CCC+cCc.....T.......",
    "........cCC+CCC+cCc.....T.......",
    "........ccccccccccc.....T.......",
    "..........pPP.PPPP......T.......",
    "..........pPP.PPPP......t.......",
    "..........ppP.PPPP..............",
    ".........bBBB.PPPP..............",
    ".........bBBB.BBBBB.............",
    ".........bbbb.BBBBB.............",
    "..............bbbbb.............",
    "................................",
    "................................",
]


def char_ranger():
    px = from_map(RANGER_MAP, RANGER_PAL)
    px.outline()
    return px


def char_blitz():
    px = from_map(BLITZ_MAP, BLITZ_PAL)
    px.outline()
    return px


def char_bastion():
    px = from_map(BASTION_MAP, BASTION_PAL)
    px.outline()
    return px


def char_jinx():
    px = from_map(JINX_MAP, JINX_PAL)
    px.outline()
    return px


def char_volt():
    px = from_map(VOLT_MAP, VOLT_PAL)
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
