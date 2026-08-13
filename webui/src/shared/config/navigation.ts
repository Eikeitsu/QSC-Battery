import { TabName, ThemePack } from "./enums";

export interface TabItem {
  name: TabName;
  label: string;
}

export const TABS: TabItem[] = [
  { name: TabName.Home, label: "概览" },
  { name: TabName.Config, label: "策略" },
  { name: TabName.Log, label: "日志" },
  { name: TabName.More, label: "我的" },
];

export const TAB_ORDER: TabName[] = TABS.map((t) => t.name);

export type DockIcons = Record<TabName, string>;

/** 每套主题四 Tab 统一描线或实底，不混用 */
export const DOCK_ICONS_BY_PACK: Record<ThemePack, DockIcons> = {
  [ThemePack.Md3]: {
    [TabName.Home]: "wap-home",
    [TabName.Config]: "setting",
    [TabName.Log]: "notes",
    [TabName.More]: "friends",
  },
  [ThemePack.Miuix]: {
    [TabName.Home]: "apps-o",
    [TabName.Config]: "cluster-o",
    [TabName.Log]: "description-o",
    [TabName.More]: "contact-o",
  },
  [ThemePack.Default]: {
    [TabName.Home]: "home-o",
    [TabName.Config]: "setting-o",
    [TabName.Log]: "notes-o",
    [TabName.More]: "user-o",
  },
};

export function dockIconsForPack(pack: ThemePack): DockIcons {
  return DOCK_ICONS_BY_PACK[pack] ?? DOCK_ICONS_BY_PACK[ThemePack.Default];
}
