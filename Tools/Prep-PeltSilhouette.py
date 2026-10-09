"""
Build the Howler pelt's silhouette sprites from the ghostCloak's code-drawn originals.

The pelt is "the cloak design minus its lower half" (docs/Opus-Notes.md): a shoulder
mantle. Every body type's mantle ends near 0.51 of the 256 canvas (the measured body
boxes put the shoulders at 0.27-0.34 and the mantle a third of the box below), so each
original is cut there - lower at the back (north), where the hide hangs down. The
result is only the registration target that Tools/Gen-WornSet.ps1 generates over and
Tools/Clean-GenWorn.py fits back to, exactly as the armour originals are.

    blender -b --factory-startup --python Tools/Prep-PeltSilhouette.py -- <cloak orig dir> <pelt texture dir>
"""
import glob
import importlib.machinery
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
cw = importlib.machinery.SourceFileLoader(
    "cw", os.path.join(HERE, "Compose-WornApparel.py")).load_module()

CUT = {"south": 0.52, "east": 0.52, "north": 0.64}

if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:]
    src, dst = os.path.abspath(a[0]), os.path.abspath(a[1])
    for f in sorted(glob.glob(os.path.join(src, "RR_GhostCloak_*_*.png"))):
        m = re.match(r"RR_GhostCloak_(\w+?)_(south|east|north)\.png$", os.path.basename(f))
        if not m or m.group(1) == "Child":
            continue
        img = cw.load_rgba(f)
        h = img.shape[0]
        # load_rgba rows run top to bottom, as the PNG does.
        img[int(round(CUT[m.group(2)] * h)):, :, :] = 0
        out = os.path.join(dst, "RR_HowlerPelt_%s_%s.png" % (m.group(1), m.group(2)))
        cw.save_png(out, img)
        print("WROTE", out)
