import { readFileSync, writeFileSync, mkdirSync } from "fs";
mkdirSync(".build", { recursive: true });
const s = readFileSync(".build/old-ucc.vue");
// detect encoding
let t;
try {
  t = s.toString("utf8");
} catch {
  t = "";
}
writeFileSync(
  ".build/old-ucc-meta.txt",
  JSON.stringify(
    {
      len: s.length,
      utf8ok: !t.includes("\uFFFD") || true,
      head: t.slice(0, 200),
      hits: [...t.matchAll(/[\u4e00-\u9fff]{2,40}/g)].slice(0, 40).map((m) => m[0]),
      broken: /[\uFFFD]/.test(t),
      linesWithCn: t
        .split(/\n/)
        .map((l, i) => ({ i: i + 1, l }))
        .filter((x) => /[\u4e00-\u9fff]/.test(x.l))
        .slice(0, 50),
    },
    null,
    2,
  ),
  "utf8",
);
console.log("wrote meta");
