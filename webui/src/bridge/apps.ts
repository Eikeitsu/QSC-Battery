import type { AppEntry } from "../shared/types";
import { exec } from "./ksu";

interface PackageInfo {
  appLabel?: string;
  name?: string;
}

/** KernelSU WebUI 图标协议，与管理器约定一致 */
export function appIconUrl(packageName: string): string {
  return `ksu://icon/${packageName}`;
}

export async function listInstalledApps(): Promise<AppEntry[]> {
  try {
    if (typeof ksu !== "undefined" && ksu) {
      let pkgs: string[] | null = null;
      if (typeof ksu.listUserPackages === "function") {
        pkgs = JSON.parse(ksu.listUserPackages() || "[]") as string[];
      } else if (typeof ksu.listAllPackages === "function") {
        pkgs = JSON.parse(ksu.listAllPackages() || "[]") as string[];
      }
      if (Array.isArray(pkgs) && pkgs.length) {
        let infos: PackageInfo[] | null = null;
        if (typeof ksu.getPackagesInfo === "function") {
          try {
            infos = JSON.parse(
              ksu.getPackagesInfo(JSON.stringify(pkgs)) || "[]",
            ) as PackageInfo[];
          } catch {
            infos = null;
          }
        }
        return pkgs.map((pkg, i) => ({
          package: pkg,
          name: infos?.[i]?.appLabel || infos?.[i]?.name || pkg,
          iconUrl: appIconUrl(pkg),
        }));
      }
    }
  } catch {
    /* fall through */
  }

  const result = await exec(
    `pm list packages -3 2>/dev/null | sed 's/^package://' | sort`,
    20000,
  );
  return result.stdout
    .split(/\r?\n/)
    .map((s) => s.trim())
    .filter(Boolean)
    .map((pkg) => ({
      package: pkg,
      name: pkg,
      iconUrl: appIconUrl(pkg),
    }));
}
