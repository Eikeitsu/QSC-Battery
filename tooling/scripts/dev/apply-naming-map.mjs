/**
 * Apply tooling/scripts/dev/naming-map.json across the repo (files + text refs).
 * Dev codemod only; device cutover is wipe-on-install (migrate.sh), not dual-read.
 */
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const map = JSON.parse(
  readFileSync(join(root, "tooling/scripts/dev/naming-map.json"), "utf8"),
);

const TEXT_EXTS = new Set([
  ".sh",
  ".ts",
  ".vue",
  ".kt",
  ".kts",
  ".conf",
  ".mjs",
  ".js",
  ".cjs",
  ".py",
  ".yml",
  ".yaml",
  ".md",
  ".json",
  ".scss",
  ".css",
  ".html",
  ".prop",
  ".txt",
]);

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    if (
      name === "node_modules" ||
      name === ".git" ||
      name === ".build" ||
      name === "release" ||
      name === "archives"
    ) {
      continue;
    }
    const p = join(dir, name);
    let st;
    try {
      st = statSync(p);
    } catch {
      continue;
    }
    if (st.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

function renamePath(oldRel, newRel) {
  const from = join(root, oldRel);
  const to = join(root, newRel);
  if (!existsSync(from)) {
    if (existsSync(to)) {
      console.log(`skip rename (already): ${oldRel} -> ${newRel}`);
      return;
    }
    console.warn(`missing: ${oldRel}`);
    return;
  }
  mkdirSync(dirname(to), { recursive: true });
  if (existsSync(to)) {
    console.log(`target exists, removing old ${oldRel}`);
    unlinkSync(from);
    return;
  }
  renameSync(from, to);
  console.log(`renamed ${oldRel} -> ${newRel}`);
}

// --- file renames ---
for (const [oldName, newName] of Object.entries(map.binScripts)) {
  renamePath(`module/bin/${oldName}`, `module/bin/${newName}`);
}
for (const [oldName, newName] of Object.entries(map.libScripts)) {
  renamePath(`module/bin/lib/${oldName}`, `module/bin/lib/${newName}`);
}
for (const [oldName, newName] of Object.entries(map.toolingScripts)) {
  renamePath(`tooling/scripts/${oldName}`, `tooling/scripts/${newName}`);
}

// --- text replacements (longest keys first to avoid partial overlaps) ---
const replacements = [];
for (const [o, n] of Object.entries(map.configKeys)) {
  replacements.push([o, n]);
}
for (const [o, n] of Object.entries(map.dataMarkers)) {
  // path-ish and bare token
  replacements.push([`data/${o}`, `data/${n}`]);
  replacements.push([`DATADIR}/${o}`, `DATADIR}/${n}`]);
  replacements.push([`DATADIR/${o}`, `DATADIR/${n}`]);
  replacements.push([`"$DATADIR/${o}"`, `"$DATADIR/${n}"`]);
  replacements.push([`'$DATADIR/${o}'`, `'$DATADIR/${n}'`]);
  replacements.push([`/${o}"`, `/${n}"`]); // ModulePaths style "$DATADIR/off_qsc"
}
for (const [o, n] of Object.entries(map.binScripts)) {
  replacements.push([o, n]);
}
for (const [o, n] of Object.entries(map.libScripts)) {
  replacements.push([o, n]);
}
for (const [o, n] of Object.entries(map.toolingScripts)) {
  replacements.push([o, n]);
}
// Variable names tied to off_qsc marker
replacements.push(["off_qsc", "module_off"]);
replacements.push(["OFF_FLAG", "MODULE_OFF_FLAG"]);
replacements.push(["QSCV_Compatibility_mode", "QSCV_compatibility_mode"]);
replacements.push(["QSCV_Shut_down", "QSCV_shut_down"]);

replacements.sort((a, b) => b[0].length - a[0].length);

const skipRel = new Set([
  "tooling/scripts/dev/naming-map.json",
  "tooling/scripts/dev/apply-naming-map.mjs",
]);

let filesTouched = 0;
for (const abs of walk(root)) {
  const rel = relative(root, abs).replace(/\\/g, "/");
  if (skipRel.has(rel)) continue;
  if (rel.startsWith("apps/android/.gradle")) continue;
  const ext = abs.includes(".") ? abs.slice(abs.lastIndexOf(".")) : "";
  if (!TEXT_EXTS.has(ext) && !abs.endsWith("module.prop")) continue;
  let text = readFileSync(abs, "utf8");
  // skip binary-ish
  if (text.includes("\u0000")) continue;
  let next = text;
  for (const [o, n] of replacements) {
    if (next.includes(o)) next = next.split(o).join(n);
  }
  if (next !== text) {
    writeFileSync(abs, next, "utf8");
    filesTouched++;
    console.log(`rewrote ${rel}`);
  }
}

// Compat stubs disabled (layout cutover wipes pre-cutover installs)
if ((map.compatStubs || []).length) {
  const stubDir = join(root, "module/bin");
  for (const oldName of map.compatStubs) {
    const newName = map.binScripts[oldName];
    if (!newName) continue;
    const stubPath = join(stubDir, oldName);
    const body = `#!/system/bin/sh
# compat stub -> ${newName}
exec "\${0%/*}/${newName}" "$@"
`;
    writeFileSync(stubPath, body, "utf8");
    console.log(`stub ${oldName} -> ${newName}`);
  }
}

console.log(`done. filesTouched=${filesTouched}`);
