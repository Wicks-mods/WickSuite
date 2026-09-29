"""WickCore style textures: the panel, ring and mask shapes each look draws with.

White on transparent, drawn at 8x and scaled down for clean edges, tinted in
game. Panels and rings are 9-sliced in game with the margin the look names
(Chrome.Styles in WickCore/Chrome.lua); masks are 64x64 and stretched whole
over an icon or the minimap.

  Hologram   corners cut at 45 degrees (slice 8), the same cut for masks
  Gilded     a wash that fades out at its sides, gold rules above and below
             it (slice 16), and a circular icon mask
  Arena      one 6 px notch, top right (slice 8), on panels and tiles alike,
             square masks, and a flat bar with a hard top edge
  Frost      a plain square and a hairline outline (slice 4), square masks,
             and a glass bar texture for health and power
"""
from PIL import Image, ImageDraw

OUT = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\WickCore\Media\Textures"
K = 8
WHITE = (255, 255, 255, 255)
CLEAR = (255, 255, 255, 0)


def canvas(w, h=None):
    h = h or w
    img = Image.new("RGBA", (w * K, h * K), CLEAR)
    return img, ImageDraw.Draw(img)


def save(img, name):
    w, h = img.size
    img.resize((w // K, h // K), Image.LANCZOS).save(f"{OUT}\\{name}.png")


def poly_pts(s, cuts, inset=0):
    """An octagon-ish outline: cuts = (tl, tr, br, bl) corner cut sizes."""
    n, i = s * K - 1, inset * K
    tl, tr, br, bl = (c * K for c in cuts)
    k = 0.41 * i
    return [(tl + k, i), (n - tr - k, i), (n - i, tr + k), (n - i, n - br - k),
            (n - br - k, n - i), (bl + k, n - i), (i, n - bl - k), (i, tl + k)]


def shape(s, cuts, ring=None):
    img, d = canvas(s)
    d.polygon(poly_pts(s, cuts), fill=WHITE)
    if ring:
        d.polygon(poly_pts(s, cuts, ring), fill=CLEAR)
    return img


# Hologram: cut corners on panels, rings and masks.
save(shape(32, (7, 7, 7, 7)), "panel-chamfer")
save(shape(32, (7, 7, 7, 7), ring=1.25), "ring-chamfer")
save(shape(64, (12, 12, 12, 12)), "mask-chamfer")

# Arena: one notch, top right.
save(shape(32, (0, 6, 0, 0)), "panel-notch")
save(shape(32, (0, 6, 0, 0), ring=1.25), "ring-notch")

# Frost and Arena masks: plain squares. Frost's hairline.
img, d = canvas(64)
d.rectangle([0, 0, 64 * K - 1, 64 * K - 1], fill=WHITE)
save(img, "mask-square")
img, d = canvas(32)
d.rectangle([0, 0, 32 * K - 1, 32 * K - 1], fill=WHITE)
save(img, "panel-square")
img, d = canvas(32)
d.rectangle([0, 0, 32 * K - 1, 32 * K - 1], fill=WHITE)
d.rectangle([K, K, 31 * K - 1, 31 * K - 1], fill=CLEAR)
save(img, "ring-hair")

# Gilded: the wash fades out over its outer 16 px left and right; the rules
# are a line along the top and bottom that fades out the same way.
W, H = 64, 64
wash = Image.new("RGBA", (W, H), CLEAR)
rules = Image.new("RGBA", (W, H), CLEAR)
for x in range(W):
    edge = min(x, W - 1 - x)
    a = min(1.0, edge / 16.0) ** 1.6
    for y in range(H):
        wash.putpixel((x, y), (255, 255, 255, int(255 * a)))
    ra = int(255 * min(1.0, edge / 16.0))
    rules.putpixel((x, 0), (255, 255, 255, ra))
    rules.putpixel((x, H - 1), (255, 255, 255, ra))
wash.save(f"{OUT}\\panel-wash.png")
rules.save(f"{OUT}\\ring-rules.png")
img, d = canvas(64)
d.ellipse([0, 0, 64 * K - 1, 64 * K - 1], fill=WHITE)
save(img, "mask-circle")

# Frost's glass bar: tinted in game, so white with shading. A bright band
# over the top third, a clear middle, a slightly deeper base, a light line
# on the top edge and a dark one on the bottom. Stretched along the bar.
bw, bh = 16, 32
bar = Image.new("RGBA", (bw, bh), CLEAR)
for y in range(bh):
    t = y / (bh - 1)
    if y == 0:
        v, a = 255, 255
    elif y == bh - 1:
        v, a = 120, 255
    elif t < 0.38:
        v, a = int(255 - 30 * (t / 0.38)), 235
    else:
        v, a = int(205 - 55 * ((t - 0.38) / 0.62)), 215
    for x in range(bw):
        bar.putpixel((x, y), (v, v, v, a))
bar.save(f"{OUT}\\bar-glass.png")

# Arena's bar: flat, with a hard light line along the top and a darker base
# two pixels deep, for a crisp printed edge.
edge = Image.new("RGBA", (16, 32), CLEAR)
for y in range(32):
    v = 255 if y == 0 else (150 if y >= 30 else 225)
    for x in range(16):
        edge.putpixel((x, y), (v, v, v, 255))
edge.save(f"{OUT}\\bar-edge.png")
print("ok")
