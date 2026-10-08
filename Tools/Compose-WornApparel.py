"""
Composite rendered apparel passes into RimWorld worn sprites and tint masks.

Run through Blender (for its bundled numpy and PNG loader), never directly:

    blender -b --factory-startup --python Tools/Compose-WornApparel.py -- \
        compose <passes_dir> <texture_prefix> [band_bottom]
    blender -b --factory-startup --python Tools/Compose-WornApparel.py -- \
        fit <reference_prefix>

<texture_prefix> is the path WITHOUT the body/facing suffix, e.g.
    Textures/Things/Pawn/Humanlike/Apparel/RR_PulseArmor/RR_PulseArmor
and gets _<Body>_<facing>.png plus the _<Body>_<facing>m.png mask (Graphic_Multi's
mask naming, decompiled - see CLAUDE.md).

WHAT A RIMWORLD BODY IS. Not a person: a rounded bean, shoulders to hips, with no
legs and no separate arms. So the compositor takes only a horizontal BAND of the
render - the top of the model down to the hips, arms included - stretches it into
the measured body box, and cuts it to a bean.

THE BEAN is procedural, from the measured boxes in CLAUDE.md, and its shape
parameters were tuned with the `fit` mode against a reference garment's
silhouettes. The reference is a MEASURING STICK ONLY - none of its pixels are read
by `compose`.

STYLE follows the RimWorld idiom measured in CLAUDE.md: flat colour, one lighter
band and one darker band (never a gradient), dark warm-grey (#26221E) seam lines,
and a thick outline of the same colour.

TINT. CompColorable multiplies the texture by the dye inside the mask, so the
dyeable plates are drawn near-white and the mask is red exactly where they are.
"""
import os
import struct
import sys
import zlib

import bpy
import numpy as np

CANVAS = 256
SS = 4                                  # supersampling factor; work at 4x, average down
OUTLINE_PX = 3.0                        # outline thickness at final resolution
# PURE BLACK. Sampled from the outline ring of VAE's heavy marine armour, VTE's
# longsword and monosword, and VFE Classical's legionnaire armour: (0, 0, 0) is
# the most common colour in every one. The earlier #26221E came from one mod's
# weapon and was wrong as a rule.
INK = np.array([0.0, 0.0, 0.0])

# Measured body boxes (x0, x1, y0, y1), fractions of a 256 canvas, y DOWN.
# Same table as New-WornApparel.ps1 and CLAUDE.md - keep the three in step.
BOXES = {
    "Male":   {"ns": (0.30, 0.69, 0.34, 0.84), "east": (0.34, 0.66, 0.34, 0.83)},
    "Female": {"ns": (0.32, 0.68, 0.30, 0.88), "east": (0.29, 0.62, 0.31, 0.88)},
    "Thin":   {"ns": (0.40, 0.59, 0.34, 0.84), "east": (0.34, 0.59, 0.35, 0.83)},
    "Fat":    {"ns": (0.19, 0.81, 0.30, 0.88), "east": (0.18, 0.77, 0.30, 0.89)},
    "Hulk":   {"ns": (0.21, 0.78, 0.27, 0.97), "east": (0.23, 0.73, 0.28, 0.97)},
}
FACINGS = ("south", "east", "north")

# Bean shape parameters, tuned by `fit`. See bean().
#
# The body is WIDEST AT THE SHOULDERS, about a third of the way down, and tapers to
# the hips. Measured, after first being guessed the other way round: the reference
# garment's widest rows sit at 0.29 (south) and 0.35 (east) of its height.
BEAN = {
    "ns":   dict(yc=0.30, pt=2.0, bw=0.65, pb=3.0, k=1.5, lean=0.5),
    "east": dict(yc=0.35, pt=2.0, bw=0.65, pb=3.0, k=1.5, lean=0.2),
}


# Per-body-type shapes, pasted from `fit` output. A body type missing here uses
# the shared BEAN shape above.
BEAN_BODY = {
    # fit IoU against the reference outline, after its outline erosion:
    # south/north east
    ("Male", "ns"):     dict(yc=0.30, pt=2.6, bw=0.65, pb=7.0, k=1.0, lean=0.5),     # 0.97 0.96
    ("Male", "east"):   dict(yc=0.36, pt=3.4, bw=0.55, pb=7.0, k=1.0, lean=0.3),     # 0.94
    ("Female", "ns"):   dict(yc=0.42, pt=1.6, bw=0.50, pb=2.0, k=1.0, lean=0.5,      # 0.86 0.86
                             hips=dict(y=0.73, hh=0.28, w=1.00, x=0.50, pe=2.0)),
    ("Female", "east"): dict(yc=0.42, pt=1.6, bw=0.50, pb=2.0, k=1.0, lean=0.75,     # 0.84
                             hips=dict(y=0.73, hh=0.28, w=0.95, x=0.46, pe=2.0)),
    ("Thin", "ns"):     dict(yc=0.24, pt=2.0, bw=0.95, pb=4.5, k=2.2, lean=0.5),     # 0.94 0.89
    ("Thin", "east"):   dict(yc=0.18, pt=3.4, bw=0.55, pb=7.0, k=1.5, lean=0.15),    # 0.80
    ("Fat", "ns"):      dict(yc=0.44, pt=1.6, bw=0.85, pb=4.5, k=2.2, lean=0.5),     # 0.95 0.94
    ("Fat", "east"):    dict(yc=0.44, pt=1.6, bw=0.85, pb=4.5, k=2.2, lean=0.45),    # 0.93
    ("Hulk", "ns"):     dict(yc=0.44, pt=2.6, bw=0.55, pb=3.0, k=0.7, lean=0.5),     # 0.96 0.95
    ("Hulk", "east"):   dict(yc=0.36, pt=2.6, bw=0.55, pb=4.5, k=1.0, lean=0.15),    # 0.88
}


# ------------------------------------------------------------------ image io
def load_rgba(path):
    """Float RGBA, shape (H, W, 4), row 0 at the TOP. Byte PNGs come back as the
    stored values / 255 with no colour-space conversion."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)[::-1].copy()     # Blender stores bottom-up


def save_png(path, rgba):
    """Write float RGBA (row 0 at top) as an 8-bit PNG. Written by hand so no
    colour management sits between these numbers and the file."""
    a = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, _ = a.shape
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


# ------------------------------------------------------------------- helpers
def resize(arr, w, h):
    """Bilinear resample of an (H, W, C) array to (h, w, C)."""
    H, W = arr.shape[:2]
    ys = (np.arange(h) + 0.5) * H / h - 0.5
    xs = (np.arange(w) + 0.5) * W / w - 0.5
    y0 = np.clip(np.floor(ys).astype(int), 0, H - 1); y1 = np.clip(y0 + 1, 0, H - 1)
    x0 = np.clip(np.floor(xs).astype(int), 0, W - 1); x1 = np.clip(x0 + 1, 0, W - 1)
    fy = np.clip(ys - y0, 0, 1)[:, None, None]
    fx = np.clip(xs - x0, 0, 1)[None, :, None]
    top = arr[y0][:, x0] * (1 - fx) + arr[y0][:, x1] * fx
    bot = arr[y1][:, x0] * (1 - fx) + arr[y1][:, x1] * fx
    return top * (1 - fy) + bot * fy


def downsample(arr, f):
    h, w = arr.shape[0] // f, arr.shape[1] // f
    return arr[:h * f, :w * f].reshape(h, f, w, f, -1).mean(axis=(1, 3))


def dilate(mask, r):
    """Disc dilation by r pixels.

    PADDED, NOT ROLLED. np.roll wraps around the edges, so anything touching the
    bottom of the canvas grew an outline at the TOP. Nothing reached the edge
    until the Realistic Body greaves, whose feet sit at y=0.999 - and every one of
    those sprites came out with a stray dark arc floating above the head."""
    r = int(round(r))
    h, w = mask.shape
    pad = np.pad(mask, r, mode="constant", constant_values=False)
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            out |= pad[r + dy:r + dy + h, r + dx:r + dx + w]
    return out


def blur(a, r):
    """Box blur of a 2-D array by radius r, via summed-area tables. Run twice it
    is close enough to a gaussian for this."""
    r = int(round(r))
    if r < 1:
        return a
    for axis in (0, 1):
        p = np.pad(a, [(r + 1, r) if i == axis else (0, 0) for i in range(2)], mode="edge")
        c = np.cumsum(p, axis=axis)
        hi = np.take(c, np.arange(2 * r + 1, c.shape[axis]), axis=axis)
        lo = np.take(c, np.arange(0, c.shape[axis] - 2 * r - 1), axis=axis)
        a = (hi - lo) / (2 * r + 1)
    return a


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


# ---------------------------------------------------------------------- bean
def bean_widths(p, h):
    """Row width (fraction of the box) for each of h rows, top to bottom.

    Above the widest row yc: a superellipse cap, so the shoulders round over.
    Below it: a taper from full width to bw at the hips (curvature k), closed off
    by a second superellipse cap (exponent pb) so the bottom is rounded, not cut."""
    y = (np.arange(h) + 0.5) / h
    yc = p["yc"]
    w = np.empty(h)
    up = y < yc
    t = (yc - y[up]) / yc
    w[up] = np.clip(1 - t ** p["pt"], 0, 1) ** (1 / p["pt"])
    t = (y[~up] - yc) / (1 - yc)
    taper = 1 - (1 - p["bw"]) * t ** p["k"]
    cap = np.clip(1 - t ** p["pb"], 0, 1) ** (1 / p["pb"])
    w[~up] = taper * cap
    return w


def bean_rows(p, w_px, h_px):
    """Boolean (h, w) mask from the row widths. lean places each row: 0 hugs the
    left (the BACK, in an east view, which faces right), 0.5 centres it - so a
    profile keeps a straight back while its chest bulges forward."""
    widths = bean_widths(p, h_px)
    x = (np.arange(w_px) + 0.5) / w_px
    left = (1 - widths) * p["lean"]
    right = left + widths
    hips = p.get("hips")
    if hips:
        # A second rounded lobe, merged with the first. The female body is an
        # hourglass - bust widest near 0.34, waist pinched at 0.48, hips at
        # 0.72-0.77 WIDER than the shoulders, and in profile the hips sit
        # further back - which a single-peak taper cannot draw however tuned.
        y = (np.arange(h_px) + 0.5) / h_px
        d = np.abs(y - hips["y"]) / hips["hh"]
        on = d < 1
        half = np.zeros(h_px)
        half[on] = 0.5 * hips["w"] * (1 - d[on] ** hips["pe"]) ** (1 / hips["pe"])
        hl, hr = hips["x"] - half, hips["x"] + half
        left = np.where(on, np.minimum(left, hl), left)
        right = np.where(on, np.maximum(right, hr), right)
    return (x[None, :] >= left[:, None]) & (x[None, :] <= right[:, None])


def bean(kind, w, h, body=None):
    """Boolean (h, w) mask of the body outline filling a w x h box. Uses the
    body type's own fitted shape where there is one (BEAN_BODY), else the
    shared one."""
    p = BEAN_BODY.get((body, kind), BEAN[kind])
    return bean_rows(p, w, h)


def place_box(kind_box):
    x0, x1, y0, y1 = kind_box
    bx, by = int(round(x0 * CANVAS)), int(round(y0 * CANVAS))
    bw, bh = int(round((x1 - x0) * CANVAS)), int(round((y1 - y0) * CANVAS))
    return bx, by, bw, bh


# ----------------------------------------------------------------------- fit
def fill_rows(m):
    """Fill each row between its outermost set pixels. The reference garment has a
    transparent collar opening on its south and east views - a garment detail,
    not part of the body - and without this it scores against a solid bean."""
    out = np.zeros_like(m)
    for y in np.where(m.any(axis=1))[0]:
        xs = np.where(m[y])[0]
        out[y, xs[0]:xs[-1] + 1] = True
    return out


def fit(ref_prefix):
    """Search bean parameters against a reference garment's silhouettes, by IoU.

    The reference is a measuring stick: only its outline's agreement with OUR
    shape is computed, and nothing of it is written anywhere. Each body type is
    placed in its own measured box, so this also checks the boxes."""
    import itertools
    o = int(round(OUTLINE_PX))
    cases = {"ns": [], "east": []}
    for body, boxes in BOXES.items():
        for facing in FACINGS:
            kind = "east" if facing == "east" else "ns"
            path = f"{ref_prefix}_{body}_{facing}.png"
            if not os.path.exists(path):
                continue
            ref = fill_rows(load_rgba(path)[..., 3] > 0.5)
            ref_inner = ~dilate(~ref, OUTLINE_PX)           # erode by the outline
            bx, by, bw, bh = place_box(boxes[kind])
            cases[kind].append((body, facing, ref_inner, bx + o, by + o, bw - 2 * o, bh - 2 * o))

    def score(p, case):
        _, _, ref_inner, x, y, w, h = case
        ours = np.zeros_like(ref_inner)
        ours[y:y + h, x:x + w] = bean_rows(p, w, h)
        return (ours & ref_inner).sum() / max(1, (ours | ref_inner).sum())

    grid = dict(yc=[0.18, 0.24, 0.30, 0.36, 0.44], pt=[1.6, 2.0, 2.6, 3.4],
                bw=[0.55, 0.65, 0.75, 0.85, 0.95], pb=[2.0, 3.0, 4.5, 7.0], k=[0.7, 1.0, 1.5, 2.2])
    def search(kind, subset):
        best = (-1, None)
        for vals in itertools.product(*grid.values(), lean_opts[kind]):
            p = dict(zip(list(grid) + ["lean"], vals))
            s = np.mean([score(p, c) for c in subset])
            if s > best[0]:
                best = (s, p)
        return best

    lean_opts = {"ns": [0.5], "east": [0.0, 0.15, 0.3, 0.45]}
    table = {}
    for kind in ("ns", "east"):
        s, p = search(kind, cases[kind])
        print(f"FIT shared {kind}: mean IoU {s:.3f}")
        for body in BOXES:
            subset = [c for c in cases[kind] if c[0] == body]
            if not subset:
                continue
            sb, pb = search(kind, subset)
            table[(body, kind)] = pb
            per = "  ".join(f"{c[1]} {score(pb, c):.3f}" for c in subset)
            print(f"FIT   {body:7s} {kind:4s} own shape: {per}   (shared gave {np.mean([score(p, c) for c in subset]):.3f})")
    # Female: the two-lobe search. Upper profile with a narrow waist (low bw),
    # plus the hip lobe.
    for kind in ("ns", "east"):
        subset = [c for c in cases[kind] if c[0] == "Female"]
        hx_opts = [0.5] if kind == "ns" else [0.30, 0.38, 0.46]
        lean_f = [0.5] if kind == "ns" else [0.45, 0.6, 0.75]
        best = (-1, None)
        for yc, pt, bw, pb, k, ln in itertools.product([0.30, 0.36, 0.42], [1.6, 2.0, 2.6],
                                                       [0.50, 0.60, 0.70], [2.0, 3.0, 4.5], [1.0, 1.5], lean_f):
            up = dict(yc=yc, pt=pt, bw=bw, pb=pb, k=k, lean=ln)
            for hy, hh, hw, hx, pe in itertools.product([0.68, 0.73, 0.78], [0.22, 0.28, 0.34],
                                                        [0.85, 0.95, 1.0], hx_opts, [2.0, 3.0]):
                q = dict(up, hips=dict(y=hy, hh=hh, w=hw, x=hx, pe=pe))
                s = np.mean([score(q, c) for c in subset])
                if s > best[0]:
                    best = (s, q)
        s, q = best
        table[("Female", kind)] = q
        print(f"FIT   Female  {kind:4s} two lobes: " + "  ".join(f"{c[1]} {score(q, c):.3f}" for c in subset))
    print("FIT BEAN_BODY = {")
    for (body, kind), p in table.items():
        print(f'FIT     ("{body}", "{kind}"): dict(' + ", ".join(f"{k}={v}" for k, v in p.items()) + "),")
    print("FIT }")


# ------------------------------------------------------------------- compose
PLATE = {"lo": 0.66, "base": 0.84, "hi": 0.97}                    # near-white: takes the dye
SUIT = {"lo": np.array([0.20, 0.19, 0.18]),
        "base": np.array([0.30, 0.29, 0.28]),
        "hi": np.array([0.39, 0.38, 0.36])}


def compose_one(passes, facing, body, band_bottom):
    kind = "east" if facing == "east" else "ns"
    alb = load_rgba(os.path.join(passes, f"{facing}_albedo.png"))
    shd = load_rgba(os.path.join(passes, f"{facing}_shade.png"))

    # The model's own extent, then the shoulders-to-hips band of it.
    a = alb[..., 3] > 0.5
    rows = np.where(a.any(axis=1))[0]
    top, bottom = rows[0], rows[-1]
    band_end = int(top + (bottom - top) * band_bottom)
    band = a[top:band_end]
    cols = np.where(band.any(axis=0))[0]
    left, right = cols[0], cols[-1] + 1

    bx, by, bw, bh = place_box(BOXES[body][kind])
    o = int(round(OUTLINE_PX))
    iw, ih = (bw - 2 * o) * SS, (bh - 2 * o) * SS

    crop_a = resize(alb[top:band_end, left:right], iw, ih)
    crop_s = resize(shd[top:band_end, left:right], iw, ih)
    shape = bean(kind, iw, ih, body)

    # SIMPLIFY BEFORE CLASSIFYING. A model has far more detail than 256 px can
    # carry; classified raw it breaks into speckle. A light blur plus a majority
    # filter merges anything under about one final pixel into its neighbour.
    # Heavier smoothing was tried and melted the plates into blotches.
    present = blur(crop_a[..., 3], SS * 0.75) > 0.5
    plate = blur(lum(crop_a[..., :3]) * crop_a[..., 3], SS * 0.75) > 0.42 * 0.95
    plate = (blur(blur(plate.astype(float), SS), SS) > 0.5) & present & shape

    # CREASES - the grooves between plates - from the shade pass: where the
    # surface is darker than its own neighbourhood. These become the panel lines,
    # since the plates are all one colour and the albedo cannot separate them.
    s = lum(crop_s[..., :3])
    cavity = s - blur(blur(s, SS * 2.5), SS * 2.5)
    crease = blur(blur((cavity < -0.05).astype(float), SS * 0.5), SS * 0.5) > 0.5
    crease &= present & shape

    # SHADING the RimWorld way: not lit, BEVELLED. One lighter band along each
    # shape's upper-left edge and one darker band along its lower-right, measured
    # in CLAUDE.md's art idiom. A pixel is in the light band when the pixel a
    # band-width up and to the left of it lies outside its shape.
    bw_px = int(round(SS * 1.6))

    def bevel(region):
        hi = region & ~np.roll(np.roll(region, bw_px, 0), bw_px, 1)
        lo = region & ~np.roll(np.roll(region, -bw_px, 0), -bw_px, 1) & ~hi
        return hi, lo

    solid = shape & ~crease
    p_hi, p_lo = bevel(plate & solid)
    s_reg = shape & ~plate & ~crease
    s_hi, s_lo = bevel(s_reg)

    rgb = np.zeros((ih, iw, 3))
    rgb[s_reg] = SUIT["base"]
    rgb[s_hi] = SUIT["hi"]
    rgb[s_lo] = SUIT["lo"]
    rgb[plate & solid] = PLATE["base"]
    rgb[p_hi] = PLATE["hi"]
    rgb[p_lo] = PLATE["lo"]

    # Seam lines: plate meeting undersuit, plus the creases. About one final px.
    edge = np.zeros_like(plate)
    edge |= plate ^ np.roll(plate, 1, 0)
    edge |= plate ^ np.roll(plate, 1, 1)
    edge = (dilate(edge, SS * 0.55) | crease) & shape
    rgb[edge] = INK

    # Into a supersampled full canvas, with the outline ring around the bean.
    C = CANVAS * SS
    body_mask = np.zeros((C, C), bool)
    col = np.zeros((C, C, 3))
    plate_c = np.zeros((C, C), bool)
    oy, ox = (by + o) * SS, (bx + o) * SS
    body_mask[oy:oy + ih, ox:ox + iw] = shape
    col[oy:oy + ih, ox:ox + iw] = rgb
    plate_c[oy:oy + ih, ox:ox + iw] = plate & ~edge
    ring = dilate(body_mask, OUTLINE_PX * SS) & ~body_mask
    col[ring] = INK
    alpha = (body_mask | ring).astype(float)

    tex = np.dstack([col * alpha[..., None], alpha])
    msk = np.dstack([plate_c.astype(float) * alpha, np.zeros((C, C)), np.zeros((C, C)), alpha])

    def finish(img):
        d = downsample(img, SS)
        out = d.copy()
        nz = d[..., 3] > 1e-4
        out[nz, :3] = d[nz, :3] / d[nz, 3:4]         # un-premultiply
        return out

    return finish(tex), finish(msk)


def compose(passes, prefix, band_bottom):
    for body in BOXES:
        for facing in FACINGS:
            tex, msk = compose_one(passes, facing, body, band_bottom)
            save_png(f"{prefix}_{body}_{facing}.png", tex)
            save_png(f"{prefix}_{body}_{facing}m.png", msk)
            print("WROTE", f"{prefix}_{body}_{facing}")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    mode = argv[0]
    if mode == "fit":
        fit(os.path.abspath(argv[1]))
    elif mode == "compose":
        compose(os.path.abspath(argv[1]), os.path.abspath(argv[2]),
                float(argv[3]) if len(argv) > 3 else 0.42)
    else:
        raise SystemExit("mode must be fit or compose")
