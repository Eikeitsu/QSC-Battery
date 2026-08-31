import type { RouteRecordRaw } from "vue-router";
import { TabName, isTabName } from "@/shared/config/enums";
import { TABS, TAB_ORDER } from "@/shared/config/navigation";
import AppShell from "@/layouts/AppShell.vue";
import { TAB_PAGES } from "./loaders";

export const routes: RouteRecordRaw[] = [
  {
    path: "/",
    // 壳层很小且必须立即出现；页面组件仍按 Tab 路由懒加载。
    component: AppShell,
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
