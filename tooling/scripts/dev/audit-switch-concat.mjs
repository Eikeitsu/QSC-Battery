import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const norm = (s) =>
  s
    .replace(/\r\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/^\n+/, "")
    .replace(/\n+$/, "\n");

function stripEntry(s) {
  let lines = norm(s).split("\n");
  let i = 0;
  if (lines[i]?.startsWith("#!")) i++;
  while (i < lines.length && (lines[i].startsWith("#") || lines[i] === "")) i++;
  if (/common\.sh/.test(lines[i] || "")) i++;
  while (i < lines.length && lines[i] === "") i++;
  return lines.slice(i).join("\n").replace(/\n+$/, "\n");
}

function stripLib(s) {
  let lines = norm(s).split("\n");
  let i = 0;
  if (lines[i]?.startsWith("#!")) i++;
  while (i < lines.length && (lines[i].startsWith("#") || lines[i] === "")) i++;
  return lines.slice(i).join("\n").replace(/\n+$/, "\n");
}

const old = stripEntry(
  execSync("git show 4ec4639:module/bin/qsc_switch.sh", {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 8e6,
  }),
);
const neo = ["switch_prelude", "switch_charge_full", "switch_eval", "switch_apply"]
  .map((n) => stripLib(readFileSync(join(root, "module/bin/lib", `${n}.sh`), "utf8")))
  .join("")
  .replace(/\n+$/, "\n");

console.log("equal_exact", old === neo, "old", old.length, "neo", neo.length);

const a = old.split("\n");
const b = neo.split("\n");
let i = 0;
let j = 0;
let miss = 0;
while (i < a.length && j < b.length) {
  if (a[i] === b[j]) {
    i++;
    j++;
    continue;
  }
  if (a[i] === "") {
    i++;
    continue;
  }
  if (b[j] === "") {
    j++;
    continue;
  }
  miss++;
  if (miss <= 25) {
    console.log("MISMATCH", { i: i + 1, j: j + 1, old: a[i], neo: b[j] });
  }
  i++;
  j++;
}
console.log(
  "content_mismatches",
  miss,
  "remain_old",
  a.length - i,
  "remain_neo",
  b.length - j,
);

// Compare non-empty lines sequences
const an = a.filter((l) => l !== "");
const bn = b.filter((l) => l !== "");
let same = an.length === bn.length && an.every((l, k) => l === bn[k]);
console.log("equal_nonempty_lines", same, "counts", an.length, bn.length);
if (!same) {
  for (let k = 0; k < Math.min(an.length, bn.length); k++) {
    if (an[k] !== bn[k]) {
      console.log("first nonempty mismatch at", k + 1, { old: an[k], neo: bn[k] });
      break;
    }
  }
}
