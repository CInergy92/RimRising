"""
Draw RimRising's loose items in RimWorld's flat item idiom: drugs, medical
items, resources and the item icons of the small apparel pieces.

Run through Blender (for its bundled numpy), never directly:

    blender -b --factory-startup --python Tools/Draw-Items.py -- <out_dir> [name ...]

WHY REDRAWN. The earlier icons sat at about a quarter of their 128 canvas with
thin outlines. Measured against installed item art (Vanilla Textures Expanded
drugs, Medieval Overhaul, Alpha Animals resources), a single item fills roughly
half the canvas and a stack fills most of it, every object carries a heavy
black outline, and shading is one darker plane, never a gradient.

STACKS. Graphic_StackCount picks _a for one item, _b for a few, _c for a full
stack, so each StackCount item is drawn as 1, 3 and 5 copies of one object
piled back to front. Each copy has its own outline ring, which is what makes a
pile read as separate objects.

Objects are written in a LOCAL frame: u right, v down, the object about -1..1,
placed on the canvas by Xform (centre, scale, rotation). Shapes, plane splits
and highlights are all expressed in u/v, so one design serves every copy.
"""
import importlib.machinery
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
dw = importlib.machinery.SourceFileLoader(
    "draw_weapons", os.path.join(HERE, "Draw-Weapons.py")).load_module()
cw = dw.cw
Canvas = dw.Canvas

# lit face, shaded face - muted, as the reference art is
dw.C.update({
    "lozenge": (np.array([0.70, 0.71, 0.73]), np.array([0.50, 0.51, 0.54])),
    "tablet":  (np.array([0.95, 0.95, 0.93]), np.array([0.76, 0.77, 0.76])),
    "foil":    (np.array([0.74, 0.77, 0.80]), np.array([0.55, 0.58, 0.62])),
    "glass":   (np.array([0.80, 0.90, 0.92]), np.array([0.60, 0.72, 0.76])),
    "orange":  (np.array([0.96, 0.55, 0.18]), np.array([0.80, 0.38, 0.10])),
    "cake":    (np.array([0.36, 0.25, 0.18]), np.array([0.25, 0.17, 0.12])),
    "crust":   (np.array([0.50, 0.37, 0.25]), np.array([0.40, 0.29, 0.19])),
    "sack":    (np.array([0.62, 0.56, 0.45]), np.array([0.47, 0.42, 0.33])),
    "ash":     (np.array([0.62, 0.62, 0.60]), np.array([0.46, 0.46, 0.45])),
    "cord":    (np.array([0.42, 0.30, 0.20]), np.array([0.32, 0.22, 0.15])),
    "can":     (np.array([0.80, 0.82, 0.84]), np.array([0.58, 0.61, 0.65])),
    "flesh":   (np.array([0.86, 0.47, 0.50]), np.array([0.68, 0.33, 0.37])),
    "ion":     (np.array([0.55, 0.62, 0.72]), np.array([0.38, 0.44, 0.54])),
    "iongrain": (np.array([0.72, 0.82, 0.92]), np.array([0.72, 0.82, 0.92])),
    "vatfluid": (np.array([0.78, 0.45, 0.50]), np.array([0.62, 0.32, 0.38])),
    "embryo":  (np.array([0.52, 0.24, 0.30]), np.array([0.52, 0.24, 0.30])),
    "violet":  (np.array([0.55, 0.40, 0.68]), np.array([0.40, 0.28, 0.52])),
    "tray":    (np.array([0.82, 0.83, 0.85]), np.array([0.62, 0.64, 0.67])),
    "gel":     (np.array([0.62, 0.84, 0.74]), np.array([0.44, 0.66, 0.57])),
    "bone":    (np.array([0.90, 0.86, 0.76]), np.array([0.72, 0.68, 0.58])),
    "red":     (np.array([0.86, 0.22, 0.20]), np.array([0.66, 0.14, 0.14])),
    "teal":    (np.array([0.38, 0.78, 0.76]), np.array([0.24, 0.58, 0.58])),
    "dark":    (np.array([0.24, 0.24, 0.27]), np.array([0.16, 0.16, 0.19])),
    "leather": (np.array([0.40, 0.31, 0.24]), np.array([0.29, 0.22, 0.17])),
    "field":   (np.array([0.70, 0.92, 0.96]), np.array([0.55, 0.82, 0.88])),
})

PANEL = 3.0     # per-part ring, in 256-units (1.5 px at 128)
OUTLINE = 4.0   # silhouette, in 256-units (2 px at 128) on top of the rings


class Xform:
    """Local frame -> canvas: centre (cx, cy), scale s (canvas fraction per local
    unit), rotation ang (degrees, clockwise on screen)."""

    def __init__(self, cv, cx, cy, s, ang=0.0):
        self.cv, self.cx, self.cy, self.s = cv, cx, cy, s
        a = math.radians(ang)
        self.c, self.sn = math.cos(a), math.sin(a)
        dx, dy = cv.x - cx, cv.y - cy
        # inverse rotation: canvas -> local
        self.u = (dx * self.c + dy * self.sn) / s
        self.v = (-dx * self.sn + dy * self.c) / s

    def p(self, u, v):
        return (self.cx + (u * self.c - v * self.sn) * self.s,
                self.cy + (u * self.sn + v * self.c) * self.s)

    def poly(self, pts):
        return self.cv.poly([self.p(*q) for q in pts])

    def ell(self, cu, cv_, ru, rv):
        return ((self.u - cu) / ru) ** 2 + ((self.v - cv_) / rv) ** 2 <= 1.0

    def rrect(self, u0, v0, u1, v1, r):
        """Rounded rectangle in local units."""
        u, v = self.u, self.v
        cu = np.clip(u, u0 + r, u1 - r)
        cv_ = np.clip(v, v0 + r, v1 - r)
        return (u - cu) ** 2 + (v - cv_) ** 2 <= r * r

    def ribbon(self, pts, w0, w1):
        return self.cv.ribbon([self.p(*q) for q in pts], w0 * self.s, w1 * self.s)

    def dark(self, off=0.0, du=1.0, dv=0.55):
        """Shaded plane: light from the upper left, so lower-right is darker."""
        return (self.u * du + self.v * dv) > off

    def line(self, pts, px, colour=None):
        self.cv.line([self.p(*q) for q in pts], px, colour)


def part(X, mask, colour, dark=None):
    X.cv.part(mask, colour, dark, panel_px=PANEL)


def fill(X, mask, colour):
    """A flat inlay with no ring of its own (labels, liquid, glints)."""
    X.cv.rgb[mask] = dw.C[colour][0]
    X.cv.alpha |= mask


# ------------------------------------------------------------------ objects
def lozenge(X):
    """Zoladone: a grey lozenge with a score across it."""
    m = X.ell(0, 0, 1.0, 0.62)
    part(X, m, "lozenge", X.dark(0.15))
    X.line([(-0.05, -0.52), (0.05, 0.52)], 2.4)
    fill(X, X.ell(-0.45, -0.22, 0.22, 0.10), "tablet")


def blister(X):
    """Nazopran: a foil sheet of six flat white tablets."""
    part(X, X.rrect(-1.0, -0.66, 1.0, 0.66, 0.14), "foil", X.dark(0.4))
    for i in range(3):
        for j in range(2):
            cu, cvv = -0.62 + i * 0.62, -0.30 + j * 0.60
            m = X.ell(cu, cvv, 0.24, 0.24)
            X.cv.part(m, "tablet", X.ell(cu + 0.08, cvv + 0.08, 0.22, 0.22) & m, panel_px=2.0)


def ampoule(X):
    """Mjolnir-6: a glass ampoule, orange inside, a dark crimped cap."""
    body = X.rrect(-0.34, -0.55, 0.34, 1.0, 0.30)
    part(X, body, "glass", X.dark(0.05, 1.0, 0.0))
    fill(X, X.rrect(-0.26, 0.0, 0.26, 0.92, 0.24) & body, "orange")
    neck = X.rrect(-0.16, -0.85, 0.16, -0.50, 0.08)
    part(X, neck, "glass")
    part(X, X.rrect(-0.24, -1.05, 0.24, -0.78, 0.08), "dark")
    fill(X, X.rrect(-0.24, -0.40, -0.12, 0.70, 0.06), "tablet")


def cake(X):
    """God's bread: a dark pressed cake of fungus, cracked across the top."""
    part(X, X.ell(0, 0.18, 1.0, 0.55), "crust", None)
    part(X, X.ell(0, -0.05, 1.0, 0.55), "cake", X.dark(0.2, 1.0, 0.0))
    X.line([(-0.55, -0.20), (-0.15, 0.0), (0.10, -0.25), (0.45, 0.05)], 2.0)
    X.line([(-0.15, 0.0), (-0.05, 0.25)], 1.8)


def pouch(X):
    """Fever cloud: a tied cloth pouch of coarse grey powder, mouth open."""
    # A round-bellied sack gathered at the neck, not a box.
    body = X.ell(0, 0.30, 0.95, 0.72) | X.poly([(-0.50, -0.30), (0.50, -0.30), (0.80, 0.10), (-0.80, 0.10)])
    part(X, body, "sack", X.dark(0.25, 1.0, 0.0))
    part(X, X.ell(0, -0.42, 0.62, 0.24), "ash", None)
    part(X, X.rrect(-0.55, -0.42, 0.55, -0.24, 0.08), "cord")


def canister(X):
    """ResFlesh: a spray canister with a window onto the living culture inside."""
    body = X.rrect(-0.48, -0.70, 0.48, 1.0, 0.18)
    part(X, body, "can", X.dark(0.10, 1.0, 0.0))
    part(X, X.rrect(-0.30, -0.25, 0.30, 0.65, 0.10), "flesh", X.dark(0.05, 1.0, 0.0))
    part(X, X.rrect(-0.30, -0.98, 0.30, -0.66, 0.08), "dark")
    part(X, X.rrect(-0.10, -1.12, 0.36, -0.92, 0.05), "red")


def ingot(X):
    """Ionsteel: a trapezoid ingot, its aligned grain showing as pale lines."""
    top = X.poly([(-0.80, -0.55), (0.80, -0.55), (1.0, -0.20), (-1.0, -0.20)])
    side = X.poly([(-1.0, -0.20), (1.0, -0.20), (1.0, 0.45), (-1.0, 0.45)])
    part(X, side, "ion", X.dark(0.0, 1.0, 0.0))
    part(X, top, "iongrain")
    for k in (-0.55, -0.15, 0.25, 0.65):
        X.line([(k, -0.05), (k + 0.20, 0.32)], 1.6, "iongrain")


def vat(X):
    """Carveling vat: a sealed glass growth cylinder, pink fluid, a curled shape."""
    glass = X.rrect(-0.62, -0.78, 0.62, 0.88, 0.22)
    part(X, glass, "glass", X.dark(0.20, 1.0, 0.0))
    fill(X, X.rrect(-0.52, -0.40, 0.52, 0.80, 0.18) & glass, "vatfluid")
    fill(X, X.ell(0.02, 0.22, 0.26, 0.32) & ~X.ell(0.10, 0.12, 0.10, 0.12), "embryo")
    fill(X, X.rrect(-0.46, -0.30, -0.34, 0.60, 0.05), "tablet")
    for v0, v1 in ((-1.0, -0.72), (0.82, 1.08)):
        part(X, X.rrect(-0.72, v0, 0.72, v1, 0.10), "dark")


# ----------------------------------------------------------- single items
def carving_kit(size=128):
    """A sealed steel tray, violet seal across the lid, three gel phials and a
    bone-cement block bedded in it."""
    cv = Canvas(size)
    X = Xform(cv, 0.5, 0.54, 0.40, -8)
    part(X, X.rrect(-1.0, -0.68, 1.0, 0.68, 0.14), "tray", X.dark(0.45))
    for i in range(3):
        cu = -0.62 + i * 0.42
        m = X.rrect(cu - 0.14, -0.48, cu + 0.14, 0.48, 0.12)
        part(X, m, "gel", X.dark(cu + 0.04, 1.0, 0.0))
    part(X, X.rrect(0.42, -0.42, 0.86, 0.42, 0.08), "bone", X.dark(0.68, 1.0, 0.0))
    part(X, X.rrect(-1.0, -0.82, 1.0, -0.62, 0.06), "violet")
    return cv.finish(OUTLINE)


def cupids_kiss(size=128):
    """A slim spinal clasp: a column of linked vertebral rings with a red core."""
    cv = Canvas(size)
    X = Xform(cv, 0.5, 0.5, 0.42, 18)
    part(X, X.rrect(-0.10, -1.05, 0.10, 1.05, 0.08), "dark")
    for k in range(6):
        v = -0.85 + k * 0.34
        part(X, X.rrect(-0.40, v - 0.11, 0.40, v + 0.11, 0.10), "can", X.dark(0.15, 1.0, 0.0))
        fill(X, X.ell(0, v, 0.10, 0.06), "red")
    return cv.finish(OUTLINE)


def synaptic_lattice(size=128):
    """A mesh of neural contacts: a hub, six spokes, a node at each tip, the
    nodes joined in a ring - the net that is grown into the scalp."""
    cv = Canvas(size)
    X = Xform(cv, 0.5, 0.5, 0.40)
    nodes = [(math.cos(math.radians(a)) * 0.82, math.sin(math.radians(a)) * 0.82)
             for a in range(-90, 270, 60)]
    for a, b in zip(nodes, nodes[1:] + nodes[:1]):
        X.line([a, b], 3.0, "teal")
    for n in nodes:
        X.line([(0, 0), n], 3.4)
    part(X, X.ell(0, 0, 0.36, 0.36), "teal", X.dark(0.1))
    for n in nodes:
        part(X, X.ell(n[0], n[1], 0.16, 0.16), "can", X.dark(n[0] + n[1] * 0.55 + 0.05))
    return cv.finish(OUTLINE)


def aegis_icon(size=128):
    """A forearm cuff with its emitter boss, throwing an oval of field."""
    cv = Canvas(size)
    X = Xform(cv, 0.5, 0.5, 0.44, -20)
    fld = X.ell(0, 0, 0.70, 1.0)
    cv.rgb[fld] = dw.C["field"][0] * 0.55 + 0.45 * np.array([0.30, 0.30, 0.33])
    cv.alpha |= fld
    X.cv.part(fld & ~X.ell(0, 0, 0.62, 0.92), "field", None, panel_px=2.0)
    part(X, X.rrect(-0.30, -0.42, 0.30, 0.42, 0.12), "leather", X.dark(0.1, 1.0, 0.0))
    part(X, X.ell(0, 0, 0.24, 0.24), "brass", X.dark(0.05))
    fill(X, X.ell(-0.06, -0.06, 0.09, 0.09), "teal")
    return cv.finish(OUTLINE)


def boot(X, latches, sole, colour):
    shaft = X.poly([(-0.42, -1.0), (0.30, -1.0), (0.34, 0.30), (0.95, 0.42),
                    (0.95, 0.82), (-0.46, 0.82)])
    part(X, shaft, colour, X.dark(0.18, 1.0, 0.0))
    for k in range(latches):
        v = -0.78 + k * 0.30
        part(X, X.rrect(-0.46, v - 0.07, 0.38, v + 0.07, 0.05), "brass")
    part(X, X.rrect(-0.50, 0.78, 1.0, 1.0, 0.07), sole)


def boots_icon(latches, colour, sole, size=128):
    cv = Canvas(size)
    boot(Xform(cv, 0.40, 0.48, 0.34, -4), latches, sole, colour)
    boot(Xform(cv, 0.60, 0.56, 0.34, 4), latches, sole, colour)
    return cv.finish(OUTLINE)


# ------------------------------------------------------------------ stacks
# (cx, cy, scale, angle) for 1, 3 and 5 copies, back to front.
STACKS = {
    "a": [(0.50, 0.52, 0.30, -18)],
    "b": [(0.36, 0.40, 0.25, 22), (0.64, 0.44, 0.25, -30), (0.48, 0.66, 0.25, -6)],
    "c": [(0.34, 0.34, 0.21, 25), (0.66, 0.32, 0.21, -15), (0.32, 0.64, 0.21, -40),
          (0.67, 0.63, 0.21, 18), (0.50, 0.50, 0.23, -4)],
}


def stack(obj, which, size=128, scale=1.0):
    cv = Canvas(size)
    for cx, cy, s, ang in STACKS[which]:
        obj(Xform(cv, cx, cy, s * scale, ang))
    return cv.finish(OUTLINE)


STACKED = {
    "Things/Item/Drug/RR_Zoladone/RR_Zoladone": (lozenge, 1.0),
    "Things/Item/Drug/RR_Nazopran/RR_Nazopran": (blister, 1.05),
    "Things/Item/Drug/RR_MjolnirSix/RR_MjolnirSix": (ampoule, 1.0),
    "Things/Item/Drug/RR_GodsBread/RR_GodsBread": (cake, 1.0),
    "Things/Item/Drug/RR_FeverCloud/RR_FeverCloud": (pouch, 1.0),
    "Things/Item/Resource/RR_ResFlesh/RR_ResFlesh": (canister, 1.0),
    "Things/Item/Resource/RR_Ionsteel/RR_Ionsteel": (ingot, 1.0),
    "Things/Item/Resource/RR_CarvelingVat/RR_CarvelingVat": (vat, 1.05),
}

SINGLE = {
    "Things/Item/Health/RR_CarvingKit": carving_kit,
    "Things/Item/Health/RR_CupidsKiss": cupids_kiss,
    "Things/Item/Health/RR_SynapticLattice": synaptic_lattice,
    "Things/Pawn/Humanlike/Apparel/RR_Aegis/RR_Aegis": aegis_icon,
    # gravBoots: three latches per leg, the field glowing at the sole.
    "Things/Pawn/Humanlike/Apparel/RR_GravBoots/RR_GravBoots": lambda: boots_icon(3, "dark", "teal"),
    # skipBoots: a quarter the weight - lighter, one latch, a plain sole.
    "Things/Pawn/Humanlike/Apparel/RR_SkipBoots/RR_SkipBoots": lambda: boots_icon(1, "leather", "dark"),
}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    out, only = os.path.abspath(args[0]), set(args[1:])
    for rel, (obj, sc) in STACKED.items():
        if only and os.path.basename(rel) not in only:
            continue
        for which in "abc":
            path = os.path.join(out, *rel.split("/")) + "_" + which + ".png"
            cw.save_png(path, stack(obj, which, scale=sc))
            print("WROTE", path)
    for rel, fn in SINGLE.items():
        if only and os.path.basename(rel) not in only:
            continue
        path = os.path.join(out, *rel.split("/")) + ".png"
        cw.save_png(path, fn())
        print("WROTE", path)
