/** WebUI：下载伴侣 APP 并用 pm install / 系统安装器安装 */
import { exec } from "./ksu";
import { APP } from "@/shared/config/app";
import { toChannelAssetUrl } from "@/shared/lib/githubCdn";
import { silentUnlinkFile } from "./silentUnlink";

const APP_PACKAGES = ["com.qsc.battery", "com.qsc.battery.debug"] as const;

export interface LocalAppInfo {
  version: string;
  versionCode: number;
  packageName: string;
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

/** 读取已安装伴侣 APP 版本（优先正式包，其次 debug） */
export async function readLocalApp(): Promise<LocalAppInfo | null> {
  for (const pkg of APP_PACKAGES) {
    const r = await exec(
      `dumpsys package ${shellQuote(pkg)} 2>/dev/null | ` +
        `grep -E 'versionName=|versionCode=' | head -n 8`,
      10_000,
    );
    const text = r.stdout || "";
    if (!text.includes("version")) continue;
    let version = "";
    let versionCode = 0;
    for (const line of text.split("\n")) {
      const vn = line.match(/versionName=(\S+)/);
      if (vn) version = (vn[1] || "").trim();
      const vc = line.match(/versionCode[=:](\d+)/);
      if (vc) versionCode = Number(vc[1] || "") || versionCode;
    }
    if (version || versionCode) {
      return { version, versionCode, packageName: pkg };
    }
  }
  return null;
}

async function openApkInstaller(apk: string): Promise<boolean> {
  const a = shellQuote(apk);
  const script = [
    `chmod 0644 ${a} 2>/dev/null || true`,
    `URI="file://${apk}"`,
    `am start -a android.intent.action.VIEW -d "$URI" -t application/vnd.android.package-archive >/dev/null 2>&1 && echo ok=1 || echo error=open_installer_failed`,
  ].join("\n");
  const r = await exec(script, 20_000);
  return /\bok=1\b/.test(`${r.stdout || ""}\n${r.stderr || ""}`);
}

/**
 * WebView 拉 APK → pm install -r；失败则打开系统安装界面。
 */
export async function downloadAndInstallApp(apkUrl: string): Promise<{
  ok: boolean;
  error: string;
  detail: string;
  apkPath: string;
  mode: "pm" | "installer" | "";
}> {
  const url = toChannelAssetUrl(String(apkUrl || "").trim());
  if (!url) {
    return { ok: false, error: "no_url", detail: "", apkPath: "", mode: "" };
  }

  const dir = "/sdcard/Download";
  const apk = `${dir}/${APP.moduleId}-update.apk`;
  const u = shellQuote(url);
  const a = shellQuote(apk);

  let downloaded = false;
  try {
    const resp = await fetch(url, { headers: { "User-Agent": "QSC-Battery-WebUI" } });
    if (resp.ok) {
      const buf = await resp.arrayBuffer();
      if (buf.byteLength > 0 && (await writeBinaryFile(apk, buf))) downloaded = true;
    }
  } catch {
    /* curl fallback */
  }

  if (!downloaded) {
    const script = [
      `mkdir -p '${dir}'`,
      `rm -f ${a}`,
      `OK=0`,
      `(command -v curl >/dev/null && curl -fsSL --connect-timeout 15 --max-time 180 -o ${a} ${u} && OK=1) || true`,
      `[ "$OK" = 1 ] || (command -v wget >/dev/null && wget -q -O ${a} ${u} && OK=1) || true`,
      `[ "$OK" = 1 ] && [ -s ${a} ] || { echo error=download_failed; exit 0; }`,
      `echo downloaded=1`,
    ].join("\n");
    const r = await exec(script, 240_000);
    const out = `${r.stdout || ""}\n${r.stderr || ""}`.trim();
    if (/error=download_failed/.test(out) || !/downloaded=1/.test(out)) {
      return { ok: false, error: "download_failed", detail: out, apkPath: "", mode: "" };
    }
  }

  const install = await exec(`pm install -r ${a} 2>&1`, 120_000);
  const out = `${install.stdout || ""}\n${install.stderr || ""}`.trim();
  if (/Success/i.test(out) || install.errno === 0) {
    silentUnlinkFile(apk);
    return { ok: true, error: "", detail: out, apkPath: apk, mode: "pm" };
  }

  if (await openApkInstaller(apk)) {
    silentUnlinkFile(apk, 180);
    return {
      ok: true,
      error: "",
      detail: out,
      apkPath: apk,
      mode: "installer",
    };
  }

  silentUnlinkFile(apk);
  return {
    ok: false,
    error: "install_failed",
    detail: out,
    apkPath: apk,
    mode: "",
  };
}

export function appInstallErrorText(code: string): string {
  const map: Record<string, string> = {
    no_url: "没有 APP 下载地址",
    download_failed: "APP 下载失败，请检查网络或切换「使用 CDN」后重试",
    install_failed: "已下载，但安装失败（降级可能被系统拒绝，可先卸载再装）",
    no_ksu_bridge: "当前不在 KernelSU 等 WebUI 环境，无法自动安装",
  };
  return map[code] || `操作失败（${code || "未知"}）`;
}
