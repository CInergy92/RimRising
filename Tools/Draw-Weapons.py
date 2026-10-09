"""
Draw the razor family in RimWorld's flat weapon idiom: the two weapon sprites
(which are also their inventory and ground icons), the whip-form ability icon,
and the lash line fleck.

Run through Blender (for its bundled numpy), never directly:

    blender -b --factory-startup --python Tools/Draw-Weapons.py -- <out_dir>

WHY REDRAWN. In the test scene's ground row the old razor - a ControlNet-painted
sprite - sat beside vanilla's longsword, monosword, plasma sword and gladius as
the one soft, thin-outlined, low-contrast object. Vanilla's are flat: a heavy
dark outline, a two-tone blade split along its length, and at most one accent
(the monosword's blue line, the plasma sword's glow).

GEOMETRY IS KEPT. Pommel, thumb stud and tip sit where the old sprite had them,
so Melee Animation's tweak data (WeaponTweakData/, derived from the hand at the
stud) still lines up - Tools re-measure it after drawing.

Coordinates are canvas fractions, x right, y DOWN. The sprites run lower-left to
upper-right, which the ground row confirmed is the angle vanilla's own weapons
lie at.
"""
import importlib.machinery
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
cw = importlib.machinery.SourceFileLoader(
    "compose_worn", os.path.join(HERE, "Compose-WornApparel.py")).load_module()

SS = 4
INK = cw.INK

C = {
    "steel":  (np.array([0.86, 0.88, 0.90]), np.array([0.60, 0.63, 0.68])),
    "edge":   (np.array([0.97, 0.98, 0.99]), np.array([0.80, 0.83, 0.86])),
    "brass":  (np.array([0.80, 0.64, 0.30]), np.array([0.58, 0.44, 0.20])),
    "grip":   (np.array([0.24, 0.22, 0.21]), np.array([0.16, 0.15, 0.15])),
    "amber":  (np.array([1.00, 0.74, 0.30]), np.array([0.86, 0.52, 0.16])),
    "glow":   (np.array([0.80, 0.96, 1.00]), np.array([0.55, 0.85, 0.95])),
}


class Canvas:
    def __init__(self, size):
        self.size = size
        # Strokes are authored for a 256 canvas and scaled with it, so a 128
        # icon is not drawn twice as heavy relative to its size.
        self.k = size / 256.0
        n = size * SS
        yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
        self.x, self.y = xx / n, yy / n           # canvas fractions
        self.rgb = np.zeros((n, n, 3), np.float32)
        self.alpha = np.zeros((n, n), bool)

    def px(self, final_px):
        """A width in FINAL pixels, as a canvas fraction."""
        return final_px / self.size

    def poly(self, pts):
        x, y = self.x, self.y
        inside = np.zeros(x.shape, bool)
        for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
            cond = (y1 > y) != (y2 > y)
            with np.errstate(divide="ignore", invalid="ignore"):
                xint = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            inside ^= cond & (x < xint)
        return inside

    def disc(self, cx, cy, r):
        return (self.x - cx) ** 2 + (self.y - cy) ** 2 <= r * r

    def ribbon(self, pts, w0, w1):
        """Polyline whose width tapers from w0 to w1 (canvas fractions)."""
        out = np.zeros(self.x.shape, bool)
        segs = list(zip(pts, pts[1:]))
        lengths = [math.dist(a, b) for a, b in segs]
        total = sum(lengths) or 1.0
        run = 0.0
        for (a, b), L in zip(segs, lengths):
            wa = w0 + (w1 - w0) * (run / total)
            wb = w0 + (w1 - w0) * ((run + L) / total)
            run += L
            dx, dy = b[0] - a[0], b[1] - a[1]
            LL = dx * dx + dy * dy or 1e-9
            t = np.clip(((self.x - a[0]) * dx + (self.y - a[1]) * dy) / LL, 0, 1)
            d2 = (self.x - a[0] - t * dx) ** 2 + (self.y - a[1] - t * dy) ** 2
            w = (wa + (wb - wa) * t) / 2
            out |= d2 <= w * w
        return out

    def part(self, mask, colour, dark=None, panel_px=2.0):
        """Draw one part: its own outline ring, then its lit face, then its dark
        face (a mask of where the darker plane falls)."""
        lit, shade = C[colour]
        ring = cw.dilate(mask, panel_px * self.k * SS) & ~mask
        self.rgb[ring] = INK
        self.rgb[mask] = lit
        if dark is not None:
            self.rgb[mask & dark] = shade
        self.alpha |= mask | ring

    def line(self, pts, width_px, colour=None):
        w = self.px(width_px * self.k)
        m = self.ribbon(pts, w, w)
        self.rgb[m] = INK if colour is None else C[colour][0]
        self.alpha |= m

    def finish(self, outline_px):
        sil = cw.dilate(self.alpha, outline_px * self.k * SS) & ~self.alpha
        self.rgb[sil] = INK
        a = (self.alpha | sil).astype(np.float32)
        img = np.dstack([self.rgb * a[..., None], a])
        d = cw.downsample(img, SS)
        out = d.copy()
        nz = d[..., 3] > 1e-4
        out[nz, :3] = d[nz, :3] / d[nz, 3:4]
        return out


# ------------------------------------------------------------ shared pieces
class Axis:
    """A straight weapon axis: t runs pommel (0) to tip (1), s is across it,
    positive toward the upper-left (the lit side)."""

    def __init__(self, p0, p1):
        self.p0 = np.array(p0, float)
        d = np.array(p1, float) - self.p0
        self.L = float(np.linalg.norm(d))
        self.u = d / self.L
        self.n = np.array([self.u[1], -self.u[0]])     # perpendicular, toward upper-left

    def at(self, t, s=0.0):
        p = self.p0 + self.u * (t * self.L) + self.n * s
        return (float(p[0]), float(p[1]))

    def side(self, cv):
        """Mask of the darker side: below the axis line (lower-right)."""
        return ((cv.x - self.p0[0]) * self.n[0] + (cv.y - self.p0[1]) * self.n[1]) < 0


def hilt(cv, ax, t_guard, stud=True, stud_t=0.155):
    """Pommel, wrapped grip with brass bands, guard collar, thumb stud."""
    dark = ax.side(cv)
    w = 0.032
    cv.part(cv.disc(*ax.at(0.035), 0.048), "brass", dark)
    grip = cv.poly([ax.at(0.05, w), ax.at(t_guard, w), ax.at(t_guard, -w), ax.at(0.05, -w)])
    cv.part(grip, "grip", dark)
    for tb in (0.09, t_guard - 0.035):
        band = cv.poly([ax.at(tb - 0.012, w + 0.004), ax.at(tb + 0.012, w + 0.004),
                        ax.at(tb + 0.012, -w - 0.004), ax.at(tb - 0.012, -w - 0.004)])
        cv.part(band, "brass", dark, panel_px=2.0)
    gw = 0.052
    guard = cv.poly([ax.at(t_guard - 0.012, gw), ax.at(t_guard + 0.022, gw * 0.8),
                     ax.at(t_guard + 0.022, -gw * 0.8), ax.at(t_guard - 0.012, -gw)])
    cv.part(guard, "brass", dark)
    if stud:
        # The shape-sensor stud under the thumb: the toggle between blade and whip.
        # stud_t is along THIS axis: a short haft needs a larger t for the same spot.
        cv.part(cv.disc(*ax.at(stud_t, 0.006), 0.017), "amber", None, panel_px=2.0)


# ------------------------------------------------------------------ designs
def razor(size=256, inset=0.0):
    """The straight razor: a slim, tapering polyenne blade - urumi-like, not a
    sabre - on a brass-fitted grip. Segment marks along the blade are the joints
    that let it go slack into the whip form."""
    cv = Canvas(size)
    # inset pulls both ends in for icon frames; the weapon sprite itself uses 0,
    # since its geometry is what the Melee Animation tweak data was derived from.
    ax = Axis((0.095 + inset, 0.915 - inset), (0.955 - inset, 0.045 + inset))
    tg = 0.255
    dark = ax.side(cv)
    # Slender on purpose - an urumi, not a sabre - but 0.030 read as a wire at game size.
    blade = cv.poly([ax.at(tg, 0.036), ax.at(0.62, 0.029), ax.at(0.93, 0.012), ax.at(1.0, 0.0),
                     ax.at(0.93, -0.014), ax.at(0.62, -0.031), ax.at(tg, -0.038)])
    cv.part(blade, "steel", dark)
    # The edge: a bright hairline along the lit side, the one accent.
    cv.line([ax.at(tg + 0.03, 0.020), ax.at(0.62, 0.016), ax.at(0.93, 0.005)], 2.0, "edge")
    for ts in (0.45, 0.62, 0.78):                     # polyenne segment joints
        cv.line([ax.at(ts, 0.022), ax.at(ts + 0.012, -0.024)], 2.2)
    hilt(cv, ax, tg)
    return cv.finish(1.0)


def reaper_razor(size=256):
    """The same object set to a sickle: a crescent on the razor's own hilt.
    Arc as in the old sprite, so the hand and the tweak data still line up."""
    cv = Canvas(size)
    ax = Axis((0.095, 0.915), (0.31, 0.70))           # the haft; t=1 is the arc's root
    acx, acy, arad = 0.40, 0.38, 0.38
    a0, a1, steps = 111.0, -53.0, 40
    outer, inner, edge = [], [], []
    for i in range(steps + 1):
        f = i / steps
        ang = math.radians(a0 + (a1 - a0) * f)
        hw = 0.050 * (1 - f) + 0.004 * f              # thick at the root, a point at the tip
        cx, cy = acx + arad * math.cos(ang), acy + arad * math.sin(ang)
        rx, ry = math.cos(ang), math.sin(ang)
        outer.append((cx + rx * hw, cy + ry * hw))
        inner.append((cx - rx * hw, cy - ry * hw))
        edge.append((cx - rx * hw * 0.55, cy - ry * hw * 0.55))
    blade = cv.poly(outer + inner[::-1])
    # Plane split: the inner half - the cutting side - is the lit face.
    dist = np.sqrt((cv.x - acx) ** 2 + (cv.y - acy) ** 2)
    cv.part(blade, "steel", dist > arad)
    cv.line(edge[2:-3], 2.0, "edge")
    for f in (0.30, 0.52, 0.72):                      # segment joints, as on the straight razor
        ang = math.radians(a0 + (a1 - a0) * f)
        hw = 0.050 * (1 - f) + 0.004 * f
        cx, cy = acx + arad * math.cos(ang), acy + arad * math.sin(ang)
        rx, ry = math.cos(ang), math.sin(ang)
        cv.line([(cx - rx * hw * 0.8, cy - ry * hw * 0.8), (cx + rx * hw * 0.8, cy + ry * hw * 0.8)], 2.2)
    hilt(cv, ax, 0.93, stud=True, stud_t=0.46)
    return cv.finish(1.0)


def whip_icon(size=128):
    """Ability icon, whip form: the grip at lower left and the blade uncoiled into
    a long tapering S-curve, with two motion lines - the razor gone slack."""
    cv = Canvas(size)
    ax = Axis((0.16, 0.86), (0.34, 0.68))
    pts = []
    for i in range(48):
        f = i / 47
        x = 0.33 + 0.58 * f
        y = 0.67 - 0.55 * f + 0.13 * math.sin(f * math.pi * 1.6)
        pts.append((x, y))
    lash = cv.ribbon(pts, 0.070, 0.012)
    dark = cv.y > (0.67 - 0.55 * ((cv.x - 0.33) / 0.58)) + 0.13 * np.sin(((cv.x - 0.33) / 0.58) * math.pi * 1.6)
    cv.part(lash, "steel", dark, panel_px=2.5)
    cv.line(pts[3:-4], 1.6, "edge")
    hilt(cv, ax, 0.98, stud=True, stud_t=0.42)
    for k, off in enumerate((0.07, 0.13)):            # motion lines
        arc = [(0.42 + 0.40 * f, 0.80 - 0.42 * f + off + 0.03 * math.sin(f * math.pi)) for f in np.linspace(0.15, 0.75, 12)]
        cv.line(arc, 2.6 - k * 0.6, "glow")
    return cv.finish(1.0)


def lash_line(size=256):
    """The whip uncoiled, hand (left) to target (right), for RR_Fleck_RazorLash.
    FleckMaker.ConnectingLine stretches the canvas's X to the lash's length and
    its height to the line width, so the blade runs edge to edge and is drawn
    tall - it is squashed several times over on the map. Thick at the hand,
    tapering to a point, with one and a half slow waves: a whip, not a beam."""
    cv = Canvas(size)
    def centre(x):
        f = (x - 0.01) / 0.98
        return 0.5 - 0.16 * np.sin(f * math.pi * 3.0) * (0.3 + 0.7 * f)

    pts = [(float(x), float(centre(x))) for x in np.linspace(0.01, 0.99, 64)]
    blade = cv.ribbon(pts, 0.20, 0.05)
    # The darker plane is the underside of the ribbon itself, not of the canvas.
    cv.part(blade, "steel", cv.y > centre(cv.x), panel_px=4.0)
    cv.line(pts[4:-6], 3.0, "edge")
    return cv.finish(4.0)


OUTPUTS = {
    "Things/Item/Equipment/WeaponMelee/RR_Razor": razor,
    "Things/Item/Equipment/WeaponMelee/RR_ReaperRazor": reaper_razor,
    "UI/Abilities/RR_RazorWhip": whip_icon,
    "Things/Mote/RR_RazorLashLine": lash_line,
    # The razor-bearing precept's icon: the razor itself at icon size, so the
    # precept and the item can't drift apart. Was a placeholder stick.
    "UI/Issues/RR_RazorBearing": lambda: razor(128, inset=0.07),
}

if __name__ == "__main__":
    out = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
    for rel, fn in OUTPUTS.items():
        path = os.path.join(out, *rel.split("/")) + ".png"
        cw.save_png(path, fn())
        print("WROTE", path)
