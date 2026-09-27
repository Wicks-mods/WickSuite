#!/usr/bin/env node
// Wick — single CLI for the Wick addon suite pipeline.
//
// Subcommands:
//   wick list                      — print the addon roster from wick.json
//   wick scaffold <Display Name>   — create a new addon (folder, files, git, github)
//   wick sync                      — regenerate cross-links in all README.md from wick.json
//   wick render                    — run grab-artboards.mjs (thumbnails + banner)
//   wick release <folder> <ver>    — version bump + CHANGELOG + commit + push + zip + CF upload
//
// Usage (bash / PowerShell):
//   node "C:/Users/jspli/Projects/Wick/WickSuite/tools/wick.mjs" <subcommand> [args]
//
// Requires:
//   - Node 18+
//   - gh CLI authenticated (for scaffold's repo creation)
//   - CURSEFORGE_API_TOKEN env var (for release's CF upload)
//   - FB_WICKS_MODS_PAGE_TOKEN env var (optional; for the post-release FB announce).
//     Falls back to deriving from the user token in C:\Users\jspli\OneDrive\Documents\Wicksmodsinfo.txt.
//   - DISCORD_BOT_TOKEN env var (optional; for the post-release Discord announce).
//     Falls back to reading from the Discord section of Wicksmodsinfo.txt.
//     Pass --no-announce to wick release to skip both social posts.

import { execSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

// ── paths ─────────────────────────────────────────────────────────────────
const __filename = fileURLToPath(import.meta.url);
const TOOLS_DIR  = path.dirname(__filename);
const SUITE_DIR  = path.dirname(TOOLS_DIR);                // .../Projects/Wick/WickSuite
const PROJECT    = path.dirname(SUITE_DIR);                // .../Projects/Wick
const CONFIG     = path.join(SUITE_DIR, "wick.json");
const TEMPLATE   = path.join(SUITE_DIR, "templates/new-addon");
const GRAB_TOOL  = "C:/Users/jspli/.claude/tools/igrab/grab-artboards.mjs";
const GH         = "C:/Program Files/GitHub CLI/gh.exe";

// ── helpers ───────────────────────────────────────────────────────────────
const log  = (...a) => console.log(...a);
const die  = (msg) => { clearProgress(); console.error("✗", msg); process.exit(1); };
const ok   = (msg) => console.log("✓", msg);

// ── Wick progress indicator (status line) ─────────────────────────────────
// Writes ~/.claude/wick-progress.json so the custom status line at
// ~/.claude/wick-statusline.mjs can render a unicode progress bar above the
// chat input while a wick command is running. See memory/reference_wick_progress_indicator.md.
const PROGRESS_FILE = path.join(
  process.env.USERPROFILE || process.env.HOME || "C:/Users/jspli",
  ".claude/wick-progress.json"
);
function setProgress(command, phase, total, label) {
  try {
    fs.writeFileSync(
      PROGRESS_FILE,
      JSON.stringify({ command, phase, total, label }) + "\n"
    );
  } catch (_) { /* status line is cosmetic; never fail the run for it */ }
}
function clearProgress() {
  try { fs.rmSync(PROGRESS_FILE); } catch (_) { /* idempotent */ }
}
process.on("exit",       clearProgress);
process.on("SIGINT",     () => { clearProgress(); process.exit(130); });
process.on("uncaughtException", (e) => { clearProgress(); console.error(e); process.exit(1); });

function readConfig() {
  return JSON.parse(fs.readFileSync(CONFIG, "utf8"));
}
function writeConfig(c) {
  fs.writeFileSync(CONFIG, JSON.stringify(c, null, 2) + "\n");
}
function run(cmd, opts = {}) {
  return execSync(cmd, { stdio: "inherit", shell: true, ...opts });
}
function runCapture(cmd, opts = {}) {
  return execSync(cmd, { encoding: "utf8", shell: true, ...opts }).trim();
}
function gitIn(dir, ...args) {
  const r = spawnSync("git", args, { cwd: dir, stdio: "inherit" });
  if (r.status !== 0) {
    die(`git ${args.join(" ")} failed (exit ${r.status}) in ${dir}`);
  }
  return r;
}

// Substitute {{TOKEN}} placeholders in a string.
function tmpl(s, vars) {
  return s.replace(/\{\{([A-Z_]+)\}\}/g, (_, k) => (vars[k] != null ? String(vars[k]) : `{{${k}}}`));
}

function slugify(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

// Derive folder from display title: "Wick's Aggro Meter" → "WicksAggroMeter"
function deriveFolder(title) {
  return title.replace(/['']/g, "").replace(/\s+/g, "");
}

// Derive slash: "Wick's Aggro Meter" → "/wam"
function deriveSlash(title) {
  const caps = title.replace(/['']/g, "").split(/\s+/)
    .map(w => w.replace(/^Wick/, "").charAt(0).toLowerCase())
    .filter(Boolean).join("");
  // Prefix with "w" for Wick
  return "/w" + caps;
}

// ── FB announce helpers ───────────────────────────────────────────────────

// Resolve a Page Access Token for the configured FB page.
// Order of resolution:
//   1. FB_WICKS_MODS_PAGE_TOKEN env var (if set, use directly)
//   2. fb_page_token from Wicksmodsinfo.txt (the canonical secrets file) — this is
//      already a Page token, so it posts directly with no Graph round-trip
//   3. fb_user_token from Wicksmodsinfo.txt, exchanged via /me/accounts for the
//      Page token matching social.fb_page_id
//   4. Legacy: an EA-prefixed user token under an `FB` header in keys.txt
// Returns null if no path works (caller logs and continues).
//
// Note: this used to read keys.txt only, but keys.txt has no Facebook section at
// all — the FB credentials live in Wicksmodsinfo.txt, which is what the header
// comment on this file has always claimed. That mismatch made every release skip
// the FB announce with "no page token available".
function resolveFBPageToken(config) {
  const fromEnv = process.env.FB_WICKS_MODS_PAGE_TOKEN;
  if (fromEnv) return fromEnv;

  const v = config.social?.fb_graph_version || "v21.0";
  const pageId = config.social?.fb_page_id;

  const readFile = (p) => {
    try { return fs.existsSync(p) ? fs.readFileSync(p, "utf8").replace(/\r/g, "") : null; }
    catch (_) { return null; }
  };

  // Exchange a user token for the Page token of the configured page.
  const derivePageToken = (userToken) => {
    if (!userToken || !pageId) return null;
    let resp;
    try {
      resp = runCapture(
        `curl -s "https://graph.facebook.com/${v}/me/accounts?fields=id,access_token&access_token=${userToken}"`
      );
    } catch (_) { return null; }
    let parsed;
    try { parsed = JSON.parse(resp); } catch (_) { return null; }
    const page = (parsed.data || []).find(p => p.id === pageId);
    return page?.access_token || null;
  };

  // 2 + 3: canonical secrets file.
  const info = readFile("C:/Users/jspli/OneDrive/Documents/Wicksmodsinfo.txt");
  if (info) {
    const direct = info.match(/^\s*fb_page_token\s*=\s*(EA[A-Za-z0-9_-]{50,})/m);
    if (direct) return direct[1];
    const user = info.match(/^\s*fb_user_token\s*=\s*(EA[A-Za-z0-9_-]{50,})/m);
    if (user) {
      const derived = derivePageToken(user[1]);
      if (derived) return derived;
    }
  }

  // 4: legacy keys.txt FB block (kept so older setups keep working).
  const keys = readFile("C:/Users/jspli/OneDrive/Documents/keys.txt");
  if (keys) {
    const m = keys.match(/^FB[\s\S]*?(EA[A-Za-z0-9_-]{100,})/m);
    if (m) {
      const derived = derivePageToken(m[1]);
      if (derived) return derived;
    }
  }

  return null;
}

// Pull the body of a single CHANGELOG version section.
// Returns the lines between `## VERSION` and the next `## ` header, trimmed.
function extractChangelogEntry(changelogPath, version) {
  if (!fs.existsSync(changelogPath)) return "";
  const body = fs.readFileSync(changelogPath, "utf8").replace(/\r\n/g, "\n");
  const escVer = version.replace(/\./g, "\\.");
  // No `m` flag: anchor against `\n##` for boundaries and `$` for end-of-string.
  // (JS regex has no \A/\Z, and `m` flag turns `$` into end-of-line which would
  // make the lazy quantifier capture zero chars.)
  const re = new RegExp(`\\n##\\s+${escVer}\\b[^\\n]*\\n([\\s\\S]*?)(?=\\n##\\s|$)`);
  const m = body.match(re);
  if (!m) return "";
  // Strip the "(edit this entry...)" stub if it's all that's there.
  const text = m[1].trim();
  if (/^- \(edit this entry/i.test(text)) return "";
  return text;
}

// The picture to attach to a social post.
//
// A social card first: 1200x630, which is the size Facebook draws a feed
// image at and the ratio a boosted post wants. The thumbnail is 460x260
// and was being upscaled about 1.7 times, which is why posts looked
// soft. The thumbnail is still the fallback for an addon that has no
// card yet, since a soft picture beats no picture.
//
// -2x files stay out of attachments either way. That rule was about
// picking between two sizes of the same thumbnail; this is a third
// image with its own job.
function findAddonThumb(addonDir) {
  const imgDir = path.join(addonDir, "images");
  if (!fs.existsSync(imgDir)) return null;
  const files = fs.readdirSync(imgDir);
  const pick = (re) => {
    const m = files.filter(f => re.test(f) && !/-2x\.png$/i.test(f));
    return m.length ? path.join(imgDir, m[0]) : null;
  };
  return pick(/^wick-social-[a-z0-9-]+\.png$/i) || pick(/^wick-thumb-[a-z0-9-]+\.png$/i);
}

// FB doesn't render markdown, so strip the syntax that would otherwise show up
// as literal characters in the post: headers, link wrappers, code fences, etc.
function sanitizeMarkdownForFB(s) {
  return s
    // Drop H3+ headers entirely (the "### Initial release" line is just clutter
    // in a release post; the version is already in the lead-in).
    .replace(/^#{3,6}\s+.*$/gm, "")
    // [text](url) → text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    // `code` → code (drop the backticks, keep the text)
    .replace(/`([^`]+)`/g, "$1")
    // Bold/italic emphasis
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/(?<!\*)\*([^*\n]+)\*(?!\*)/g, "$1")
    // Collapse 3+ blank lines that the header strip might leave behind
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// Compose the FB post caption from addon metadata + changelog body.
function composeFBCaption(addon, version, changelogBody) {
  const cfUrl = `https://www.curseforge.com/wow/addons/${addon.cf_slug}`;
  const lines = [];
  lines.push(`${addon.title} v${version} is out now.`);
  lines.push("");
  if (addon.tagline) {
    lines.push(addon.tagline);
    lines.push("");
  }
  if (changelogBody) {
    const cleaned = sanitizeMarkdownForFB(changelogBody);
    if (cleaned) {
      lines.push("What's new:");
      // Headlines, for the same reason Discord gets them: a changelog
      // explains a decision and defends it, and a feed wants the line
      // that says what changed.
      lines.push(...headlines(cleaned, 8));
      lines.push("");
    }
  }
  lines.push(`Download on CurseForge: ${cfUrl}`);
  return lines.join("\n");
}

// Post a release announcement to the Wick's Mods FB page. Best-effort:
// any failure is logged and swallowed — the release itself already succeeded.
function announceFB(addon, version, addonDir, config) {
  const marker = path.join(addonDir, `.wick-fb-announced-v${version}`);
  if (fs.existsSync(marker)) {
    log(`  (FB: already announced v${version}, skipping — delete ${path.basename(marker)} to re-post)`);
    return;
  }

  const token = resolveFBPageToken(config);
  if (!token) {
    log(`  (FB: no page token available — set FB_WICKS_MODS_PAGE_TOKEN or fix keys.txt; skipping announce)`);
    return;
  }
  const pageId = config.social?.fb_page_id;
  const v = config.social?.fb_graph_version || "v21.0";
  if (!pageId) {
    log(`  (FB: wick.json missing social.fb_page_id; skipping announce)`);
    return;
  }

  const changelog = path.join(addonDir, "CHANGELOG.md");
  const body = extractChangelogEntry(changelog, version);
  const caption = composeFBCaption(addon, version, body);
  const captionPath = path.join(rootOf(config, addon), `.wick-fb-caption-${addon.folder}.txt`);
  fs.writeFileSync(captionPath, caption);

  const thumb = findAddonThumb(addonDir);
  const cfUrl = `https://www.curseforge.com/wow/addons/${addon.cf_slug}`;

  let cmd, target;
  if (thumb) {
    target = `/${pageId}/photos`;
    cmd = [
      `curl -s -X POST`,
      `-F "source=@${thumb}"`,
      `-F "caption=<${captionPath}"`,
      `-F "access_token=${token}"`,
      `"https://graph.facebook.com/${v}${target}"`,
    ].join(" ");
  } else {
    target = `/${pageId}/feed`;
    cmd = [
      `curl -s -X POST`,
      `-F "message=<${captionPath}"`,
      `-F "link=${cfUrl}"`,
      `-F "access_token=${token}"`,
      `"https://graph.facebook.com/${v}${target}"`,
    ].join(" ");
  }

  log(`\nPosting to Facebook (${config.social.fb_page_name})${thumb ? " with thumbnail" : ""} ...`);
  let resp;
  try { resp = runCapture(cmd); }
  catch (e) { log(`  (FB: curl failed: ${e.message})`); try { fs.rmSync(captionPath); } catch (_) {} return; }
  try { fs.rmSync(captionPath); } catch (_) {}

  let parsed = null;
  try { parsed = JSON.parse(resp); } catch (_) {}
  if (parsed && parsed.error) {
    const e = parsed.error;
    log(`  (FB: post failed: type=${e.type} code=${e.code} subcode=${e.error_subcode || "-"} msg=${e.message})`);
    if (e.error_user_msg) log(`       user_msg: ${e.error_user_msg}`);
    if (e.fbtrace_id)     log(`       fbtrace_id: ${e.fbtrace_id}`);
    return;
  }
  if (parsed && (parsed.id || parsed.post_id)) {
    fs.writeFileSync(marker, `${new Date().toISOString()}\n${JSON.stringify(parsed)}\n`);
    ok(`FB: posted to ${config.social.fb_page_name} (post id ${parsed.post_id || parsed.id})`);
    return;
  }
  log(`  (FB: unexpected response, raw: ${resp.slice(0, 600)})`);
}

// ── Discord announce helpers ──────────────────────────────────────────────

function resolveDiscordBotToken() {
  const fromEnv = process.env.DISCORD_BOT_TOKEN;
  if (fromEnv) return fromEnv;

  const keysPath = "C:/Users/jspli/OneDrive/Documents/Wicksmodsinfo.txt";
  if (!fs.existsSync(keysPath)) return null;
  const keys = fs.readFileSync(keysPath, "utf8").replace(/\r/g, "");
  // Discord bot tokens: base64url segment (24+ chars), dot, 6-char segment, dot, 27+ char segment.
  // Match the first such token that appears after a "Discord" section header.
  const m = keys.match(/Discord[\s\S]*?([A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,})/i);
  return m ? m[1] : null;
}

// Return the Discord #announcements channel ID. Checks wick.json first; if
// missing, fetches the guild channel list, caches the result, and returns it.
function resolveDiscordAnnouncementsChannel(config, token) {
  if (config.social?.discord_announcements_channel_id) {
    return config.social.discord_announcements_channel_id;
  }
  const guildId = config.social?.discord_guild_id;
  if (!guildId) return null;

  let resp;
  try {
    resp = runCapture(
      `curl -s -H "Authorization: Bot ${token}" "https://discord.com/api/v10/guilds/${guildId}/channels"`
    );
  } catch (_) { return null; }
  let channels;
  try { channels = JSON.parse(resp); } catch (_) { return null; }
  if (!Array.isArray(channels)) return null;
  const ch = channels.find(c => c.type === 0 && c.name === "announcements");
  if (!ch) return null;

  // Cache in wick.json so we don't call the channels list endpoint every time.
  config.social.discord_announcements_channel_id = ch.id;
  writeConfig(config);
  ok(`Discord: cached #announcements channel ID ${ch.id}`);
  return ch.id;
}

// A changelog bullet is written to explain a decision and defend it,
// which is right in a repository and wrong in a feed. The first
// sentence is the one that says what changed; the rest is the
// reasoning, and it stays where it belongs.
//
// Bullets only, since the prose between them is all reasoning. Headings
// go too: a feed post does not need Added and Changed.
function headlines(body, max) {
  const out = [];
  let current = null;
  const flush = () => {
    if (current === null) return;
    const one = current.replace(/\s+/g, " ").trim();
    // Up to the first full stop that ends a sentence rather than sitting
    // inside a version number or an abbreviation.
    const m = one.match(/^(.*?[.!?])(\s|$)/);
    const said = (m ? m[1] : one).trim();
    if (said) out.push("- " + said.replace(/^[-*]\s*/, ""));
    current = null;
  };
  for (const raw of body.split("\n")) {
    const line = raw.trimEnd();
    if (/^\s*[-*]\s+/.test(line)) {
      flush();
      current = line.replace(/^\s*[-*]\s+/, "");
    } else if (current !== null && /^\s+\S/.test(line)) {
      current += " " + line.trim();      // a wrapped bullet
    } else {
      flush();
    }
    if (out.length >= max) break;
  }
  flush();
  return out.slice(0, max);
}

function composeDiscordEmbed(addon, version, changelogBody) {
  const cfUrl = `https://www.curseforge.com/wow/addons/${addon.cf_slug}`;
  const descLines = [];
  if (addon.tagline) descLines.push(addon.tagline);
  if (changelogBody) {
    const cleaned = changelogBody.replace(/\n{3,}/g, "\n\n").trim();
    if (cleaned && !/^\(edit this entry/i.test(cleaned)) {
      descLines.push("");
      descLines.push("**What's new**");
      descLines.push(...headlines(cleaned, 10));
      descLines.push("");
      descLines.push(`[Full changelog](https://github.com/Wicksmods/${addon.repo || addon.folder}/blob/main/CHANGELOG.md)`);
    }
  }
  // Parse accent hex → decimal int for Discord's color field.
  const colorHex = (addon.accent || "#4FC778").replace(/^#/, "");
  const color = parseInt(colorHex, 16);
  return {
    title: `${addon.title} v${version} is out now`,
    description: descLines.join("\n") || undefined,
    color,
    url: cfUrl,
    footer: { text: "Wick's Mods · wicksmods.com" },
  };
}

// Post a release announcement to the Wick's Mods Discord #announcements channel.
// Best-effort: any failure is logged and swallowed.
function announceDiscord(addon, version, addonDir, config) {
  const marker = path.join(addonDir, `.wick-discord-announced-v${version}`);
  if (fs.existsSync(marker)) {
    log(`  (Discord: already announced v${version}, skipping — delete ${path.basename(marker)} to re-post)`);
    return;
  }

  const token = resolveDiscordBotToken();
  if (!token) {
    log(`  (Discord: no bot token — set DISCORD_BOT_TOKEN or check Wicksmodsinfo.txt; skipping)`);
    return;
  }
  const channelId = resolveDiscordAnnouncementsChannel(config, token);
  if (!channelId) {
    log(`  (Discord: could not resolve #announcements channel ID; skipping)`);
    return;
  }

  const changelog = path.join(addonDir, "CHANGELOG.md");
  const body = extractChangelogEntry(changelog, version);
  const embed = composeDiscordEmbed(addon, version, body);
  const payload = JSON.stringify({ embeds: [embed] });
  const payloadPath = path.join(rootOf(config, addon), `.wick-discord-payload-${addon.folder}.json`);
  fs.writeFileSync(payloadPath, payload);

  log(`\nPosting to Discord #announcements ...`);
  let resp;
  try {
    resp = runCapture([
      `curl -s -X POST`,
      `-H "Authorization: Bot ${token}"`,
      `-H "Content-Type: application/json"`,
      `--data-binary "@${payloadPath}"`,
      `"https://discord.com/api/v10/channels/${channelId}/messages"`,
    ].join(" "));
  } catch (e) {
    log(`  (Discord: curl failed: ${e.message})`);
    try { fs.rmSync(payloadPath); } catch (_) {}
    return;
  }
  try { fs.rmSync(payloadPath); } catch (_) {}

  let parsed = null;
  try { parsed = JSON.parse(resp); } catch (_) {}
  // Discord errors return { code: <int>, message: <string> }
  if (parsed && parsed.code !== undefined && !parsed.id) {
    log(`  (Discord: post failed: code=${parsed.code} message=${parsed.message})`);
    return;
  }
  if (parsed && parsed.id) {
    fs.writeFileSync(marker, `${new Date().toISOString()}\n${JSON.stringify(parsed)}\n`);
    ok(`Discord: posted to #announcements (message id ${parsed.id})`);
    return;
  }
  log(`  (Discord: unexpected response, raw: ${resp.slice(0, 400)})`);
}

// ═══════════════════════════════════════════════════════════════════════════
// list
// ═══════════════════════════════════════════════════════════════════════════
function cmdList() {
  const c = readConfig();
  log(`Wick suite · ${c.addons.length} active addon${c.addons.length === 1 ? "" : "s"}\n`);
  for (const a of c.addons) {
    log(`  ${a.title}`);
    log(`    folder  : ${a.folder}`);
    log(`    slash   : ${a.slash}`);
    log(`    accent  : ${a.accent} (${a.accent_name})`);
    log(`    cf slug : ${a.cf_slug}  id=${a.cf_project_id ?? "?"}`);
    log(`    repo    : https://github.com/${c.github_user}/${a.repo}`);
    log("");
  }
  if (c.retired?.length) {
    log(`Retired: ${c.retired.map(r => r.folder).join(", ")}`);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// scaffold <Display Name>
// ═══════════════════════════════════════════════════════════════════════════
function cmdScaffold(rawTitle) {
  if (!rawTitle) die("usage: wick scaffold <Display Name>  (e.g. \"Wick's Aggro Meter\")");
  const config = readConfig();
  const TOTAL = 5;  // templates → junction → git → GitHub → wick.json
  const cmd = `wick scaffold "${rawTitle}"`;

  // Normalize title to always start with "Wick's "
  let title = rawTitle.trim();
  if (!/^Wick['']s\s/i.test(title)) title = `Wick's ${title}`;
  const folder = deriveFolder(title);
  const short = title.replace(/^Wick['']s\s+/i, "");
  const slug = slugify(short);
  const slash = deriveSlash(title);
  const slashUpper = slash.slice(1).toUpperCase();
  const namespace = folder.toUpperCase(); // e.g. WICKSAGGROMETER, or use derived short
  const savedvars = namespace + "DB";

  const destAddon = path.join(config.addons_root_local, folder);
  const destJunct = path.join(config.project_home, folder);

  if (fs.existsSync(destAddon)) die(`folder already exists: ${destAddon}`);

  log(`\nScaffolding ${title}`);
  log(`  folder    : ${folder}`);
  log(`  slash     : ${slash}`);
  log(`  savedvars : ${savedvars}`);
  log(`  location  : ${destAddon}\n`);

  const vars = {
    TITLE:       title,
    FOLDER:      folder,
    SHORT:       short,
    SHORT_SLUG:  slug,
    SLASH:       slash,
    SLASH_UPPER: slashUpper,
    NAMESPACE:   namespace,
    SAVEDVARS:   savedvars,
    TAGLINE:     `${short} for TBC Classic. Part of the Wick suite.`,
    CF_SLUG:     slug,
    REPO:        folder,
    YEAR:        String(new Date().getFullYear()),
    DATE:        new Date().toISOString().slice(0, 10),
    FEATURE_BULLETS: "- Feature one\n- Feature two\n- Feature three",
  };

  // ── 1. Copy templates with placeholder substitution ────────────────
  setProgress(cmd, 1, TOTAL, "writing addon files from template");
  fs.mkdirSync(destAddon, { recursive: true });
  for (const entry of fs.readdirSync(TEMPLATE)) {
    const srcPath = path.join(TEMPLATE, entry);
    const dstName = tmpl(entry, vars);
    const dstPath = path.join(destAddon, dstName);
    if (fs.statSync(srcPath).isDirectory()) continue; // flat template
    const body = fs.readFileSync(srcPath, "utf8");
    fs.writeFileSync(dstPath, tmpl(body, vars));
  }
  // Copy logo.svg from suite
  fs.copyFileSync(path.join(SUITE_DIR, "logo.svg"), path.join(destAddon, "logo.svg"));
  ok(`files written to ${destAddon}`);

  // ── 2. Junction into project home so it shows up in Projects\Wick\ ─
  setProgress(cmd, 2, TOTAL, "creating directory junction");
  try {
    run(`cmd /c mklink /J "${destJunct}" "${destAddon}"`);
    ok(`junction: ${destJunct} → ${destAddon}`);
  } catch (e) {
    console.warn("! mklink failed (not fatal — you can run it manually later)");
  }

  // ── 3. git init + initial commit ────────────────────────────────────
  setProgress(cmd, 3, TOTAL, "git init + initial commit");
  gitIn(destAddon, "init", "-b", "main");
  gitIn(destAddon, "add", "-A");
  gitIn(destAddon, "-c", "user.name=Wick", "-c", "user.email=" + config.author_email,
        "commit", "-q", "-m", `Initial commit: ${title} v0.1.0`);
  ok("git: initial commit created");

  // ── 4. Create GitHub repo + push ───────────────────────────────────
  setProgress(cmd, 4, TOTAL, "creating GitHub repo + push");
  try {
    const ghCmd = `"${GH}" repo create ${config.github_user}/${folder} --public --source=. --remote=origin --push --description="${vars.TAGLINE}"`;
    run(ghCmd, { cwd: destAddon });
    run(`"${GH}" repo edit ${config.github_user}/${folder} --enable-wiki=true --enable-issues=true --enable-discussions=true --add-topic wow --add-topic wow-addon --add-topic tbc-classic --add-topic lua`, { cwd: destAddon });
    ok(`github: https://github.com/${config.github_user}/${folder}`);
  } catch (e) {
    console.warn("! gh repo create failed — run manually:");
    console.warn(`    gh repo create ${config.github_user}/${folder} --public --source=. --remote=origin --push`);
  }

  // ── 5. Register in wick.json ────────────────────────────────────────
  setProgress(cmd, 5, TOTAL, "registering in wick.json");
  config.addons.push({
    folder,
    title,
    short,
    slash,
    tagline: vars.TAGLINE,
    accent: "#4FC778",
    accent_name: "fel-green",
    cf_slug: slug,
    cf_project_id: null,
    features: ["Feature one", "Feature two", "Feature three"],
    repo: folder,
  });
  writeConfig(config);
  ok(`wick.json: registered ${folder}`);

  clearProgress();
  log(`\n✓ Done. Next steps:`);
  log(`   1. Edit ${folder}/Core.lua and ${folder}/UI.lua to implement your addon`);
  log(`   2. Take in-game screenshots — save to WickSuite/images/{short-key}/screenshots/main.png`);
  log(`      (pick a short key like bis, cd, macro — same one you'll use in SUITE_ADDONS)`);
  log(`   3. Add a Shot entry to WickSuite/thumbnails.html (component + artboard)`);
  log(`   4. 'wick sync' to regenerate cross-link tables`);
  log(`   5. 'wick render' to generate thumbnails + banner`);
  log(`   6. Create the CurseForge project manually (CF has no API for project creation)`);
  log(`   7. Once CF project ID is known, update cf_project_id in wick.json`);
  log(`   8. 'wick release ${folder} 0.1.0' to publish\n`);
}

// ═══════════════════════════════════════════════════════════════════════════
// sync — regenerate suite cross-link blocks from wick.json
// ═══════════════════════════════════════════════════════════════════════════
function cmdSync() {
  const config = readConfig();
  const marker = {
    start: "<!-- wick:suite-table:start -->",
    end:   "<!-- wick:suite-table:end -->",
  };
  const table = [
    "| Addon | GitHub | CurseForge |",
    "|---|---|---|",
    ...config.addons.filter(a => !a.benched).map(a =>
      `| **${a.title}** | [repo](https://github.com/${config.github_user}/${a.repo}) | [CurseForge](https://www.curseforge.com/wow/addons/${a.cf_slug}) |`),
  ].join("\n");
  const discord = config.social?.discord_invite
    ? `\n\n**Community:** [Discord](${config.social.discord_invite})`
    : "";
  const block = `${marker.start}\n${table}${discord}\n${marker.end}`;

  // Each addon README + each MoreFromWick.lua + the suite README is one phase.
  const TOTAL = config.addons.length * 2 + 1;
  let phase = 0;

  let touched = 0;
  for (const a of config.addons) {
    phase++;
    setProgress("wick sync", phase, TOTAL, `README: ${a.folder}`);
    const readme = path.join(config.addons_root_local, a.folder, "README.md");
    if (!fs.existsSync(readme)) continue;
    let body = fs.readFileSync(readme, "utf8");
    const re = new RegExp(`${marker.start}[\\s\\S]*?${marker.end}`);
    if (re.test(body)) {
      const next = body.replace(re, block);
      if (next !== body) { fs.writeFileSync(readme, next); touched++; ok(`updated ${a.folder}/README.md`); }
    } else {
      log(`  (${a.folder}/README.md has no wick:suite-table marker — add it manually to enable sync)`);
    }
  }
  // Also sync WickSuite/README.md
  phase++;
  setProgress("wick sync", phase, TOTAL, "README: WickSuite");
  const suiteReadme = path.join(SUITE_DIR, "README.md");
  if (fs.existsSync(suiteReadme)) {
    let body = fs.readFileSync(suiteReadme, "utf8");
    const re = new RegExp(`${marker.start}[\\s\\S]*?${marker.end}`);
    if (re.test(body)) {
      const next = body.replace(re, block);
      if (next !== body) { fs.writeFileSync(suiteReadme, next); touched++; ok(`updated WickSuite/README.md`); }
    }
  }
  // ── MoreFromWick.lua suite-data block ─────────────────────────────
  // Any addon with a MoreFromWick.lua gets its SUITE table regenerated from
  // wick.json. Excludes the host addon and any addon without cf_project_id.
  const luaMarker = {
    start: "-- wick:suite-data:start",
    end:   "-- wick:suite-data:end",
  };
  const luaEsc = s => String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  for (const a of config.addons) {
    phase++;
    setProgress("wick sync", phase, TOTAL, `MoreFromWick: ${a.folder}`);
    const mfwPath = path.join(config.addons_root_local, a.folder, "MoreFromWick.lua");
    if (!fs.existsSync(mfwPath)) continue;
    const rows = config.addons
      .filter(x => !x.benched && x.folder !== a.folder && x.cf_project_id)
      .map(x => {
        const tag = x.short_tagline || x.tagline || "";
        return `    { folder = "${luaEsc(x.folder)}", title = "${luaEsc(x.title)}", tagline = "${luaEsc(tag)}", slug = "${luaEsc(x.cf_slug)}" },`;
      })
      .join("\n");
    const luaBlock = `${luaMarker.start}\nlocal SUITE = {\n${rows}\n}\n${luaMarker.end}`;
    let body = fs.readFileSync(mfwPath, "utf8");
    const re = new RegExp(`${luaMarker.start}[\\s\\S]*?${luaMarker.end}`);
    if (re.test(body)) {
      const next = body.replace(re, luaBlock);
      if (next !== body) { fs.writeFileSync(mfwPath, next); touched++; ok(`updated ${a.folder}/MoreFromWick.lua`); }
    } else {
      log(`  (${a.folder}/MoreFromWick.lua has no wick:suite-data marker — add it manually to enable sync)`);
    }
  }

  clearProgress();
  log(touched ? `\n✓ ${touched} file(s) synced` : `\n(no files had the marker; add <!-- wick:suite-table:start --> … <!-- wick:suite-table:end --> to enable sync)`);
}

// ═══════════════════════════════════════════════════════════════════════════
// render — shortcut to grab-artboards.mjs
// ═══════════════════════════════════════════════════════════════════════════
function cmdRender() {
  setProgress("wick render", 1, 1, "rendering all artboards");
  try {
    run(`node "${GRAB_TOOL}"`);
  } finally {
    clearProgress();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// release <folder> <version> [--no-announce]
// ═══════════════════════════════════════════════════════════════════════════

// ---------------------------------------------------------------------------
// Clients
//
// The suite used to be one game: one addons root, one game version, one
// interface, all at the top of wick.json. Forever has its own of each, and
// Bags and Trade Hall ship on both, so a folder name no longer names one
// addon on its own.
//
// Old entries carry no client and mean tbc, so nothing already written has
// to change.
// ---------------------------------------------------------------------------
function clientOf(config, addon) {
  const name = (addon && addon.client) || "tbc";
  const c = (config.clients || {})[name];
  if (c) return c;
  // A config from before the clients map: the top level is the tbc client.
  return {
    label: name,
    addons_root: config.addons_root_local,
    cf_game_version_id: config.cf_game_version_id,
    cf_game_version_type_id: config.cf_game_version_type_id,
    interface: config.interface,
  };
}

function rootOf(config, addon) { return clientOf(config, addon).addons_root; }

// Folder plus flavour. Two addons can share a folder name across clients, so
// say which rather than picking one and hoping.
function resolveAddon(config, folder, flags) {
  const want = (flags || []).includes("--forever") ? "forever"
             : (flags || []).includes("--tbc") ? "tbc" : null;
  const all = config.addons.filter(a => a.folder === folder);
  if (all.length === 0) die(`addon not found in wick.json: ${folder}`);
  if (want) {
    const hit = all.find(a => (a.client || "tbc") === want);
    if (!hit) die(`${folder} has no ${want} entry in wick.json`);
    return hit;
  }
  if (all.length === 1) return all[0];
  const names = all.map(a => a.client || "tbc").join(", ");
  die(`${folder} exists for more than one client (${names}); pass --forever or --tbc`);
}

async function cmdRelease(folder, newVer, ...flags) {
  if (!folder || !newVer) die("usage: wick release <folder> <version> [--no-announce]");
  const noAnnounce = flags.includes("--no-announce");
  // Shipping several addons in one sitting: Discord wants every one of them,
  // because it is the changelog people follow, while a run of near identical
  // Facebook posts inside a few minutes reads as spam and risks the rate
  // limit. --no-fb keeps the per addon Discord line and leaves Facebook for
  // one post covering the lot.
  const noFB = noAnnounce || flags.includes("--no-fb");
  const noX  = noAnnounce || flags.includes("--no-x");
  const config = readConfig();
  const addon = resolveAddon(config, folder, flags);
  if (!addon.cf_project_id) die(`wick.json missing cf_project_id for ${folder} — set it first`);

  const token = process.env.CURSEFORGE_API_TOKEN;
  if (!token) die("CURSEFORGE_API_TOKEN env var not set");

  const dir = path.join(rootOf(config, addon), folder);
  const toc = path.join(dir, `${folder}.toc`);
  if (!fs.existsSync(toc)) die(`.toc not found: ${toc}`);

  // 7 visible phases: bump → changelog → git → zip → CF upload → FB announce → Discord announce.
  const TOTAL = noAnnounce ? 5 : 7;
  const cmd   = `wick release ${folder} v${newVer}`;

  // ── Bump version in .toc ──────────────────────────────────────────
  setProgress(cmd, 1, TOTAL, "bumping .toc version");
  let tocBody = fs.readFileSync(toc, "utf8");
  const oldVer = (tocBody.match(/^## Version:\s*(.+)$/m) || [])[1] || "?";
  tocBody = tocBody.replace(/^## Version:.*$/m, `## Version: ${newVer}`);
  fs.writeFileSync(toc, tocBody);
  ok(`${folder}.toc : ${oldVer} → ${newVer}`);

  // ── Append CHANGELOG entry (stub — user edits after) ───────────────
  // Skip the append if an entry for this version already exists (re-release
  // or the user pre-wrote real notes before running `wick release`).
  setProgress(cmd, 2, TOTAL, "updating CHANGELOG");
  const changelog = path.join(dir, "CHANGELOG.md");
  if (fs.existsSync(changelog)) {
    const date = new Date().toISOString().slice(0, 10);
    const existing = fs.readFileSync(changelog, "utf8");
    if (new RegExp(`^##\\s+${newVer.replace(/\./g, "\\.")}\\b`, "m").test(existing)) {
      log(`  CHANGELOG.md already has a ${newVer} entry — leaving it as-is`);
    } else {
      const head = `# ${addon.title} — Changelog\n\n## ${newVer} — ${date}\n\n- (edit this entry with the actual changes)\n\n`;
      const body = existing.startsWith(`# ${addon.title}`)
        ? existing.replace(/^(# [^\n]+\n\n)/, `$1## ${newVer} — ${date}\n\n- (edit this entry with the actual changes)\n\n`)
        : head + existing;
      fs.writeFileSync(changelog, body);
      ok(`CHANGELOG.md: appended ${newVer}`);
    }
  }

  // ── Commit + tag + push ───────────────────────────────────────────
  setProgress(cmd, 3, TOTAL, "git commit + tag + push");
  gitIn(dir, "add", "-A");
  // Only commit if there's something to commit. Lets us re-ship a version
  // whose code was already committed earlier (e.g. inaugural releases where
  // v0.1.0 was committed before the CF project existed).
  const status = runCapture(`git -C "${dir}" status --porcelain`);
  if (status.trim()) {
    gitIn(dir, "-c", `user.name=${config.author}`, "-c", `user.email=${config.author_email}`,
          "commit", "-q", "-m", `Release ${newVer}`);
  } else {
    log(`  working tree clean — skipping release commit`);
  }
  // Bags and Trade Hall keep both builds in one repo, TBC on main and
  // Forever on its own branch, so a bare vX.Y.Z collides: Bags had already
  // used v0.9.0 through v0.9.3 on the TBC line. Non-tbc releases get their
  // own prefix so the two lines can run at the same numbers.
  const tagName = (addon.client && addon.client !== "tbc")
    ? `${addon.client}-v${newVer}`
    : `v${newVer}`;
  // An existing tag on this very commit is a re-ship, not a mistake:
  // the same reason the commit above is skipped when the tree is clean.
  // A tag pointing somewhere else is a real conflict and stops here.
  const tagged = runCapture(`git -C "${dir}" tag -l ${tagName}`).trim();
  if (!tagged) {
    gitIn(dir, "tag", tagName);
  } else {
    const at = runCapture(`git -C "${dir}" rev-list -n 1 ${tagName}`).trim();
    const head = runCapture(`git -C "${dir}" rev-parse HEAD`).trim();
    if (at !== head) die(`${tagName} already exists and points at ${at.slice(0, 7)}, not HEAD`);
    log(`  ${tagName} already on this commit — leaving it`);
  }
  // Detect branch: WicksSurvivors uses 'master'; all others use 'main'.
  const currentBranch = runCapture(`git -C "${dir}" rev-parse --abbrev-ref HEAD`).trim();
  gitIn(dir, "push", "origin", currentBranch);
  gitIn(dir, "push", "origin", tagName);
  ok(`git: tagged ${tagName} and pushed`);

  // ── Zip the addon folder ─────────────────────────────────────────
  setProgress(cmd, 4, TOTAL, "building release zip");
  const zipName = `${folder}-v${newVer}.zip`;
  // AddOns root is often write-protected; use %TEMP% which is always writable.
  const zipDir = process.env.TEMP || process.env.TMP || config.addons_root_local;
  const zipPath = path.join(zipDir, zipName);
  if (fs.existsSync(zipPath)) fs.rmSync(zipPath);
  // Compress-Archive writes backslash ZIP entries which CF rejects — use ZipArchive directly.
  const psZip = [
    `Add-Type -AssemblyName System.IO.Compression`,
    `Add-Type -AssemblyName System.IO.Compression.FileSystem`,
    `$src = '${dir.replace(/'/g, "''")}'`,
    `$dst = '${zipPath.replace(/'/g, "''")}'`,
    `$folder = '${folder}'`,
    `$stream = [System.IO.File]::Open($dst, [System.IO.FileMode]::Create)`,
    `$zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)`,
    `try {`,
    `  foreach ($f in Get-ChildItem -Path $src -Recurse -File -Force) {`,
    `    $rel = $f.FullName.Substring($src.Length + 1).Replace('\\', '/')`,
    `    if ($rel -like '.git/*' -or $rel -like '.claude/*' -or $rel -eq '.gitignore') { continue }`,
    `    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $folder + '/' + $rel, [System.IO.Compression.CompressionLevel]::Optimal)`,
    `  }`,
    `} finally { $zip.Dispose(); $stream.Dispose() }`,
  ].join("; ");
  run(`powershell -NoProfile -Command "${psZip}"`);
  ok(`zip: ${zipName}`);

  // ── Upload to CurseForge ─────────────────────────────────────────
  // Write metadata to a temp JSON file and use curl's `-F metadata=<file`
  // reader. Avoids cross-shell single-quote hell (cmd.exe / bash / ps) that
  // would otherwise split the JSON on spaces and lose the metadata field.
  setProgress(cmd, 5, TOTAL, "uploading to CurseForge");
  log(`\nUploading to CurseForge project ${addon.cf_project_id} ...`);
  const metadata = JSON.stringify({
    // An addon that ships one package for several clients lists them all
    // in cf_game_versions; everything else takes the suite default.
    gameVersions: addon.cf_game_versions || [clientOf(config, addon).cf_game_version_id],
    releaseType: "release",
    changelog: `Release ${newVer}. See CHANGELOG.md for details.`,
    changelogType: "markdown",
    // Bags and Trade Hall host both flavours on one project, so the file
    // list would otherwise show two files with the same name and nothing
    // to tell them apart. TBC names are left exactly as they were.
    displayName: (addon.client && addon.client !== "tbc")
      ? `${addon.title} v${newVer} (${clientOf(config, addon).label})`
      : `${addon.title} v${newVer}`,
  });
  const metaPath = path.join(zipDir, `.wick-cf-meta-${folder}.json`);
  // Buffer.from ensures BOM-free UTF-8 — a bare writeFileSync on some Node/PS combos emits a BOM
  // which CF returns as errorCode 1002 "Invalid JSON" with no hint it's a BOM issue.
  fs.writeFileSync(metaPath, Buffer.from(metadata, "utf8"));
  // Use spawnSync so metadata is passed as a literal arg — avoids shell quoting
  // issues with $(cat ...) on cmd.exe and single-quote escaping on bash.
  const curlArgs = [
    "-s", "-X", "POST",
    "-H", `X-Api-Token: ${token}`,
    "--form-string", `metadata=${metadata}`,
    "-F", `file=@${zipPath}`,
    `${config.cf_api_base}/api/projects/${addon.cf_project_id}/upload-file`,
  ];
  const curlResult = spawnSync("curl", curlArgs, { encoding: "utf8" });
  let resp = ((curlResult.stdout || "") + (curlResult.stderr || "")).trim();
  try { fs.rmSync(metaPath); } catch (_) {}
  log(resp);
  let parsed = null;
  try { parsed = JSON.parse(resp); } catch (_) {}
  if (parsed && parsed.errorCode) {
    die(`CurseForge upload failed (${parsed.errorCode}): ${parsed.errorMessage || "unknown error"}`);
  }
  ok(`CurseForge: uploaded v${newVer}`);

  // ── Announce on Facebook (best effort) ───────────────────────────
  if (noFB) {
    log(`  (FB: skipping post, ${noAnnounce ? "--no-announce" : "--no-fb"} passed)`);
  } else {
    setProgress(cmd, 6, TOTAL, "posting to Facebook");
    try { announceFB(addon, newVer, dir, config); }
    catch (e) { log(`  (FB: announce threw, swallowed: ${e.message})`); }
  }

  // ── Announce on Discord (best effort) ────────────────────────────
  if (noAnnounce) {
    log(`  (Discord: --no-announce passed, skipping post)`);
  } else {
    setProgress(cmd, 7, TOTAL, "posting to Discord");
    try { announceDiscord(addon, newVer, dir, config); }
    catch (e) { log(`  (Discord: announce threw, swallowed: ${e.message})`); }
  }

  // ── X (Twitter) intent URL — auto API is paywalled, click-to-post ──
  if (!noX) {
    const cfUrl = `https://www.curseforge.com/wow/addons/${addon.cf_slug}`;
    const tagline = addon.short_tagline || addon.tagline || "";
    // The tags follow the client this release is for. Every post
    // said TBC Classic, the Forever ones included, which is the
    // wrong audience to put it in front of.
    const tags = (addon.client || "tbc") === "forever"
      ? "#WoWForever #Warcraft"
      : "#WoWClassic #TBCClassic";
    const xText = [
      `${addon.title} v${newVer} is live on CurseForge.`,
      "",
      tagline,
      "",
      cfUrl,
      "",
      tags,
    ].join("\n");
    const xUrl = `https://twitter.com/intent/tweet?text=${encodeURIComponent(xText)}`;
    log(`\nX (click to compose):\n  ${xUrl}`);
  }

  clearProgress();
  log(`\n✓ Release complete.`);
  log(`  • Update CHANGELOG.md with real changes (stub inserted)`);
  log(`  • Re-upload Featured image if needed`);
  log(`  • Check https://www.curseforge.com/wow/addons/${addon.cf_slug}`);
}

// ═══════════════════════════════════════════════════════════════════════════
// audit-secrets — scan all suite repos for accidentally committed secrets
// ═══════════════════════════════════════════════════════════════════════════
function cmdAuditSecrets() {
  const config = readConfig();

  // ── Build repo list ──────────────────────────────────────────────
  const repos = [];
  for (const addon of config.addons.filter(a => !a.benched)) {
    const dir = path.join(rootOf(config, addon), addon.folder);
    if (fs.existsSync(path.join(dir, ".git"))) repos.push({ name: addon.folder, dir });
  }
  if (fs.existsSync(path.join(SUITE_DIR, ".git"))) {
    repos.push({ name: "WickSuite", dir: SUITE_DIR });
  }
  const landingDir = path.join(config.project_home, "Wicksmods.github.io");
  if (fs.existsSync(path.join(landingDir, ".git"))) {
    repos.push({ name: "Wicksmods.github.io", dir: landingDir });
  }

  // ── Secret patterns ──────────────────────────────────────────────
  // regex: used for Node.js content scan (working tree)
  // git_regex: POSIX ERE passed to git log -G (history scan)
  const PATTERNS = [
    {
      name: "Discord bot token",
      regex: /[A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}/,
      git_regex: "[A-Za-z0-9_-]{24,}\\.[A-Za-z0-9_-]{6}\\.[A-Za-z0-9_-]{27,}",
      note: "Rotate: discord.com/developers/applications -> Bot -> Reset Token",
    },
    {
      name: "Facebook Graph API token",
      regex: /EAA[A-Za-z0-9_-]{50,}/,
      git_regex: "EAA[A-Za-z0-9_-]{50,}",
      note: "Invalidate: developers.facebook.com/tools/access_token",
    },
    {
      name: "GitHub classic token",
      regex: /ghp_[A-Za-z0-9]{36}/,
      git_regex: "ghp_[A-Za-z0-9]{36}",
      note: "Revoke: github.com/settings/tokens",
    },
    {
      name: "GitHub fine-grained token",
      regex: /github_pat_[A-Za-z0-9_]{82}/,
      git_regex: "github_pat_[A-Za-z0-9_]{82}",
      note: "Revoke: github.com/settings/tokens",
    },
    {
      name: "Private key",
      regex: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
      git_regex: "-----BEGIN.*PRIVATE KEY-----",
      note: "Revoke and regenerate this key pair immediately",
    },
    {
      name: "AWS access key",
      regex: /AKIA[0-9A-Z]{16}/,
      git_regex: "AKIA[0-9A-Z]{16}",
      note: "Deactivate: console.aws.amazon.com/iam/",
    },
  ];

  // Filenames that should never be tracked in git
  const SENSITIVE_FILES = [
    "Wicksmodsinfo.txt", "keys.txt", ".env", ".env.local",
    "secrets.json", "credentials.json", "settings.local.json",
  ];

  const SKIP_EXT  = /\.(png|jpe?g|gif|ico|zip|whl|wasm|ttf|otf|exe|dll|so|bin|pdf)$/i;
  const SKIP_PATH = /\bnode_modules\b/;
  const MAX_FILE  = 2 * 1024 * 1024; // skip files > 2 MB

  // ── Scan ─────────────────────────────────────────────────────────
  log(`\nWick audit-secrets`);
  log(`==================`);
  log(`Scanning ${repos.length} repos — working tree + full history\n`);

  const allFindings = [];

  for (let i = 0; i < repos.length; i++) {
    const { name, dir } = repos[i];
    setProgress("wick audit-secrets", i + 1, repos.length, `scanning ${name}`);
    const repoFindings = [];

    // ── Working tree: sensitive filenames ──────────────────────────
    let tracked = [];
    try { tracked = runCapture(`git -C "${dir}" ls-files`).split("\n").filter(Boolean); }
    catch (_) {}

    for (const fname of SENSITIVE_FILES) {
      if (tracked.some(f => f === fname || f.endsWith(`/${fname}`))) {
        repoFindings.push({
          where: "working-tree",
          pattern: `Credentials file tracked: ${fname}`,
          detail: fname,
          note: `Remove from index: git rm --cached ${fname}  then add to .gitignore`,
        });
      }
    }

    // ── Working tree: pattern scan ─────────────────────────────────
    for (const file of tracked) {
      if (SKIP_EXT.test(file) || SKIP_PATH.test(file)) continue;
      const full = path.join(dir, file.replace(/\//g, path.sep));
      let content;
      try { content = fs.readFileSync(full, "utf8"); } catch (_) { continue; }
      if (content.length > MAX_FILE) continue;

      const lines = content.split("\n");
      for (let ln = 0; ln < lines.length; ln++) {
        for (const p of PATTERNS) {
          if (p.regex.test(lines[ln])) {
            repoFindings.push({
              where: "working-tree",
              pattern: p.name,
              detail: `${file}:${ln + 1}`,
              note: p.note,
            });
          }
        }
      }
    }

    // ── History: sensitive filenames ever committed ────────────────
    for (const fname of SENSITIVE_FILES) {
      let out = "";
      try { out = runCapture(`git -C "${dir}" log --all --oneline --diff-filter=A -- "${fname}"`); }
      catch (_) {}
      for (const commit of out.trim().split("\n").filter(Boolean)) {
        repoFindings.push({
          where: "history",
          pattern: `Credentials file committed: ${fname}`,
          detail: commit,
          note: "Remove from history with git-filter-repo (see remediation below)",
        });
      }
    }

    // ── History: pattern scan via git log -G ───────────────────────
    for (const p of PATTERNS) {
      let out = "";
      try {
        out = runCapture(
          `git -C "${dir}" log --all --oneline --no-merges -G "${p.git_regex}"`
        );
      } catch (_) {}
      for (const commit of out.trim().split("\n").filter(Boolean)) {
        repoFindings.push({
          where: "history",
          pattern: p.name,
          detail: commit,
          note: p.note,
        });
      }
    }

    // ── Per-repo output ────────────────────────────────────────────
    if (repoFindings.length === 0) {
      log(`  ${name}: clean`);
    } else {
      log(`  ${name}: ${repoFindings.length} finding${repoFindings.length === 1 ? "" : "s"}`);
      for (const f of repoFindings) {
        log(`    ! [${f.where}] ${f.pattern}`);
        log(`      ${f.detail}`);
      }
    }
    for (const f of repoFindings) allFindings.push({ ...f, repo: name, dir });
  }

  clearProgress();

  // ── Summary ───────────────────────────────────────────────────────
  log(`\n${"─".repeat(60)}`);
  if (allFindings.length === 0) {
    log(`\n✓ No secrets found across ${repos.length} repos.\n`);
    return;
  }

  log(`\n! ${allFindings.length} finding${allFindings.length === 1 ? "" : "s"} across ${repos.length} repos\n`);
  log(`IMPORTANT: Rotate any exposed credentials first. Scrubbing history does not`);
  log(`invalidate a secret that was already cloned or cached by GitHub/CF/etc.\n`);

  // Group by repo for remediation steps
  const byRepo = {};
  for (const f of allFindings) {
    if (!byRepo[f.repo]) byRepo[f.repo] = { dir: f.dir, findings: [] };
    byRepo[f.repo].findings.push(f);
  }

  log(`Remediation`);
  log(`-----------`);
  for (const [rName, { dir: rDir, findings: rFindings }] of Object.entries(byRepo)) {
    log(`\n[${rName}]`);
    const notes = [...new Set(rFindings.map(f => f.note).filter(Boolean))];
    for (const n of notes) log(`  * ${n}`);
    if (rFindings.some(f => f.where === "history")) {
      log(`  To scrub from history:`);
      log(`    pip install git-filter-repo          (if not installed)`);
      log(`    cd "${rDir}"`);
      log(`    # Create expressions.txt with one line per secret:`);
      log(`    #   literal:<the_secret>==><REDACTED>`);
      log(`    git filter-repo --force --replace-text expressions.txt`);
      log(`    git push origin --force --all`);
      log(`    git push origin --force --tags`);
      log(`    # Also notify any collaborators to re-clone.`);
    }
  }
  log("");
  process.exitCode = 1;
}

// ════════════════════════════════════════════════════════════════════════════
// milestone — post the download counter crossing a round number
// ════════════════════════════════════════════════════════════════════════════

// The card says the true count, the words say the round number. That is
// how a milestone is told: you cross five thousand, not five thousand
// and eleven.
function milestoneCopy(exact) {
  const round = Math.floor(exact / 1000) * 1000;
  const r = round.toLocaleString("en-US");
  const fb = [
    `${r} downloads.`,
    ``,
    `The counter went past it this week, so here is the ceremony.`,
    ``,
    `Every one of these addons started as something missing from my own UI. That other people ended up running them is still the strange and good part. Thank you for installing them, for the bug reports, and for telling me when something looked wrong.`,
    ``,
    `Precision addons for TBC Classic, and a growing set being built for the Forever beta ahead of launch.`,
    ``,
    `https://wicksmods.com`,
  ].join("\n");
  const x = [
    `${r} downloads across the suite.`,
    ``,
    `Every one of these started as something missing from my own UI. Thank you for installing them, and for telling me when something looked wrong.`,
    ``,
    `https://wicksmods.com`,
    ``,
    `#WoWClassic #WoWForever`,
  ].join("\n");
  const discord = [
    `The counter went past ${r} this week.`,
    ``,
    `Every one of these addons started as something missing from my own UI. Thank you for installing them, for the bug reports, and for telling me when something looked wrong.`,
    ``,
    `Exact count at the time of posting: ${exact.toLocaleString("en-US")}.`,
  ].join("\n");
  return { round, r, fb, x, discord };
}

function milestonesFile(config) {
  return path.join(config.project_home, "Wicksmods.github.io", "data", "milestones-hit.json");
}

function readMilestones(config) {
  const f = milestonesFile(config);
  if (!fs.existsSync(f)) return [];
  try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch (_) { return []; }
}

async function cmdMilestone(nArg, ...flags) {
  const exact = parseInt(String(nArg || "").replace(/[^0-9]/g, ""), 10);
  if (!exact) die("usage: wick milestone <count> [--no-fb] [--no-discord] [--force]");
  const config = readConfig();
  const { round, r, fb, x, discord } = milestoneCopy(exact);
  if (!round) die(`${exact} has not crossed a thousand yet`);

  const dry = flags.includes("--dry-run");
  const hit = readMilestones(config);
  const highest = hit.length ? Math.max(...hit) : 0;
  if (!flags.includes("--force")) {
    // At or below one already announced. The exact-match check alone
    // let `milestone 2500` through, because it floors to 2000 and only
    // 2500 was in the list, and a two thousand post went out after a
    // two and a half thousand one.
    if (round <= highest) {
      die(`${r} is not past ${highest.toLocaleString("en-US")}, which has already been announced`
        + ` (pass --force if you really mean to post it again)`);
    }
  }

  // Rendered by `wick render`, from the Milestone artboard in
  // thumbnails.html. Rendering it here would mean a browser launch for
  // a card that is usually already correct.
  const card = path.join(SUITE_DIR, "images", "suite", "milestone.png");
  if (!fs.existsSync(card)) {
    die(`no milestone card at ${card} — set MILESTONE in thumbnails.html and run: wick render`);
  }

  const tmp = os.tmpdir();
  const captionPath = path.join(tmp, "wick-milestone-caption.txt");

  // ── Facebook ──
  if (dry) {
    log(`\n── Facebook ──\n${fb}`);
    log(`\n── Discord ──\n${discord}`);
    log(`\n── X ──\n${x}`);
    log(`\ncard: ${card}`);
    log(`\n(dry run: nothing posted, nothing recorded)`);
    return;
  }

  if (!flags.includes("--no-fb")) {
    const token = resolveFBPageToken(config);
    const pageId = config.social?.fb_page_id;
    const v = config.social?.fb_graph_version || "v21.0";
    if (!token || !pageId) {
      log(`  (FB: no page token or page id; skipping)`);
    } else {
      fs.writeFileSync(captionPath, fb);
      log(`\nPosting to Facebook (${config.social.fb_page_name}) with the milestone card ...`);
      let resp = "";
      try {
        resp = runCapture([
          `curl -s -X POST`,
          `-F "source=@${card}"`,
          `-F "caption=<${captionPath}"`,
          `-F "access_token=${token}"`,
          `"https://graph.facebook.com/${v}/${pageId}/photos"`,
        ].join(" "));
      } catch (e) { log(`  (FB: curl failed: ${e.message})`); }
      try { fs.rmSync(captionPath); } catch (_) {}
      let parsed = null;
      try { parsed = JSON.parse(resp); } catch (_) {}
      if (parsed && parsed.post_id) ok(`FB: posted (post id ${parsed.post_id})`);
      else if (parsed && parsed.id) ok(`FB: posted (id ${parsed.id})`);
      else log(`  (FB: unexpected response: ${String(resp).slice(0, 200)})`);
    }
  }

  // ── Discord ──
  if (!flags.includes("--no-discord")) {
    const token = resolveDiscordBotToken();
    const channelId = token && resolveDiscordAnnouncementsChannel(config, token);
    if (!channelId) {
      log(`  (Discord: no bot token or channel; skipping)`);
    } else {
      // The card rides along as an attachment and the embed points at
      // it, so the post carries the picture rather than a bare link.
      const payload = JSON.stringify({
        embeds: [{
          title: `${r} downloads`,
          description: discord,
          color: 0x4FC778,
          url: "https://wicksmods.com",
          image: { url: "attachment://milestone.png" },
        }],
      });
      const payloadPath = path.join(tmp, "wick-milestone-discord.json");
      fs.writeFileSync(payloadPath, payload);
      log(`\nPosting to Discord #announcements ...`);
      let resp = "";
      try {
        resp = runCapture([
          `curl -s -X POST`,
          `-H "Authorization: Bot ${token}"`,
          `-F "payload_json=<${payloadPath}"`,
          `-F "files[0]=@${card};type=image/png"`,
          `"https://discord.com/api/v10/channels/${channelId}/messages"`,
        ].join(" "));
      } catch (e) { log(`  (Discord: curl failed: ${e.message})`); }
      try { fs.rmSync(payloadPath); } catch (_) {}
      let parsed = null;
      try { parsed = JSON.parse(resp); } catch (_) {}
      if (parsed && parsed.id) ok(`Discord: posted (message id ${parsed.id})`);
      else log(`  (Discord: unexpected response: ${String(resp).slice(0, 200)})`);
    }
  }

  // ── record it, so a second run says so rather than posting twice ──
  const f = milestonesFile(config);
  if (fs.existsSync(path.dirname(f))) {
    const list = readMilestones(config);
    if (!list.includes(round)) {
      list.push(round);
      list.sort((a, b) => a - b);
      fs.writeFileSync(f, JSON.stringify(list, null, 2) + "\n");
      ok(`recorded ${r} in milestones-hit.json`);
    }
  }

  log(`\nX (click to compose):\n  https://twitter.com/intent/tweet?text=${encodeURIComponent(x)}`);
  log(`\n✓ Milestone posted.`);
}

// ═══════════════════════════════════════════════════════════════════════════
// Dispatch
// ═══════════════════════════════════════════════════════════════════════════
const [,, sub, ...rest] = process.argv;
switch (sub) {
  case "list":     cmdList(); break;
  case "scaffold": cmdScaffold(rest.join(" ")); break;
  case "sync":     cmdSync(); break;
  case "render":   cmdRender(); break;
  case "release":       await cmdRelease(rest[0], rest[1], ...rest.slice(2)); break;
  case "audit-secrets": cmdAuditSecrets(); break;
  case "milestone":     await cmdMilestone(rest[0], ...rest.slice(1)); break;
  case "announce": {
    // Manually re-post a release announcement (e.g., if --no-announce was used,
    // or a token wasn't set at release time, or you want to re-post).
    const folder = rest[0], ver = rest[1];
    if (!folder || !ver) die("usage: wick announce <folder> <version>");
    const cfg = readConfig();
    // The same resolution release uses. This used to join the TBC root
    // for everything, so announcing a Forever addon looked in a folder
    // that does not exist: no thumbnail was found, the post went out
    // without a picture, and writing the marker then threw.
    const a = resolveAddon(cfg, folder, rest.slice(2));
    const dir = path.join(rootOf(cfg, a), a.folder);
    if (!fs.existsSync(dir)) die(`addon folder not found: ${dir}`);
    announceFB(a, ver, dir, cfg);
    announceDiscord(a, ver, dir, cfg);
    break;
  }
  case undefined:
  case "-h":
  case "--help":
    log(`wick — Wick addon suite CLI

usage:
  wick list                                list active addons
  wick scaffold "<Display Name>"           create a new addon (files, git, github, wick.json)
  wick sync                                regenerate suite cross-link tables in every README
  wick render                              run grab-artboards.mjs (thumbnails + banner)
  wick release <folder> <ver> [--no-announce]
                                           bump, commit, tag, push, zip, upload to CurseForge,
                                           and post a release announcement to FB + Discord
  wick announce <folder> <ver>             re-post a release announcement to FB + Discord
                                           (idempotent; writes marker files to dedupe)
  wick milestone <count> [--dry-run] [--no-fb] [--no-discord] [--force]
                                           post the download counter crossing a round
                                           number, with the milestone card; records it
                                           in the landing site's milestones-hit.json.
                                           --dry-run prints the copy and posts nothing
  wick audit-secrets                       scan all suite repos (working tree + full history)
                                           for accidentally committed secrets; exits 1 if found

examples:
  node tools/wick.mjs list
  node tools/wick.mjs scaffold "Wick's Aggro Meter"
  node tools/wick.mjs release WicksCDTracker 0.3.0
  node tools/wick.mjs release WicksCDTracker 0.3.0 --no-announce
  node tools/wick.mjs announce WicksQuestKey 1.0.0
  node tools/wick.mjs audit-secrets`);
    break;
  default:
    die(`unknown subcommand: ${sub}\n(try: wick --help)`);
}
