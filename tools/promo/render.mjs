// Render a promo from a shot list (an EDL json the scout writes):
//   node render.mjs <edl.json>
//
// EDL: { source, format: "vertical"|"landscape"|"square", addon, kicker,
//        shots: [{ in, out, crop: [x,y,w,h], speed, caption }],
//        end: { kicker, caption } | false, out,
//        music: { file, start, volume } }   (file in design-handoff/music)
// Times are seconds or "m:ss.s". Each shot's footage is cropped to the
// addon, scaled into the layout's hole, and laid over a frame of Wick's Mods
// chrome rendered from layout.html; an end card closes it. With "music",
// a track from design-handoff/music plays under it (faded in and out) and
// its CC BY credit line is written to <out>.credits.txt for the post.
// H.264 + AAC for every platform.

import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const puppeteer = createRequire("C:/Users/jspli/.claude/tools/igrab/")("puppeteer-core");
const here = path.dirname(fileURLToPath(import.meta.url));
const SIZES = { vertical: [1080, 1920], landscape: [1920, 1080], square: [1080, 1080] };
const FPS = 60;

const edlPath = path.resolve(process.argv[2]);
const edl = JSON.parse(fs.readFileSync(edlPath, "utf8"));
const [W, H] = SIZES[edl.format || "vertical"];
const work = path.join(path.dirname(edlPath), path.basename(edlPath, ".json") + "_work");
fs.mkdirSync(work, { recursive: true });
const sec = t => typeof t === "number" ? t : t.split(":").reduce((a, b) => a * 60 + parseFloat(b), 0);
const even = n => Math.round(n / 2) * 2;

// Where the footage goes: as wide as the layout allows, keeping the crop's shape.
function holeFor(crop) {
  const [, , cw, ch] = crop;
  const maxW = W - 2 * Math.round(80 * W / 1080);
  const top = Math.round((edl.format === "landscape" ? 300 : 380) * W / 1080);
  const maxH = H - top - Math.round((edl.format === "vertical" ? 520 : 260) * W / 1080);
  const k = Math.min(maxW / cw, maxH / ch);
  const hw = even(cw * k), hh = even(ch * k);
  // Vertical: centre the footage (a little high, the caption sits below it).
  const y = edl.format === "vertical" ? Math.max(top, even((H - hh) / 2 - 40 * W / 1080)) : top;
  return [even((W - hw) / 2), y, hw, hh];
}

const browser = await puppeteer.launch({ executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
const page = await browser.newPage();
async function frame(params, file) {
  await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
  const url = pathToFileURL(path.join(here, "layout.html")).href + "#" + encodeURIComponent(JSON.stringify({ w: W, h: H, ...params }));
  await page.goto("about:blank");
  await page.goto(url, { waitUntil: "networkidle0" });
  await page.waitForSelector("body[data-ready='1']");
  await (await page.$("#art")).screenshot({ path: file, omitBackground: !!params.overlay });
}

const ff = args => execFileSync("ffmpeg", ["-v", "error", "-y", ...args], { stdio: "inherit" });
const parts = [];
const enc = ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", String(FPS), "-c:a", "aac", "-b:a", "128k"];

// Full-bleed style: the footage fills the frame, a transparent overlay adds
// the corner brand mark and the caption (or the hook on the first shot).
// A shot's "dur" (seconds, e.g. whole bars of the music) wins over "out".
//   mode "fill": crop [x,y,w,h] scaled to cover the frame, pushing in from
//                zoom[0] to zoom[1] (default 1 to 1.06) over the shot.
//   mode "fit":  crop blown up to the frame width over a blurred, darkened
//                backdrop of the same moment, framed in brand chrome.
async function fullbleedShot(i, s) {
  const a = sec(s.in), speed = s.speed || 1;
  const dur = s.dur || (sec(s.out) - a) / speed;
  const [cx, cy, cw, ch] = s.crop;
  const [z0, z1] = s.zoom || [1, 1.06];
  const ov = path.join(work, `ov_${i}.png`);
  let filter, frameRect = null;
  const src = `[1:v]setpts=(PTS-STARTPTS)/${speed}`;
  const cover = Math.max(W / cw, H / ch) * 1.005;   // a hair over, so rounding never leaves it short
  const push = `scale=w='trunc(${cw * cover}*(${z0}+(${z1 - z0})*t/${dur})/2)*2':h=-2:eval=frame:flags=lanczos,crop=${W}:${H}`;
  if ((s.mode || "fill") === "fill") {
    filter = `${src},crop=${cw}:${ch}:${cx}:${cy},${push}[v]`;
  } else {
    // backdrop: a 9:16 slice centred on the region, blurred and dimmed
    const bw = Math.min(1920, Math.round(1080 * W / H)), bx = Math.max(0, Math.min(1920 - bw, Math.round(cx + cw / 2 - bw / 2)));
    const fw = even(W - 2 * Math.round(70 * W / 1080)), fh = even(ch * fw / cw);
    const fx = (W - fw) / 2, fy = even((H - fh) / 2 + 120 * W / 1080);
    frameRect = [fx, fy, fw, fh];
    filter = `${src},split[a][b];[a]crop=${bw}:1080:${bx}:0,scale=${W}:${H},boxblur=24:2,eq=brightness=-0.28[bg];` +
      `[b]crop=${cw}:${ch}:${cx}:${cy},scale=${fw}:${fh}:flags=lanczos[fg];[bg][fg]overlay=${fx}:${fy}[v]`;
  }
  await frame({ overlay: true, addon: edl.addon, hook: s.hook || "", caption: s.caption || "", frame: frameRect }, ov);
  const out = path.join(work, `part_${i}.mp4`);
  ff(["-ss", String(a), "-t", String(dur * speed + 0.5), "-i", edl.source, "-loop", "1", "-framerate", String(FPS), "-i", ov,
    "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
    "-filter_complex", filter.replace("[1:v]", "[0:v]") + `;[v][1:v]overlay=0:0,fps=${FPS},format=yuv420p[o]`,
    "-map", "[o]", "-map", "2:a", "-t", String(dur), ...enc, out]);
  return out;
}

for (const [i, s] of edl.shots.entries()) {
  if (edl.style === "fullbleed") {
    parts.push(await fullbleedShot(i, s));
    console.log(`shot ${i + 1}/${edl.shots.length}: ${s.in} ${s.mode || "fill"} "${s.hook || s.caption || ""}"`);
    continue;
  }
  const hole = holeFor(s.crop);
  const bg = path.join(work, `bg_${i}.png`);
  await frame({ addon: edl.addon, kicker: edl.kicker, caption: s.caption || "", hole }, bg);
  const a = sec(s.in), b = sec(s.out), speed = s.speed || 1, dur = (b - a) / speed;
  const [cx, cy, cw, ch] = s.crop;
  const out = path.join(work, `part_${i}.mp4`);
  ff(["-loop", "1", "-framerate", String(FPS), "-i", bg, "-ss", String(a), "-t", String(b - a), "-i", edl.source,
    "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
    "-filter_complex",
    `[1:v]crop=${cw}:${ch}:${cx}:${cy},scale=${hole[2]}:${hole[3]}:flags=lanczos,setpts=(PTS-STARTPTS)/${speed},fps=${FPS}[v];` +
    `[0:v][v]overlay=${hole[0]}:${hole[1]}:shortest=1,fade=t=in:d=0.25,fade=t=out:st=${Math.max(0, dur - 0.25)}:d=0.25,format=yuv420p[o]`,
    "-map", "[o]", "-map", "2:a", "-t", String(dur), "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", String(FPS),
    "-c:a", "aac", "-b:a", "128k", out]);
  parts.push(out);
  console.log(`shot ${i + 1}/${edl.shots.length}: ${s.in}-${s.out} "${s.caption || ""}"`);
}
if (edl.end !== false) {
  const card = path.join(work, "end.png");
  await frame({ end: true, addon: edl.addon, ...(edl.end || {}) }, card);
  const out = path.join(work, "part_end.mp4");
  ff(["-loop", "1", "-framerate", String(FPS), "-i", card, "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", String((edl.end && edl.end.dur) || 2.8),
    "-vf", "fade=t=in:d=0.3,format=yuv420p", "-c:v", "libx264", "-crf", "18", "-r", String(FPS), "-c:a", "aac", "-b:a", "128k", "-shortest", out]);
  parts.push(out);
}
await browser.close();

const list = path.join(work, "list.txt");
fs.writeFileSync(list, parts.map(p => `file '${p.replace(/\\/g, "/")}'`).join("\n"));
const final = path.resolve(path.dirname(edlPath), edl.out || path.basename(edlPath, ".json") + ".mp4");
const joined = edl.music ? path.join(work, "joined.mp4") : final;
ff(["-f", "concat", "-safe", "0", "-i", list, "-c", "copy", "-movflags", "+faststart", joined]);

if (edl.music) {
  const musicDir = path.join(here, "..", "..", "..", "design-handoff", "music");
  const file = path.resolve(musicDir, edl.music.file);
  const dur = parseFloat(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", joined]).toString());
  const vol = edl.music.volume ?? 0.8;
  ff(["-i", joined, "-ss", String(edl.music.start || 0), "-i", file, "-filter_complex",
    `[1:a]atrim=0:${dur},asetpts=PTS-STARTPTS,afade=t=in:d=0.4,afade=t=out:st=${Math.max(0, dur - 1.8)}:d=1.8,volume=${vol}[a]`,
    "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", final]);
  // The CC BY credit line, from the library's ATTRIBUTION.md row for this file.
  const row = fs.readFileSync(path.join(musicDir, "ATTRIBUTION.md"), "utf8").split(/\r?\n/).find(l => l.includes(edl.music.file));
  const credit = row ? row.split("|").map(c => c.trim()).filter(Boolean).pop() : `Music: ${edl.music.file}`;
  fs.writeFileSync(final.replace(/\.mp4$/, ".credits.txt"), credit + "\n");
  console.log("credit:", credit);
}
console.log("wrote", final);
