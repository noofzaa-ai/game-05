"""Tiles the preview PNGs of build_base_character.py into one overview image (run with Blender, which ships numpy):

    blender -b --python tools/blender/contact_sheet.py -- <folder with the PNGs>
"""
import os
import sys

import bpy
import numpy as np

folder = sys.argv[sys.argv.index("--") + 1]
names = [
    "01_body_front", "03_body_three_quarter", "02_body_side", "04_top_down", "05_skeleton_front",
    "10_pose_idle", "11_pose_run", "12_pose_punch", "13_pose_big_swing", "17_pose_big_swing_top",
]
columns = 5
tiles = []
for name in names:
    image = bpy.data.images.load(os.path.join(folder, name + ".png"))
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)
    tile = pixels[::2, ::2].copy()  # half size
    tile[tile[..., 3] < 0.5] = (0.16, 0.18, 0.22, 1.0)  # the render leaves the background transparent
    tiles.append(tile)
rows = (len(tiles) + columns - 1) // columns
tile_h, tile_w = tiles[0].shape[0], tiles[0].shape[1]
sheet = np.ones((rows * tile_h, columns * tile_w, 4), dtype=np.float32)
for index, tile in enumerate(tiles):
    row, column = divmod(index, columns)
    # Blender images are stored bottom row first: the first sheet row must be the top one
    top = (rows - 1 - row) * tile_h
    sheet[top:top + tile_h, column * tile_w:(column + 1) * tile_w] = tile
sheet[..., 3] = 1.0
out = bpy.data.images.new("sheet", columns * tile_w, rows * tile_h)
out.pixels = sheet.flatten().tolist()
out.filepath_raw = os.path.join(folder, "overview.png")
out.file_format = "PNG"
out.save()
print("DONE", out.filepath_raw)
