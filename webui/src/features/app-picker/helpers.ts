import type { AppEntry } from "../../shared/types";

export function sortAppsSelectedFirst(
  apps: AppEntry[],
  selected: Iterable<string>,
): AppEntry[] {
  const selectedSet = selected instanceof Set ? selected : new Set(selected);
  return [...apps].sort((a, b) => {
    const aOn = selectedSet.has(a.package);
    const bOn = selectedSet.has(b.package);
    if (aOn !== bOn) return aOn ? -1 : 1;
    return (a.name || a.package).localeCompare(b.name || b.package, "zh");
  });
}

export function initialFromName(name: string): string {
  const t = (name || "").trim();
  if (!t) return "?";
  return t.slice(0, 1).toUpperCase();
}

export function hueFromPackage(pkg: string): number {
  let h = 0;
  for (let i = 0; i < pkg.length; i++) h = (h * 31 + pkg.charCodeAt(i)) >>> 0;
  return h % 360;
}
