#!/usr/bin/env node
// Wick's Mods site: one page per addon, an index of them, the sitemap and
// robots.txt, generated from wick.json, the card copy on the landing
// pages, each addon's CHANGELOG.md and the images the site already holds.
//
//   node tools/site-pages.mjs            write everything
//   node tools/site-pages.mjs --check    report what would change, write nothing
//
// Run after a release so the latest changes and version follow it.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SUITE = path.resolve(HERE, "..");
const SITE = path.resolve(SUITE, "..", "Wicksmods.github.io");
const ORIGIN = "https://wicksmods.com";
const CHECK = process.argv.includes("--check");

const config = JSON.parse(fs.readFileSync(path.join(SUITE, "wick.json"), "utf8"));

// Where each addon's art lives under the site's images/.
const IMAGE_DIR = {
  "wicks-tbc-bis-tracker": "bis", "wicks-cd-tracker": "cd", "trade-hall": "trade",
  "wicks-macro-builder": "macro", "wicks-combat-log": "combat", "wicks-stats": "stats",
  "wicks-quest-key": "questkey", "wicks-totems-and-things": "totems", "wicks-bags": "bags",
  "wicks-travel-form": "travel", "wicks-ledger": "ledger", "wicks-wardrobe": "wardrobe",
  "wicks-survivors": "survivors", "wickcore": "core", "wicks-comforts": "comforts",
  "wicks-beasts-and-things": "beasts", "wicks-stances-and-things": "stances",
  "wicks-seals-and-things": "seals", "wicks-poisons-and-things": "poisons",
  "wicks-demons-and-things": "demons", "wicks-gear": "gear", "wicks-reminders": "reminders",
  "wicks-ui": "ui",
};

// Pages the site already has by hand; these take the place of a generated one.
const HAND_PAGES = { "wicks-ui": "/ui/" };

const CLIENT_LABEL = {
  forever: "World of Warcraft: Forever",
  tbc: "TBC Classic Anniversary",
  both: "World of Warcraft: Forever and TBC Classic",
};
const CLIENT_SHORT = { forever: "WoW Forever", tbc: "TBC Classic", both: "WoW Forever and TBC Classic" };

// ── helpers ─────────────────────────────────────────────────────────────
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const read = (p) => (fs.existsSync(p) ? fs.readFileSync(p, "utf8") : null);
// "A live combat log viewer" reads as "a live..." mid-title; a word that is
// itself capitalized, like TBC or a name, is left alone.
const lowerFirst = (s) => (/^[A-Z](?:[a-z]|\s)/.test(s) && !/^(Wick|TBC|WoW)/.test(s) ? s.charAt(0).toLowerCase() + s.slice(1) : s);
const noPeriod = (s) => s.replace(/[.\s]+$/, "");
// House style on anything rendered: no dashes as punctuation, US spelling.
const tidy = (s) => String(s)
  .replace(/\s*[—–]\s*|\s+--\s+/g, ", ")
  .replace(/\s+\/\s+/g, " and ")
  .replace(/levelling/g, "leveling")
  .replace(/, ,/g, ",");
const today = new Date().toISOString().slice(0, 10);

function status() {
  const j = read(path.join(SITE, "data", "addons-status.json"));
  return j ? JSON.parse(j).status || {} : {};
}

// The taglines written for the cards on the landing pages, by CurseForge slug.
function cardCopy(file) {
  const html = read(path.join(SITE, file)) || "";
  const out = {};
  const re = /card-tagline">([\s\S]*?)<\/div>[\s\S]*?wow\/addons\/([^"/?#]+)/g;
  let m;
  while ((m = re.exec(html))) out[m[2]] = m[1].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
  return out;
}

// One record per CurseForge project, whichever clients it ships for.
function roster() {
  const live = status();
  const byCf = new Map();
  for (const a of config.addons) {
    if (a.benched || !a.cf_project_id || !a.cf_slug) continue;
    // A project CurseForge has not approved yet gets no page. One that has a
    // page already keeps it: the status check flips on a blocked request now
    // and then, and a page should not come and go with it.
    const hasPage = HAND_PAGES[a.cf_slug] || fs.existsSync(path.join(SITE, "addons", a.cf_slug, "index.html"));
    if (live[a.cf_slug] && live[a.cf_slug] !== "live" && !hasPage) continue;
    const r = byCf.get(a.cf_slug) || { slug: a.cf_slug, entries: [], clients: new Set() };
    r.entries.push(a);
    const c = a.client || "tbc";
    if (c === "both") { r.clients.add("forever"); r.clients.add("tbc"); } else r.clients.add(c);
    byCf.set(a.cf_slug, r);
  }
  const forever = cardCopy("index.html"), tbc = cardCopy("tbc/index.html");
  const list = [];
  for (const r of byCf.values()) {
    const a = r.entries.find((e) => e.client === "forever" || e.client === "both") || r.entries[0];
    const client = r.clients.size === 2 ? "both" : [...r.clients][0];
    list.push({
      slug: r.slug, title: a.title, short: a.short, folder: a.folder, repo: a.repo, slash: a.slash,
      cfId: a.cf_project_id, client,
      lede: forever[r.slug] || tbc[r.slug] || a.tagline,
      short_tagline: a.short_tagline || a.tagline,
      features: [...new Set(r.entries.flatMap((e) => e.features || []))],
      url: HAND_PAGES[r.slug] || `/addons/${r.slug}/`,
      generated: !HAND_PAGES[r.slug],
    });
  }
  list.sort((x, y) => x.title.localeCompare(y.title));
  return list;
}

// ── the addon folder: changelog and version ────────────────────────────
function addonDir(a) {
  const roots = a.client === "tbc" ? ["tbc"] : ["forever", "tbc"];
  for (const c of roots) {
    const d = path.join(config.clients[c].addons_root, a.folder);
    if (fs.existsSync(path.join(d, "CHANGELOG.md"))) return d;
  }
  return null;
}

function tocVersion(dir, folder) {
  const toc = read(path.join(dir, folder + ".toc")) || "";
  const m = toc.match(/^## Version:\s*(\S+)/m);
  return m ? m[1] : null;
}

function inline(s) {
  return esc(tidy(s)).replace(/`([^`]+)`/g, "<code>$1</code>");
}

// A changelog section's body: ### headings, bullets, paragraphs.
function renderBody(lines) {
  const out = [];
  let para = [], list = [];
  const flushPara = () => { if (para.length) { out.push(`<p>${inline(para.join(" "))}</p>`); para = []; } };
  const flushList = () => { if (list.length) { out.push(`<ul>${list.map((l) => `<li>${inline(l)}</li>`).join("")}</ul>`); list = []; } };
  for (const raw of lines) {
    const line = raw.replace(/\s+$/, "");
    if (/^###\s+/.test(line)) { flushPara(); flushList(); out.push(`<h4>${inline(line.replace(/^###\s+/, ""))}</h4>`); continue; }
    if (/^\s*[-*]\s+/.test(line)) { flushPara(); list.push(line.replace(/^\s*[-*]\s+/, "")); continue; }
    if (/^\s{2,}\S/.test(line) && list.length) { list[list.length - 1] += " " + line.trim(); continue; }
    if (!line.trim()) { flushPara(); flushList(); continue; }
    flushList(); para.push(line.trim());
  }
  flushPara(); flushList();
  return out.join("\n");
}

function changelog(dir, count = 3) {
  const md = read(path.join(dir, "CHANGELOG.md"));
  if (!md) return [];
  const sections = md.split(/\r?\n(?=## )/);
  const out = [];
  for (const s of sections) {
    const m = s.match(/^## \[?v?(\d+\.\d+\.\d+)\]?([^\n]*)\n([\s\S]*)$/);
    if (!m) continue;
    const date = (m[2].match(/\d{4}-\d{2}-\d{2}/) || [null])[0];
    out.push({ version: m[1], date, html: renderBody(m[3].split(/\r?\n/)) });
    if (out.length >= count) break;
  }
  return out;
}

// ── images ──────────────────────────────────────────────────────────────
function images(a) {
  const dir = IMAGE_DIR[a.slug];
  if (!dir) return { thumb: null, thumb2x: null, shots: [] };
  const base = path.join(SITE, "images", dir);
  // A thumb the site lacks is taken from the addon's own repo images.
  if (!fs.existsSync(path.join(base, "thumb.png"))) {
    const src = addonDir(a);
    const imgs = src && fs.existsSync(path.join(src, "images")) ? fs.readdirSync(path.join(src, "images")) : [];
    const one = imgs.find((f) => /^wick-thumb-[a-z-]+\.png$/.test(f) && !/-2x\.png$/.test(f));
    if (one) {
      if (!CHECK) {
        fs.mkdirSync(base, { recursive: true });
        fs.copyFileSync(path.join(src, "images", one), path.join(base, "thumb.png"));
        const two = imgs.find((f) => f === one.replace(/\.png$/, "-2x.png"));
        if (two) fs.copyFileSync(path.join(src, "images", two), path.join(base, "thumb-2x.png"));
      }
      console.log(`  images/${dir}/thumb.png taken from ${a.folder}/images/${one}`);
    }
  }
  const has = (f) => fs.existsSync(path.join(base, f));
  const shotsDir = path.join(base, "screenshots");
  const shots = fs.existsSync(shotsDir)
    ? fs.readdirSync(shotsDir).filter((f) => /\.(png|jpg|jpeg|webp)$/i.test(f)).sort()
    : [];
  return {
    thumb: has("thumb.png") ? `/images/${dir}/thumb.png` : null,
    thumb2x: has("thumb-2x.png") ? `/images/${dir}/thumb-2x.png` : null,
    shots: shots.map((f) => `/images/${dir}/screenshots/${encodeURIComponent(f)}`),
  };
}

// ── the page ────────────────────────────────────────────────────────────
const CSS = `
  :root { --fel:#4FC778; --void:#0D0A14; --shadow:#171124; --border:#383058; --text:#D4C8A1; --text-dim:#8F8870; }
  * { box-sizing:border-box; margin:0; padding:0; }
  html, body { background:var(--void); color:var(--text); }
  body { font-family:'Space Grotesk', sans-serif; font-size:16px; line-height:1.6; min-height:100vh; }
  a { color:var(--fel); text-decoration:none; } a:hover { color:var(--text); }
  code { font-family:'Space Mono', monospace; font-size:0.9em; color:var(--text); background:var(--shadow); padding:0 4px; }
  .container { max-width:1000px; margin:0 auto; padding:0 24px; }
  .top { border-bottom:1px solid var(--border); background:var(--shadow); }
  .top .container { display:flex; align-items:center; justify-content:space-between; height:56px; gap:16px; flex-wrap:wrap; }
  .brand { font-family:'Cinzel', serif; font-weight:700; letter-spacing:0.08em; color:var(--text); font-size:18px; }
  .brand .apo { color:var(--fel); }
  .nav a { margin-left:18px; font-size:14px; color:var(--text-dim); } .nav a:hover { color:var(--fel); }
  .hero { padding:56px 0 36px; border-bottom:1px solid var(--border); }
  .eyebrow { font-family:'Space Mono', monospace; font-size:12px; letter-spacing:0.28em; text-transform:uppercase; color:var(--fel); margin-bottom:14px; }
  h1 { font-family:'Cinzel', serif; font-weight:700; font-size:40px; line-height:1.15; color:var(--text); margin-bottom:14px; }
  h1 .apo { color:var(--fel); }
  .lede { font-size:19px; color:var(--text); max-width:760px; margin-bottom:22px; }
  .meta { font-family:'Space Mono', monospace; font-size:13px; color:var(--text-dim); margin-bottom:22px; }
  .meta span + span::before { content:'\\00a0\\00b7\\00a0'; color:var(--border); }
  .actions { display:flex; gap:12px; flex-wrap:wrap; }
  .btn { display:inline-block; padding:10px 18px; border:1px solid var(--border); color:var(--text); font-weight:500; font-size:15px; }
  .btn.primary { border-color:var(--fel); color:var(--fel); }
  .btn:hover { border-color:var(--fel); color:var(--fel); }
  .panel { position:relative; border:1px solid var(--border); background:var(--shadow); padding:22px; }
  .panel::before, .panel::after { content:''; position:absolute; width:10px; height:10px; border-color:var(--fel); border-style:solid; }
  .panel::before { top:-1px; left:-1px; border-width:2px 0 0 2px; }
  .panel::after { bottom:-1px; right:-1px; border-width:0 2px 2px 0; }
  .grid { display:grid; grid-template-columns:1fr 1fr; gap:28px; align-items:start; margin:36px 0; }
  .thumb img { display:block; width:100%; height:auto; border:1px solid var(--border); }
  h2 { font-family:'Cinzel', serif; font-weight:700; font-size:22px; color:var(--text); margin:36px 0 14px; }
  h3 { font-size:17px; font-weight:600; color:var(--text); margin:22px 0 6px; }
  h4 { font-family:'Space Mono', monospace; font-size:12px; letter-spacing:0.2em; text-transform:uppercase; color:var(--fel); margin:16px 0 6px; }
  ul { padding-left:20px; } li { margin:4px 0; } p { margin:8px 0; }
  .features li { margin:6px 0; }
  .shots { display:grid; grid-template-columns:repeat(auto-fill, minmax(300px, 1fr)); gap:16px; }
  .shots img { display:block; width:100%; height:auto; border:1px solid var(--border); }
  .log .ver { font-family:'Space Mono', monospace; color:var(--text-dim); font-size:13px; }
  .suite { display:grid; grid-template-columns:repeat(auto-fill, minmax(220px, 1fr)); gap:10px 24px; }
  .suite a { font-size:15px; }
  footer { border-top:1px solid var(--border); margin-top:56px; padding:28px 0 40px; color:var(--text-dim); font-size:14px; }
  footer a { color:var(--text-dim); } footer a:hover { color:var(--fel); }
  @media (max-width:760px) { .grid { grid-template-columns:1fr; } h1 { font-size:32px; } .top .container { height:auto; padding:10px 24px; } }
`;

const HEAD_FONTS = `<link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@400;700;900&family=Space+Grotesk:wght@300;400;500;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">`;

function nav() {
  return `<div class="top"><div class="container">
  <a class="brand" href="/">WICK<span class="apo">'</span>S MODS</a>
  <nav class="nav"><a href="/">Forever</a><a href="/tbc/">TBC Classic</a><a href="/ui/">Wick's UI</a><a href="/addons/">All addons</a><a href="https://discord.gg/GWGTMhYBZY">Discord</a></nav>
</div></div>`;
}

function footer() {
  return `<footer><div class="container">
  <a href="https://discord.gg/GWGTMhYBZY">Discord</a> &middot;
  <a href="https://www.facebook.com/profile.php?id=61588703194645">Facebook</a> &middot;
  <a href="https://x.com/wicksmods">X</a> &middot;
  <a href="https://github.com/Wicks-mods">Wick's Mods on GitHub</a> &middot;
  <a href="https://www.curseforge.com/members/wicksmods/projects">Wick on CurseForge</a> &middot;
  <a href="/privacy/">Privacy</a>
</div></footer>`;
}

function titleHtml(title) {
  // "Wick's Bags" with the apostrophe in the accent, as the cards do.
  return esc(title).replace(/^Wick&#39;s|^Wick's/, `Wick<span class="apo">'</span>s`);
}

function page(a, all) {
  const dir = addonDir(a);
  const version = dir ? tocVersion(dir, a.folder) : null;
  const log = dir ? changelog(dir) : [];
  const img = images(a);
  const cf = `https://www.curseforge.com/wow/addons/${a.slug}`;
  const gh = `https://github.com/${config.github_user}/${a.repo}`;
  const url = ORIGIN + a.url;
  // "Wick's Bags: bags and bank in one window, for WoW Forever". A tagline
  // with a colon of its own is cut at it, so the title never has two.
  const what = lowerFirst(noPeriod(tidy(a.short_tagline)).split(":")[0].trim());
  const titleTag = `${a.title}: ${what}, for ${CLIENT_SHORT[a.client]}`;
  let descFull = noPeriod(tidy(a.lede)) + ".";
  if (descFull.length < 80 && a.features.length) {
    descFull += " " + a.features.slice(0, 3).map((f) => noPeriod(tidy(f))).join(". ") + ".";
  }
  const description = descFull.length > 155 ? descFull.slice(0, 152).replace(/[,\s]+\S*$/, "") + "..." : descFull;
  const ogImage = img.thumb2x || img.thumb ? ORIGIN + (img.thumb2x || img.thumb) : `${ORIGIN}/images/suite/site-card-2x.jpg`;
  const latest = log[0];

  const ld = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: a.title,
    url,
    description: noPeriod(tidy(a.lede)) + ".",
    applicationCategory: "GameApplication",
    applicationSubCategory: "World of Warcraft addon",
    operatingSystem: "Windows, macOS",
    ...(version ? { softwareVersion: version } : {}),
    ...(latest && latest.date ? { dateModified: latest.date } : {}),
    downloadUrl: cf,
    installUrl: cf,
    image: ogImage,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    author: { "@type": "Organization", name: "Wick's Mods", url: ORIGIN },
    isPartOf: { "@type": "SoftwareApplication", name: "Wick's Mods suite", url: ORIGIN },
    sameAs: [cf, gh],
  };
  const crumbs = {
    "@context": "https://schema.org", "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Wick's Mods", item: ORIGIN + "/" },
      { "@type": "ListItem", position: 2, name: "All addons", item: ORIGIN + "/addons/" },
      { "@type": "ListItem", position: 3, name: a.title, item: url },
    ],
  };

  const others = all.filter((o) => o.slug !== a.slug && o.slug !== "wickcore");
  const shots = img.shots.map((s) => `<img src="${s}" alt="${esc(a.title)} in game" loading="lazy">`).join("\n");
  const logHtml = log.map((l) => `<h3>${esc(l.version)} <span class="ver">${l.date ? esc(l.date) : ""}</span></h3>\n${l.html}`).join("\n");

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(titleTag)}</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${url}">
<link rel="icon" type="image/png" sizes="256x256" href="/images/favicon.png">
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(titleTag)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${ogImage}">
<meta property="og:url" content="${url}">
<meta property="og:site_name" content="Wick's Mods">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:site" content="@wicksmods">
<meta name="twitter:title" content="${esc(titleTag)}">
<meta name="twitter:description" content="${esc(description)}">
<meta name="twitter:image" content="${ogImage}">
<meta name="theme-color" content="#0D0A14">
${HEAD_FONTS}
<style>${CSS}</style>
<script type="application/ld+json">${JSON.stringify(ld)}</script>
<script type="application/ld+json">${JSON.stringify(crumbs)}</script>
</head>
<body>
${nav()}
<section class="hero"><div class="container">
  <div class="eyebrow">${esc(CLIENT_LABEL[a.client])}</div>
  <h1>${titleHtml(a.title)}</h1>
  <p class="lede">${esc(tidy(a.lede))}</p>
  <div class="meta">${version ? `<span>version ${esc(version)}</span>` : ""}${a.slash ? `<span>${esc(a.slash)}</span>` : ""}<span>free, open source</span></div>
  <div class="actions">
    <a href="${cf}" class="btn primary">Get it on CurseForge &rarr;</a>
    <a href="${gh}" class="btn">Source on GitHub</a>
    <a href="https://discord.gg/GWGTMhYBZY" class="btn">Discord</a>
  </div>
</div></section>
<main class="container">
  <div class="grid">
    <div class="panel">
      <h2 style="margin-top:0">What it does</h2>
      <ul class="features">${a.features.map((f) => `<li>${esc(tidy(f))}</li>`).join("")}</ul>
      ${a.slug === "wickcore" ? "" : `<p style="margin-top:14px;color:var(--text-dim)">Needs <a href="/addons/wickcore/">WickCore</a>, the shared base every Wick addon draws from. CurseForge installs it alongside.</p>`}
    </div>
    ${img.thumb ? `<div class="thumb"><img src="${img.thumb2x || img.thumb}" alt="${esc(a.title)} card" width="920" height="520"></div>` : ""}
  </div>
  ${shots ? `<h2>In game</h2><div class="shots">${shots}</div>` : ""}
  ${logHtml ? `<h2>Latest changes</h2><div class="log">${logHtml}</div><p style="color:var(--text-dim)">The full changelog is in <a href="${gh}/blob/main/CHANGELOG.md">the repository</a>.</p>` : ""}
  <h2>More from the suite</h2>
  <div class="suite">${others.map((o) => `<a href="${o.url}">${esc(o.title)}</a>`).join("")}</div>
</main>
${footer()}
</body>
</html>
`;
}

function indexPage(all) {
  const url = ORIGIN + "/addons/";
  const titleTag = "Every Wick's Mods addon for World of Warcraft: Forever and TBC Classic";
  const description = "Every addon in the Wick's Mods suite, for World of Warcraft: Forever and TBC Classic Anniversary. Free and open source, all on one shared core.";
  const group = (c) => all.filter((a) => a.client === c || a.client === "both");
  const list = (items) => `<div class="suite">${items.map((a) => `<div><a href="${a.url}"><strong>${esc(a.title)}</strong></a><br><span style="color:var(--text-dim);font-size:14px">${esc(noPeriod(tidy(a.short_tagline)))}.</span></div>`).join("")}</div>`;
  const ld = {
    "@context": "https://schema.org", "@type": "ItemList", name: "Wick's Mods addons", url,
    itemListElement: all.map((a, i) => ({ "@type": "ListItem", position: i + 1, name: a.title, url: ORIGIN + a.url })),
  };
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(titleTag)}</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${url}">
<link rel="icon" type="image/png" sizes="256x256" href="/images/favicon.png">
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(titleTag)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${ORIGIN}/images/suite/site-card-2x.jpg">
<meta property="og:url" content="${url}">
<meta property="og:site_name" content="Wick's Mods">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:site" content="@wicksmods">
<meta name="twitter:title" content="${esc(titleTag)}">
<meta name="twitter:description" content="${esc(description)}">
<meta name="twitter:image" content="${ORIGIN}/images/suite/site-card-2x.jpg">
<meta name="theme-color" content="#0D0A14">
${HEAD_FONTS}
<style>${CSS}</style>
<script type="application/ld+json">${JSON.stringify(ld)}</script>
</head>
<body>
${nav()}
<section class="hero"><div class="container">
  <div class="eyebrow">The suite</div>
  <h1>Every Wick<span class="apo">'</span>s Mods addon</h1>
  <p class="lede">Each one free and open source, each one drawn in the same look, all on one shared core. Pick the client you play.</p>
</div></section>
<main class="container">
  <h2>For World of Warcraft: Forever</h2>
  ${list(group("forever"))}
  <h2>For TBC Classic Anniversary</h2>
  ${list(group("tbc"))}
</main>
${footer()}
</body>
</html>
`;
}

function sitemap(all) {
  const gitDate = (rel) => {
    try {
      const { execSync } = require_("node:child_process");
      return execSync(`git log -1 --format=%cs -- "${rel}"`, { cwd: SITE }).toString().trim() || today;
    } catch { return today; }
  };
  const urls = [
    { loc: "/", lastmod: gitDate("index.html"), priority: "1.0" },
    { loc: "/tbc/", lastmod: gitDate("tbc/index.html"), priority: "0.9" },
    { loc: "/ui/", lastmod: gitDate("ui/index.html"), priority: "0.9" },
    { loc: "/addons/", lastmod: today, priority: "0.8" },
    ...all.filter((a) => a.generated).map((a) => {
      const dir = addonDir(a);
      const latest = dir ? changelog(dir, 1)[0] : null;
      return { loc: a.url, lastmod: latest && latest.date ? latest.date : today, priority: "0.7" };
    }),
    { loc: "/privacy/", lastmod: gitDate("privacy/index.html"), priority: "0.2" },
  ];
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((u) => `  <url><loc>${ORIGIN}${u.loc}</loc><lastmod>${u.lastmod}</lastmod><priority>${u.priority}</priority></url>`).join("\n")}
</urlset>
`;
}

import { createRequire } from "node:module";
const require_ = createRequire(import.meta.url);

const ROBOTS = `User-agent: *
Allow: /

Sitemap: ${ORIGIN}/sitemap.xml
`;

// ── write ───────────────────────────────────────────────────────────────
function put(rel, content) {
  const p = path.join(SITE, rel);
  // A checkout on Windows may hold the file with CRLF line endings; git
  // normalizes them, so only the content counts.
  const before = read(p);
  const changed = (before === null ? null : before.replace(/\r\n/g, "\n")) !== content;
  if (changed && !CHECK) {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  }
  console.log(`${changed ? (before === null ? "new    " : "changed") : "same   "} ${rel}`);
}

const all = roster();
for (const a of all) {
  if (!a.generated) continue;
  if (!addonDir(a)) console.log(`  (no CHANGELOG.md found for ${a.folder}; the page carries no version or changes)`);
  put(`addons/${a.slug}/index.html`, page(a, all));
}
put("addons/index.html", indexPage(all));
put("sitemap.xml", sitemap(all));
put("robots.txt", ROBOTS);
console.log(`${all.length} addons, ${all.filter((a) => a.generated).length} pages generated${CHECK ? " (check only)" : ""}`);
