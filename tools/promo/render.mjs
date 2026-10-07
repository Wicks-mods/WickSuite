// Render a promo from a shot list (an EDL json the scout writes):
//   node render.mjs <edl.json>
//
// EDL: { source, format: "vertical"|"landscape"|"square", addon, kicker,
//        shots: [{ in, out, crop: [x,y,w,h], speed, caption }],
//        end: { kicker, caption } | false, out }
// Times are seconds or "m:ss.s". Each shot's footage is cropped to the
// addon, scaled into the layout's hole, and laid over a frame of Wick's Mods
// chrome rendered from layout.html; an end card closes it. Silent audio
// track (music bed comes later), H.264 for every platform.

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
  await (await page.$("#art")).screenshot({ path: file });
}

const ff = args => execFileSync("ffmpeg", ["-v", "error", "-y", ...args], { stdio: "inherit" });
const parts = [];
for (const [i, s] of edl.shots.entries()) {
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
  ff(["-loop", "1", "-framerate", String(FPS), "-i", card, "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", "2.8",
    "-vf", "fade=t=in:d=0.3,format=yuv420p", "-c:v", "libx264", "-crf", "18", "-r", String(FPS), "-c:a", "aac", "-b:a", "128k", "-shortest", out]);
  parts.push(out);
}
await browser.close();

const list = path.join(work, "list.txt");
fs.writeFileSync(list, parts.map(p => `file '${p.replace(/\\/g, "/")}'`).join("\n"));
const final = path.resolve(path.dirname(edlPath), edl.out || path.basename(edlPath, ".json") + ".mp4");
ff(["-f", "concat", "-safe", "0", "-i", list, "-c", "copy", "-movflags", "+faststart", final]);
console.log("wrote", final);
