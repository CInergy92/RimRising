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
    "ink":   (np.array([0x26, 0x22, 0x1E]) / 255.0, np.array([0x26, 0x22, 0x1E]) / 255.0),
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


DESIGNS = {"pulse": pulse_armor}


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
    parts = DESIGNS[design](fr, facing, body_mask, legs)

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


def write_icon(design, path):
    tex, msk = draw(design, "Male", "south", box=ICON_BOX)
    f = CANVAS // ICON_SIZE

    def half(img):
        d = cw.downsample(img * np.dstack([img[..., 3:4]] * 3 + [np.ones_like(img[..., 3:4])]), f)
        out = d.copy()
        nz = d[..., 3] > 1e-4
        out[nz, :3] = d[nz, :3] / d[nz, 3:4]
        return out

    cw.save_png(path + ".png", half(tex))
    # Graphic_Single's mask is <texPath>_m (MaskSuffix, decompiled - see CLAUDE.md).
    cw.save_png(path + "_m.png", half(msk))
    print("WROTE", path, "(icon)")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    design, prefix = argv[0], os.path.abspath(argv[1])
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
            cw.save_png(f"{prefix}_{body}_{facing}m.png", msk)
            print("WROTE", f"{prefix}_{body}_{facing}")
