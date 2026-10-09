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

dw.C.update({
    "ridge":   (np.array([0.70, 0.65, 0.57]), np.array([0.70, 0.65, 0.57])),
    "under":   (np.array([0.45, 0.41, 0.36]), np.array([0.45, 0.41, 0.36])),
    "blotch":  (np.array([0.42, 0.37, 0.31]), np.array([0.42, 0.37, 0.31])),
    "socket":  (np.array([0.30, 0.27, 0.24]), np.array([0.30, 0.27, 0.24])),
})


def _bezier(p0, p1, p2, n):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in np.linspace(0, 1, n)]


def _normal(pts, i):
    (ax, ay), (bx, by) = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
    dx, dy = bx - ax, by - ay
    L = math.hypot(dx, dy) or 1
    return -dy / L, dx / L


# A pit viper at rest: a tight coil on the ground and an S-neck raised out of it,
# the broad wedge head pointing the way the animal faces. (cx, cy) is the coil's
# centre, (hx, hy) the head, ctrl the neck's bend, ang the head's heading.
POSES = {
    "south": dict(cx=0.50, cy=0.68, hx=0.52, hy=0.42, ctrl=(0.70, 0.36), ang=90),
    "north": dict(cx=0.50, cy=0.68, hx=0.50, hy=0.26, ctrl=(0.34, 0.46), ang=-90),
    "east":  dict(cx=0.40, cy=0.66, hx=0.80, hy=0.38, ctrl=(0.52, 0.30), ang=8),
}


def pitviper(pose, dry=False, size=128):
    P = POSES[pose]
    cv = Canvas(size)
    # Coil: one and a bit turns, tail first, the tail tapering to a point.
    coil = spiral(P["cx"], P["cy"], 0.31, 0.12, 1.15, math.radians(200), n=70)
    neck = _bezier(coil[-1], P["ctrl"], (P["hx"], P["hy"]), 24)
    half = len(coil) // 2
    coil_mask = cv.ribbon(coil[:half + 1], 0.012, 0.13) | cv.ribbon(coil[half:], 0.13, 0.12)
    neck_mask = cv.ribbon(neck, 0.11, 0.085)
    X = Xform(cv, P["hx"], P["hy"], 0.10, P["ang"])
    head = X.poly([(1.15, 0.0), (0.55, -0.66), (-0.30, -0.86), (-0.80, -0.42),
                   (-0.80, 0.42), (-0.30, 0.86), (0.55, 0.66)])

    def shade(pts, w, mask):
        """Roundness: a darker underside along the lower-right edge, a pale ridge
        along the upper-left of the spine. Light from the upper left."""
        under = mask.copy()
        lit = np.zeros_like(mask)
        for k in range(len(pts) - 1):
            nx, ny = _normal(pts, k)
            if nx + ny * 0.6 > 0:          # make the normal point upper-left
                nx, ny = -nx, -ny
            off = 0.28 * w
            seg = [(pts[k][0] + nx * off, pts[k][1] + ny * off),
                   (pts[k + 1][0] + nx * off, pts[k + 1][1] + ny * off)]
            lit |= cv.ribbon(seg, w * 0.95, w * 0.95)
        under &= ~lit
        cv.rgb[under & mask] = dw.C["under"][0]

    if dry:
        cv.part(coil_mask, "bonewhite", None, panel_px=2.0)
        keep = cv.rgb.copy()
        cv.part(neck_mask | head, "bonewhite", None, panel_px=2.0)
        join = cv.disc(*coil[-1], 0.09) & coil_mask & ~(neck_mask | head)
        cv.rgb[join] = keep[join]
        for pts, w in ((coil, 0.10), (neck, 0.08)):
            cv.line(pts[3:-3], 1.6)                             # spine
            for i in range(4, len(pts) - 3, 4):                 # ribs
                nx, ny = _normal(pts, i)
                cv.line([(pts[i][0] - nx * w * 0.5, pts[i][1] - ny * w * 0.5),
                         (pts[i][0] + nx * w * 0.5, pts[i][1] + ny * w * 0.5)], 1.8)
        if pose != "north":
            fill(X, X.ell(0.15, -0.42, 0.22, 0.20) | X.ell(0.15, 0.42, 0.22, 0.20), "socket")
        return cv.finish(SNAKE_OUTLINE)

    # The coil, then the neck and head drawn OVER it as one shape, so the head
    # has no seam; where the neck leaves the coil, the coil's colour is restored
    # over the neck's ring so no line cuts across the body at the join.
    cv.part(coil_mask, "rock", None, panel_px=2.0)
    shade(coil, 0.12, coil_mask)
    for i in range(6, len(coil) - 2, 7):                        # soft blotches down the spine
        w = 0.05 * min(1.0, i / 20)
        fill(X, cv.disc(*coil[i], w) & coil_mask, "blotch")
    keep = cv.rgb.copy()
    front = neck_mask | head
    cv.part(front, "rock", None, panel_px=2.0)
    join = cv.disc(*coil[-1], 0.09) & coil_mask & ~front
    cv.rgb[join] = keep[join]
    shade(neck, 0.10, neck_mask & ~head)
    for i in range(5, len(neck) - 6, 6):
        fill(X, cv.disc(*neck[i], 0.035) & neck_mask, "blotch")
    cv.rgb[head & X.dark(0.1, 0.0, 1.0)] = dw.C["under"][0]
    # The pit viper's mark: a dark chevron on the crown, pointing forward.
    fill(X, X.poly([(0.55, 0.0), (-0.40, -0.55), (-0.55, -0.38), (0.20, 0.0),
                    (-0.55, 0.38), (-0.40, 0.55)]), "blotch")
    if pose != "north":
        sides = (-1, 1) if pose == "south" else (-1,)
        for s in sides:
            fill(X, X.ell(0.30, 0.50 * s, 0.17, 0.15), "eye")
            fill(X, X.ell(0.30, 0.50 * s, 0.05, 0.13), "socket")
    return cv.finish(SNAKE_OUTLINE)


def spiral(cx, cy, r0, r1, turns, a0, n=60):
    pts = []
    for i in range(n):
        f = i / (n - 1)
        a = a0 + f * turns * 2 * math.pi
        r = r0 + (r1 - r0) * f
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.78))
    return pts



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
    PITVIPER + "_east": lambda: pitviper("east"),
    PITVIPER + "_south": lambda: pitviper("south"),
    PITVIPER + "_north": lambda: pitviper("north"),
    "Things/Pawn/Animal/RR_Pitviper/RR_Pitviper_Dessicated_east": lambda: pitviper("east", dry=True),
    "Things/Pawn/Animal/RR_Pitviper/RR_Pitviper_Dessicated_south": lambda: pitviper("south", dry=True),
    "Things/Pawn/Animal/RR_Pitviper/RR_Pitviper_Dessicated_north": lambda: pitviper("north", dry=True),
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
