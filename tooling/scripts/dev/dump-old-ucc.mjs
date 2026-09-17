import { execFileSync } from "node:child_process";
import { writeFileSync, mkdirSync } from "node:fs";

mkdirSync(".build", { recursive: true });
const buf = execFileSync(
  "git",
  ["show", "8c39546:webui/src/pages/more/ui/UpdateChannelCard.vue"],
  { maxBuffer: 8e6 },
);
writeFileSync(".build/old-ucc.vue", buf);
const t = buf.toString("utf8");
const lines = t.split(/\n/);
const interesting = [];
for (let i = 0; i < lines.length; i++) {
  if (/notice|预发|正式|切换|刷|检查|通道|守护|模块|更新|CI/.test(lines[i])) {
    interesting.push(`${i + 1}|${lines[i]}`);
  }
}
writeFileSync(".build/old-ucc-cn.txt", interesting.join("\n"), "utf8");
console.log(interesting.join("\n"));
console.log("--- broken?", /�/.test(t), "cjk", /[\u4e00-\u9fff]/.test(t));
