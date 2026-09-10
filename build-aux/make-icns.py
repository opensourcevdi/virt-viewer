#!/usr/bin/python3

# Render the scalable icon as a .icns, the macOS counterpart of the .ico that
# icotool builds for Windows. The tree ships PNGs only to 256px and .icns wants
# 512 and 1024, so every size is rasterised from the SVG rather than upscaled.
# iconutil reads a populated .iconset directory, not a list of files.

import os
import shutil
import subprocess
import sys
import tempfile

if len(sys.argv) != 3:
    print("syntax: %s INPUT.svg OUTPUT.icns" % sys.argv[0], file=sys.stderr)
    sys.exit(1)

svg, icns = sys.argv[1], sys.argv[2]

with tempfile.TemporaryDirectory() as tmp:
    iconset = os.path.join(tmp, "virt-viewer.iconset")
    os.mkdir(iconset)

    for size in (16, 32, 64, 128, 256, 512, 1024):
        png = os.path.join(iconset, "icon_%dx%d.png" % (size, size))
        subprocess.check_call([
            "rsvg-convert", "-w", str(size), "-h", str(size), svg, "-o", png,
        ])
        # iconutil wants each size's @2x as its own entry.
        if size > 16:
            half = size // 2
            shutil.copyfile(
                png, os.path.join(iconset, "icon_%dx%d@2x.png" % (half, half)))

    # There is no plain 1024 slot; 1024 exists only as 512x512@2x.
    os.remove(os.path.join(iconset, "icon_1024x1024.png"))

    subprocess.check_call(["iconutil", "-c", "icns", iconset, "-o", icns])
