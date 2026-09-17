/** WebUI：下载模块 zip → 无人值守 CLI 刷入（失败再打开管理器）。 */
import { exec } from "./ksu";
import { PATHS } from "@/shared/config/paths";
import { APP } from "@/shared/config/app";
import { toChannelAssetUrl } from "@/shared/lib/githubCdn";
import { silentUnlinkFile } from "./silentUnlink";

export interface LocalModuleInfo {
  version: string;
  versionCode: number;
}

/** 与 APP ModulePaths.INSTALL_AUTO 一致：customize.sh 见此文件则跳过音量键 */
const INSTALL_AUTO = "/data/adb/qsc/install_auto";

/** 常见模块管理器包名（CLI 失败时兜底）。 */
const MANAGER_PACKAGES = [
  "com.rifsxd.ksunext",
  "me.weishu.kernelsu",
  "com.tiann.kernelsu",
  "com.topjohnwu.magisk",
  "io.github.vvb2060.magisk",
  "me.bmax.apatch",
  "com.sukisu.ultra",
] as const;

const INSTALL_TIMEOUT_MS = 300_000;

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

async function writeBinaryFile(dest: string, data: ArrayBuffer): Promise<boolean> {
  const bytes = new Uint8Array(data);
  const dir = dest.replace(/\/[^/]+$/, "");
  const init = await exec(`mkdir -p '${dir}' && : > '${dest}' && echo ok`, 10_000);
  if (!(init.stdout || "").includes("ok")) return false;
  const chunk = 18 * 1024;
  for (let i = 0; i < bytes.length; i += chunk) {
    const slice = bytes.subarray(i, Math.min(i + chunk, bytes.length));
    let bin = "";
    for (let j = 0; j < slice.length; j++) bin += String.fromCharCode(slice[j]!);
    const b64 = btoa(bin);
    const r = await exec(`echo '${b64}' | base64 -d >> '${dest}'`, 60_000);
    if (r.errno === -1) return false;
  }
  const check = await exec(`[ -s '${dest}' ] && echo ok`, 5_000);
  return (check.stdout || "").includes("ok");
}

async function downloadZip(
  url: string,
  zip: string,
): Promise<{ ok: boolean; detail: string }> {
  const u = shellQuote(url);
  const z = shellQuote(zip);
  const dir = zip.replace(/\/[^/]+$/, "");

  try {
    const resp = await fetch(url, { headers: { "User-Agent": "QSC-Battery-WebUI" } });
    if (resp.ok) {
      const buf = await resp.arrayBuffer();
      if (buf.byteLength > 0 && (await writeBinaryFile(zip, buf))) {
        return { ok: true, detail: `webview bytes=${buf.byteLength}` };
      }
    }
  } catch {
    /* curl fallback */
  }

  const script = [
    `mkdir -p '${dir}'`,
    `rm -f ${z}`,
    `OK=0`,
    `(command -v curl >/dev/null && curl -fsSL --connect-timeout 15 --max-time 180 -o ${z} ${u} && OK=1) || true`,
    `[ "$OK" = 1 ] || (command -v wget >/dev/null && wget -q -O ${z} ${u} && OK=1) || true`,
    `[ "$OK" = 1 ] && [ -s ${z} ] || { echo error=download_failed; exit 0; }`,
    `echo downloaded=1`,
  ].join("\n");
  const r = await exec(script, 240_000);
  const out = `${r.stdout || ""}\n${r.stderr || ""}`.trim();
  if (/error=download_failed/.test(out) || !/downloaded=1/.test(out)) {
    return { ok: false, detail: out };
  }
  return { ok: true, detail: out };
}

async function enableUnattended(): Promise<void> {
  await exec(`mkdir -p /data/adb/qsc && touch '${INSTALL_AUTO}'`, 5_000);
}

async function clearUnattended(): Promise<void> {
  silentUnlinkFile(INSTALL_AUTO);
}

/** Root CLI 刷入；任一成功即返回 */
async function installModuleCli(zip: string): Promise<{ ok: boolean; detail: string }> {
  const path = zip.replace(/'/g, "");
  const attempts = [
    `magisk --install-module '${path}'`,
    `ksud module install '${path}'`,
    `/data/adb/ksud module install '${path}'`,
    `nsenter --mount=/proc/1/ns/mnt -- /data/adb/ksud module install '${path}'`,
    `nsenter --mount=/proc/1/ns/mnt -- /data/adb/magisk/magisk --install-module '${path}'`,
    `/data/adb/ap/bin/apd module install '${path}'`,
    `nsenter --mount=/proc/1/ns/mnt -- /data/adb/ap/bin/apd module install '${path}'`,
  ];
  const logs: string[] = [];
  for (const cmd of attempts) {
    logs.push(`$ ${cmd}`);
    const r = await exec(cmd, INSTALL_TIMEOUT_MS);
    const out = `${r.stdout || ""}\n${r.stderr || ""}`.trim();
    if (out) logs.push(out);
    logs.push(`# exit=${r.errno}`);
    // 与 APP RootBridge 一致：优先看 errno；部分环境成功输出含 Success
    if (
      r.errno === 0 ||
      /\bSuccess\b/i.test(out) ||
      /installed successfully/i.test(out)
    ) {
      return { ok: true, detail: logs.join("\n") };
    }
  }
  return { ok: false, detail: logs.join("\n") };
}

async function openZipInManager(zip: string): Promise<{ ok: boolean; detail: string }> {
  const z = shellQuote(zip);
  const pkgs = MANAGER_PACKAGES.map((p) => shellQuote(p)).join(" ");
  const script = [
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
  const r = await exec(script, 30_000);
  const out = `${r.stdout || ""}\n${r.stderr || ""}`.trim();
  return { ok: /\bok=1\b/.test(out), detail: out };
}

export type ModuleInstallMode = "cli" | "manager" | "";

/**
 * 下载 → 写 install_auto → CLI 无人值守刷入 → 清 flag。
 * CLI 失败再打开模块管理器。
 */
export async function downloadAndOpenModuleInstaller(zipUrl: string): Promise<{
  ok: boolean;
  error: string;
  detail: string;
  zipPath: string;
  mode: ModuleInstallMode;
}> {
  const url = toChannelAssetUrl(String(zipUrl || "").trim());
  if (!url) {
    return { ok: false, error: "no_url", detail: "", zipPath: "", mode: "" };
  }

  const dir = "/sdcard/Download";
  const zip = `${dir}/${APP.moduleId}-update.zip`;

  const dl = await downloadZip(url, zip);
  if (!dl.ok) {
    return {
      ok: false,
      error: "download_failed",
      detail: dl.detail,
      zipPath: "",
      mode: "",
    };
  }

  try {
    await enableUnattended();
    const cli = await installModuleCli(zip);
    if (cli.ok) {
      silentUnlinkFile(zip);
      return {
        ok: true,
        error: "",
        detail: `${dl.detail}\n${cli.detail}`,
        zipPath: zip,
        mode: "cli",
      };
    }

    const opened = await openZipInManager(zip);
    if (opened.ok) {
      // 管理器可能还要读：延迟静默删
      silentUnlinkFile(zip, 120);
      return {
        ok: true,
        error: "",
        detail: `${cli.detail}\n${opened.detail}`,
        zipPath: zip,
        mode: "manager",
      };
    }
    silentUnlinkFile(zip);
    return {
      ok: false,
      error: "install_failed",
      detail: `${cli.detail}\n${opened.detail}`,
      zipPath: zip,
      mode: "",
    };
  } finally {
    await clearUnattended();
  }
}

/** @deprecated 使用 downloadAndOpenModuleInstaller */
export async function downloadAndInstallModule(zipUrl: string) {
  return downloadAndOpenModuleInstaller(zipUrl);
}

export function moduleInstallErrorText(code: string): string {
  const map: Record<string, string> = {
    no_url: "没有模块下载地址",
    download_failed: "下载失败，请检查网络或切换「使用 CDN」后重试",
    download_empty: "下载文件为空",
    open_manager_failed: "已下载，但未能打开模块管理器，请到 Download 目录手动刷入 zip",
    install_failed: "无人值守刷入失败，且未能打开管理器；请到 Download 目录手动安装 zip",
    no_ksu_bridge: "当前不在 KernelSU 等 WebUI 环境，无法自动刷入",
  };
  return map[code] || `操作失败（${code || "未知"}）`;
}
