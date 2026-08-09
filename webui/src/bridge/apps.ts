import type { AppEntry } from "../shared/types";
import { exec } from "./ksu";

interface PackageInfo {
  packageName?: string;
  package?: string;
  appLabel?: string;
  name?: string;
  appName?: string;
  label?: string;
  error?: string;
}

/** KernelSU WebUI 图标协议，与管理器约定一致 */
export function appIconUrl(packageName: string): string {
  return `ksu://icon/${packageName}`;
}

function pickLabel(info?: PackageInfo | null): string {
  if (!info || info.error) return "";
  const label = info.appLabel || info.appName || info.label || info.name || "";
  return String(label).trim();
}

function pickPkg(info: PackageInfo): string {
  return String(info.packageName || info.package || "").trim();
}

/** 用 packageName 建索引，避免 infos 顺序/缺项导致名称为包名 */
function labelMapFromInfos(infos: PackageInfo[] | null | undefined): Map<string, string> {
  const map = new Map<string, string>();
  if (!Array.isArray(infos)) return map;
  for (const info of infos) {
    const pkg = pickPkg(info);
    const label = pickLabel(info);
    if (pkg && label && label !== pkg) map.set(pkg, label);
  }
  return map;
}

/** dumpsys 批量解析 applicationLabel（无 KSU 元数据时的兜底） */
async function labelsFromDumpsys(pkgs: string[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (!pkgs.length) return map;
  try {
    const result = await exec(`dumpsys package 2>/dev/null`, 45000);
    const want = new Set(pkgs);
    let pkg = "";
    for (const raw of result.stdout.split(/\r?\n/)) {
      const line = raw.trim();
      const m = line.match(/^Package\s*\[([^\]]+)\]/);
      if (m) {
        pkg = m[1];
        continue;
      }
      if (!pkg || !want.has(pkg)) continue;
      const li = line.indexOf("applicationLabel=");
      if (li < 0) continue;
      const label = line.slice(li + "applicationLabel=".length).trim();
      if (label) map.set(pkg, label);
      pkg = "";
    }
  } catch {
    /* ignore */
  }
  return map;
}

function toEntries(pkgs: string[], labels: Map<string, string>): AppEntry[] {
  return pkgs.map((pkg) => ({
    package: pkg,
    name: labels.get(pkg) || pkg,
    iconUrl: appIconUrl(pkg),
  }));
}

export async function listInstalledApps(): Promise<AppEntry[]> {
  let pkgs: string[] = [];

  try {
    if (typeof ksu !== "undefined" && ksu) {
      if (typeof ksu.listUserPackages === "function") {
        pkgs = JSON.parse(ksu.listUserPackages() || "[]") as string[];
      } else if (typeof ksu.listAllPackages === "function") {
        pkgs = JSON.parse(ksu.listAllPackages() || "[]") as string[];
      }
    }
  } catch {
    pkgs = [];
  }

  if (!Array.isArray(pkgs) || !pkgs.length) {
    const result = await exec(
      `pm list packages -3 2>/dev/null | sed 's/^package://' | sort`,
      20000,
    );
    pkgs = result.stdout
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean);
  }

  pkgs = [...new Set(pkgs.filter(Boolean))];
  if (!pkgs.length) return [];

  let labels = new Map<string, string>();
  try {
    if (typeof ksu !== "undefined" && ksu && typeof ksu.getPackagesInfo === "function") {
      // 分批，避免单次 JSON 过大
      const chunk = 80;
      const infos: PackageInfo[] = [];
      for (let i = 0; i < pkgs.length; i += chunk) {
        const part = pkgs.slice(i, i + chunk);
        try {
          const raw = ksu.getPackagesInfo(JSON.stringify(part)) || "[]";
          const parsed = JSON.parse(raw) as PackageInfo[];
          if (Array.isArray(parsed)) infos.push(...parsed);
        } catch {
          /* continue */
        }
      }
      labels = labelMapFromInfos(infos);
    }
  } catch {
    /* fall through */
  }

  const missing = pkgs.filter((p) => !labels.has(p));
  if (missing.length) {
    const fromDump = await labelsFromDumpsys(missing);
    for (const [pkg, label] of fromDump) labels.set(pkg, label);
  }

  return toEntries(pkgs, labels);
}
