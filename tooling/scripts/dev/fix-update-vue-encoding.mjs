import { readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

const files = [
  "apps/webui/src/features/update/UpdateChannelNotices.vue",
  "apps/webui/src/pages/more/ui/UpdateChannelCard.vue",
  "apps/webui/src/features/update/UpdateChannelToolbar.vue",
  "apps/webui/src/features/update/UpdateResultPanel.vue",
  "apps/webui/src/features/update/UpdateActionProgress.vue",
];

for (const p of files) {
  execFileSync("git", ["checkout", "HEAD", "--", p], { stdio: "inherit" });
}

for (const p of files) {
  let t = readFileSync(p, "utf8");
  const before = t;
  t = t.replaceAll('@use "./update-channel.scss"', '@use "./update-channel"');
  t = t.replaceAll(
    '@use "@/features/update/update-channel.scss"',
    '@use "@/features/update/update-channel"',
  );
  if (t !== before) {
    writeFileSync(p, t, "utf8");
    console.log("fixed @use", p);
  } else {
    const m = t.match(/@use[^\n]+/);
    console.log("unchanged @use", p, m?.[0] ?? "(none)");
  }
  console.log(
    " ",
    "cjk=",
    /[\u4e00-\u9fff]/.test(t),
    "badClose=",
    /[\uFFFD]|版\?<\/|新\?<\/|式\?/.test(t),
  );
}
