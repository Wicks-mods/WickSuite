"""Join the look switcher frames into the Wick's UI looks GIF.

    node C:/Users/jspli/.claude/tools/igrab/capture-looks-gif.mjs <url> <frames>
    python looks-gif.py <frames> [out.gif]

Hard cuts, one frame per look, each held 2.4 seconds. CurseForge refuses
uploads of 2 MB or more, so the size is checked.
"""
import glob
import os
import sys
from PIL import Image

frames_dir = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else r"C:\Users\jspli\Projects\Wick\design-handoff\images\wick-ui-looks-cf.gif"

frames = [Image.open(f).convert("RGB") for f in sorted(glob.glob(os.path.join(frames_dir, "look-*.png")))]
assert frames, "no frames in " + frames_dir
# A one-line blurb makes a shorter frame: pad each to the tallest in the
# page's own ground rather than cut the others' second line.
W = max(f.size[0] for f in frames)
H = max(f.size[1] for f in frames)


def pad(f):
    ground = Image.new("RGB", (W, H), f.getpixel((0, f.size[1] - 1)))
    ground.paste(f, (0, 0))
    return ground


frames = [pad(f) for f in frames]

# The screenshot and the band under it (chips and caption) get palettes of
# their own, joined into the frame's one: left to a single palette, the
# screenshot takes the colours and the looks' accents on the small chips
# drift.
lower = int(H * 0.69)
SHOT, BAND = 176, 80


def quantize(f):
    top = f.crop((0, 0, W, lower)).quantize(colors=SHOT, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    band = f.crop((0, lower, W, H)).quantize(colors=BAND, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = Image.new("P", (W, H))
    out.paste(top, (0, 0))
    out.paste(band.point(lambda i: i + SHOT), (0, lower))
    pal = top.getpalette()[:SHOT * 3]
    pal += [0] * (SHOT * 3 - len(pal))
    out.putpalette(pal + band.getpalette()[:BAND * 3])
    return out


frames = [quantize(f) for f in frames]
frames[0].save(out, save_all=True, append_images=frames[1:], duration=2400, loop=0, optimize=True, disposal=1)
size = os.path.getsize(out)
print(f"wrote {out}: {len(frames)} frames, {W}x{H}, {size / 1e6:.2f} MB")
if size >= 2_000_000:
    sys.exit("too big for CurseForge (2 MB)")
