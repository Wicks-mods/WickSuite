// wick fb-token: put a working Facebook Page token back in the secrets file.
//
// Facebook ends every token of an account when its password changes or when
// it resets the sessions for security (error 190, subcode 460). After that
// nothing in the pipeline can post until a new Page token is saved. Doing
// that by hand is three fiddly steps with long secrets on the clipboard:
// extend the one-hour token, read the Page token out of me/accounts, paste
// both into the file. This does those steps and never prints a token.
//
//   wick fb-token             take the fresh token from the clipboard, extend it,
//                             derive the Page token, check it, save both
//   wick fb-token --check     is the saved Page token still accepted? (read-only)
//   wick fb-token --dry-run   everything except writing the file
//   wick fb-token --from-env  take the fresh token from FB_FRESH_TOKEN, not the clipboard
//
// The one step only Wick can do comes first: in the Graph API Explorer
// (developers.facebook.com/tools/explorer) choose the posting app, add the
// permissions in NEEDED, press Generate Access Token, tick the page, copy
// the token.

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const TOOLS = path.dirname(fileURLToPath(import.meta.url));
const SUITE = path.dirname(TOOLS);
const DOCS = "C:/Users/jspli/OneDrive/Documents";
const SECRETS = `${DOCS}/Wicksmodsinfo.txt`;
// The app the posts go through sits in the streaming side's business
// portfolio, so its id and secret may be in that side's file. Only those two
// lines are read from it, and only to sign the calls below.
const OTHER_SECRETS = `${DOCS}/Wickidspliffinfo.txt`;

const TOKEN = /^EA[A-Za-z0-9_-]{50,}$/;
const NEEDED = ["pages_show_list", "pages_read_engagement", "pages_manage_posts"];

const read = (p) => { try { return fs.readFileSync(p, "utf8"); } catch { return null; } };
// First uncommented "key = value" line; a "# key = ..." line never matches.
const value = (text, key) => ((text || "").match(new RegExp(`^[ \\t]*${key}[ \\t]*=[ \\t]*(\\S+)`, "m")) || [])[1] || "";
const enc = encodeURIComponent;
// Whatever Facebook says back is shown to a person, so take anything that
// looks like a token or an app token out of it first.
const scrub = (s) => String(s ?? "no reason given")
  .replace(/EA[A-Za-z0-9_-]{30,}/g, "<token>")
  .replace(/\d{10,}\|[A-Za-z0-9_-]+/g, "<app token>")
  .replace(/[.\s]+$/, "");
const ok = (s) => console.log(`✓ ${s}`);
const day = (unix) => new Date(unix * 1000).toISOString().slice(0, 10);

class Stop extends Error {}
const stop = (msg) => { throw new Stop(msg); };

async function graph(v, pathAndQuery) {
  try {
    const res = await fetch(`https://graph.facebook.com/${v}/${pathAndQuery}`);
    return await res.json();
  } catch (e) {
    // The message of a failed fetch carries no address; the cause's code says why.
    return { error: { message: `no answer from Facebook (${e.cause?.code || e.message})`, offline: true } };
  }
}

// Every app whose id and secret are on this machine. A token can only be
// inspected and extended by the app that issued it, so each is tried.
function apps() {
  const out = [];
  const add = (id, secret, where) => {
    if (id && secret && !out.some((a) => a.id === id)) out.push({ id, secret, where });
  };
  add(process.env.FB_APP_ID, process.env.FB_APP_SECRET, "FB_APP_ID / FB_APP_SECRET");
  const mine = read(SECRETS), other = read(OTHER_SECRETS);
  add(value(mine, "fb_posting_app_id"), value(mine, "fb_posting_app_secret"), "Wicksmodsinfo.txt (fb_posting_app_*)");
  add(value(mine, "fb_app_id"), value(mine, "fb_app_secret"), "Wicksmodsinfo.txt (fb_app_*)");
  add(value(other, "fb_app_id"), value(other, "fb_app_secret"), "Wickidspliffinfo.txt (fb_app_*)");
  return out;
}

// What Facebook knows about a token: the app that issued it, its kind, its
// permissions, when it ends. Works on a dead token too, which is how the
// posting app is recognised after every token has been ended.
async function inspect(token, candidates, v) {
  let last = "no app id and secret on this machine";
  for (const app of candidates) {
    const r = await graph(v, `debug_token?input_token=${enc(token)}&access_token=${enc(`${app.id}|${app.secret}`)}`);
    if (r.data && r.data.app_id === app.id) return { app, data: r.data };
    last = r.error?.message || r.data?.error?.message || last;
    if (r.error?.offline) break;
  }
  return { app: null, error: scrub(last) };
}

function savedPageToken() {
  const t = process.env.FB_WICKS_MODS_PAGE_TOKEN || value(read(SECRETS), "fb_page_token");
  return TOKEN.test(t) ? t : "";
}

// Read-only: does Facebook still take the saved Page token? Used by
// `wick fb-token --check` and by `wick audit --remote`, so a dead token is
// found before a release round rather than in the middle of one.
export async function checkSaved(config) {
  const v = config.social?.fb_graph_version || "v21.0";
  const pageId = config.social?.fb_page_id;
  const token = savedPageToken();
  if (!token) return { state: "missing", detail: "no fb_page_token in Wicksmodsinfo.txt" };
  const r = await graph(v, `${pageId}?fields=id,name&access_token=${enc(token)}`);
  if (r.error?.offline) return { state: "unreachable", detail: r.error.message };
  const d = await describe(token, v);
  const app = d.known ? d.app : null;
  if (r.error) {
    return { state: "refused", code: r.error.code ?? null, subcode: r.error.error_subcode ?? null, detail: scrub(r.error.message), app };
  }
  // A User token can read the page's name too, so being answered is not
  // enough: only a Page token for this page can post as it.
  if (d.known && d.kind !== "PAGE") {
    return { state: "refused", code: null, subcode: null, app, detail: `the saved fb_page_token is a ${d.kind === "USER" ? "User" : d.kind} token, not a Page token, so it cannot post as the page` };
  }
  if (d.known && d.profile && d.profile !== String(pageId)) {
    return { state: "refused", code: null, subcode: null, app, detail: "the saved fb_page_token is for another page" };
  }
  return { state: "ok", page: r.name, app, expires: d.known ? d.expires : null };
}

// What Facebook says a token is, in the few facts that matter here.
async function describe(token, v) {
  const seen = await inspect(token, apps(), v);
  if (!seen.app) return { known: false, detail: seen.error };
  const d = seen.data;
  return {
    known: true, valid: !!d.is_valid, kind: d.type || null,
    app: { id: d.app_id, name: d.application || null },
    profile: d.profile_id ? String(d.profile_id) : null,
    scopes: d.scopes || [], expires: d.expires_at ? day(d.expires_at) : null,
    detail: d.is_valid ? null : scrub(d.error?.message),
  };
}

// The secrets file with new values on the two token lines and nothing else
// touched: same line endings, same comments, same order. A key that is not
// there yet is added at the end.
export function rewrite(text, values, note) {
  const eol = /\r\n/.test(text) ? "\r\n" : "\n";
  let out = text;
  const done = [];
  for (const [key, val] of Object.entries(values)) {
    if (!val) continue;
    const line = new RegExp(`^([ \\t]*${key}[ \\t]*=[ \\t]*)[^\\r\\n]*`, "m");
    // A function, so a "$" in a token is never read as a replacement pattern.
    if (line.test(out)) { out = out.replace(line, (_, lead) => lead + val); done.push(`${key} replaced`); }
    else { out = out.replace(/[\r\n]*$/, "") + `${eol}${key} = ${val}${eol}`; done.push(`${key} added`); }
  }
  if (note && values.fb_page_token) {
    // One dated line above the Page token, replaced on the next renewal.
    out = out.replace(/^# renewed [^\r\n]*by wick fb-token[^\r\n]*\r?\n/m, "");
    out = out.replace(/^([ \t]*fb_page_token[ \t]*=)/m, (m) => `# renewed ${note}${eol}${m}`);
  }
  return { text: out, done };
}

function clipboard() {
  try {
    return execFileSync("powershell", ["-NoProfile", "-Command", "Get-Clipboard -Raw"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch { return ""; }
}
// A token left on the clipboard is a token anything can paste somewhere.
function clearClipboard() {
  try { execFileSync("cmd", ["/c", "echo off | clip"], { stdio: "ignore" }); return true; } catch { return false; }
}

function sayCheck(c) {
  const via = c.app ? ` (issued by ${c.app.name || `app ${c.app.id}`})` : "";
  if (c.state === "ok") ok(`Facebook accepts the saved Page token for ${c.page}${via}${c.expires ? `, until ${c.expires}` : ", no end date"}`);
  else if (c.state === "refused") console.log(`✗ Facebook refuses the saved Page token${via}: ${c.detail} (code ${c.code}${c.subcode ? `, subcode ${c.subcode}` : ""})\n  Nothing can post to Facebook until a new one is saved. See: wick fb-token --help`);
  else console.log(`✗ ${c.detail}`);
}

const HELP = `wick fb-token                 renew the Facebook Page token from a token on the clipboard
wick fb-token --check         is the saved Page token still accepted? (read-only)
wick fb-token --dry-run       every step except writing Wicksmodsinfo.txt
wick fb-token --from-env      take the fresh token from FB_FRESH_TOKEN instead of the clipboard
wick fb-token --from-saved    take it from the fb_user_token line already in Wicksmodsinfo.txt

First, by hand (the one step that needs your Facebook login):
  1. Open https://developers.facebook.com/tools/explorer
  2. Meta App: the app the page posts through. "User or Page": Get User Access Token.
  3. Permissions: ${NEEDED.join(", ")}
  4. Generate Access Token, approve it, tick only the page it is for.
  5. Copy the Access Token, then run: wick fb-token
No token is ever printed. The old file is kept beside the new one as Wicksmodsinfo.txt.bak.`;

async function renew(config, args) {
  const v = config.social?.fb_graph_version || "v21.0";
  const pageId = config.social?.fb_page_id;
  const pageName = config.social?.fb_page_name || "the page";
  if (!pageId) stop("wick.json has no social.fb_page_id");
  const dry = args.includes("--dry-run");
  const fromEnv = args.includes("--from-env");
  // The token already pasted into the file as fb_user_token: the case of a
  // renewal started by hand and left at "now read the Page token out".
  const fromSaved = args.includes("--from-saved");

  // 1. The fresh token.
  const source = fromSaved ? "the fb_user_token line of Wicksmodsinfo.txt" : fromEnv ? "FB_FRESH_TOKEN" : "the clipboard";
  const fresh = (fromSaved ? value(read(SECRETS), "fb_user_token") : fromEnv ? process.env.FB_FRESH_TOKEN || "" : clipboard()).trim();
  if (!TOKEN.test(fresh)) {
    stop(fromSaved || fromEnv
      ? `${source} does not hold a Facebook token (they start with EA)`
      : "the clipboard does not hold a Facebook token (they start with EA).\n  Copy the Access Token from the Graph API Explorer, then run this again. Steps: wick fb-token --help");
  }
  ok(`token read from ${source} (${fresh.length} characters)`);

  // 2. Whose it is and what it may do.
  const candidates = apps();
  if (!candidates.length) stop("no Facebook app id and secret found. Add fb_posting_app_id and fb_posting_app_secret to Wicksmodsinfo.txt");
  const seen = await inspect(fresh, candidates, v);
  if (!seen.app) {
    stop(`none of the ${candidates.length} app(s) on this machine issued that token, or Facebook does not accept it: ${seen.error}\n  If it came from another app, add that app's fb_posting_app_id and fb_posting_app_secret to Wicksmodsinfo.txt`);
  }
  const d = seen.data;
  if (!d.is_valid) stop(`that token is no longer valid: ${scrub(d.error?.message)}. Generate a new one in the Explorer`);
  const appName = d.application || `app ${d.app_id}`;
  // Posts made through an app in Development mode are shown only to people
  // with a role on the app: every release post from May to October 2026 was
  // hidden from the public that way. So the token has to come from the app
  // named as the posting app, not from whichever app the Explorer had open.
  const posting = config.social?.fb_posting_app_id;
  if (posting && d.app_id !== posting) {
    stop(`that token was issued by "${appName}", not by the posting app ${config.social.fb_posting_app_name || posting}.\n  Posts through an app in Development mode are hidden from the public. In the Explorer set Meta App to ${config.social.fb_posting_app_name || posting} and generate the token again`);
  }
  ok(`issued by ${appName}${posting ? ", the posting app" : ""}`);
  const missing = NEEDED.filter((s) => !(d.scopes || []).includes(s));
  if (missing.length) stop(`the token lacks ${missing.join(", ")}. Add ${missing.length > 1 ? "them" : "it"} under Permissions in the Explorer and generate the token again`);
  ok(`permissions: ${NEEDED.join(", ")}`);

  // 3 and 4. A long-lived user token, then the Page token it gives.
  let user = "", page = "";
  if (d.type === "PAGE") {
    if (String(d.profile_id) !== String(pageId)) stop(`that is a Page token for another page, not ${pageName}`);
    if (d.expires_at) stop(`that Page token ends on ${day(d.expires_at)}. Copy the User token from the Explorer instead, so a lasting one can be made`);
    page = fresh;
  } else {
    const ex = await graph(v, `oauth/access_token?grant_type=fb_exchange_token&client_id=${enc(seen.app.id)}&client_secret=${enc(seen.app.secret)}&fb_exchange_token=${enc(fresh)}`);
    if (!ex.access_token) stop(`Facebook would not extend the token: ${scrub(ex.error?.message)}`);
    user = ex.access_token;
    ok(`extended to a long-lived user token${ex.expires_in ? ` (about ${Math.round(ex.expires_in / 86400)} days)` : ""}`);
    const acc = await graph(v, `me/accounts?fields=id,name,access_token&limit=100&access_token=${enc(user)}`);
    if (acc.error) stop(`Facebook would not list the pages: ${scrub(acc.error.message)}`);
    const hit = (acc.data || []).find((p) => String(p.id) === String(pageId));
    if (!hit) {
      const names = (acc.data || []).map((p) => p.name).join(", ") || "no page at all";
      stop(`the token does not cover ${pageName}; it covers ${names}.\n  Generate it again and tick ${pageName} when Facebook asks which pages`);
    }
    page = hit.access_token;
  }

  // 5. The Page token, checked the way a post would use it.
  const pd = await inspect(page, [seen.app], v);
  if (!pd.app || !pd.data.is_valid) stop(`the Page token did not pass Facebook's own check: ${pd.error || scrub(pd.data?.error?.message)}`);
  if (pd.data.expires_at) stop(`the Page token would end on ${day(pd.data.expires_at)}, so it was not saved. A lasting one comes from a User token: copy that one from the Explorer`);
  const who = await graph(v, `${pageId}?fields=id,name&access_token=${enc(page)}`);
  if (who.error || String(who.id) !== String(pageId)) stop(`the page did not accept the new token: ${scrub(who.error?.message)}`);
  ok(`Page token for ${who.name}: accepted, no end date`);

  // 6. Save.
  if (dry) { console.log("\n(dry run: nothing written, clipboard left as it was)"); return; }
  const before = read(SECRETS);
  if (before === null) stop(`cannot read ${SECRETS}`);
  const note = `${new Date().toLocaleDateString("en-CA")} by wick fb-token (app: ${appName}; no end date)`;
  const { text, done } = rewrite(before, { fb_page_token: page, fb_user_token: user }, note);
  fs.writeFileSync(`${SECRETS}.bak`, before);
  fs.writeFileSync(SECRETS, text);
  if (savedPageToken() !== page && !process.env.FB_WICKS_MODS_PAGE_TOKEN) {
    fs.writeFileSync(SECRETS, before);
    stop("the file did not read back with the new token, so the old file was put back");
  }
  ok(`saved in Wicksmodsinfo.txt: ${done.join(", ")} (the old file is Wicksmodsinfo.txt.bak)`);
  if (process.env.FB_WICKS_MODS_PAGE_TOKEN) console.log("  note: FB_WICKS_MODS_PAGE_TOKEN is set and wins over the file; clear it or set it to the new token");
  if (!fromEnv && !fromSaved && clearClipboard()) ok("clipboard cleared");
  console.log("\nFacebook posting is back. Check any time with: wick fb-token --check");
}

export async function run(args = []) {
  if (args.includes("--help") || args.includes("-h")) { console.log(HELP); return; }
  const known = ["--check", "--dry-run", "--from-env", "--from-saved"];
  const unknown = args.filter((a) => !known.includes(a));
  if (unknown.length) { console.error(`✗ fb-token does not know ${unknown.join(", ")}. Flags: ${known.join(" ")}`); process.exitCode = 1; return; }
  const config = JSON.parse(fs.readFileSync(path.join(SUITE, "wick.json"), "utf8"));
  try {
    if (args.includes("--check")) {
      const c = await checkSaved(config);
      sayCheck(c);
      // The saved User token too: a live one is all --from-saved needs.
      const u = value(read(SECRETS), "fb_user_token");
      if (TOKEN.test(u)) {
        const d = await describe(u, config.social?.fb_graph_version || "v21.0");
        const lacks = d.known ? NEEDED.filter((s) => !d.scopes.includes(s)) : [];
        console.log(!d.known ? `  saved fb_user_token: Facebook does not accept it (${d.detail})`
          : !d.valid ? `  saved fb_user_token: no longer valid (${d.detail})`
          : `  saved fb_user_token: a live ${d.kind === "USER" ? "User" : d.kind} token from ${d.app.name || d.app.id}, ${d.expires ? `until ${d.expires}` : "no end date"}`
            + (lacks.length ? `; lacks ${lacks.join(", ")}` : "; has the permissions")
            + (c.state !== "ok" && d.kind === "USER" && !lacks.length ? "\n  That is enough to finish: wick fb-token --from-saved" : ""));
      }
      if (c.state !== "ok") process.exitCode = 1;
      return;
    }
    await renew(config, args);
  } catch (e) {
    if (!(e instanceof Stop)) throw e;
    console.error(`✗ ${e.message}`);
    console.error("  Nothing was written.");
    process.exitCode = 1;
  }
}
