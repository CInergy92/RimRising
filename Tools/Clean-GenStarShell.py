"""
Turn the generated starShell art (Art/Gen/StarShell/*.png, made with fal - see
fal_manifest.jsonl there) into the framework's module textures.

    blender -b --factory-startup --python Tools/Clean-GenStarShell.py -- <repo_root>

WHY GENERATED. The code-drawn starShell (Tools/Draw-StarShell.py, kept for its
measurements) was judged "much lower quality" beside The Dead Man's Switch -
MobileDragoon in the user's own game. The user chose generate-and-clean-up.

The cleanup is what makes generated art behave like a sprite:
1. CUT OUT: the model cannot do transparency, so it draws on flat white; every
   near-white pixel connected to the border is background.
2. GREYSCALE: the framework tints each module through its colorGenerator,
   which multiplies the whole texture, so the art carries light greys only.
3. FIT to the Dragoon's measured footprint (see Draw-StarShell.py's header):
   the core fills its 512 canvas from y 0.10 to 0.97, the hood the middle half
   of its canvas, the arm a narrow upright piece rotated per facing.
4. OUTLINE: a pure black silhouette ring, 6 px at 512 - the same pixels per
   cell as the armour sprites' 6 px at 256 over 1.5 cells.
"""
import math
import os
import sys
import importlib.machinery

import numpy as np

ROOT = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
cw = importlib.machinery.SourceFileLoader(
    "cw", os.path.join(ROOT, "Tools", "Compose-WornApparel.py")).load_module()

SRC = os.path.join(ROOT, "Art", "Gen", "StarShell")
DST = os.path.join(ROOT, "Textures", "Things", "Pawn", "Humanlike", "Apparel", "RR_StarShell")


def cutout(img, thresh=0.90):
    """Background = near-white pixels 4-connected to the border."""
    near = img[..., :3].min(axis=2) > thresh
    bg = np.zeros_like(near)
    bg[0, :], bg[-1, :], bg[:, 0], bg[:, -1] = near[0, :], near[-1, :], near[:, 0], near[:, -1]
    while True:
        grown = bg.copy()
        grown[1:, :] |= bg[:-1, :]
        grown[:-1, :] |= bg[1:, :]
        grown[:, 1:] |= bg[:, :-1]
        grown[:, :-1] |= bg[:, 1:]
        grown &= near
        if grown.sum() == bg.sum():
            break
        bg = grown
    out = img.copy()
    out[..., 3] = (~bg).astype(np.float32)
    return out


def grey(img):
    lum = img[..., 0] * 0.30 + img[..., 1] * 0.59 + img[..., 2] * 0.11
    out = img.copy()
    out[..., :3] = lum[..., None]
    return out


def rotate(img, deg):
    """Rotate about the centre (clockwise on screen), bilinear, canvas kept."""
    h, w = img.shape[:2]
    a = math.radians(deg)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    sx = (xx - cx) * math.cos(a) + (yy - cy) * math.sin(a) + cx
    sy = -(xx - cx) * math.sin(a) + (yy - cy) * math.cos(a) + cy
    x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
    fx, fy = (sx - x0)[..., None], (sy - y0)[..., None]
    def at(y, x):
        ok = (x >= 0) & (x < w) & (y >= 0) & (y < h)
        v = img[np.clip(y, 0, h - 1), np.clip(x, 0, w - 1)]
        return v * ok[..., None]
    return (at(y0, x0) * (1 - fx) * (1 - fy) + at(y0, x0 + 1) * fx * (1 - fy)
            + at(y0 + 1, x0) * (1 - fx) * fy + at(y0 + 1, x0 + 1) * fx * fy)


def fit(img, size, box):
    """Scale the opaque part to fit box (x0, y0, x1, y1 as canvas fractions),
    keeping aspect, centred horizontally in the box and sitting on its bottom."""
    a = img[..., 3] > 0.5
    ys, xs = np.where(a)
    crop = img[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    ch, cw_ = crop.shape[:2]
    bw, bh = (box[2] - box[0]) * size, (box[3] - box[1]) * size
    s = min(bw / cw_, bh / ch)
    nw, nh = max(1, int(cw_ * s)), max(1, int(ch * s))
    # premultiplied resample so the white fringe does not bleed in
    pm = crop.copy()
    pm[..., :3] *= pm[..., 3:4]
    small = cw.resize(pm, nw, nh)
    nz = small[..., 3] > 1e-4
    small[nz, :3] /= small[nz, 3:4]
    out = np.zeros((size, size, 4), np.float32)
    x0 = int((box[0] + box[2]) / 2 * size - nw / 2)
    y0 = int(box[3] * size - nh)
    out[y0:y0 + nh, x0:x0 + nw] = small
    return out


def outline(img, px):
    a = img[..., 3] > 0.5
    ring = cw.dilate(a, px) & ~a
    out = img.copy()
    out[ring, :3] = 0.0
    out[ring, 3] = 1.0
    # lift the greys so the tint has light material to multiply, keep the inks
    lit = out[..., :3]
    out[..., :3] = np.where(lit > 0.25, np.clip(0.18 + lit * 0.86, 0, 1), lit)
    return out


def prep(name):
    return grey(cutout(cw.load_rgba(os.path.join(SRC, name))))


CORE_BOX = (0.08, 0.10, 0.92, 0.97)
HOOD_BOX = (0.26, 0.26, 0.74, 0.74)

PIECES = {
    # out name: (source, box, rotation)
    "RR_StarShellCore_south": ("core_south_3.png", CORE_BOX, 0),
    "RR_StarShellCore_east": ("core_east3.png", CORE_BOX, 0),
    "RR_StarShellCore_north": ("core_north.png", CORE_BOX, 0),
    "RR_StarShellHead_south": ("hood_south.png", HOOD_BOX, 0),
    "RR_StarShellHead_east": ("hood_east.png", HOOD_BOX, 0),
    "RR_StarShellHead_north": ("hood_north.png", HOOD_BOX, 0),
    # The arm: upright in south and north, swung forward-down in east, as the
    # Dragoon's forearm (bbox measured: south x 0.38-0.67 y 0.06-0.67).
    "RR_StarShellArm_south": ("arm_south.png", (0.36, 0.06, 0.68, 0.68), 8),
    "RR_StarShellArm_north": ("arm_south.png", (0.32, 0.10, 0.64, 0.68), -8),
    "RR_StarShellArm_east": ("arm_south.png", (0.03, 0.16, 0.62, 0.66), -62),
}

if __name__ == "__main__":
    srcs = {}
    for out_name, (src, box, rot) in PIECES.items():
        if src not in srcs:
            srcs[src] = prep(src)
        img = srcs[src]
        if rot:
            img = rotate(img, rot)
        sprite = outline(fit(img, 512 * 2, box), 6 * 2)       # work at 2x, then halve
        sprite = cw.downsample(sprite, 2)
        cw.save_png(os.path.join(DST, out_name + ".png"), sprite)
        print("WROTE", out_name)
        if out_name.endswith("_south"):
            icon = outline(fit(img, 256 * 2, (0.06, 0.06, 0.94, 0.94)), 4 * 2)
            cw.save_png(os.path.join(DST, out_name[:-6] + ".png"), cw.downsample(icon, 2))
            print("WROTE", out_name[:-6])
