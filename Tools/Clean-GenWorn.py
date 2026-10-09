"""
Fit a generated worn-apparel image back onto the measured sprite it was made
from, so a high-detail redraw still registers with the body.

    blender -b --factory-startup --python Tools/Clean-GenWorn.py -- \
        <generated.png> <reference_sprite.png> <out.png> [--dyed] [--outline PX]

The user's direction (2026-10-08): high-detail art - worn items, weapons,
vehicles - is generative. The measured flat-panel sprites (Draw-PanelArmor.py)
remain the REGISTRATION TARGET: each is fed to the image model as the silhouette
reference, and this script puts the result back exactly where the reference was.

1. CUT OUT the flat white background (border flood fill; the models cannot do
   transparency on fal).
2. FIT: scale and move the generated opaque area onto the reference sprite's
   opaque bounding box, x and y independently, so the pauldrons land on the same
   shoulders. Models drift a few percent either way; this absorbs it.
3. DYE MASK (--dyed): caste-dyed armour is generated with GOLD plates. Gold
   pixels become the mask's red (CompColorable/CutoutComplex dyes red regions)
   and are lightened to grey in the texture, because the dye multiplies them -
   the shipped texture is pale where it is dyed, as the procedural one was.
4. OUTLINE: a pure black silhouette ring, as the armour idiom measured (6 px at
   256 including the model's own edge line).
"""
import importlib.machinery
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
cw = importlib.machinery.SourceFileLoader(
    "cw", os.path.join(HERE, "Compose-WornApparel.py")).load_module()


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


def bbox(a):
    ys, xs = np.where(a)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def place(gen, ref, width_only=False, contain=False):
    """Resample gen's opaque area into ref's opaque box, at ref's size.

    width_only: match the reference's WIDTH and bottom edge and keep the
    generated aspect, so a redesign may rise past the old top - a horned helm
    on the old helmet's base. Clipped at the canvas top."""
    H, W = ref.shape[:2]
    rx0, ry0, rx1, ry1 = bbox(ref[..., 3] > 0.5)
    gx0, gy0, gx1, gy1 = bbox(gen[..., 3] > 0.5)
    crop = gen[gy0:gy1, gx0:gx1].copy()
    crop[..., :3] *= crop[..., 3:4]
    if contain:
        # Keep the generated aspect, fit INSIDE the reference box, centred - a
        # redesign whose outline the reference does not share (the Drachenjager).
        s = min((rx1 - rx0) / (gx1 - gx0), (ry1 - ry0) / (gy1 - gy0))
        w, h = int(round((gx1 - gx0) * s)), int(round((gy1 - gy0) * s))
        cx, cy = (rx0 + rx1) // 2, (ry0 + ry1) // 2
        rx0, ry0 = cx - w // 2, cy - h // 2
        rx1, ry1 = rx0 + w, ry0 + h
        small = cw.resize(crop, w, h)
    elif width_only:
        w = rx1 - rx0
        h = int(round((gy1 - gy0) * w / (gx1 - gx0)))
        ry0 = max(0, ry1 - h)
        small = cw.resize(crop, w, h)[h - (ry1 - ry0):]
    else:
        small = cw.resize(crop, rx1 - rx0, ry1 - ry0)
    nz = small[..., 3] > 1e-4
    small[nz, :3] /= small[nz, 3:4]
    out = np.zeros((H, W, 4), np.float32)
    out[ry0:ry1, rx0:rx1] = small
    return out


def gold_mask(img):
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    mx, mn = img[..., :3].max(axis=2), img[..., :3].min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    # yellow-orange hue: red and green both high, blue clearly lower
    return (sat > 0.28) & (mx > 0.30) & (b < g * 0.80) & (r > g * 0.85) & (img[..., 3] > 0.5)


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:]
    gen_p, ref_p, out_p = (os.path.abspath(x) for x in a[:3])
    dyed = "--dyed" in a
    px = float(a[a.index("--outline") + 1]) if "--outline" in a else 3.0

    ref = cw.load_rgba(ref_p)
    scale = 4                                   # work at 4x the sprite, then reduce
    big_ref = cw.resize(ref, ref.shape[1] * scale, ref.shape[0] * scale)
    gen = cutout(cw.load_rgba(gen_p))
    img = place(gen, big_ref, width_only="--width-only" in a, contain="--contain" in a)

    mask = None
    if dyed:
        m = gold_mask(img)
        lum = img[..., 0] * 0.30 + img[..., 1] * 0.59 + img[..., 2] * 0.11
        # pale plates: the dye multiplies them, so they need to be light
        img[m, :3] = np.clip(0.30 + lum[m] * 0.85, 0, 1)[..., None]
        mask = np.zeros_like(img)
        mask[..., 0] = m.astype(np.float32)
        mask[..., 3] = 1.0

    a_ = img[..., 3] > 0.5
    ring = cw.dilate(a_, px * scale) & ~a_
    img[ring, :3] = 0.0
    img[ring, 3] = 1.0

    out = cw.downsample(img, scale)
    cw.save_png(out_p, out)
    print("WROTE", out_p)
    if mask is not None:
        mask[ring, 0] = 0.0
        root, ext = os.path.splitext(out_p)
        cw.save_png(root + "m" + ext, cw.downsample(mask, scale))
        print("WROTE", root + "m" + ext)
