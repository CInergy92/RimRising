"""
Fit a generated animal (east/south/north on white) onto RimWorld pawn canvases
at ONE scale, so the creature is the same size whichever way it faces.

    blender -b --factory-startup --python Tools/Fit-GenAnimal.py -- \
        <size> <out_prefix> <east.png> <south.png> <north.png> [--outline PX]

Each view is cut out (Clean-GenWorn.cutout). The scale is set by STANDING
HEIGHT, which is the same animal in every view: the height every view is drawn
at is the largest that keeps the front/back views inside 88% of the canvas and
the side view - the widest - inside 92% of it. Each view is centred on the canvas,
as a pawn is drawn centred on its cell. Writes <out_prefix>_east/_south/_north.png.

Generated rather than code-drawn: the user's direction that high-detail art is
generative (CLAUDE.md); the griffin is the first animal through it.
"""
import importlib.machinery
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
cw = importlib.machinery.SourceFileLoader(
    "cw", os.path.join(HERE, "Compose-WornApparel.py")).load_module()
cg = importlib.machinery.SourceFileLoader(
    "cg", os.path.join(HERE, "Clean-GenWorn.py")).load_module()


def outline(img, px):
    """Pure black ring outside the silhouette, as Clean-GenWorn draws one."""
    a = img[..., 3] > 0.5
    grown = a.copy()
    r = int(round(px))
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            grown |= np.roll(np.roll(a, dy, 0), dx, 1)
    ring = grown & ~a
    out = img.copy()
    out[ring] = (0, 0, 0, 1)
    return out


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:]
    px = float(a[a.index("--outline") + 1]) if "--outline" in a else 3.0
    size, prefix = int(a[0]), os.path.abspath(a[1])
    views = dict(zip(("east", "south", "north"), a[2:5]))
    scale = 4                                       # work at 4x, then reduce
    S = size * scale
    cut = {}
    for k, f in views.items():
        img = cg.cutout(cw.load_rgba(os.path.abspath(f)))
        x0, y0, x1, y1 = cg.bbox(img[..., 3] > 0.5)
        crop = img[y0:y1, x0:x1].copy()
        cut[k] = crop
    ht = min([0.88 * S for k in ("south", "north")] +
             [0.88 * S * c.shape[0] / c.shape[1] for c in [cut["south"], cut["north"]]] +
             [0.92 * S * cut["east"].shape[0] / cut["east"].shape[1]])
    for k, crop in cut.items():
        h = int(round(ht))
        w = int(round(crop.shape[1] * ht / crop.shape[0]))
        pre = crop.copy()
        pre[..., :3] *= pre[..., 3:4]
        small = cw.resize(pre, w, h)
        nz = small[..., 3] > 1e-4
        small[nz, :3] /= small[nz, 3:4]
        canvas = np.zeros((S, S, 4), np.float32)
        x0 = (S - w) // 2
        y0 = (S - h) // 2                   # pawns draw centred on their cell
        canvas[y0:y0 + h, x0:x0 + w] = small
        canvas = outline(canvas, px * scale)
        out = "%s_%s.png" % (prefix, k)
        cw.save_png(out, cw.downsample(canvas, scale))
        print("WROTE", out, "%dx%d" % (w // scale, h // scale))
