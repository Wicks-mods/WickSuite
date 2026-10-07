"""Ingest an OBS recording for promo editing.

    python ingest.py [video | latest] [--every 3]

Writes design-handoff/video/<recording>/:
  frames/       one frame every N seconds (640 wide, timestamp burned in)
  sheet_NN.jpg  contact sheets, 4x4 frames each, for the scout to read
  index.json    source path, duration, size, fps, frame times, scene cuts

The recording itself stays where OBS saved it; nothing is copied.
"""
import json, os, re, subprocess, sys, glob
from PIL import Image

HOME = os.path.expanduser('~')
VIDEOS = os.path.join(HOME, 'Videos')
OUT_ROOT = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'design-handoff', 'video')
COLS, ROWS = 4, 4


def probe(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration:stream=codec_type,width,height,r_frame_rate',
                          '-of', 'json', path], capture_output=True, text=True, check=True).stdout
    j = json.loads(out)
    v = next(s for s in j['streams'] if s['codec_type'] == 'video')
    num, den = v['r_frame_rate'].split('/')
    return {'duration': float(j['format']['duration']), 'width': v['width'], 'height': v['height'],
            'fps': round(int(num) / int(den), 2), 'audio': any(s['codec_type'] == 'audio' for s in j['streams'])}


def hms(t):
    return f'{int(t // 60):02d}:{t % 60:04.1f}'


def scene_cuts(path, threshold=0.3):
    # Big visual changes (a window opening, a loading screen): good shot boundaries.
    r = subprocess.run(['ffmpeg', '-hide_banner', '-i', path, '-vf', f"scale=320:-1,select='gt(scene,{threshold})',showinfo",
                        '-an', '-f', 'null', '-'], capture_output=True, text=True)
    return [round(float(t), 2) for t in re.findall(r'pts_time:([\d.]+)', r.stderr)]


def main():
    args = sys.argv[1:]
    every = 3
    if '--every' in args:
        i = args.index('--every'); every = float(args[i + 1]); del args[i:i + 2]
    src = args[0] if args else 'latest'
    if src == 'latest':
        vids = sorted(glob.glob(os.path.join(VIDEOS, '*.mp4')) + glob.glob(os.path.join(VIDEOS, '*.mkv')), key=os.path.getmtime)
        src = vids[-1]
    src = os.path.abspath(src)
    name = os.path.splitext(os.path.basename(src))[0].replace(' ', '_')
    out = os.path.abspath(os.path.join(OUT_ROOT, name))
    frames = os.path.join(out, 'frames')
    os.makedirs(frames, exist_ok=True)
    meta = probe(src)
    print(f'{src}: {hms(meta["duration"])} {meta["width"]}x{meta["height"]} {meta["fps"]}fps')

    font = 'C\\:/Windows/Fonts/consola.ttf'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', src, '-vf',
                    f"fps=1/{every},scale=640:-1,drawtext=fontfile='{font}':text='%{{pts\\:hms}}':x=8:y=8:fontsize=22:"
                    "fontcolor=yellow:box=1:boxcolor=black@0.65",
                    os.path.join(frames, 'f_%04d.jpg')], check=True)
    files = sorted(glob.glob(os.path.join(frames, 'f_*.jpg')))
    times = [round(i * every, 2) for i in range(len(files))]

    for old in glob.glob(os.path.join(out, 'sheet_*.jpg')):
        os.remove(old)
    w, h = Image.open(files[0]).size
    per = COLS * ROWS
    sheets = []
    for n in range(0, len(files), per):
        chunk = files[n:n + per]
        sheet = Image.new('RGB', (w * COLS, h * ((len(chunk) + COLS - 1) // COLS)))
        for i, f in enumerate(chunk):
            sheet.paste(Image.open(f), ((i % COLS) * w, (i // COLS) * h))
        p = os.path.join(out, f'sheet_{n // per:02d}.jpg')
        sheet.save(p, quality=82)
        sheets.append({'file': os.path.basename(p), 'from': times[n], 'to': times[n + len(chunk) - 1]})

    cuts = scene_cuts(src)
    index = {'source': src, **meta, 'every': every, 'frames': len(files), 'sheets': sheets, 'scene_cuts': cuts}
    json.dump(index, open(os.path.join(out, 'index.json'), 'w'), indent=2)
    print(f'{len(files)} frames, {len(sheets)} sheets, {len(cuts)} scene cuts -> {out}')


if __name__ == '__main__':
    main()
