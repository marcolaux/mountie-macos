#!/usr/bin/env node
/**
 * publish — push the built website to GitHub Pages.
 *
 *   npm run build && npm run publish          # publish, or report "nothing to do"
 *   npm run publish -- --check               # verify dist + report drift, write nothing
 *
 * WHERE AND WHY. The site is served by GitHub Pages from this repo itself —
 * `marcolaux/mountie-macos` is public — on its own branch, `gh-pages`, so
 * `main` keeps doing what it does. Nothing here touches `main`.
 *
 * HOW. The Git Data API, through `gh`: upload the blobs the branch does not
 * already have, build one tree, commit it with NO parent, and force the ref
 * to it. An orphan commit every time is deliberate — a Vite build renames
 * every hashed asset, and a branch that accumulated them would carry every
 * build ever made. There is no clone, no temp directory and no working copy
 * to leave behind, and auth is `gh`'s own (`gh auth status`), never a token
 * in this repo.
 *
 * Before anything is uploaded, the dist is checked for the things Pages needs
 * and a publish cannot take back: `CNAME` must equal `site.config.json`'s
 * domain (Pages forgets a custom domain the moment a deploy lacks the file),
 * `.nojekyll` must exist, both languages must be in the bundle, and the size
 * budgets hold. `--check` stops after those and the drift report.
 *
 * ONE-TIME SETUP, by hand, after the first publish: in the repo, Settings →
 * Pages → Source: branch `gh-pages`, folder `/`; Custom domain: the hostname
 * in `site.config.json`; wait for the certificate, then Enforce HTTPS.
 * DNS: `CNAME mountie → marcolaux.github.io`. Verify the domain under your
 * user Settings → Pages so nobody else can claim it.
 *
 * Adapted from hypha's scripts/site-publish.mjs; same house style.
 */
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { resolve, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

const SITE = resolve(fileURLToPath(import.meta.url), "../..");
const DIST = join(SITE, "dist");
const CONFIG = JSON.parse(readFileSync(join(SITE, "site.config.json"), "utf8"));
const REPO = CONFIG.releasesRepo;
const BRANCH = CONFIG.pagesBranch;

const BUDGET = {
  jsGzip: 150 * 1024, // every JS chunk, gzipped, together
  image: 250 * 1024, // any one image
  total: 4 * 1024 * 1024 // the whole dist — four screenshots, one font, the icons
};

const checkOnly = process.argv.includes("--check");

const log = (m) => process.stdout.write(`${m}\n`);
function fail(msg, hint) {
  process.stderr.write(`\n\x1b[31m✗ publish: ${msg}\x1b[0m\n`);
  if (hint) process.stderr.write(`  ${hint}\n`);
  process.exit(1);
}

function gh(args, opts = {}) {
  try {
    // stderr piped, not inherited: the first publish looks the branch up
    // before it exists, and `gh`'s own "Not Found" line would otherwise print
    // above the script's explanation of exactly that.
    return execFileSync("gh", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["pipe", "pipe", "pipe"], ...opts }).trim();
  } catch (e) {
    const stderr = (e.stderr ?? "").toString().trim();
    const err = new Error(stderr || e.message);
    err.stderr = stderr;
    throw err;
  }
}
const ghJson = (args, opts) => JSON.parse(gh(args, opts));

/** Every file under dist, as `{ path, bytes }` with POSIX paths. */
function walk(dir, base = dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full, base));
    else out.push({ path: relative(base, full).split(sep).join("/"), bytes: readFileSync(full) });
  }
  return out.sort((a, b) => a.path.localeCompare(b.path));
}

/** Git's own blob id, so unchanged files are recognised without uploading. */
const blobSha = (bytes) =>
  createHash("sha1").update(`blob ${bytes.length}\0`).update(bytes).digest("hex");

const kb = (n) => `${(n / 1024).toFixed(1)} KB`;

/* ── 1. The dist exists and is what Pages needs ──────────────────────────── */

if (!existsSync(join(DIST, "index.html"))) fail("website/dist has no index.html", "run `npm run build` first");
const files = walk(DIST);
const byPath = new Map(files.map((f) => [f.path, f]));

const cname = byPath.get("CNAME")?.bytes.toString("utf8").trim();
if (cname !== CONFIG.domain) fail(`dist/CNAME is ${JSON.stringify(cname)}, site.config.json says ${JSON.stringify(CONFIG.domain)}`);
if (!byPath.has(".nojekyll")) fail("dist/.nojekyll is missing", "website/public/.nojekyll must exist");

const html = byPath.get("index.html").bytes.toString("utf8");
if (!/<html[^>]*\blang="en"/.test(html)) fail("index.html does not declare lang=\"en\"");

// Both languages are in the shipped JS: the German hero title and the English
// one. Read from the catalogs, so the check follows the copy.
const heroTitle = (file) => {
  const src = readFileSync(join(SITE, "src/i18n", file), "utf8");
  const m = /title:\s*"([^"]+)"/.exec(src);
  if (!m) fail(`could not find hero.title in ${file}`);
  return m[1];
};
const js = files.filter((f) => f.path.endsWith(".js"));
const jsText = js.map((f) => f.bytes.toString("utf8")).join("\n");
for (const file of ["en.ts", "de.ts"]) {
  const title = heroTitle(file);
  if (!jsText.includes(title)) fail(`the bundle does not contain the ${file} hero title ${JSON.stringify(title)}`);
}

const jsGzip = js.reduce((n, f) => n + gzipSync(f.bytes).length, 0);
const total = files.reduce((n, f) => n + f.bytes.length, 0);
const bigImages = files.filter((f) => /\.(avif|webp|png|jpe?g)$/.test(f.path) && f.bytes.length > BUDGET.image);
log(`  dist: ${files.length} files, ${kb(total)} total, JS ${kb(jsGzip)} gzipped`);
if (jsGzip > BUDGET.jsGzip) fail(`JS is ${kb(jsGzip)} gzipped; the budget is ${kb(BUDGET.jsGzip)}`);
if (bigImages.length) fail(`images over ${kb(BUDGET.image)}: ${bigImages.map((f) => `${f.path} (${kb(f.bytes.length)})`).join(", ")}`);
if (total > BUDGET.total) fail(`dist is ${kb(total)}; the budget is ${kb(BUDGET.total)}`);

/* ── 2. What the branch holds now ────────────────────────────────────────── */

try {
  gh(["auth", "status"], { stdio: ["ignore", "pipe", "pipe"] });
} catch {
  fail("gh is not authenticated", "run `gh auth login`");
}

let remote = null; // { sha, tree: Map<path, blobSha> }
try {
  const ref = ghJson(["api", `repos/${REPO}/git/ref/heads/${BRANCH}`]);
  const tree = ghJson(["api", `repos/${REPO}/git/trees/${ref.object.sha}?recursive=1`]);
  remote = { sha: ref.object.sha, tree: new Map(tree.tree.filter((t) => t.type === "blob").map((t) => [t.path, t.sha])) };
} catch (e) {
  if (!/404|Not Found/i.test(e.stderr ?? "")) throw e;
}

const local = new Map(files.map((f) => [f.path, blobSha(f.bytes)]));
const changed = files.filter((f) => remote?.tree.get(f.path) !== local.get(f.path));
const removed = remote ? [...remote.tree.keys()].filter((p) => !local.has(p)) : [];

if (remote && changed.length === 0 && removed.length === 0) {
  log(`publish: ${REPO}@${BRANCH} already holds this build — nothing to do`);
  process.exit(0);
}
log(`  ${remote ? `branch ${BRANCH} @ ${remote.sha.slice(0, 7)}` : `branch ${BRANCH} does not exist yet`}`);
log(`  ${changed.length} file(s) to upload, ${removed.length} to drop`);
if (checkOnly) {
  for (const f of changed) log(`    ~ ${f.path}`);
  for (const p of removed) log(`    - ${p}`);
  fail(`${REPO}@${BRANCH} differs from the local build (--check: not written)`, "run `npm run publish` to publish it");
}

/* ── 3. Blobs → tree → orphan commit → ref ───────────────────────────────── */

// A blob the branch already has under ANY path can be reused by sha; the
// tree names it and Git does the rest.
const known = new Set(remote ? remote.tree.values() : []);
let uploaded = 0;
for (const f of changed) {
  const sha = local.get(f.path);
  if (known.has(sha)) continue;
  const res = ghJson(["api", "--method", "POST", `repos/${REPO}/git/blobs`, "--input", "-"], {
    input: JSON.stringify({ content: f.bytes.toString("base64"), encoding: "base64" })
  });
  if (res.sha !== sha) fail(`blob sha mismatch for ${f.path}: local ${sha}, GitHub ${res.sha}`);
  known.add(sha);
  uploaded += 1;
}
log(`  uploaded ${uploaded} blob(s)`);

const tree = ghJson(["api", "--method", "POST", `repos/${REPO}/git/trees`, "--input", "-"], {
  input: JSON.stringify({ tree: files.map((f) => ({ path: f.path, mode: "100644", type: "blob", sha: local.get(f.path) })) })
});

const commit = ghJson(["api", "--method", "POST", `repos/${REPO}/git/commits`, "--input", "-"], {
  input: JSON.stringify({
    message: `site: build for ${CONFIG.domain} (Mountie ${CONFIG.version})`,
    tree: tree.sha,
    parents: []
  })
});

if (remote) {
  gh(["api", "--method", "PATCH", `repos/${REPO}/git/refs/heads/${BRANCH}`, "--input", "-"], {
    input: JSON.stringify({ sha: commit.sha, force: true })
  });
} else {
  gh(["api", "--method", "POST", `repos/${REPO}/git/refs`, "--input", "-"], {
    input: JSON.stringify({ ref: `refs/heads/${BRANCH}`, sha: commit.sha })
  });
}

log(`publish: ${REPO}@${BRANCH} → ${commit.sha.slice(0, 7)}`);
log(`  https://${CONFIG.domain}/  (Pages rebuilds within a minute or two)`);
if (!remote) {
  log("  FIRST PUBLISH: now enable Pages on the branch — Settings → Pages → Source: gh-pages / (root),");
  log(`  Custom domain: ${CONFIG.domain}, then Enforce HTTPS once the certificate is issued.`);
}
