import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const paths = [
  "4ec4639:webui/src/pages/more/ui/UpdateChannelCard.vue",
  "40c41a6:apps/webui/src/features/update/UpdateChannelNotices.vue",
  "40c41a6:apps/webui/src/pages/more/ui/UpdateChannelCard.vue",
];

let report = "";
for (const p of paths) {
  try {
    const t = execFileSync("git", ["show", p], { maxBuffer: 8e6 }).toString("utf8");
    report += `==== ${p} len=${t.length} fffd=${t.includes("\uFFFD")}\n`;
    t.split(/\n/).forEach((l, i) => {
      if (
        /预发|正式|刷|可切|检查更新|三通道|notice soft|SectionHead|loading|moduleCanSwitch|daemonCanSwitch/.test(
          l,
        )
      ) {
        report += `${i + 1}|${l}\n`;
      }
    });
  } catch (e) {
    report += `MISS ${p} ${e.message.slice(0, 100)}\n`;
  }
}
writeFileSync(".build/ucc-report.txt", report, "utf8");
console.log(report);
