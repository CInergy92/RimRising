"""
Draw RimRising's living things: the pitviper (alive and desiccated, three
facings) and the haemanthus (three Graphic_Random variants).

    blender -b --factory-startup --python Tools/Draw-Nature.py -- <out_dir>

MEASURED, from installed mods' loose art:
- A SNAKE (Boomsnake, 2801160906) is one tapered ribbon in an S or a coil with
  a head at one end, filling about 80% of a 128 canvas, under a thin dark
  outline. East is a side-on S with the head right; north and south are coils,
  head away from or toward the viewer. Its desiccated texture is the same pose
  in bone.
- A FLOWER (Vanilla Textures Expanded's dandelion) grows from the bottom centre
  of its canvas, a short stem and a bloom, with a soft dark edge rather than an
  item's heavy black one.

The pitviper's whole strategy is that "its colour matches the rock", so it is
helium-seam grey-brown with darker bands, not a showy snake. The haemanthus
is a blood lily: a round head of red filaments on a short dark stem.
"""
import importlib.machinery
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
di = importlib.machinery.SourceFileLoader(
    "draw_items", os.path.join(HERE, "Draw-Items.py")).load_module()
dw, cw, Canvas, Xform, part, fill = di.dw, di.cw, di.Canvas, di.Xform, di.part, di.fill

dw.C.update({
    "rock":     (np.array([0.58, 0.53, 0.46]), np.array([0.44, 0.40, 0.35])),
    "rockband": (np.array([0.36, 0.32, 0.28]), np.array([0.36, 0.32, 0.28])),
    "belly":    (np.array([0.74, 0.66, 0.52]), np.array([0.74, 0.66, 0.52])),
    "eye":      (np.array([0.95, 0.72, 0.20]), np.array([0.95, 0.72, 0.20])),
    "bonewhite": (np.array([0.88, 0.85, 0.76]), np.array([0.70, 0.67, 0.58])),
    "stem":     (np.array([0.24, 0.26, 0.18]), np.array([0.17, 0.19, 0.13])),
    "leaf":     (np.array([0.30, 0.36, 0.22]), np.array([0.22, 0.27, 0.16])),
    "bloom":    (np.array([0.80, 0.14, 0.16]), np.array([0.60, 0.08, 0.11])),
    "pollen":   (np.array([0.98, 0.80, 0.40]), np.array([0.98, 0.80, 0.40])),
})

SNAKE_OUTLINE = 3.0
PLANT_OUTLINE = 2.0


def spiral(cx, cy, r0, r1, turns, a0, n=60):
    pts = []
    for i in range(n):
        f = i / (n - 1)
        a = a0 + f * turns * 2 * math.pi
        r = r0 + (r1 - r0) * f
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.80))
    return pts


def snake(pts, head_at_end=True, dry=False, size=128, eyes=True, w0=0.15, w1=0.045):
    """A tapered body along pts (canvas fractions, tail first), with bands, and a
    head at the last point. dry=True draws the desiccated form: bone, ribs."""
    cv = Canvas(size)
    body = cv.ribbon(pts, w1, w0) if head_at_end else cv.ribbon(pts, w0, w1)
    hx, hy = pts[-1]
    px, py = pts[-4]
    ang = math.atan2(hy - py, hx - px)
    X = Xform(cv, hx, hy, 0.095, math.degrees(ang))
    head = X.ell(0.25, 0, 0.95, 0.72)
    if dry:
        part(X, body | head, "bonewhite", None)
        for i in range(4, len(pts) - 4, 3):        # ribs across the spine
            (ax, ay), (bx, by) = pts[i - 1], pts[i + 1]
            dx, dy = bx - ax, by - ay
            L = math.hypot(dx, dy) or 1
            nx, ny = -dy / L, dx / L
            w = 0.045
            cv.line([(pts[i][0] - nx * w, pts[i][1] - ny * w),
                     (pts[i][0] + nx * w, pts[i][1] + ny * w)], 2.0)
        cv.line(pts[2:-2], 1.6)                        # spine
        fill(X, X.ell(0.55, -0.28, 0.16, 0.14) | X.ell(0.55, 0.28, 0.16, 0.14), "rockband")
        return cv.finish(SNAKE_OUTLINE)
    lit = dw.C["rock"]
    cv.part(body, "rock", None, panel_px=2.0)
    for i in range(3, len(pts) - 5, 5):                # narrow cross-bands, clipped to the body
        (ax, ay), (bx, by) = pts[i - 1], pts[i + 1]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        band = cv.ribbon([(pts[i][0] - nx * 0.09, pts[i][1] - ny * 0.09),
                          (pts[i][0] + nx * 0.09, pts[i][1] + ny * 0.09)], 0.035, 0.035) & body
        cv.rgb[band] = dw.C["rockband"][0]
    cv.part(head, "rock", X.dark(0.0, 0.0, 1.0), panel_px=2.0)
    fill(X, X.ell(0.10, 0.0, 0.30, 0.40), "rockband")
    if eyes:
        for s in (-1, 1):
            fill(X, X.ell(0.55, 0.38 * s, 0.14, 0.13), "eye")
    return cv.finish(SNAKE_OUTLINE)


def east(dry=False):
    pts = [(0.07 + 0.80 * f, 0.60 - 0.18 * math.sin(f * math.pi * 2.2)) for f in np.linspace(0, 1, 40)]
    return snake(pts, dry=dry)


def coil(head_dy, eyes, dry=False):
    pts = spiral(0.50, 0.58, 0.36, 0.12, 1.3, math.radians(30))
    hx, hy = pts[-1]
    pts += [(hx + 0.01 * k, hy + head_dy * k / 6) for k in range(1, 7)]
    return snake(pts, dry=dry, eyes=eyes)


PITVIPER = "Things/Pawn/Animal/RR_Pitviper/RR_Pitviper"


def haemanthus(variant, size=128):
    """A short dark stem from the bottom centre, two strap leaves at its foot,
    and the blood-lily head: a red ball of filaments tipped with pollen."""
    rng = np.random.default_rng(7 + variant)
    cv = Canvas(size)
    lean = (-0.04, 0.03, 0.0)[variant]
    hy = (0.36, 0.42, 0.30)[variant]
    hx = 0.50 + lean
    for side in (-1, 1):                               # strap leaves
        cv.part(cv.ribbon([(0.50, 0.96), (0.50 + side * 0.16, 0.80), (0.50 + side * 0.30, 0.74)],
                          0.08, 0.02), "leaf", None, panel_px=1.5)
    cv.part(cv.ribbon([(0.50, 0.97), (hx, hy + 0.10)], 0.05, 0.035), "stem", None, panel_px=1.5)
    X = Xform(cv, hx, hy, 0.20)
    head = X.ell(0, 0, 1.0, 0.90)
    cv.part(head, "bloom", X.dark(0.15), panel_px=1.5)
    for _ in range(26):                                # filaments past the rim
        a = rng.uniform(0, 2 * math.pi)
        r0, r1 = 0.55, rng.uniform(1.05, 1.30)
        p0 = (math.cos(a) * r0, math.sin(a) * r0 * 0.9)
        p1 = (math.cos(a) * r1, math.sin(a) * r1 * 0.9)
        X.line([p0, p1], 1.6, "bloom")
        fill(X, X.ell(p1[0], p1[1], 0.07, 0.07), "pollen")
    return cv.finish(PLANT_OUTLINE)


OUTPUTS = {
    PITVIPER + "_east": lambda: east(),
    PITVIPER + "_south": lambda: coil(0.10, eyes=True),
    PITVIPER + "_north": lambda: coil(-0.10, eyes=False),
    "Things/Pawn/Animal/RR_Pitviper/RR_Pitviper_Dessicated_east": lambda: east(dry=True),
    "Things/Pawn/Animal/RR_Pitviper/RR_Pitviper_Dessicated_south": lambda: coil(0.10, False, dry=True),
    "Things/Pawn/Animal/RR_Pitviper/RR_Pitviper_Dessicated_north": lambda: coil(-0.10, False, dry=True),
    "Things/Plant/RR_Haemanthus/RR_Haemanthus_a": lambda: haemanthus(0),
    "Things/Plant/RR_Haemanthus/RR_Haemanthus_b": lambda: haemanthus(1),
    "Things/Plant/RR_Haemanthus/RR_Haemanthus_c": lambda: haemanthus(2),
}

if __name__ == "__main__":
    out = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
    for rel, fn in OUTPUTS.items():
        path = os.path.join(out, *rel.split("/")) + ".png"
        cw.save_png(path, fn())
        print("WROTE", path)
