"""Wick's UI glyphs: flat white marks on transparent, 32x32, drawn at 8x
and scaled down for clean edges. Tinted in game with SetVertexColor."""
import math
from PIL import Image, ImageDraw

OUT = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\WicksUI\Media\Textures"
S = 32
K = 8
N = S * K
W = int(2.2 * K)  # stroke width, about 2.2 px at final size


def canvas():
    img = Image.new("RGBA", (N, N), (255, 255, 255, 0))
    return img, ImageDraw.Draw(img)


def line(d, pts):
    d.line([(x * K, y * K) for x, y in pts], fill=(255, 255, 255, 255), width=W, joint="curve")
    for x, y in (pts[0], pts[-1]):
        r = W / 2
        d.ellipse([x * K - r, y * K - r, x * K + r, y * K + r], fill=(255, 255, 255, 255))


def save(img, name):
    img.resize((S, S), Image.LANCZOS).save(f"{OUT}\\glyph-{name}.png")


def chevron(name, pts):
    img, d = canvas()
    line(d, pts)
    save(img, name)


chevron("down", [(10, 13), (16, 19), (22, 13)])
chevron("up", [(10, 19), (16, 13), (22, 19)])
chevron("left", [(19, 10), (13, 16), (19, 22)])
chevron("right", [(13, 10), (19, 16), (13, 22)])

img, d = canvas(); line(d, [(10, 16), (22, 16)]); save(img, "minus")
img, d = canvas(); line(d, [(10, 16), (22, 16)]); line(d, [(16, 10), (16, 22)]); save(img, "plus")
img, d = canvas(); line(d, [(11, 11), (21, 21)]); line(d, [(21, 11), (11, 21)]); save(img, "close")

# Gear: a ring with eight teeth.
img, d = canvas()
cx = cy = 16 * K
ro, ri = 9.5 * K, 6.8 * K
teeth = 8
poly = []
for i in range(teeth * 4):
    a = (i / (teeth * 4)) * 2 * math.pi
    r = ro if (i % 4) in (1, 2) else ri + 0.9 * K
    poly.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
d.polygon(poly, fill=(255, 255, 255, 255))
hole = 3.2 * K
d.ellipse([cx - hole, cy - hole, cx + hole, cy + hole], fill=(255, 255, 255, 0))
save(img, "gear")

# Reset: an open ring with an arrow head.
img, d = canvas()
r = 7 * K
d.arc([cx - r, cy - r, cx + r, cy + r], start=40, end=330, fill=(255, 255, 255, 255), width=W)
ax, ay = cx + math.cos(math.radians(40)) * r, cy + math.sin(math.radians(40)) * r
head = 3.4 * K
d.polygon([(ax - head, ay - head * 0.2), (ax + head * 0.9, ay - head * 0.9), (ax + head * 0.3, ay + head)], fill=(255, 255, 255, 255))
save(img, "reset")
print("ok")
