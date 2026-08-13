import type { RouteRecordRaw } from "vue-router";
import { TabName, isTabName } from "@/shared/config/enums";
import { TABS, TAB_ORDER } from "@/shared/config/navigation";

const TAB_PAGES = {
  [TabName.Home]: () => import("@/pages/home/HomePage.vue"),
  [TabName.Config]: () => import("@/pages/config/ConfigPage.vue"),
  [TabName.Log]: () => import("@/pages/log/LogPage.vue"),
  [TabName.More]: () => import("@/pages/more/MorePage.vue"),
} as const;

export const routes: RouteRecordRaw[] = [
  {
    path: "/",
    component: () => import("@/layouts/AppShell.vue"),
    redirect: { name: TabName.Home },
    children: TABS.map((t) => ({
      path: t.name,
      name: t.name,
      component: TAB_PAGES[t.name],
      meta: { order: TAB_ORDER.indexOf(t.name), title: t.label },
    })),
  },
  {
    path: "/:pathMatch(.*)*",
    redirect: { name: TabName.Home },
  },
];

export { isTabName };
