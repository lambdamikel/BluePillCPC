#!/usr/bin/env python3
"""Double a MAME CPC snapshot vertically.

MAME writes the framebuffer at 1:1, but the CPC's mode 2 is 640x200 shown
on a 4:3 display - each pixel is twice as tall as it is wide. Saved raw,
everything comes out squashed to half height. NEAREST keeps the pixels
crisp; anything smoother would blur a 1-pixel-wide mode 2 character stroke.
"""
import sys
from PIL import Image
for path in sys.argv[1:]:
    im = Image.open(path)
    w, h = im.size
    im.resize((w, h * 2), Image.NEAREST).save(path)
    print("  %s  %dx%d -> %dx%d" % (path, w, h, w, h * 2))
