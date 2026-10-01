#!/usr/bin/env node
// OBS remote control over obs-websocket v5, no dependencies (Node 22+ has
// WebSocket built in). Runs standalone or as `wick obs <cmd>`.
//
// The password is read from OBS's own config every run, so it is never
// copied anywhere:
//   %APPDATA%/obs-studio/plugin_config/obs-websocket/config.json
// OBS_HOST / OBS_PORT / OBS_PASSWORD env vars override it.
//
// Commands:
//   status                         version, collection, scene, record/stream/replay state
//   scenes                         list scenes (* marks the live one)
//   scene <name>                   switch the program scene
//   sources [scene]                list the items in a scene
//   collections                    list scene collections
//   collection <name>              switch scene collection
//   shot [file] [--source X] [--width N]
//                                  save a PNG of a source (default: the live scene)
//   capture <slug> [--source X]    shot into design-handoff/images/screenshots/screenshot-<slug>.png
//   record start|stop|toggle|pause|resume|status
//   replay start|stop|save|status  replay buffer; `save` prints the clip path
//   stream start --yes|stop|status going live needs --yes
//   call <RequestType> [json]      send any raw obs-websocket request

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const TOOLS_DIR = path.dirname(fileURLToPath(import.meta.url));
const PROJECT   = path.dirname(path.dirname(TOOLS_DIR));
const SHOTS_DIR = path.join(PROJECT, "design-handoff", "images", "screenshots");

function die(msg) { console.error(`obs: ${msg}`); process.exit(1); }

function connInfo() {
  let cfg = {};
  const p = path.join(process.env.APPDATA || "", "obs-studio", "plugin_config", "obs-websocket", "config.json");
  try { cfg = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
  return {
    host: process.env.OBS_HOST || "127.0.0.1",
    port: Number(process.env.OBS_PORT || cfg.server_port || 4455),
    password: process.env.OBS_PASSWORD ?? (cfg.auth_required === false ? "" : cfg.server_password || ""),
  };
}

const sha = s => crypto.createHash("sha256").update(s).digest("base64");

export async function connect() {
  const { host, port, password } = connInfo();
  const ws = new WebSocket(`ws://${host}:${port}`);
  const pending = new Map();
  let nextId = 1;

  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`no answer from ws://${host}:${port}; is OBS running with the WebSocket server on?`)), 5000);
    ws.onerror = () => { clearTimeout(t); reject(new Error(`cannot reach ws://${host}:${port}; is OBS running with the WebSocket server on?`)); };
    ws.onclose = e => { clearTimeout(t); reject(new Error(e.code === 4009 ? "authentication failed (check the OBS WebSocket password)" : `closed: ${e.code} ${e.reason}`)); };
    ws.onmessage = ev => {
      const msg = JSON.parse(ev.data);
      if (msg.op === 0) {                       // Hello
        const d = { rpcVersion: 1, eventSubscriptions: 0 };
        const a = msg.d.authentication;
        if (a) d.authentication = sha(sha(password + a.salt) + a.challenge);
        ws.send(JSON.stringify({ op: 1, d }));
      } else if (msg.op === 2) {                // Identified
        clearTimeout(t);
        resolve();
      }
    };
  });

  ws.onclose = () => { for (const p of pending.values()) p.reject(new Error("OBS closed the connection")); pending.clear(); };
  ws.onmessage = ev => {
    const msg = JSON.parse(ev.data);
    if (msg.op !== 7) return;                   // RequestResponse
    const p = pending.get(msg.d.requestId);
    if (!p) return;
    pending.delete(msg.d.requestId);
    const st = msg.d.requestStatus;
    if (st.result) p.resolve(msg.d.responseData || {});
    else p.reject(new Error(`${msg.d.requestType} failed (${st.code})${st.comment ? ": " + st.comment : ""}`));
  };

  return {
    call(requestType, requestData = {}) {
      const requestId = String(nextId++);
      return new Promise((resolve, reject) => {
        pending.set(requestId, { resolve, reject });
        ws.send(JSON.stringify({ op: 6, d: { requestType, requestId, requestData } }));
      });
    },
    close() { ws.onclose = null; ws.close(); },
  };
}

function opt(args, name) {
  const i = args.indexOf(name);
  if (i < 0) return undefined;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
}

async function currentScene(obs) {
  return (await obs.call("GetCurrentProgramScene")).currentProgramSceneName;
}

async function saveShot(obs, file, source, width) {
  const sourceName = source || await currentScene(obs);
  const abs = path.resolve(file);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  const req = { sourceName, imageFormat: "png", imageFilePath: abs };
  if (width) req.imageWidth = Number(width);
  await obs.call("SaveSourceScreenshot", req);
  console.log(`saved ${abs}  (source: ${sourceName})`);
}

const onOff = b => (b ? "on" : "off");

export async function run(argv) {
  const args = [...argv];
  const cmd = args.shift();
  if (!cmd || cmd === "-h" || cmd === "--help") {
    const src = fs.readFileSync(fileURLToPath(import.meta.url), "utf8");
    console.log(src.split("\n").filter(l => l.startsWith("//")).map(l => l.slice(3)).join("\n"));
    return;
  }

  let obs;
  try { obs = await connect(); } catch (e) { die(e.message); }
  try {
    switch (cmd) {
      case "status": {
        const v   = await obs.call("GetVersion");
        const col = await obs.call("GetSceneCollectionList");
        const rec = await obs.call("GetRecordStatus");
        const str = await obs.call("GetStreamStatus");
        let rep = "unavailable (enable it in Settings > Output)";
        try { rep = onOff((await obs.call("GetReplayBufferStatus")).outputActive); } catch {}
        const vid = await obs.call("GetVideoSettings");
        console.log(`OBS ${v.obsVersion}, websocket ${v.obsWebSocketVersion}`);
        console.log(`collection: ${col.currentSceneCollectionName}`);
        console.log(`scene:      ${await currentScene(obs)}`);
        console.log(`canvas:     ${vid.baseWidth}x${vid.baseHeight} -> ${vid.outputWidth}x${vid.outputHeight} @ ${(vid.fpsNumerator / vid.fpsDenominator).toFixed(0)}fps`);
        console.log(`recording:  ${onOff(rec.outputActive)}${rec.outputActive ? ` ${rec.outputTimecode}` : ""}`);
        console.log(`streaming:  ${onOff(str.outputActive)}${str.outputActive ? ` ${str.outputTimecode}` : ""}`);
        console.log(`replay:     ${rep}`);
        break;
      }
      case "scenes": {
        const r = await obs.call("GetSceneList");
        for (const s of [...r.scenes].reverse())
          console.log(`${s.sceneName === r.currentProgramSceneName ? "*" : " "} ${s.sceneName}`);
        break;
      }
      case "scene": {
        const name = args.join(" ");
        if (!name) die("usage: scene <name>");
        await obs.call("SetCurrentProgramScene", { sceneName: name });
        console.log(`scene -> ${name}`);
        break;
      }
      case "sources": {
        const sceneName = args.join(" ") || await currentScene(obs);
        const r = await obs.call("GetSceneItemList", { sceneName });
        console.log(`${sceneName}:`);
        for (const i of [...r.sceneItems].reverse())
          console.log(`  ${i.sceneItemEnabled ? "on " : "off"} ${i.sourceName}  [${i.inputKind || (i.isGroup ? "group" : "scene")}]`);
        break;
      }
      case "collections": {
        const r = await obs.call("GetSceneCollectionList");
        for (const c of r.sceneCollections)
          console.log(`${c === r.currentSceneCollectionName ? "*" : " "} ${c}`);
        break;
      }
      case "collection": {
        const name = args.join(" ");
        if (!name) die("usage: collection <name>");
        await obs.call("SetCurrentSceneCollection", { sceneCollectionName: name });
        console.log(`collection -> ${name}`);
        break;
      }
      case "shot": {
        const source = opt(args, "--source"), width = opt(args, "--width");
        const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
        await saveShot(obs, args[0] || path.join(SHOTS_DIR, `obs-${stamp}.png`), source, width);
        break;
      }
      case "capture": {
        const source = opt(args, "--source"), width = opt(args, "--width");
        const slug = args[0];
        if (!slug) die("usage: capture <slug> [--source X]");
        await saveShot(obs, path.join(SHOTS_DIR, `screenshot-${slug}.png`), source, width);
        break;
      }
      case "record": {
        const sub = args[0] || "status";
        const req = { start: "StartRecord", stop: "StopRecord", toggle: "ToggleRecord",
                      pause: "PauseRecord", resume: "ResumeRecord", status: "GetRecordStatus" }[sub];
        if (!req) die("usage: record start|stop|toggle|pause|resume|status");
        const r = await obs.call(req);
        if (sub === "status") console.log(`recording ${onOff(r.outputActive)}${r.outputPaused ? " (paused)" : ""} ${r.outputTimecode || ""}`);
        else if (r.outputPath) console.log(`saved ${r.outputPath}`);
        else console.log(`record ${sub}`);
        break;
      }
      case "replay": {
        const sub = args[0] || "status";
        if (sub === "save") {
          await obs.call("SaveReplayBuffer");
          await new Promise(r => setTimeout(r, 1500));   // the file lands a moment after the request
          console.log(`saved ${(await obs.call("GetLastReplayBufferReplay")).savedReplayPath}`);
          break;
        }
        const req = { start: "StartReplayBuffer", stop: "StopReplayBuffer", status: "GetReplayBufferStatus" }[sub];
        if (!req) die("usage: replay start|stop|save|status");
        const r = await obs.call(req);
        console.log(sub === "status" ? `replay buffer ${onOff(r.outputActive)}` : `replay ${sub}`);
        break;
      }
      case "stream": {
        const sub = args[0] || "status";
        if (sub === "start" && !args.includes("--yes")) die("stream start goes live; pass --yes to confirm");
        const req = { start: "StartStream", stop: "StopStream", status: "GetStreamStatus" }[sub];
        if (!req) die("usage: stream start --yes|stop|status");
        const r = await obs.call(req);
        console.log(sub === "status" ? `streaming ${onOff(r.outputActive)} ${r.outputTimecode || ""}` : `stream ${sub}`);
        break;
      }
      case "call": {
        const type = args[0];
        if (!type) die("usage: call <RequestType> [json]");
        console.log(JSON.stringify(await obs.call(type, args[1] ? JSON.parse(args[1]) : {}), null, 2));
        break;
      }
      default:
        die(`unknown command: ${cmd} (try --help)`);
    }
  } catch (e) {
    die(e.message);
  } finally {
    obs.close();
  }
}

if (path.resolve(process.argv[1] || "") === fileURLToPath(import.meta.url)) await run(process.argv.slice(2));
