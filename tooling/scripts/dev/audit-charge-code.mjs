import { execSync } from "node:child_process";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const out = [];
const log = (...a) => {
  out.push(a.map(String).join(" "));
  console.log(...a);
};

const nonempty = (s) =>
  s
    .replace(/\r\n/g, "\n")
    .split("\n")
    .filter((l) => l !== "" && !l.startsWith("#!"));
function strip(lines) {
  let i = 0;
  while (i < lines.length && lines[i].startsWith("#")) i++;
  return lines.slice(i);
}

const old = strip(
  nonempty(
    execSync("git show 4ec4639:module/bin/lib/charge.sh", {
      cwd: root,
      encoding: "utf8",
      maxBuffer: 8e6,
    }),
  ),
);
const parts = [
  "charge_nodes.sh",
  "charge_write.sh",
  "charge_mca.sh",
  "charge_unplug.sh",
  "charge_restore.sh",
];
const neo = parts.flatMap((n) =>
  strip(nonempty(readFileSync(join(root, "module/bin/lib", n), "utf8"))),
);

const oc = old.filter((l) => !l.trimStart().startsWith("#"));
const nc = neo.filter((l) => !l.trimStart().startsWith("#"));
log(
  "equal_code_only",
  oc.length === nc.length && oc.every((l, i) => l === nc[i]),
  oc.length,
  nc.length,
);
if (!(oc.length === nc.length && oc.every((l, i) => l === nc[i]))) {
  for (let i = 0; i < Math.min(oc.length, nc.length); i++) {
    if (oc[i] !== nc[i]) {
      log("code mismatch", i + 1);
      log("OLD", oc[i]);
      log("NEO", nc[i]);
      // context
      log("OLD ctx", oc.slice(Math.max(0, i - 2), i + 5).join(" || "));
      log("NEO ctx", nc.slice(Math.max(0, i - 2), i + 5).join(" || "));
      break;
    }
  }
  const os = new Set(oc);
  const ns = new Set(nc);
  log(
    "only_old",
    [...os]
      .filter((x) => !ns.has(x))
      .slice(0, 20)
      .join("\n"),
  );
  log(
    "only_neo",
    [...ns]
      .filter((x) => !os.has(x))
      .slice(0, 20)
      .join("\n"),
  );
}

mkdirSync(join(root, ".build"), { recursive: true });
writeFileSync(join(root, ".build/charge-audit.txt"), out.join("\n"), "utf8");
