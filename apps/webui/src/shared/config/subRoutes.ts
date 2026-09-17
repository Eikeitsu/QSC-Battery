import { TabName } from "./enums";

/** 二级页路由名（平铺，带 parentTab） */
export const SubRouteName = {
  ConfigSwitches: "config-switches",
  ConfigRuntime: "config-runtime",
  ConfigDaemon: "config-daemon",
  MoreDevice: "more-device",
  MoreTools: "more-tools",
  MoreAbout: "more-about",
} as const;

export type SubRouteName = (typeof SubRouteName)[keyof typeof SubRouteName];

export interface SubRouteMeta {
  parentTab: TabName;
  title: string;
}

export const SUB_ROUTE_META: Record<SubRouteName, SubRouteMeta> = {
  [SubRouteName.ConfigSwitches]: {
    parentTab: TabName.Config,
    title: "供电开关与排障",
  },
  [SubRouteName.ConfigRuntime]: {
    parentTab: TabName.Config,
    title: "运行与采样",
  },
  [SubRouteName.ConfigDaemon]: {
    parentTab: TabName.Config,
    title: "事件唤醒守护",
  },
  [SubRouteName.MoreDevice]: {
    parentTab: TabName.More,
    title: "机型与社区",
  },
  [SubRouteName.MoreTools]: {
    parentTab: TabName.More,
    title: "快捷入口与说明",
  },
  [SubRouteName.MoreAbout]: {
    parentTab: TabName.More,
    title: "关于",
  },
};

export function isSubRouteName(v: unknown): v is SubRouteName {
  return typeof v === "string" && v in SUB_ROUTE_META;
}

/** 当前路由所属底栏 Tab */
export function parentTabOfRoute(name: unknown, metaParent?: unknown): TabName {
  if (metaParent && Object.values(TabName).includes(metaParent as TabName)) {
    return metaParent as TabName;
  }
  if (isSubRouteName(name)) return SUB_ROUTE_META[name].parentTab;
  if (Object.values(TabName).includes(name as TabName)) return name as TabName;
  return TabName.Home;
}
