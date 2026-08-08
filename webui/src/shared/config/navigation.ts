import type { TabName, ThemePack } from "@/shared/types";

export interface TabItem {
  name: TabName;
  label: string;
}

export const TAB_ORDER: TabName[] = ["home", "config", "log", "more"];

export const TABS: TabItem[] = [
  { name: "home", label: "概览" },
  { name: "config", label: "策略" },
  { name: "log", label: "日志" },
  { name: "more", label: "我的" },
];

export type DockIcons = Record<TabName, string>;

/** 每套主题四 Tab 统一描线或实底，不混用 */
export const DOCK_ICONS_BY_PACK: Record<ThemePack, DockIcons> = {
  md3: {
    home: "wap-home",
    config: "setting",
    log: "notes",
    more: "friends",
  },
  miuix: {
    home: "apps-o",
    config: "cluster-o",
    log: "description-o",
    more: "contact-o",
  },
  default: {
    home: "home-o",
    config: "setting-o",
    log: "notes-o",
    more: "user-o",
  },
};

export function dockIconsForPack(pack: ThemePack): DockIcons {
  return DOCK_ICONS_BY_PACK[pack] ?? DOCK_ICONS_BY_PACK.default;
}
