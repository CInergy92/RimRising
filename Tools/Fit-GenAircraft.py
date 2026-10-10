"""
Fit a generated top-down aircraft (nose DOWN, on white) to a Vehicle Framework
sprite set: <out>_south, _east, _north on a square canvas.

    blender -b --factory-startup --python Tools/Fit-GenAircraft.py -- \
        <gen.png> <out_prefix> <size> [--outline PX]

Seen from directly above, an aircraft facing another way is the SAME image turned,
so one generation gives every facing and they cannot disagree (the Drachenjaeger,
a walker drawn in profile for east, needed separate generations; this does not).
south = as generated (nose down); east = turned so the nose points right; north =
turned half round. Graphic_Vehicle mirrors east for west.

Cut out with Clean-GenWorn.cutout, fitted inside 94% of the canvas keeping aspect,
centred, black outline. Size: 128 px per drawSize cell, as the Drachenjaeger
(CLAUDE.md, "Vehicle art").
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
fa = importlib.machinery.SourceFileLoader(
    "fa", os.path.join(HERE, "Fit-GenAnimal.py")).load_module()

if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:]
    src, prefix, size = os.path.abspath(a[0]), os.path.abspath(a[1]), int(a[2])
    px = float(a[a.index("--outline") + 1]) if "--outline" in a else 4.0
    scale = 4
    S = size * scale
    img = cg.cutout(cw.load_rgba(src))
    x0, y0, x1, y1 = cg.bbox(img[..., 3] > 0.5)
    crop = img[y0:y1, x0:x1].copy()
    k = 0.94 * S / max(crop.shape[0], crop.shape[1])
    w, h = int(round(crop.shape[1] * k)), int(round(crop.shape[0] * k))
    pre = crop.copy()
    pre[..., :3] *= pre[..., 3:4]
    small = cw.resize(pre, w, h)
    nz = small[..., 3] > 1e-4
    small[nz, :3] /= small[nz, 3:4]
    south = np.zeros((S, S, 4), np.float32)
    south[(S - h) // 2:(S - h) // 2 + h, (S - w) // 2:(S - w) // 2 + w] = small
    south = fa.outline(south, px * scale)
    # load_rgba rows run top to bottom. Nose at the bottom; np.rot90 turns
    # counter-clockwise, which carries the bottom edge to the right.
    views = {"south": south, "east": np.rot90(south, 1), "north": np.rot90(south, 2)}
    for k_, v in views.items():
        out = "%s_%s.png" % (prefix, k_)
        cw.save_png(out, cw.downsample(np.ascontiguousarray(v), scale))
        print("WROTE", out)
