"""
Draw RimWorld worn armour as FLAT PANELS - the house style of every armour mod it
was compared against in game - and write the sprite and tint mask for every
body type and facing.

Run through Blender (for its bundled numpy), never directly:

    blender -b --factory-startup --python Tools/Draw-PanelArmor.py -- <design> <texture_prefix>

WHY NOT THE 3D RENDER. Tested in game beside vanilla marine and cataphract armour,
Alpha Genes, Vanilla Armour Expanded and VFE Classical, the rendered pulse armour
read as a mottled, skinny bodysuit. The others are a handful of big flat panels
with heavy outlines, and they EXTEND PAST THE BODY - measured overhang beyond the
Male body box, as a fraction of its width per side:

    VAE heavy marine    ~0.40 sides, ~0.25 top
    AG Forsaken marine  ~0.45 sides, ~0.13 top
    VFE legionnaire     ~0.27 sides,  0.01 top
    VAE royal trooper   ~0.10 sides,  0.05 top

Pulse armour is heavy powered plate, so it sits between Roman and heavy marine.

THE IDIOM, as read off those sprites:
  - each panel is its own shape with its own thick dark outline, drawn back to
    front, so panels overlap and read as separate pieces of plate;
  - shading is by PLANE, not by edge: a panel splits into a lit face and a grey
    side face along a straight line;
  - plate is near-white or grey, so the material or dye colours it;
  - the sprite stops at the hips - legs belong to the body (or to a leg mod).

COORDINATES are in BODY-BOX units: u across (0 = left edge of the measured box,
1 = right), v down (0 = top, 1 = bottom), and may go outside 0..1 for overhang.
So one design fits all five body types, the same way the boxes fit the body.
"""
import importlib.machinery
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
cw = importlib.machinery.SourceFileLoader(
    "compose_worn", os.path.join(HERE, "Compose-WornApparel.py")).load_module()

CANVAS, SS = cw.CANVAS, cw.SS
INK = cw.INK
# MEASURED IN THE SOURCE TEXTURES, not estimated from screenshots. The black run
# at the silhouette edge is 7 px in VAE's heavy marine and 5 px in VFE's
# legionnaire, at 256. The silhouette ring sits OUTSIDE each panel's own ring,
# so the two stack at the edge: 6 + 4 measured 10 px here, twice theirs, which
# read as heavy in game. 3 + 2.5 gives ~5.5 at the edge and 3 px panel lines.
OUTLINE = 2.5          # silhouette outline, final px (added outside the panel rings)
PANEL_LINE = 3.0       # outline round each panel, final px
SEAM = 1.3             # internal seam lines, final px

# Values: lit face, side face. Plate is near-white for the dye; suit stays dark.
TONE = {
    "plate": (np.array([0.90, 0.90, 0.89]), np.array([0.66, 0.66, 0.66])),
    "trim":  (np.array([0.62, 0.62, 0.63]), np.array([0.46, 0.46, 0.47])),
    "suit":  (np.array([0.26, 0.25, 0.24]), np.array([0.19, 0.18, 0.18])),
    "glow":  (np.array([0.42, 0.80, 0.82]), np.array([0.30, 0.62, 0.66])),
    "ink":   (INK, INK),
    # duroArmor: stamped steel in its own colour - not dyed, not stuff-made.
    "steel": (np.array([0.70, 0.72, 0.75]), np.array([0.50, 0.52, 0.56])),
    "strap": (np.array([0.44, 0.32, 0.22]), np.array([0.31, 0.22, 0.15])),
    # scarabSkin: a lattice that drinks light - near-black, faint form.
    "skin":  (np.array([0.17, 0.18, 0.20]), np.array([0.11, 0.12, 0.13])),
    "lattice": (np.array([0.28, 0.30, 0.34]), np.array([0.22, 0.24, 0.27])),
    # ghostCloak: woven polyenne, a muted slate; the lining darker.
    "cloth": (np.array([0.44, 0.49, 0.48]), np.array([0.32, 0.36, 0.35])),
    "lining": (np.array([0.21, 0.23, 0.23]), np.array([0.16, 0.17, 0.17])),
}
DYED = {"plate"}

# REALISTIC BODY LEGS. [NL] Realistic Body (nals.realisticbody) retextures only
# Male, Female and Thin, and draws legs BELOW the vanilla body box, down to the
# bottom of the canvas; Fat and Hulk keep vanilla's legless bodies. These are the
# OUTER EDGES of its legs, measured from its body textures as canvas fractions
# (y down) - a fit target for our own greaves, none of its pixels used. Each entry
# is (y, x_left, x_right); a body with two separate legs lists both.
RB_LEGS = {
    ("Male", "ns"): [
        [(0.790, 0.355, 0.497), (0.880, 0.357, 0.498), (0.940, 0.357, 0.496), (0.990, 0.369, 0.488), (0.999, 0.379, 0.480)],
        [(0.790, 0.503, 0.645), (0.880, 0.502, 0.643), (0.940, 0.504, 0.643), (0.990, 0.512, 0.631), (0.999, 0.520, 0.621)],
    ],
    ("Male", "east"): [
        [(0.780, 0.383, 0.561), (0.828, 0.369, 0.535), (0.883, 0.375, 0.523), (0.938, 0.383, 0.506), (0.992, 0.410, 0.498), (0.999, 0.422, 0.465)],
    ],
    # Female thighs meet below the hips, so it is drawn as one tapered column with
    # a centre seam rather than two greaves with a gap that is not there.
    ("Female", "ns"): [
        [(0.760, 0.348, 0.652), (0.822, 0.371, 0.629), (0.873, 0.387, 0.611), (0.924, 0.398, 0.602), (0.975, 0.432, 0.568), (0.996, 0.459, 0.541)],
    ],
    ("Female", "east"): [
        [(0.773, 0.359, 0.504), (0.828, 0.352, 0.490), (0.883, 0.361, 0.475), (0.938, 0.365, 0.461), (0.992, 0.395, 0.453)],
    ],
    ("Thin", "ns"): [
        [(0.775, 0.402, 0.598), (0.826, 0.410, 0.590), (0.877, 0.416, 0.584), (0.928, 0.426, 0.574), (0.979, 0.445, 0.555), (0.996, 0.473, 0.527)],
    ],
    ("Thin", "east"): [
        [(0.773, 0.357, 0.482), (0.826, 0.350, 0.467), (0.879, 0.354, 0.453), (0.932, 0.354, 0.432), (0.984, 0.381, 0.418)],
    ],
}
RB_BODIES = ("Male", "Female", "Thin")
GREAVE_PAD = 0.010     # canvas fractions the plate stands proud of the leg
RB_FOLDER = "1.6/Mods/RealisticBody/Textures"


# ---------------------------------------------------------------- primitives
class Frame:
    """Maps body-box units to supersampled canvas pixels for one body/facing."""

    def __init__(self, box, male_box):
        x0, x1, y0, y1 = box
        # k converts a FIXED width, given in Male box widths, into this box's
        # units. Pauldrons are the same plate on any wearer; scaled with the box
        # they were enormous on Fat and spindly on Thin.
        self.k = (male_box[1] - male_box[0]) / (x1 - x0)
        self.ox, self.oy = x0 * CANVAS * SS, y0 * CANVAS * SS
        self.bw, self.bh = (x1 - x0) * CANVAS * SS, (y1 - y0) * CANVAS * SS
        n = CANVAS * SS
        yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
        self.u = (xx - self.ox) / self.bw
        self.v = (yy - self.oy) / self.bh
        self.box = box

    def from_canvas(self, x, y):
        """A canvas-fraction point (y down) in this frame's box units."""
        x0, x1, y0, y1 = self.box
        return (x - x0) / (x1 - x0), (y - y0) / (y1 - y0)

    def px(self, length_u):
        return length_u * self.bw


def poly(fr, pts, round_=0.0):
    """Filled polygon in box units; round_ rounds its corners (box-width units)."""
    u, v = fr.u, fr.v
    inside = np.zeros(u.shape, bool)
    n = len(pts)
    for i in range(n):
        (u1, v1), (u2, v2) = pts[i], pts[(i + 1) % n]
        cond = (v1 > v) != (v2 > v)
        with np.errstate(divide="ignore", invalid="ignore"):
            xint = (u2 - u1) * (v - v1) / (v2 - v1) + u1
        inside ^= cond & (u < xint)
    if round_ > 0:
        r = fr.px(round_)
        inside = cw.blur(cw.blur(inside.astype(np.float32), r), r) > 0.5
    return inside


def ellipse(fr, cu, cv, ru, rv):
    return ((fr.u - cu) / ru) ** 2 + ((fr.v - cv) / rv) ** 2 <= 1.0


def line(fr, pts, width_px):
    """Polyline of the given width in FINAL pixels."""
    u, v = fr.u, fr.v
    w = width_px * SS / 2.0
    out = np.zeros(u.shape, bool)
    for (u1, v1), (u2, v2) in zip(pts, pts[1:]):
        # distance in pixels from each point to the segment
        ax, ay = u1 * fr.bw, v1 * fr.bh
        bx, by = u2 * fr.bw, v2 * fr.bh
        px, py = u * fr.bw, v * fr.bh
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy or 1.0
        t = np.clip(((px - ax) * dx + (py - ay) * dy) / L, 0, 1)
        d2 = (px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2
        out |= d2 <= w * w
    return out


def plane_split(fr, mask, a, b, c):
    """The SIDE face of a panel: where a*u + b*v > c. One straight plane break."""
    return mask & (a * fr.u + b * fr.v > c)


def greaves(fr, legs, add, profile=False):
    """Plate over each measured leg, padded out a little so it reads as armour
    over a limb, with a knee cop. Drawn BEFORE the torso panels, so the hip plates
    overlap the top of the thighs the way they would on a real suit."""
    for leg in legs:
        pts_l = [fr.from_canvas(xl - GREAVE_PAD, y) for y, xl, xr in leg]
        pts_r = [fr.from_canvas(xr + GREAVE_PAD, y) for y, xl, xr in leg]
        shape = poly(fr, pts_l + pts_r[::-1], round_=0.03)
        mid_u = np.mean([fr.from_canvas((xl + xr) / 2, y)[0] for y, xl, xr in leg])
        add(shape, "plate", plane_split(fr, shape, 1.0, 0.0, mid_u))
        # Knee cop: a short band two-fifths of the way down the leg.
        y0, y1 = leg[0][0], leg[-1][0]
        yk = y0 + (y1 - y0) * 0.40
        row = min(leg, key=lambda r: abs(r[0] - yk))
        a, b = fr.from_canvas(row[1] - GREAVE_PAD * 0.5, yk - 0.020), fr.from_canvas(row[2] + GREAVE_PAD * 0.5, yk + 0.020)
        knee = poly(fr, [(a[0], a[1]), (b[0], a[1]), (b[0], b[1]), (a[0], b[1])], round_=0.03)
        add(knee, "plate", plane_split(fr, knee, 1.0, 0.0, mid_u))
    if len(legs) == 1 and not profile:
        # One column for two legs (Female, Thin) seen from the front or back: a
        # centre seam keeps them two legs. Not in profile, where the legs overlap.
        top = fr.from_canvas(np.mean(legs[0][0][1:]), legs[0][0][0] + 0.02)
        bot = fr.from_canvas(np.mean(legs[0][-1][1:]), legs[0][-1][0])
        add(line(fr, [top, bot], PANEL_LINE * 0.8), "ink")


def skin_legs(fr, legs, add, profile=False):
    """Skin-tight legs: the measured outline with no padding - a bodysuit, not
    plate. Used by scarabSkin, whose lattice continues down them."""
    for leg in legs:
        pts_l = [fr.from_canvas(xl, y) for y, xl, xr in leg]
        pts_r = [fr.from_canvas(xr, y) for y, xl, xr in leg]
        shape = poly(fr, pts_l + pts_r[::-1], round_=0.02)
        mid_u = np.mean([fr.from_canvas((xl + xr) / 2, y)[0] for y, xl, xr in leg])
        add(shape, "skin", plane_split(fr, shape, 1.0, 0.0, mid_u))
    if len(legs) == 1 and not profile:
        top = fr.from_canvas(np.mean(legs[0][0][1:]), legs[0][0][0] + 0.02)
        bot = fr.from_canvas(np.mean(legs[0][-1][1:]), legs[0][-1][0])
        add(line(fr, [top, bot], PANEL_LINE * 0.8), "ink")


def lattice(fr, region, period_px=7.0, width_px=1.1):
    """The light-drinking weave: two families of diagonal lines, in final pixels."""
    x, y = fr.u * fr.bw, fr.v * fr.bh
    p, w = period_px * SS, width_px * SS
    a = np.mod(x + y, p) < w
    b = np.mod(x - y, p) < w
    return region & (a | b)


# ------------------------------------------------------------------- designs
def pulse_armor(fr, facing, body_mask, legs=None):
    """Pulse armour: a sleek cuirass over a dark servo suit, flared pauldrons,
    a dark gorget the head sits in, a cinched waist over hip plates - and on the
    back, the shield generator that rides the spine.

    Returns a list of (mask, tone, side_mask) back to front; side_mask is the
    part of the panel that takes the darker plane."""
    P = []
    def add(mask, tone, side=None):
        P.append((mask, tone, side if side is not None else np.zeros_like(mask)))

    # The servo suit under everything: the body itself, dark.
    add(body_mask, "suit")
    if legs:
        greaves(fr, legs, add, profile=(facing == "east"))

    if facing in ("south", "north"):
        back = facing == "north"
        # Hip plates (tassets), two, flaring outward. Light comes from the left,
        # so every panel's RIGHT face is the darker plane - one rule, all panels.
        # Narrow and separated, with dark suit showing between and around them:
        # drawn wide and touching, the whole lower half read as one gold block -
        # a tabard, not plate - beside armour that defines its hips with gaps.
        for s in (-1, 1):
            cu = 0.5 + s * 0.22
            lo_out, lo_in = (cu - 0.19, cu + 0.13) if s < 0 else (cu - 0.13, cu + 0.19)
            t = poly(fr, [(cu - 0.15, 0.76), (cu + 0.15, 0.76), (lo_in, 0.97), (lo_out, 0.97)],
                     round_=0.04)
            add(t, "plate", plane_split(fr, t, 1.0, 0.0, cu))

        # Waist: dark cinch band, narrower than the chest.
        waist = poly(fr, [(0.18, 0.56), (0.82, 0.56), (0.76, 0.80), (0.24, 0.80)], round_=0.03)
        add(waist, "suit")
        # Cuirass. Front: a broad chest plate tapering to the waist. Back: the
        # same outline, flatter.
        cuirass = poly(fr, [(0.06, 0.10), (0.94, 0.10), (0.92, 0.36), (0.74, 0.60),
                            (0.26, 0.60), (0.08, 0.36)], round_=0.06)
        add(cuirass, "plate", plane_split(fr, cuirass, 1.0, 0.55, 0.5 + 0.55 * 0.36))
        # Abdominal plate under the chest, on the front only.
        if not back:
            ab = poly(fr, [(0.36, 0.58), (0.64, 0.58), (0.60, 0.72), (0.40, 0.72)], round_=0.03)
            add(ab, "plate", plane_split(fr, ab, 1.0, 0.0, 0.52))

        if back:
            # The shield generator: a raised pack down the spine with a lit vent.
            # Top edge kept below the neck line: at 0.06 it crowded up into the
            # hair, where every comparison armour leaves the neck clear.
            pack = poly(fr, [(0.30, 0.15), (0.70, 0.15), (0.66, 0.58), (0.34, 0.58)], round_=0.05)
            add(pack, "trim", plane_split(fr, pack, 1.0, 0.0, 0.52))
            add(poly(fr, [(0.43, 0.24), (0.57, 0.24), (0.56, 0.48), (0.44, 0.48)], round_=0.02), "glow")
        else:
            # Gorget: the dark collar the head sits in.
            add(ellipse(fr, 0.5, 0.06, 0.22, 0.11), "suit")

        # Pauldrons: flared shells that rise past the shoulder line and overhang
        # the body - this bulk is what makes armour read as armour.
        hw = 0.26 * fr.k                                      # fixed size, see Frame.k
        for s in (-1, 1):
            cu = 0.5 + s * (0.5 + 0.02 * fr.k)               # centred on the shoulder edge
            sh = poly(fr, [(cu - hw, 0.00), (cu + hw, 0.00),
                           (cu + hw * (0.92 if s > 0 else 0.55), 0.36),
                           (cu - hw * (0.55 if s > 0 else 0.92), 0.36)], round_=0.07 * fr.k)
            sh |= ellipse(fr, cu, 0.02, hw, 0.12)            # domed top
            right = plane_split(fr, sh, 1.0, 0.0, cu + 0.15 * hw)
            under = sh & (fr.v > 0.27)
            add(sh, "plate", right | under)

    else:  # east: profile facing right; the back is on the left
        # Shield generator pack on the back, standing proud of the spine.
        pack = poly(fr, [(-0.22, 0.04), (0.14, 0.02), (0.16, 0.58), (-0.16, 0.56)], round_=0.06)
        add(pack, "trim", plane_split(fr, pack, 0.0, 1.0, 0.40))
        add(poly(fr, [(-0.12, 0.14), (-0.04, 0.14), (-0.04, 0.46), (-0.12, 0.46)], round_=0.02), "glow")
        # Hip plate.
        tas = poly(fr, [(0.30, 0.76), (0.82, 0.76), (0.80, 0.97), (0.36, 0.97)], round_=0.04)
        add(tas, "plate", plane_split(fr, tas, 0.0, 1.0, 0.90))
        add(poly(fr, [(0.10, 0.56), (0.92, 0.56), (0.86, 0.80), (0.16, 0.80)], round_=0.03), "suit")
        # Cuirass in profile: chest pushed forward past the body.
        cuirass = poly(fr, [(0.04, 0.08), (0.80, 0.06), (1.10, 0.24), (1.04, 0.52),
                            (0.84, 0.64), (0.10, 0.64)], round_=0.07)
        add(cuirass, "plate", plane_split(fr, cuirass, 0.0, 1.0, 0.46))
        # Gorget at the front of the neck.
        add(ellipse(fr, 0.66, 0.05, 0.20, 0.10), "suit")
        # Near pauldron: a big shell over the shoulder, tipped forward.
        sh = poly(fr, [(0.06, -0.06), (0.74, -0.08), (0.84, 0.30), (0.12, 0.40)], round_=0.08)
        sh |= ellipse(fr, 0.42, -0.04, 0.34, 0.12)
        add(sh, "plate", plane_split(fr, sh, 0.0, 1.0, 0.26))

    return P


def recoil_armor(fr, facing, body_mask, legs=None):
    """recoilArmor: interlocking plates that coil round the body "closer to a
    liquid settling than a suit fastening". So it is drawn as LAMES - horizontal
    bands stacked and overlapping, each drawn under the one above - where pulse
    armour is a few big shells. Lighter bulk than pulse (no generator, smaller
    pauldrons), a plate gorget rather than a dark collar, and the same caste dye."""
    P = []

    def add(mask, tone, side=None):
        P.append((mask, tone, side if side is not None else np.zeros_like(mask)))

    add(body_mask, "suit")
    if legs:
        greaves(fr, legs, add, profile=(facing == "east"))

    if facing in ("south", "north"):
        # Skirt of three lames over the hips.
        for i, (v0, v1, w) in enumerate([(0.88, 0.98, 0.30), (0.80, 0.90, 0.33), (0.72, 0.82, 0.35)]):
            lame = poly(fr, [(0.5 - w, v0), (0.5 + w, v0), (0.5 + w - 0.03, v1), (0.5 - w + 0.03, v1)], round_=0.03)
            add(lame, "plate", plane_split(fr, lame, 1.0, 0.0, 0.62))
        add(poly(fr, [(0.20, 0.60), (0.80, 0.60), (0.76, 0.72), (0.24, 0.72)], round_=0.03), "suit")
        # Torso lames, bottom first so each upper band overlaps the one below.
        bands = [(0.10, 0.27, 0.42), (0.24, 0.41, 0.42), (0.38, 0.54, 0.37), (0.50, 0.64, 0.30)]
        for v0, v1, w in reversed(bands):
            b = poly(fr, [(0.5 - w, v0), (0.5 + w, v0), (0.5 + w - 0.04, v1), (0.5 - w + 0.04, v1)], round_=0.04)
            add(b, "plate", plane_split(fr, b, 1.0, 0.0, 0.5 + w * 0.45))
        if facing == "north":
            spine = poly(fr, [(0.45, 0.06), (0.55, 0.06), (0.54, 0.64), (0.46, 0.64)], round_=0.02)
            add(spine, "plate", plane_split(fr, spine, 1.0, 0.0, 0.5))
        else:
            gorget = ellipse(fr, 0.5, 0.06, 0.24, 0.11)
            add(gorget, "plate", plane_split(fr, gorget, 1.0, 0.0, 0.58))
            add(ellipse(fr, 0.5, 0.05, 0.13, 0.065), "suit")
        # Pauldrons: two stacked lames each side, the lower one wider.
        hw = 0.19 * fr.k
        for s in (-1, 1):
            cu = 0.5 + s * (0.5 + 0.01 * fr.k)
            low = poly(fr, [(cu - hw, 0.12), (cu + hw, 0.12), (cu + hw * 0.9, 0.34), (cu - hw * 0.9, 0.34)], round_=0.06 * fr.k)
            add(low, "plate", plane_split(fr, low, 1.0, 0.0, cu + 0.2 * hw))
            top = poly(fr, [(cu - hw * 0.85, -0.02), (cu + hw * 0.85, -0.02), (cu + hw * 0.8, 0.18), (cu - hw * 0.8, 0.18)], round_=0.06 * fr.k)
            top |= ellipse(fr, cu, 0.0, hw * 0.85, 0.08)
            add(top, "plate", plane_split(fr, top, 1.0, 0.0, cu + 0.2 * hw))
    else:
        for v0, v1, a, b in [(0.88, 0.98, 0.32, 0.80), (0.80, 0.90, 0.28, 0.84), (0.72, 0.82, 0.24, 0.88)]:
            lame = poly(fr, [(a, v0), (b, v0), (b - 0.02, v1), (a + 0.02, v1)], round_=0.03)
            add(lame, "plate", plane_split(fr, lame, 0.0, 1.0, (v0 + v1) / 2 + 0.02))
        add(poly(fr, [(0.10, 0.60), (0.92, 0.60), (0.86, 0.72), (0.16, 0.72)], round_=0.03), "suit")
        bands = [(0.08, 0.26, 0.02, 0.86), (0.22, 0.40, 0.02, 1.04), (0.36, 0.52, 0.04, 1.00), (0.48, 0.64, 0.08, 0.90)]
        for v0, v1, a, b in reversed(bands):
            band = poly(fr, [(a, v0), (b, v0), (b - 0.03, v1), (a + 0.02, v1)], round_=0.04)
            add(band, "plate", plane_split(fr, band, 0.0, 1.0, v0 + (v1 - v0) * 0.62))
        add(ellipse(fr, 0.66, 0.05, 0.18, 0.09), "suit")
        hw = 0.30
        for v0, v1, sc in [(0.12, 0.36, 1.0), (-0.04, 0.20, 0.85)]:
            sh = poly(fr, [(0.46 - hw * sc, v0), (0.46 + hw * sc, v0), (0.46 + hw * sc * 0.9, v1), (0.46 - hw * sc * 0.9, v1)], round_=0.06)
            add(sh, "plate", plane_split(fr, sh, 0.0, 1.0, v0 + (v1 - v0) * 0.66))
    return P


def duro_armor(fr, facing, body_mask, legs=None):
    """duroArmor: "a stamped duroSteel cuirass with shoulder caps, issued by the
    crate and fitted by nobody." A Middle-layer cuirass and nothing else: plain
    steel with a pressed centre ridge, a leather belt, small caps set close to the
    neck. No suit is drawn under it - whatever the pawn wears shows below and
    around it, which is what makes it read as cheap kit over clothes. Torso and
    shoulders only, so it never has legs."""
    P = []

    def add(mask, tone, side=None):
        P.append((mask, tone, side if side is not None else np.zeros_like(mask)))

    if facing in ("south", "north"):
        cuirass = poly(fr, [(0.08, 0.10), (0.92, 0.10), (0.90, 0.40), (0.78, 0.68), (0.22, 0.68), (0.10, 0.40)], round_=0.05)
        # The pressed ridge down the middle IS the plane break: left lit, right dark.
        add(cuirass, "steel", plane_split(fr, cuirass, 1.0, 0.0, 0.5))
        add(poly(fr, [(0.20, 0.62), (0.80, 0.62), (0.78, 0.70), (0.22, 0.70)], round_=0.015), "strap")
        if facing == "south":
            add(poly(fr, [(0.45, 0.62), (0.55, 0.62), (0.55, 0.70), (0.45, 0.70)], round_=0.01), "trim")
            add(ellipse(fr, 0.5, 0.08, 0.17, 0.08), "suit")       # neck opening
        hw = 0.13 * fr.k
        for s in (-1, 1):
            cu = 0.5 + s * (0.40 + 0.02 * fr.k)
            cap = ellipse(fr, cu, 0.10, hw, 0.12)
            add(cap, "steel", plane_split(fr, cap, 1.0, 0.0, cu))
    else:
        cuirass = poly(fr, [(0.08, 0.10), (0.78, 0.08), (1.02, 0.26), (0.96, 0.52), (0.82, 0.68), (0.14, 0.68)], round_=0.06)
        add(cuirass, "steel", plane_split(fr, cuirass, 0.0, 1.0, 0.40))
        add(poly(fr, [(0.12, 0.62), (0.86, 0.62), (0.84, 0.70), (0.14, 0.70)], round_=0.015), "strap")
        cap = ellipse(fr, 0.44, 0.12, 0.22, 0.12)
        add(cap, "steel", plane_split(fr, cap, 0.0, 1.0, 0.14))
    return P


def scarab_skin(fr, facing, body_mask, legs=None):
    """scarabSkin: "a skin rather than a suit ... woven from a lattice that drinks
    light." Fitted to the body with no overhang at all, near-black, the lattice as
    a faint diagonal weave, and only the slightest plane of form - a thing you
    are meant to fail to see."""
    P = []

    def add(mask, tone, side=None):
        P.append((mask, tone, side if side is not None else np.zeros_like(mask)))

    side = (plane_split(fr, body_mask, 1.0, 0.0, 0.62) if facing != "east"
            else plane_split(fr, body_mask, 0.0, 1.0, 0.70))
    add(body_mask, "skin", side)
    if legs:
        skin_legs(fr, legs, add, profile=(facing == "east"))
    allb = np.zeros_like(body_mask)
    for m, _, _ in P:
        allb |= m
    weave = lattice(fr, allb)
    P.append((weave, "lattice", np.zeros_like(weave)))
    # A collar seam and a waist seam: the only lines on it.
    if facing != "north":
        add(line(fr, [(0.30, 0.10), (0.5, 0.18), (0.70, 0.10)] if facing == "south" else [(0.50, 0.08), (0.70, 0.16), (0.90, 0.12)], PANEL_LINE * 0.7), "ink")
    add(line(fr, [(0.18, 0.64), (0.82, 0.64)] if facing != "east" else [(0.12, 0.64), (0.88, 0.64)], PANEL_LINE * 0.6), "ink")
    return P


def ghost_cloak(fr, facing, body_mask, legs=None):
    """ghostCloak: a Howler's cloak - "unremarkable cloth until it is switched
    on". Shell layer, so it hangs over whatever is worn under it: from the front,
    two panels falling from the shoulders and open down the middle; from behind,
    one wide drape with a hood; in profile, a drape behind the back. A faint
    cyan hairline at the hem is the refractive lattice, the one hint of what it is.

    On Realistic Body the hem drops lower, to mid-shin, since there are legs for
    it to cover; on vanilla's legless body it stops just past the hips."""
    P = []

    def add(mask, tone, side=None):
        P.append((mask, tone, side if side is not None else np.zeros_like(mask)))

    hem = fr.from_canvas(0.5, 0.94)[1] if legs else 1.06
    if facing == "north":
        hood = ellipse(fr, 0.5, 0.02, 0.30, 0.13)
        add(hood, "lining")
        drape = poly(fr, [(-0.04, 0.02), (1.04, 0.02), (1.14, hem), (-0.14, hem)], round_=0.05)
        add(drape, "cloth", plane_split(fr, drape, 1.0, 0.0, 0.70))
        for x0 in (0.30, 0.52, 0.74):
            add(line(fr, [(x0, 0.18), (x0 + 0.04 * (x0 - 0.5), hem - 0.03)], PANEL_LINE * 0.6), "ink")
        add(line(fr, [(-0.12, hem - 0.03), (1.12, hem - 0.03)], 1.4), "glow")
        add(ellipse(fr, 0.5, 0.05, 0.22, 0.09), "cloth", ellipse(fr, 0.5, 0.05, 0.22, 0.09) & (fr.u > 0.56))
    elif facing == "south":
        add(ellipse(fr, 0.5, 0.0, 0.32, 0.12), "lining")          # hood fallen behind the neck
        # Panels fall from the shoulders, wide, leaving a narrow opening down the
        # front. Drawn first so the mantle overlaps their tops.
        for s in (-1, 1):
            pts = [(0.5 + s * 0.12, 0.14), (0.5 + s * 0.60, 0.14), (0.5 + s * 0.68, hem), (0.5 + s * 0.18, hem)]
            panel = poly(fr, pts, round_=0.04)
            add(panel, "cloth", plane_split(fr, panel, 1.0, 0.0, 0.5 + s * 0.45) if s > 0 else None)
            edge = poly(fr, [(0.5 + s * 0.12, 0.14), (0.5 + s * 0.19, 0.14), (0.5 + s * 0.25, hem), (0.5 + s * 0.18, hem)], round_=0.015)
            add(edge & panel, "lining")
            add(line(fr, [(0.5 + s * 0.66, hem - 0.03), (0.5 + s * 0.19, hem - 0.03)], 1.4), "glow")
        # The mantle across the shoulders is what makes a cloak read as a cloak
        # from the front; two strips alone read as trousers.
        mantle = poly(fr, [(-0.12, 0.06), (0.30, -0.02), (0.70, -0.02), (1.12, 0.06),
                           (1.10, 0.26), (0.5, 0.32), (-0.10, 0.26)], round_=0.06)
        add(mantle, "cloth", plane_split(fr, mantle, 1.0, 0.0, 0.64))
        add(ellipse(fr, 0.5, 0.05, 0.16, 0.08), "lining")           # the neck, inside the mantle
        clasp = ellipse(fr, 0.5, 0.14, 0.06, 0.045)
        add(clasp, "trim", plane_split(fr, clasp, 1.0, 0.0, 0.5))
    else:
        add(ellipse(fr, 0.18, 0.02, 0.26, 0.12), "lining")
        drape = poly(fr, [(0.02, 0.02), (0.70, 0.04), (0.60, hem), (-0.32, hem)], round_=0.05)
        add(drape, "cloth", plane_split(fr, drape, 0.0, 1.0, 0.55))
        add(line(fr, [(0.22, 0.24), (0.02, hem - 0.04)], PANEL_LINE * 0.6), "ink")
        add(line(fr, [(-0.30, hem - 0.03), (0.58, hem - 0.03)], 1.4), "glow")
        mantle = poly(fr, [(0.0, 0.0), (0.82, 0.02), (0.90, 0.24), (0.04, 0.30)], round_=0.06)
        add(mantle, "cloth", plane_split(fr, mantle, 0.0, 1.0, 0.16))
    return P


# design -> (function, dyed?, which body types get a Realistic Body variant)
#   dyed: writes tint masks (worn and icon); only caste-coloured plate is dyed.
#   rb:   True when the design draws something on Realistic Body's legs.
DESIGNS = {
    "pulse":  (pulse_armor, True, True),
    "recoil": (recoil_armor, True, True),
    "duro":   (duro_armor, False, False),
    "scarab": (scarab_skin, False, True),
    "cloak":  (ghost_cloak, False, True),
}


# --------------------------------------------------------------------- draw
def draw(design, body, facing, box=None, rb=False):
    """box overrides the measured body box - the item icon uses it to draw the
    same front design scaled up to fill its own frame."""
    kind = "east" if facing == "east" else "ns"
    box = box or cw.BOXES[body][kind]
    fr = Frame(box, cw.BOXES["Male"][kind])
    n = CANVAS * SS

    # The body outline, from the compositor's fitted beans, as the suit layer.
    bx, by, bw, bh = cw.place_box(box)
    body_mask = np.zeros((n, n), bool)
    b = cw.bean(kind, bw * SS, bh * SS, body)
    body_mask[by * SS:by * SS + b.shape[0], bx * SS:bx * SS + b.shape[1]] = b

    legs = RB_LEGS.get((body, kind)) if rb else None
    parts = DESIGNS[design][0](fr, facing, body_mask, legs)

    rgb = np.zeros((n, n, 3), np.float32)
    alpha = np.zeros((n, n), bool)
    dyed = np.zeros((n, n), bool)
    panel_ring = PANEL_LINE * SS

    for mask, tone, side in parts:
        if not mask.any():
            continue
        lit, dark = TONE[tone]
        ring = cw.dilate(mask, panel_ring) & ~mask
        rgb[ring] = INK
        dyed[ring] = False
        rgb[mask] = lit
        rgb[mask & side] = dark
        dyed[mask] = tone in DYED
        alpha |= mask | ring

    # The silhouette gets the heavier outline, under everything.
    sil = cw.dilate(alpha, OUTLINE * SS) & ~alpha
    rgb[sil] = INK
    alpha |= sil

    a = alpha.astype(np.float32)
    tex = np.dstack([rgb * a[..., None], a])
    msk = np.dstack([dyed.astype(np.float32) * a, np.zeros_like(a), np.zeros_like(a), a])

    def finish(img):
        d = cw.downsample(img, SS)
        out = d.copy()
        nz = d[..., 3] > 1e-4
        out[nz, :3] = d[nz, :3] / d[nz, 3:4]
        return out

    return finish(tex), finish(msk)


# The item icon: the front design with the body box placed so the whole suit -
# pauldrons at about -0.28..1.28 box widths, top at -0.12 - fills a square frame
# with a margin. Drawn on the 256 canvas and halved to the measured 128x128 item
# size, so the icon matches the worn sprite by construction.
ICON_BOX = (0.22, 0.78, 0.20, 0.82)
ICON_SIZE = 128


# Which view an item icon shows. Front by default; the cloak's front is two
# panels with nobody inside them and read as trousers, so it shows its back.
ICON_FACING = {"cloak": "north"}


def write_icon(design, path):
    tex, msk = draw(design, "Male", ICON_FACING.get(design, "south"), box=ICON_BOX)
    f = CANVAS // ICON_SIZE

    def half(img):
        d = cw.downsample(img * np.dstack([img[..., 3:4]] * 3 + [np.ones_like(img[..., 3:4])]), f)
        out = d.copy()
        nz = d[..., 3] > 1e-4
        out[nz, :3] = d[nz, :3] / d[nz, 3:4]
        return out

    cw.save_png(path + ".png", half(tex))
    # Graphic_Single's mask is <texPath>_m (MaskSuffix, decompiled - see CLAUDE.md).
    if DESIGNS[design][1]:
        cw.save_png(path + "_m.png", half(msk))
    print("WROTE", path, "(icon)")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    design, prefix = argv[0], os.path.abspath(argv[1])
    if len(argv) > 2 and argv[2] == "--rb" and not DESIGNS[design][2]:
        print("SKIP", design, "has nothing for Realistic Body's legs; base sprites serve")
        sys.exit(0)
    if len(argv) > 2 and argv[2] == "--rb":
        # Realistic Body variants: Male, Female, Thin only, with greaves, written
        # under 1.6/Mods/RealisticBody/Textures at the SAME relative path as the
        # base sprites. LoadFolders lists that folder last and gated on
        # nals.realisticbody; the game keeps the first file it finds walking load
        # folders last-to-first (ModContentPack.AddFolders / GetAllFilesForMod,
        # decompiled), so these override the base sprites only for RB players.
        repo = os.path.dirname(HERE)
        rel = os.path.relpath(prefix, os.path.join(repo, "Textures"))
        out = os.path.join(repo, *RB_FOLDER.split("/"), rel)
        for body in RB_BODIES:
            for facing in cw.FACINGS:
                tex, msk = draw(design, body, facing, rb=True)
                cw.save_png(f"{out}_{body}_{facing}.png", tex)
                if DESIGNS[design][1]:
                    cw.save_png(f"{out}_{body}_{facing}m.png", msk)
                print("WROTE", f"{out}_{body}_{facing}")
        sys.exit(0)
    if len(argv) > 2 and argv[2] == "--icon":
        write_icon(design, prefix)
        # Optional second target: the same icon, undyed, for a precept that is
        # about this armour (pulse armour -> UI/Issues/RR_ArmorBearing). Masks
        # are irrelevant there; precept icons are never tinted.
        if len(argv) > 3:
            tex, _ = draw(design, "Male", "south", box=ICON_BOX)
            f = CANVAS // ICON_SIZE
            prem = tex * np.dstack([tex[..., 3:4]] * 3 + [np.ones_like(tex[..., 3:4])])
            d = cw.downsample(prem, f)
            nz = d[..., 3] > 1e-4
            d[nz, :3] = d[nz, :3] / d[nz, 3:4]
            cw.save_png(os.path.abspath(argv[3]), d)
            print("WROTE", argv[3], "(precept icon)")
        sys.exit(0)
    for body in cw.BOXES:
        for facing in cw.FACINGS:
            tex, msk = draw(design, body, facing)
            cw.save_png(f"{prefix}_{body}_{facing}.png", tex)
            if DESIGNS[design][1]:
                cw.save_png(f"{prefix}_{body}_{facing}m.png", msk)
            print("WROTE", f"{prefix}_{body}_{facing}")
