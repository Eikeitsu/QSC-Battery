import { execSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const old = execSync("git show 4ec4639:module/customize.sh", {
  cwd: root,
  encoding: "utf8",
  maxBuffer: 8e6,
});
const funcs = [...old.matchAll(/^([a-zA-Z_][a-zA-Z0-9_]*)\(\)\s*\{/gm)].map((m) => m[1]);
const install = readdirSync(join(root, "module/install"))
  .filter((f) => f.endsWith(".sh"))
  .map((f) => readFileSync(join(root, "module/install", f), "utf8"))
  .join("\n");
const cust = readFileSync(join(root, "module/customize.sh"), "utf8");
const all = `${install}\n${cust}`;
const missing = funcs.filter((f) => !new RegExp(`${f}\\s*\\(\\s*\\)`).test(all));
console.log("old customize funcs", funcs.length);
console.log("missing after split", missing.length ? missing.join(", ") : "(none)");
console.log(
  "opt-out deletes current fragments",
  /current_limits\.sh/.test(cust) && /current_bypass\.sh/.test(cust),
);
