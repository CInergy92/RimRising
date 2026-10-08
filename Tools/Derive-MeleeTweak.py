"""
Derive Melee Animation tweak data for a weapon sprite and write the JSON.

Run through Blender (for its bundled numpy), never directly:

    blender -b --factory-startup --python Tools/Derive-MeleeTweak.py -- \
        <sprite.png> <defName> <hand_x> <hand_y> <blade_x> <blade_y> <type> [axis_deg]

hand and blade points are canvas fractions, y DOWN - the grip point the hand
closes on, and where the blade begins. type is MeleeWeaponType (6 for both
razors - see CLAUDE.md). axis_deg defaults to the sprite's principal axis.

THE METHOD, from CLAUDE.md "Deriving the numbers without the in-game editor":
Rotation is the sprite's principal axis (CCW from +X, +Y up). Everything else is
measured in one frame - origin at the canvas centre, units of canvas widths -
projected onto that axis:

    OffX       = -(t of the grip point)
    OffY       = -(u of the grip point)          (u is across the axis)
    BladeStart = OffX + (t where the blade begins)
    BladeEnd   = OffX + (t of the far end of the sprite) - 0.02

The 0.02 matches the reference authors, who set the tip a hair inside the last
antialiased pixel. Reconstructing two reference weapons this way landed within
2% of their shipped values.

Written to WeaponTweakData/<defName>_cinergy92.rimrising.json, the file name
ItemTweakData.MakeFileName requires.
"""
import importlib.machinery
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
cw = importlib.machinery.SourceFileLoader(
    "compose_worn", os.path.join(HERE, "Compose-WornApparel.py")).load_module()
PACKAGE_ID = "cinergy92.rimrising"


def principal_axis_deg(alpha):
    ys, xs = np.nonzero(alpha > 0.15)
    h = alpha.shape[0]
    x = xs.astype(float)
    y = (h - 1 - ys).astype(float)                 # +Y up
    x -= x.mean(); y -= y.mean()
    cxx, cyy, cxy = (x * x).mean(), (y * y).mean(), (x * y).mean()
    return math.degrees(0.5 * math.atan2(2 * cxy, cxx - cyy))


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    # Absolute: Blender's image loader does not resolve relative paths against
    # the working directory (the same trap Render-ApparelPasses.py hit).
    path, def_name = os.path.abspath(a[0]), a[1]
    hx, hy, bx, by = map(float, a[2:6])
    wtype = int(a[6])
    img = cw.load_rgba(path)
    alpha = img[..., 3]
    axis = float(a[7]) if len(a) > 7 else round(principal_axis_deg(alpha) * 2) / 2
    th = math.radians(axis)
    ct, st = math.cos(th), math.sin(th)

    def project(px, py_down):
        dx, dy = px - 0.5, 0.5 - py_down
        return dx * ct + dy * st, -dx * st + dy * ct

    h, w = alpha.shape
    ys, xs = np.nonzero(alpha > 0.15)
    t_all = ((xs + 0.5) / w - 0.5) * ct + (0.5 - (ys + 0.5) / h) * st
    t_max = float(t_all.max())

    th_, uh = project(hx, hy)
    tb, _ = project(bx, by)
    off_x, off_y = -th_, -uh
    data = {
        "TextureModID": PACKAGE_ID,
        "ItemDefName": def_name,
        "ItemType": "ThingDef",
        "ItemTypeNamespace": "Verse",
        "OffX": round(off_x, 4),
        "OffY": round(off_y, 4),
        "Rotation": axis,
        "HandsMode": 1,
        "BladeStart": round(off_x + tb, 4),
        "BladeEnd": round(off_x + t_max - 0.02, 4),
        "MeleeWeaponType": wtype,
    }
    out = os.path.join(os.path.dirname(HERE), "WeaponTweakData", f"{def_name}_{PACKAGE_ID}.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("TWEAK", json.dumps(data))
    print("WROTE", out)


main()
