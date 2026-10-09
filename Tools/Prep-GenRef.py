"""
Prepare a sprite as a reference image for the generative pipeline: composite it
onto flat white and upscale to 1024, which is what the image models take best.

    blender -b --factory-startup --python Tools/Prep-GenRef.py -- <in.png> <out.png> [size]
"""
import importlib.machinery
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
cw = importlib.machinery.SourceFileLoader(
    "cw", os.path.join(HERE, "Compose-WornApparel.py")).load_module()

if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:]
    src, dst = os.path.abspath(a[0]), os.path.abspath(a[1])
    size = int(a[2]) if len(a) > 2 else 1024
    img = cw.load_rgba(src)
    # Pad to a square first, centred, so a non-square sprite (a 768x1024
    # vehicle body) is not squashed; Clean-GenWorn.py fits by bounding box, so
    # the padding costs nothing on the way back.
    h, w = img.shape[:2]
    if h != w:
        n = max(h, w)
        sq = np.zeros((n, n, 4), np.float32)
        sq[(n - h) // 2:(n - h) // 2 + h, (n - w) // 2:(n - w) // 2 + w] = img
        img = sq
    img = cw.resize(img, size, size)
    al = img[..., 3:4]
    out = np.ones((size, size, 4), np.float32)
    out[..., :3] = img[..., :3] * al + (1 - al)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    cw.save_png(dst, out)
    print("WROTE", dst)
