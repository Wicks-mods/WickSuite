"""Title the look screenshots: each style's name, large, across the middle
of its screenshot, in that style's heading font and accent colour.

    python title-look-shots.py [Name ...]     (default: every look)

Reads design-handoff/images/screenshots/<Name>.png and writes a copy to
design-handoff/images/screenshots/titled/<Name>.png; the originals are
never written.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = r"C:\Users\jspli\Projects\Wick\design-handoff\images\screenshots"
OUT = os.path.join(ROOT, "titled")
FONTS = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\WickCore\Media\Fonts"

# file name -> (title as the style writes it, heading font, accent colour)
LOOKS = {
    "WicksModern": ("Wick Modern", "PT_Sans-Narrow-Web-Bold.ttf", "4FC778"),
    "WicksOG":     ("Wick OG", "PT_Sans-Narrow-Web-Bold.ttf", "4FC778"),
    "Hologram":    ("HOLOGRAM", "Jost-SemiBold.ttf", "3FE0FF"),
    "Rebel":       ("REBEL", "Anton-Regular.ttf", "E5091A"),
    "Gilded":      ("Gilded", "CormorantSC-SemiBold.ttf", "D4B66A"),
    "Arena":       ("ARENA", "BarlowCondensed-Bold.ttf", "FF5263"),
    "Foundry":     ("FOUNDRY", "Tektur-SemiBold.ttf", "FF8A1F"),
    "Frost":       ("FROST", "Michroma-Regular.ttf", "8FD3FF"),
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fit_font(path, text, width):
    """The largest size at which the text spans about the given width."""
    size = 40
    while True:
        f = ImageFont.truetype(path, size)
        l, t, r, b = f.getbbox(text)
        if r - l >= width or size > 900:
            return f
        size += 4


def title(name):
    text, font_file, accent = LOOKS[name]
    src = os.path.join(ROOT, name + ".png")
    base = Image.open(src).convert("RGBA")
    W, H = base.size
    font = fit_font(os.path.join(FONTS, font_file), text, int(W * 0.62))
    l, t, r, b = font.getbbox(text)
    x = (W - (r - l)) // 2 - l
    y = (H - (b - t)) // 2 - t

    # A soft dark halo under the letters so they read over busy scenery,
    # then the letters in the accent.
    halo = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).text((x, y), text, font=font, fill=(0, 0, 0, 230))
    halo = halo.filter(ImageFilter.GaussianBlur(max(6, H // 90)))
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x + max(2, H // 300), y + max(3, H // 250)), text, font=font, fill=(0, 0, 0, 200))
    ink = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(ink).text((x, y), text, font=font, fill=rgb(accent) + (255,))

    out = Image.alpha_composite(base, halo)
    out = Image.alpha_composite(out, halo)
    out = Image.alpha_composite(out, shadow)
    out = Image.alpha_composite(out, ink)
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name + ".png")
    assert os.path.abspath(dst) != os.path.abspath(src)
    out.convert("RGB").save(dst)
    print("wrote", dst)


for n in (sys.argv[1:] or list(LOOKS)):
    title(n)
