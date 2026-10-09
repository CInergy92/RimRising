"""
Draw RimRising's ranged weapons and their projectiles in RimWorld's flat idiom.

    blender -b --factory-startup --python Tools/Draw-Ranged.py -- <out_dir>

ORIENTATION, measured from installed mods' loose art rather than assumed:

- GUNS lie HORIZONTAL, muzzle to the right (Vanilla Textures Expanded's charge
  rifle, autopistol, minigun...). Our pulseFist and scorcher carry no
  equippedAngleOffset, so their sprites must follow that. Pistols fill about
  half the canvas width, rifles nearly all of it. Spacer guns are a few flat
  panels with one accent line.
- PROJECTILES point UP: nose at the top of the canvas, trail below (Rimatomics'
  missiles, Vanilla Weapons Expanded's arrows and charge bolts). Projectile.
  ExactRotation looks along the heading, so a diagonal sprite - which ours were -
  flies 45 degrees off its own path. Energy shots are soft glows, not outlined
  shapes; a physical warhead is outlined like any object.

Shapes reuse Draw-Items' local-frame Xform, so they are written in u (right) and
v (down) about -1..1.
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
    "gold":    (np.array([0.82, 0.66, 0.32]), np.array([0.62, 0.48, 0.22])),
    "gunmetal": (np.array([0.50, 0.52, 0.55]), np.array([0.36, 0.38, 0.41])),
    "smock":   (np.array([0.62, 0.60, 0.55]), np.array([0.46, 0.45, 0.41])),
    "coil":    (np.array([0.92, 0.52, 0.20]), np.array([0.74, 0.38, 0.12])),
    "cyan":    (np.array([0.62, 0.92, 0.98]), np.array([0.40, 0.78, 0.88])),
    "olive":   (np.array([0.40, 0.42, 0.32]), np.array([0.29, 0.31, 0.23])),
})

GUN_OUTLINE = 5.0   # 256-units; VTE's spacer guns sit a touch under the armour's 6


# -------------------------------------------------------------------- guns
def pulse_fist(size=256):
    """A gauntlet: an armoured forearm housing in Gold's plate, a knuckle block,
    and the emitter ring at the front where the pulse leaves."""
    cv = Canvas(size)
    X = Xform(cv, 0.47, 0.52, 0.30)
    part(X, X.rrect(-1.15, -0.34, 0.20, 0.34, 0.14), "gold", X.dark(0.0, 0.0, 1.0))
    for u in (-0.85, -0.45):
        part(X, X.rrect(u - 0.07, -0.40, u + 0.07, 0.40, 0.05), "dark")
    part(X, X.rrect(0.05, -0.46, 0.80, 0.46, 0.16), "dark", X.dark(0.05, 0.0, 1.0))
    for k in range(3):                                   # knuckle plates
        v = -0.30 + k * 0.30
        part(X, X.rrect(0.62, v - 0.11, 0.95, v + 0.11, 0.08), "gold", X.dark(v + 0.03, 0.0, 1.0))
    part(X, X.ell(1.12, 0.0, 0.20, 0.36), "brass", X.dark(0.0, 0.0, 1.0))
    fill(X, X.ell(1.15, 0.0, 0.10, 0.22), "cyan")
    # The closed fist under the housing: what makes it a gauntlet and not a can.
    part(X, X.rrect(0.05, 0.30, 0.70, 0.72, 0.16), "leather", X.dark(0.5, 0.0, 1.0))
    for u in (0.22, 0.40, 0.58):
        X.line([(u, 0.36), (u, 0.66)], 2.2)
    X.line([(-1.0, -0.12), (0.0, -0.12)], 2.6, "cyan")   # the one accent
    return cv.finish(GUN_OUTLINE)


def scorcher(size=256):
    """A cheap boxy carbine: grey body, a skeletal stock, a short barrel ringed
    with orange heat coils, vent slots. Built down to a price."""
    cv = Canvas(size)
    X = Xform(cv, 0.50, 0.50, 0.44)
    part(X, X.poly([(-1.05, -0.12), (-0.55, -0.20), (-0.55, 0.08), (-1.05, 0.30)]), "gunmetal")
    part(X, X.rrect(-0.62, -0.26, 0.40, 0.16, 0.06), "smock", X.dark(0.0, 0.0, 1.0))
    part(X, X.poly([(-0.20, 0.10), (0.02, 0.10), (-0.06, 0.48), (-0.26, 0.48)]), "gunmetal")
    part(X, X.rrect(0.10, 0.10, 0.26, 0.38, 0.04), "dark")              # magazine cell
    part(X, X.rrect(0.36, -0.15, 1.05, 0.02, 0.05), "gunmetal", X.dark(-0.06, 0.0, 1.0))
    for u in (0.48, 0.64, 0.80):
        part(X, X.rrect(u - 0.05, -0.20, u + 0.05, 0.07, 0.03), "coil")
    for u in (-0.40, -0.25, -0.10, 0.05, 0.20):
        X.line([(u, -0.18), (u, -0.02)], 2.2)
    return cv.finish(GUN_OUTLINE)


def pulse_cannon(size=256):
    """Suit-scale: a heavy housing, a thick barrel with three emitter collars and
    a shoulder brace. It is the arm's gun, so it is long."""
    cv = Canvas(size)
    X = Xform(cv, 0.50, 0.50, 0.46)
    part(X, X.poly([(-1.05, -0.38), (-0.25, -0.40), (-0.20, 0.34), (-1.0, 0.40)]), "gunmetal",
         X.dark(0.0, 0.0, 1.0))
    part(X, X.rrect(-0.85, 0.30, -0.45, 0.62, 0.06), "dark")              # brace
    part(X, X.rrect(-0.30, -0.22, 0.92, 0.18, 0.10), "dark", X.dark(-0.02, 0.0, 1.0))
    for u in (0.05, 0.38, 0.70):
        part(X, X.rrect(u - 0.08, -0.30, u + 0.08, 0.26, 0.05), "gold")
    part(X, X.ell(0.98, -0.02, 0.10, 0.26), "brass")
    fill(X, X.ell(1.0, -0.02, 0.05, 0.16), "cyan")
    X.line([(-0.95, -0.15), (-0.32, -0.15)], 2.8, "cyan")
    return cv.finish(GUN_OUTLINE)


# ------------------------------------------------------------- projectiles
def glow(cv, core, colour, halo_px, core_colour=(1.0, 1.0, 1.0)):
    """A soft energy shot: a bright core and a blurred halo of `colour`, alpha
    from the halo itself. No outline - charge shots have none."""
    n = cv.size * 4
    h = cw.blur(cw.blur(core.astype(np.float32), halo_px * 4 * cv.k), halo_px * 4 * cv.k)
    h = np.clip(h * 1.6, 0, 1)
    a = np.maximum(h, core.astype(np.float32))
    col = np.array(colour)[None, None, :] * np.ones((n, n, 1), np.float32)
    col[core] = np.array(core_colour)
    img = np.dstack([col * a[..., None], a])
    d = cw.downsample(img, 4)
    out = d.copy()
    nz = d[..., 3] > 1e-4
    out[nz, :3] = d[nz, :3] / d[nz, 3:4]
    return out


def pulse_wave(size=64):
    """The cannon's compression wave: a bright crescent leading, heat behind."""
    cv = Canvas(size)
    X = Xform(cv, 0.5, 0.5, 0.40)
    front = X.ell(0, -0.20, 0.80, 0.50) & ~X.ell(0, 0.10, 0.80, 0.55)
    trail = X.ell(0, 0.30, 0.22, 0.60)
    return glow(cv, front | trail, (1.0, 0.62, 0.25), 24)


def particle_lance(size=64):
    """A particle cannon bolt: a thin white-cyan lance, long and straight."""
    cv = Canvas(size)
    X = Xform(cv, 0.5, 0.5, 0.45)
    core = X.rrect(-0.07, -1.0, 0.07, 0.85, 0.07)
    return glow(cv, core, (0.45, 0.85, 1.0), 14)


def warhead(size=64):
    """A rack missile seen from above, nose up: olive body, pale nose cone,
    four fins at the tail, a short exhaust glow."""
    cv = Canvas(size)
    X = Xform(cv, 0.5, 0.48, 0.42)
    flame = X.ell(0, 1.05, 0.14, 0.24)
    cv.rgb[flame] = np.array([1.0, 0.70, 0.30])
    cv.alpha |= flame
    part(X, X.poly([(-0.45, 0.55), (-0.15, 0.25), (-0.15, 0.85), (-0.45, 0.95)]), "dark")
    part(X, X.poly([(0.45, 0.55), (0.15, 0.25), (0.15, 0.85), (0.45, 0.95)]), "dark")
    part(X, X.rrect(-0.18, -0.55, 0.18, 0.90, 0.10), "olive", X.dark(0.0, 1.0, 0.0))
    part(X, X.poly([(-0.18, -0.50), (0.18, -0.50), (0.0, -1.0)]), "bone")
    part(X, X.rrect(-0.20, -0.20, 0.20, -0.08, 0.03), "red")
    return cv.finish(4.0)


OUTPUTS = {
    "Things/Item/Equipment/WeaponRanged/RR_PulseFist": pulse_fist,
    "Things/Item/Equipment/WeaponRanged/RR_Scorcher": scorcher,
    "Things/Weapons/RR_PulseCannon": pulse_cannon,
    "Things/Projectile/RR_PulseWave": pulse_wave,
    "Things/Projectile/RR_ParticleLance": particle_lance,
    "Things/Projectile/RR_Warhead": warhead,
}

if __name__ == "__main__":
    out = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
    for rel, fn in OUTPUTS.items():
        path = os.path.join(out, *rel.split("/")) + ".png"
        cw.save_png(path, fn())
        print("WROTE", path)
