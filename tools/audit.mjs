// wick audit: read-only state of every Wick addon folder, as a table and as JSON.
//
//   wick audit            local checks: git, versions, TOC header, files, README
//   wick audit --remote   also CurseForge's newest file and the GitHub repo settings
//   wick audit --json     print the JSON instead of the table
//
// The JSON goes to shared-memory/state/suite-audit.json, the one file Claude,
// Codex and any later dashboard read for "where does the suite stand". Nothing
// here writes to an addon, a repo or CurseForge. Exit code 1 when a check fails.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const TOOLS = path.dirname(fileURLToPath(import.meta.url));
const SUITE = path.dirname(TOOLS);
const EM = "—";

const git = (dir, ...args) => {
  try { return execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); }
  catch { return ""; }
};
const read = p => (fs.existsSync(p) ? fs.readFileSync(p, "utf8") : null);
const tocField = (toc, key) => ((toc || "").match(new RegExp(`^##\\s*${key}\\s*:\\s*(.*?)\\s*$`, "mi")) || [])[1] || null;

function trees(config) {
  const seen = new Set(), out = [];
  for (const [client, c] of Object.entries(config.clients)) {
    if (!fs.existsSync(c.addons_root)) continue;
    for (const name of fs.readdirSync(c.addons_root)) {
      if (!/^Wick/.test(name)) continue;
      const dir = path.join(c.addons_root, name);
      if (!fs.existsSync(path.join(dir, ".git"))) continue;
      const real = fs.realpathSync(dir);
      if (seen.has(real)) continue;                       // a junction to a folder already counted
      seen.add(real);
      const entries = config.addons.filter(a => a.folder === name);
      const entry = entries.find(a => (a.client || "tbc") === client) || entries.find(a => a.client === "both") || null;
      out.push({ folder: name, dir: real, client: entry?.client || client, home: client, entry });
    }
  }
  return out;
}

function checkTree(t) {
  const issues = [];
  const e = t.entry;
  const toc = read(path.join(t.dir, `${t.folder}.toc`));
  const version = tocField(toc, "Version");
  const status = git(t.dir, "status", "--porcelain", "--branch").split("\n");
  const head = status[0] || "";
  const dirty = status.slice(1).filter(Boolean).length;
  const ahead = +((head.match(/ahead (\d+)/) || [])[1] || 0);
  const behind = +((head.match(/behind (\d+)/) || [])[1] || 0);
  const branch = git(t.dir, "rev-parse", "--abbrev-ref", "HEAD");
  const tags = git(t.dir, "tag", "--sort=-creatordate").split("\n").filter(Boolean);
  const want = t.home === "forever" && t.client === "forever" ? [/^forever-v/, /^v\d/] : [/^v\d/, /^forever-v/];
  const tag = want.map(re => tags.find(x => re.test(x))).find(Boolean) || null;
  const tagVer = tag ? tag.replace(/^(forever-)?v/, "") : null;
  const log = read(path.join(t.dir, "CHANGELOG.md"));
  const logHead = ((log || "").match(/^##\s+(.+?)\s*$/m) || [])[1] || null;
  const unreleased = /^\(?unreleased\)?$/i.test(logHead || "");
  const pending = dirty > 0 || ahead > 0 || unreleased;

  if (behind) issues.push(`behind its remote by ${behind}`);
  if (!e) return { ...base(), listed: false, issues };          // internal or unlisted: git state only
  if (e.benched) return { ...base(), listed: true, benched: true, issues };

  if (!toc) issues.push("no .toc");
  if (!log) issues.push("no CHANGELOG.md");
  if (version && tagVer && version !== tagVer && !pending) issues.push(`TOC says ${version}, newest tag is ${tag}`);
  if (version && logHead && !unreleased && !logHead.startsWith(version)) issues.push(`CHANGELOG starts at "${logHead}", TOC says ${version}`);
  if (logHead && !unreleased && !/^\d+\.\d+\.\d+( \(\d{4}-\d{2}-\d{2}\))?$/.test(logHead)) issues.push(`CHANGELOG heading "${logHead}" is not "X.Y.Z (YYYY-MM-DD)"`);

  const title = tocField(toc, "Title") || "";
  if (!title.includes("|cffD4C8A1")) issues.push("TOC title is not two-tone");
  if (!tocField(toc, "IconTexture")) issues.push("TOC has no IconTexture");
  if (tocField(toc, "Category") !== "Wick's Mods") issues.push("TOC Category is not Wick's Mods");
  if (!tocField(toc, "X-Website")) issues.push("TOC has no X-Website");
  if (!tocField(toc, "X-License")) issues.push("TOC has no X-License");
  if (e.cf_project_id && tocField(toc, "X-Curse-Project-ID") !== String(e.cf_project_id)) issues.push("TOC X-Curse-Project-ID does not match wick.json");

  for (const f of ["README.md", "LICENSE", "logo.svg", ".gitignore"])
    if (!fs.existsSync(path.join(t.dir, f))) issues.push(`no ${f}`);
  const lic = read(path.join(t.dir, "LICENSE"));
  if (lic && !lic.includes(`"${e.title}"`)) issues.push("LICENSE carve-out does not name this addon");
  if (lic && !/NOT licensed under the MIT/.test(lic)) issues.push("LICENSE has no trademark carve-out");
  const readme = read(path.join(t.dir, "README.md"));
  if (readme) {
    if (!readme.includes("wick:badges:start")) issues.push("README has no badge row");
    if (!readme.includes("wick:suite-table:start")) issues.push("README has no suite table");
    if (readme.includes(EM)) issues.push("README has an em-dash");
    if (!/^<p align="center"><img/.test(readme.trimStart())) issues.push("README has no banner image");
  }
  return { ...base(), listed: true, issues };

  function base() {
    return { folder: t.folder, dir: t.dir, client: t.client, home: t.home, repo: e?.repo || null, cf_project_id: e?.cf_project_id || null,
             branch, version, tag, changelog: logHead, dirty, ahead, behind, pending };
  }
}

async function remote(config, rows) {
  const ua = { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36" };
  const label = { tbc: config.clients.tbc.label, forever: config.clients.forever.label };
  const cache = new Map();
  for (const r of rows.filter(x => x.listed && !x.benched && x.cf_project_id)) {
    try {
      if (!cache.has(r.cf_project_id)) {
        const res = await fetch(`https://www.curseforge.com/api/v1/mods/${r.cf_project_id}/files?pageSize=8&sort=dateCreated&sortDescending=true`, { headers: ua });
        cache.set(r.cf_project_id, res.ok ? (await res.json()).data || [] : null);
      }
      const files = cache.get(r.cf_project_id);
      if (files === null) { r.cf = { state: "unreachable" }; continue; }
      const isForever = f => /Forever/i.test(f.displayName) || (f.gameVersions || []).some(v => /^1\.6/.test(v));
      const mine = r.home === "forever" && r.client === "forever" ? files.find(isForever) : files.find(f => !/\(World of Warcraft: Forever\)/.test(f.displayName)) || files[0];
      const ver = ((mine?.displayName || "").match(/v(\d+\.\d+\.\d+)/) || [])[1] || null;
      r.cf = { newest: ver, date: (mine?.dateCreated || "").slice(0, 10) };
      const tagVer = r.tag ? r.tag.replace(/^(forever-)?v/, "") : null;
      if (!files.length) { if (tagVer) r.issues.push("tagged, but CurseForge has no file"); }
      else if (tagVer && ver && ver !== tagVer) {
        // An upload sits in CurseForge's review queue before the public file
        // list shows it. A tag under two days old is waiting, not adrift.
        let age = Infinity;
        try {
          age = Date.now() / 1000 - Number(execFileSync("git", ["-C", r.dir, "log", "-1", "--format=%ct", r.tag], { encoding: "utf8" }).trim());
        } catch {}
        if (age < 2 * 86400) r.cf.awaiting = tagVer;
        else r.issues.push(`CurseForge's newest is ${ver}, newest tag is ${r.tag}`);
      }
    } catch { r.cf = { state: "unreachable" }; }
  }
  try {
    const list = JSON.parse(execFileSync("gh", ["repo", "list", config.github_user, "--limit", "100", "--json",
      "name,description,homepageUrl,repositoryTopics,licenseInfo,defaultBranchRef,isArchived"], { encoding: "utf8" }));
    const by = Object.fromEntries(list.map(x => [x.name, x]));
    const done = new Set();
    for (const r of rows.filter(x => x.listed && !x.benched && x.repo && !done.has(x.repo))) {
      done.add(r.repo);
      const g = by[r.repo];
      if (!g) { r.issues.push(`GitHub repo ${r.repo} not found`); continue; }
      r.github = { default_branch: g.defaultBranchRef?.name || null, topics: (g.repositoryTopics || []).length, homepage: g.homepageUrl || null };
      if (!g.description) r.issues.push("GitHub repo has no description");
      else if (g.description.includes(EM)) r.issues.push("GitHub description has an em-dash");
      if (!g.homepageUrl) r.issues.push("GitHub repo has no homepage");
      if ((g.repositoryTopics || []).length < 5) r.issues.push("GitHub repo has fewer than five topics");
      if (!g.licenseInfo) r.issues.push("GitHub sees no LICENSE on the default branch");
    }
  } catch { /* gh missing or offline: local results still stand */ }
}

export async function run(args = []) {
  const config = JSON.parse(fs.readFileSync(path.join(SUITE, "wick.json"), "utf8"));
  const rows = trees(config).map(checkTree).sort((a, b) => a.folder.localeCompare(b.folder) || a.home.localeCompare(b.home));
  if (args.includes("--remote")) await remote(config, rows);

  const listed = rows.filter(r => r.listed && !r.benched);
  const report = {
    generated: new Date().toISOString(),
    remote: args.includes("--remote"),
    summary: {
      folders: rows.length,
      checked: listed.length,
      with_issues: rows.filter(r => r.issues.length).length,
      issues: rows.reduce((n, r) => n + r.issues.length, 0),
      pending_release: listed.filter(r => r.pending).map(r => `${r.folder}${r.home === "forever" && r.client !== "both" ? " (forever)" : ""}`),
      awaiting_curseforge: listed.filter(r => r.cf?.awaiting).map(r => `${r.folder}${r.home === "forever" && r.client !== "both" ? " (forever)" : ""} ${r.cf.awaiting}`),
    },
    addons: rows,
  };
  const home = config.project_home || path.dirname(SUITE);
  const outDir = path.join(home, "shared-memory", "state");
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, "suite-audit.json");
  fs.writeFileSync(outFile, JSON.stringify(report, null, 2) + "\n");

  if (args.includes("--json")) { console.log(JSON.stringify(report, null, 2)); }
  else {
    for (const r of rows) {
      const state = r.issues.length ? "ISSUE  " : !r.listed ? "unlisted" : r.benched ? "benched" : r.pending ? "pending" : r.cf?.awaiting ? "cf wait" : "ok     ";
      const where = `${r.folder}${r.home === "forever" ? " [forever]" : ""}`;
      console.log(`${state.padEnd(8)} ${where.padEnd(36)} ${String(r.version || "-").padEnd(8)} ${String(r.tag || "-").padEnd(16)} ${r.branch}${r.dirty ? `  ${r.dirty} changed` : ""}${r.ahead ? `  ${r.ahead} unpushed` : ""}`);
      for (const i of r.issues) console.log(`           - ${i}`);
    }
    const s = report.summary;
    console.log(`\n${s.folders} folders, ${s.checked} checked, ${s.issues} issue(s) in ${s.with_issues}, ${s.pending_release.length} with unreleased work`
      + (s.awaiting_curseforge.length ? `, ${s.awaiting_curseforge.length} uploaded and waiting on CurseForge's review` : ""));
    console.log(`state written to ${outFile}`);
  }
  if (report.summary.issues) process.exitCode = 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await run(process.argv.slice(2));
