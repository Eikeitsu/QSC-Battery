import { TabName } from "@/shared/config/enums";
import { SubRouteName } from "@/shared/config/subRoutes";

export const TAB_PAGES = {
  [TabName.Home]: () => import("@/pages/home/HomePage.vue"),
  [TabName.Config]: () => import("@/pages/config/ConfigPage.vue"),
  [TabName.Log]: () => import("@/pages/log/LogPage.vue"),
  [TabName.More]: () => import("@/pages/more/MorePage.vue"),
} as const;

export const SUB_PAGES = {
  [SubRouteName.ConfigSwitches]: () => import("@/pages/config/ConfigSwitchesPage.vue"),
  [SubRouteName.ConfigRuntime]: () => import("@/pages/config/ConfigRuntimePage.vue"),
  [SubRouteName.ConfigPower]: () => import("@/pages/config/ConfigPowerPolicyPage.vue"),
  [SubRouteName.ConfigDaemon]: () => import("@/pages/config/ConfigDaemonPage.vue"),
  [SubRouteName.MoreDevice]: () => import("@/pages/more/MoreDevicePage.vue"),
  [SubRouteName.MoreTools]: () => import("@/pages/more/MoreToolsPage.vue"),
  [SubRouteName.MoreAbout]: () => import("@/pages/more/MoreAboutPage.vue"),
} as const;

/** 预热路由代码块，但仍保持按需加载和独立分包。 */
export function preloadTab(name: TabName): Promise<unknown> {
  return TAB_PAGES[name]();
}

export function preloadSub(name: SubRouteName): Promise<unknown> {
  return SUB_PAGES[name]();
}
