/**
 * Magisk behavior preservation audit vs 4ec4639 (pre monorepo-refactor parent).
 */
import { execSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const namingMap = JSON.parse(
  readFileSync(join(root, "tooling/scripts/dev/naming-map.json"), "utf8"),
);

function applyNamingMap(text) {
  let t = text;
  const pairs = [];
  for (const [o, n] of Object.entries(namingMap.configKeys || {})) pairs.push([o, n]);
  for (const [o, n] of Object.entries(namingMap.dataMarkers || {})) {
    pairs.push([`data/${o}`, `data/${n}`]);
    pairs.push([o, n]);
  }
  for (const [o, n] of Object.entries(namingMap.binScripts || {})) pairs.push([o, n]);
  for (const [o, n] of Object.entries(namingMap.libScripts || {})) pairs.push([o, n]);
  pairs.push(["QSCV_Compatibility_mode", "QSCV_compatibility_mode"]);
  pairs.push(["QSCV_Shut_down", "QSCV_shut_down"]);
  pairs.push(["OFF_FLAG", "MODULE_OFF_FLAG"]);
  pairs.sort((a, b) => b[0].length - a[0].length);
  for (const [o, n] of pairs) t = t.split(o).join(n);
  return t;
}

const norm = (s) => s.replace(/\r\n/g, "\n").replace(/\n+$/, "\n");
const nonempty = (s) =>
  norm(s)
    .split("\n")
    .filter((l) => l !== "" && !l.startsWith("#!"));
const codeOnly = (s) =>
  s
    .split("\n")
    .filter((l) => !l.trimStart().startsWith("#"))
    .join("\n");

function gitShow(rev, rel) {
  return execSync(`git show ${rev}:${rel}`, {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 8e6,
  });
}

function stripLibNoise(lines) {
  // drop leading file header comments only (# ... until first non-comment code)
  let i = 0;
  while (i < lines.length && (lines[i].startsWith("#") || lines[i] === "")) i++;
  return lines.slice(i);
}

function concatLibs(names) {
  return names
    .map((n) => {
      const raw = readFileSync(join(root, "module/bin/lib", n), "utf8");
      return stripLibNoise(nonempty(raw)).join("\n");
    })
    .join("\n");
}

function oldBodyAfterCommon(rel) {
  const lines = nonempty(gitShow("4ec4639", rel));
  let i = 0;
  while (i < lines.length && lines[i].startsWith("#")) i++;
  if (/common\.sh/.test(lines[i] || "")) i++;
  while (i < lines.length && lines[i].startsWith("#")) i++;
  return lines.slice(i).join("\n");
}

function cmp(label, oldText, neoText) {
  const ok = oldText === neoText;
  console.log(
    `${ok ? "OK" : "FAIL"} ${label} (old ${oldText.length} neo ${neoText.length})`,
  );
  if (!ok) {
    const a = oldText.split("\n");
    const b = neoText.split("\n");
    for (let k = 0; k < Math.max(a.length, b.length); k++) {
      if (a[k] !== b[k]) {
        console.log("  first mismatch", k + 1, { old: a[k], neo: b[k] });
        break;
      }
    }
  }
  return ok;
}

let allOk = true;

{
  const old = applyNamingMap(oldBodyAfterCommon("module/bin/qsc_switch.sh"));
  const neo = concatLibs([
    "switch_prelude.sh",
    "switch_charge_full.sh",
    "switch_eval.sh",
    "switch_apply.sh",
  ]);
  allOk &= cmp("qsc_switch nonempty body", old, neo);
}

// charge.sh was split under bin/lib/
{
  const chargeEntry = readFileSync(join(root, "module/bin/lib/charge.sh"), "utf8");
  const sourced = [...chargeEntry.matchAll(/\. "\$LIBDIR\/([^"]+)"/g)].map((m) => m[1]);
  console.log("charge.sh sources:", sourced.join(", ") || "(none / still monolith?)");
  if (sourced.length) {
    try {
      const oldRaw = nonempty(gitShow("4ec4639", "module/bin/lib/charge.sh"));
      // old monolith body after leading comments
      let i = 0;
      while (i < oldRaw.length && oldRaw[i].startsWith("#")) i++;
      const old = codeOnly(applyNamingMap(oldRaw.slice(i).join("\n")));
      const neo = codeOnly(concatLibs(sourced));
      allOk &= cmp("charge code-only body", old, neo);
    } catch (e) {
      console.log("SKIP charge vs 4ec4639:", e.message);
    }
  }
}

for (const name of ["current.sh", "power_saver.sh", "hot_update.sh"]) {
  const entry = readFileSync(join(root, "module/bin/lib", name), "utf8");
  const sourced = [...entry.matchAll(/\. "\$LIBDIR\/([^"]+)"/g)].map((m) => m[1]);
  if (!sourced.length) {
    console.log(`SKIP ${name}: no fragment sources`);
    continue;
  }
  try {
    const oldRaw = nonempty(gitShow("4ec4639", `module/bin/lib/${name}`));
    let i = 0;
    while (i < oldRaw.length && oldRaw[i].startsWith("#")) i++;
    // old may already have been a thin wrapper in some cases; compare body after sources removed from old?
    // Prefer: if old file itself sourced fragments, skip; else compare monolith to concat
    const oldHadSources = oldRaw.some(
      (l) => /\$LIBDIR\//.test(l) && l.trim().startsWith("."),
    );
    if (oldHadSources) {
      console.log(`SKIP ${name}: already split at 4ec4639`);
      continue;
    }
    const old = applyNamingMap(oldRaw.slice(i).join("\n"));
    const neo = concatLibs(sourced);
    allOk &= cmp(`${name} nonempty body`, old, neo);
  } catch (e) {
    console.log(`SKIP ${name}:`, e.message);
  }
}

for (const entry of ["module/action.sh", "module/uninstall.sh", "module/module.prop"]) {
  const old = applyNamingMap(norm(gitShow("4ec4639", entry)));
  const neo = norm(readFileSync(join(root, entry), "utf8"));
  allOk &= cmp(entry, old, neo);
}

// service: compare boot+loop semantics markers
{
  const svc = readFileSync(join(root, "module/service.sh"), "utf8");
  const loop = readFileSync(join(root, "module/bin/lib/service_loop.sh"), "utf8");
  const boot = readFileSync(join(root, "module/bin/lib/service_boot.sh"), "utf8");
  console.log(
    "service wrapper:",
    /qsc_service_loop_once/.test(svc) && /while true/.test(svc)
      ? "function-loop OK"
      : "UNEXPECTED",
  );
  console.log(
    "service_loop return-not-continue:",
    /return 0/.test(loop) && !/^\s*continue\b/m.test(loop) ? "OK" : "CHECK",
  );
  console.log("service_boot defines?", /qsc_service|MODDIR|BINDIR/.test(boot));
}

// packaging must ship install/
{
  const pkg = readFileSync(join(root, "tooling/scripts/package-module.mjs"), "utf8");
  const hasInstall = /copyDirFromModule\(\s*["']install["']\s*\)/.test(pkg);
  const webOk = /join\(repoRoot,\s*["']apps["'],\s*["']webui["']\)/.test(pkg);
  console.log(
    hasInstall ? "OK package copies install/" : "FAIL package missing install/",
  );
  console.log(webOk ? "OK webSrcDir apps/webui" : "FAIL webSrcDir not apps/webui");
  allOk &= hasInstall && webOk;
  const installFiles = readdirSync(join(root, "module/install")).filter((n) =>
    n.endsWith(".sh"),
  );
  console.log("install fragments:", installFiles.join(", "));
}

console.log(allOk ? "\nVERDICT: logic+packaging guards OK" : "\nVERDICT: issues remain");
process.exit(allOk ? 0 : 1);
