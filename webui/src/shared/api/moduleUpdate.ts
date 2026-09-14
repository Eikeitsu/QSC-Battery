/** WebUI：下载模块 zip，并拉起 Magisk / KSU / APatch 等管理器的刷写界面（非无感 CLI）。 */
import { exec } from "./ksu";
import { PATHS } from "@/shared/config/paths";
import { APP } from "@/shared/config/app";

export interface LocalModuleInfo {
  version: string;
  versionCode: number;
}

/** 常见模块管理器包名（优先匹配当前机上已安装的）。 */
const MANAGER_PACKAGES = [
  "com.rifsxd.ksunext",
  "me.weishu.kernelsu",
  "com.tiann.kernelsu",
  "com.topjohnwu.magisk",
  "io.github.vvb2060.magisk",
  "me.bmax.apatch",
  "com.sukisu.ultra",
] as const;

export async function readLocalModule(): Promise<LocalModuleInfo | null> {
  const r = await exec(
    `grep -E '^(version|versionCode)=' '${PATHS.MODDIR}/module.prop' 2>/dev/null`,
    8_000,
  );
  if (r.errno !== 0 && !r.stdout) return null;
  let version = "";
  let versionCode = 0;
  for (const line of (r.stdout || "").split("\n")) {
    const v = line.match(/^version=(.*)$/);
    if (v) version = (v[1] || "").trim();
    const c = line.match(/^versionCode=(.*)$/);
    if (c) versionCode = Number((c[1] || "").trim()) || 0;
  }
  if (!version && !versionCode) return null;
  return { version, versionCode };
}

function shellQuote(s: string): string {
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

/**
 * 下载 zip 到公共 Download，再用 ACTION_VIEW 拉起已安装的模块管理器刷写页。
 */
export async function downloadAndOpenModuleInstaller(zipUrl: string): Promise<{
  ok: boolean;
  error: string;
  detail: string;
  zipPath: string;
}> {
  const url = String(zipUrl || "").trim();
  if (!url) return { ok: false, error: "no_url", detail: "", zipPath: "" };

  const dir = "/sdcard/Download";
  const zip = `${dir}/${APP.moduleId}-update.zip`;
  const u = shellQuote(url);
  const z = shellQuote(zip);
  const pkgs = MANAGER_PACKAGES.map((p) => shellQuote(p)).join(" ");

  const script = [
    `mkdir -p '${dir}'`,
    `rm -f ${z}`,
    `OK=0`,
    `(command -v curl >/dev/null && curl -fsSL --connect-timeout 15 --max-time 180 -o ${z} ${u} && OK=1) || true`,
    `[ "$OK" = 1 ] || (command -v wget >/dev/null && wget -q -O ${z} ${u} && OK=1) || true`,
    `[ "$OK" = 1 ] && [ -s ${z} ] || { echo error=download_failed; exit 0; }`,
    `chmod 0644 ${z} 2>/dev/null || true`,
    `URI="file://${zip}"`,
    `LAUNCHED=0`,
    `for pkg in ${pkgs}; do`,
    `  pm path "$pkg" >/dev/null 2>&1 || continue`,
    `  am start -a android.intent.action.VIEW -d "$URI" -t application/zip -p "$pkg" >/dev/null 2>&1 && LAUNCHED=1 && echo manager=$pkg && break`,
    `done`,
    `if [ "$LAUNCHED" != 1 ]; then`,
    `  am start -a android.intent.action.VIEW -d "$URI" -t application/zip >/dev/null 2>&1 && LAUNCHED=1`,
    `fi`,
    `[ "$LAUNCHED" = 1 ] && echo ok=1 || echo error=open_manager_failed`,
    `echo zip=${zip}`,
  ].join("\n");

  const r = await exec(script, 240_000);
  const out = `${r.stdout || ""}\n${r.stderr || ""}`.trim();
  const zipPath = (out.match(/zip=(\S+)/) || [])[1] || zip;

  if (/\bok=1\b/.test(out)) {
    return { ok: true, error: "", detail: out, zipPath };
  }
  if (/error=download_failed/.test(out)) {
    return { ok: false, error: "download_failed", detail: out, zipPath: "" };
  }
  if (/error=open_manager_failed/.test(out)) {
    return { ok: false, error: "open_manager_failed", detail: out, zipPath };
  }
  return {
    ok: false,
    error: r.errno === -1 ? "no_ksu_bridge" : "open_manager_failed",
    detail: out || r.stderr || `errno=${r.errno}`,
    zipPath,
  };
}

/** @deprecated 使用 downloadAndOpenModuleInstaller */
export async function downloadAndInstallModule(zipUrl: string) {
  return downloadAndOpenModuleInstaller(zipUrl);
}

export function moduleInstallErrorText(code: string): string {
  const map: Record<string, string> = {
    no_url: "没有模块下载地址",
    download_failed: "下载失败，请检查网络后重试",
    download_empty: "下载文件为空",
    open_manager_failed: "已下载，但未能打开模块管理器，请到 Download 目录手动刷入 zip",
    install_failed: "未能打开刷写界面，请到 Download 目录手动安装 zip",
    no_ksu_bridge: "当前不在 KernelSU 等 WebUI 环境，无法自动拉起管理器",
  };
  return map[code] || `操作失败（${code || "未知"}）`;
}
