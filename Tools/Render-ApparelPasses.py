"""
Render a GLB apparel model into the raw passes the worn-sprite compositor needs.

Run through Blender, never directly:

    blender -b --factory-startup --python Tools/Render-ApparelPasses.py -- <model.glb> <out_dir> [size]

Writes, for each RimWorld facing (south, east, north):

    <facing>_albedo.png  Workbench, FLAT lighting, TEXTURE colour: the model's own
                         colours with no shading at all. This is what separates the
                         dyeable plates from the undersuit, so it is what the tint
                         mask is cut from.
    <facing>_shade.png   Workbench, STUDIO lighting, plain white material: form
                         only, no texture. Quantised later into RimWorld's one
                         highlight band and one shadow band.

WHY WORKBENCH. Both passes are information, not pictures. Workbench gives an exact
albedo and an exact shading term with no noise, no samples and no light setup to
drift between facings, and it renders in about a second.

CAMERAS. Orthographic and dead level, because RimWorld draws pawns straight on
with no perspective. glTF faces +Z, which Blender's importer turns into -Y, so:

    south  camera at -Y looking +Y   (the front)
    east   camera at -X looking +X   (profile, front toward screen-right)
    north  camera at +Y looking -Y   (the back)

Verified against a probe render, not assumed: the front view showed the chest, the
east view put the toes on the right.

Every facing shares one ortho scale and one camera height, so the three views of
the model stay in proportion to each other before the compositor fits each to its
own body box.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
# ABSOLUTE, both. Blender does not resolve render.filepath against the process's
# working directory the way Python's os functions do, so a relative out_dir had
# os.makedirs create the folder while every render silently landed elsewhere.
glb, out_dir = os.path.abspath(argv[0]), os.path.abspath(argv[1])
size = int(argv[2]) if len(argv) > 2 else 1024
os.makedirs(out_dir, exist_ok=True)

# Empty scene.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("no mesh in " + glb)

# World-space bounds over every mesh.
lo = Vector((math.inf,) * 3)
hi = Vector((-math.inf,) * 3)
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        lo = Vector(map(min, lo, w))
        hi = Vector(map(max, hi, w))
centre = (lo + hi) / 2
extent = hi - lo
print("BOUNDS lo", tuple(round(v, 3) for v in lo), "hi", tuple(round(v, 3) for v in hi))

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = size
scene.render.resolution_y = size
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"   # no Filmic/AgX tone curve on the albedo

sh = scene.display.shading
sh.show_shadows = False
sh.show_cavity = False
sh.show_object_outline = False
sh.show_specular_highlight = False

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
# One scale for all facings: the largest extent, plus a margin.
cam_data.ortho_scale = max(extent.x, extent.y, extent.z) * 1.08
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

dist = max(extent) * 4
facings = {
    "south": (Vector((centre.x, lo.y - dist, centre.z)), (math.radians(90), 0, 0)),
    "east":  (Vector((lo.x - dist, centre.y, centre.z)), (math.radians(90), 0, math.radians(-90))),
    "north": (Vector((centre.x, hi.y + dist, centre.z)), (math.radians(90), 0, math.radians(180))),
}

passes = {
    "albedo": dict(light="FLAT", color_type="TEXTURE"),
    "shade":  dict(light="STUDIO", color_type="SINGLE"),
}

for facing, (loc, rot) in facings.items():
    cam.location = loc
    cam.rotation_euler = rot
    for pname, p in passes.items():
        sh.light = p["light"]
        sh.color_type = p["color_type"]
        if p["color_type"] == "SINGLE":
            sh.single_color = (1.0, 1.0, 1.0)
        scene.render.filepath = os.path.join(out_dir, f"{facing}_{pname}.png")
        bpy.ops.render.render(write_still=True)
        print("WROTE", scene.render.filepath)
