import { TabName } from "@/shared/config/enums";

export const TAB_PAGES = {
  [TabName.Home]: () => import("@/pages/home/HomePage.vue"),
  [TabName.Config]: () => import("@/pages/config/ConfigPage.vue"),
  [TabName.Log]: () => import("@/pages/log/LogPage.vue"),
  [TabName.More]: () => import("@/pages/more/MorePage.vue"),
} as const;

/** 预热路由代码块，但仍保持按需加载和独立分包。 */
export function preloadTab(name: TabName): Promise<unknown> {
  return TAB_PAGES[name]();
}
