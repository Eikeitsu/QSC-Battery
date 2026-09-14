import type { RouteRecordRaw } from "vue-router";
import { TabName } from "@/shared/config/enums";
import { TABS, TAB_ORDER } from "@/shared/config/navigation";
import { SubRouteName, SUB_ROUTE_META } from "@/shared/config/subRoutes";
import AppShell from "@/layouts/AppShell.vue";
import { TAB_PAGES, SUB_PAGES } from "./loaders";

const tabChildren: RouteRecordRaw[] = TABS.map((t) => ({
  path: t.name,
  name: t.name,
  component: TAB_PAGES[t.name],
  meta: { order: TAB_ORDER.indexOf(t.name), title: t.label },
}));

const subChildren: RouteRecordRaw[] = (Object.keys(SUB_ROUTE_META) as SubRouteName[]).map(
  (name) => {
    const meta = SUB_ROUTE_META[name];
    const path = name.replace(/-/g, "/"); // config-switches → config/switches
    return {
      path,
      name,
      component: SUB_PAGES[name],
      meta: {
        parentTab: meta.parentTab,
        title: meta.title,
        order: TAB_ORDER.indexOf(meta.parentTab),
      },
    };
  },
);

export const routes: RouteRecordRaw[] = [
  {
    path: "/",
    component: AppShell,
    redirect: { name: TabName.Home },
    children: [...tabChildren, ...subChildren],
  },
  {
    path: "/:pathMatch(.*)*",
    redirect: { name: TabName.Home },
  },
];

export { isTabName } from "@/shared/config/enums";
