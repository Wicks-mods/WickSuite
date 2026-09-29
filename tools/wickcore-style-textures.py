"""WickCore style textures: the panel, ring and mask shapes each style draws with.

White on transparent, drawn at 8x and scaled down for clean edges, tinted in
game. Panels and rings are 32x32 and 9-sliced in game with the margin the
style names (Chrome.Styles in WickCore/Chrome.lua); masks are 64x64 and
stretched whole over an icon or the minimap.

  Obsidian  a 12 px radius (slice 12) and a circular icon mask
  Hologram  corners cut at 45 degrees (slice 8), the same cut for masks
  Runic     a small diamond for the corner marks
"""
from PIL import Image, ImageDraw

OUT = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\WickCore\Media\Textures"
K = 8
WHITE = (255, 255, 255, 255)


def canvas(s):
    img = Image.new("RGBA", (s * K, s * K), (255, 255, 255, 0))
    return img, ImageDraw.Draw(img)


def save(img, s, name):
    img.resize((s, s), Image.LANCZOS).save(f"{OUT}\\{name}.png")


def rounded(s, r, ring=None):
    img, d = canvas(s)
    d.rounded_rectangle([0, 0, s * K - 1, s * K - 1], radius=r * K, fill=WHITE)
    if ring:
        w = ring * K
        d.rounded_rectangle([w, w, s * K - 1 - w, s * K - 1 - w], radius=max(0, (r - ring)) * K, fill=(255, 255, 255, 0))
    return img


def chamfer_pts(s, c, inset=0):
    n, c, i = s * K - 1, c * K, inset * K
    return [(c + i * 0.41, i), (n - c - i * 0.41, i), (n - i, c + i * 0.41), (n - i, n - c - i * 0.41),
            (n - c - i * 0.41, n - i), (c + i * 0.41, n - i), (i, n - c - i * 0.41), (i, c + i * 0.41)]


def chamfer(s, c, ring=None):
    img, d = canvas(s)
    d.polygon(chamfer_pts(s, c), fill=WHITE)
    if ring:
        d.polygon(chamfer_pts(s, c, ring), fill=(255, 255, 255, 0))
    return img


# Obsidian: deep rounding, circular icons.
save(rounded(32, 12), 32, "panel-r12")
save(rounded(32, 12, ring=1.25), 32, "ring-r12")
img, d = canvas(64)
d.ellipse([0, 0, 64 * K - 1, 64 * K - 1], fill=WHITE)
save(img, 64, "mask-circle")

# Hologram: cut corners on panels, rings and masks.
save(chamfer(32, 7), 32, "panel-chamfer")
save(chamfer(32, 7, ring=1.25), 32, "ring-chamfer")
save(chamfer(64, 12), 64, "mask-chamfer")

# Runic: the corner mark.
img, d = canvas(16)
m = 16 * K - 1
d.polygon([(m / 2, 0), (m, m / 2), (m / 2, m), (0, m / 2)], fill=WHITE)
d.polygon([(m / 2, m * 0.3), (m * 0.7, m / 2), (m / 2, m * 0.7), (m * 0.3, m / 2)], fill=(255, 255, 255, 0))
save(img, 16, "diamond")
print("ok")
