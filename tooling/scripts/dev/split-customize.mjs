#!/usr/bin/env node
/**
 * Surgical customize.sh split: extract function-only fragments; keep flow intact.
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "../..");
const mod = join(root, "module");
const installDir = join(mod, "install");

function linesOf(path) {
  return readFileSync(path, "utf8").replace(/\r\n/g, "\n").split("\n");
}
function write(path, content) {
  writeFileSync(path, content.endsWith("\n") ? content : `${content}\n`, "utf8");
  console.log(
    `wrote ${path.slice(root.length + 1)} (~${content.split("\n").length} lines)`,
  );
}
function sliceJoin(lines, start1, end1) {
  return (
    lines
      .slice(start1 - 1, end1)
      .join("\n")
      .replace(/\n+$/, "") + "\n"
  );
}
function find1(lines, pred, from = 0) {
  for (let i = from; i < lines.length; i++) {
    if (pred(lines[i], i)) return i + 1;
  }
  throw new Error(`not found: ${pred}`);
}
function funcEnd1(lines, start1) {
  let depth = 0;
  let started = false;
  for (let i = start1 - 1; i < lines.length; i++) {
    const line = lines[i];
    const opens = (line.match(/{/g) || []).length;
    const closes = (line.match(/}/g) || []).length;
    if (opens) {
      depth += opens;
      started = true;
    }
    if (closes) depth -= closes;
    if (started && depth <= 0) return i + 1;
  }
  throw new Error(`func end not found at ${start1}`);
}

mkdirSync(installDir, { recursive: true });
const p = join(mod, "customize.sh");
if (readFileSync(p, "utf8").includes("install/helpers.sh")) {
  console.log("already split");
  process.exit(0);
}

const L = linesOf(p);

const abortAt = find1(L, (l) => l.startsWith("qsc_abort()"));
const abortEnd = funcEnd1(L, abortAt);
const confValAt = find1(L, (l) => l.startsWith("qsc_conf_value()"));
const confTokAt = find1(L, (l) => l.startsWith("qsc_conf_token()"));
const mergeAt = find1(L, (l) => l.startsWith("qsc_merge_config()"));
const mergeEnd = funcEnd1(L, mergeAt);

const oldNameAt = find1(L, (l) => l.startsWith("qsc_old_module_name()"));
const uninstallAt = find1(L, (l) => l.startsWith("qsc_uninstall_old_module()"));
const uninstallEnd = funcEnd1(L, uninstallAt);

const qscdPrefAt = find1(L, (l) => l.startsWith("qscd_conf_pref()"));
const installQscdAt = find1(L, (l) => l.startsWith("install_qscd()"));
const installQscdEnd = funcEnd1(L, installQscdAt);

const companionAt = find1(L, (l) => l.startsWith("install_companion_app()"));
const companionEnd = funcEnd1(L, companionAt);

const cliAt = find1(L, (l) => l.startsWith("install_qsc_cli()"));
const cliEnd = funcEnd1(L, cliAt);

write(
  join(installDir, "helpers.sh"),
  `#!/system/bin/sh\n# install helpers\n${sliceJoin(L, abortAt, abortEnd)}${sliceJoin(L, confValAt, mergeEnd)}`,
);
write(
  join(installDir, "migrate.sh"),
  `#!/system/bin/sh\n# old module helpers\n${sliceJoin(L, oldNameAt, uninstallEnd)}`,
);
write(
  join(installDir, "qscd.sh"),
  `#!/system/bin/sh\n# qscd install helpers\n${sliceJoin(L, qscdPrefAt, installQscdEnd)}`,
);
write(
  join(installDir, "companion.sh"),
  `#!/system/bin/sh\n# companion APK\n${sliceJoin(L, companionAt, companionEnd)}`,
);
write(
  join(installDir, "cli.sh"),
  `#!/system/bin/sh\n# CLI install\n${sliceJoin(L, cliAt, cliEnd)}`,
);

const drop = [
  [abortAt, abortEnd],
  [confValAt, mergeEnd],
  [oldNameAt, uninstallEnd],
  [qscdPrefAt, installQscdEnd],
  [companionAt, companionEnd],
  [cliAt, cliEnd],
];
const keep = [];
for (let i = 0; i < L.length; i++) {
  const n1 = i + 1;
  if (drop.some(([a, b]) => n1 >= a && n1 <= b)) continue;
  keep.push(L[i]);
}

// After QSC_INSTALL_AUTO block (first occurrence of install_auto path check's closing fi)
let insertAt = keep.findIndex((l) => l.includes("/data/adb/qsc/install_auto"));
if (insertAt < 0) throw new Error("install_auto marker missing");
while (insertAt < keep.length && keep[insertAt] !== "fi") insertAt++;
insertAt += 1;

keep.splice(
  insertAt,
  0,
  "",
  "# install fragments（customize.sh 文件名冻结）",
  '. "$MODPATH/install/helpers.sh"',
  '. "$MODPATH/install/migrate.sh"',
  '. "$MODPATH/install/qscd.sh"',
  '. "$MODPATH/install/companion.sh"',
  '. "$MODPATH/install/cli.sh"',
  "",
);

let text = keep.join("\n");
text = text.replace(
  'rm -f "$MODPATH/bin/lib/current.sh"',
  'rm -f "$MODPATH/bin/lib/current.sh" "$MODPATH/bin/lib/current_limits.sh" \\\n\t\t"$MODPATH/bin/lib/current_bypass.sh" "$MODPATH/bin/lib/current_apply.sh"',
);

write(p, text.replace(/\n+$/, "") + "\n");
console.log(`customize.sh now ~${text.split("\n").length} lines`);
