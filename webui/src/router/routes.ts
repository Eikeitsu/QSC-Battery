import type { RouteRecordRaw } from "vue-router";
import { TAB_ORDER } from "@/shared/config/navigation";
import type { TabName } from "@/shared/types";

export const routes: RouteRecordRaw[] = [
  {
    path: "/",
    component: () => import("@/layouts/AppShell.vue"),
    redirect: { name: "home" },
    children: [
      {
        path: "home",
        name: "home",
        component: () => import("@/pages/home/HomePage.vue"),
        meta: { order: TAB_ORDER.indexOf("home"), title: "概览" },
      },
      {
        path: "config",
        name: "config",
        component: () => import("@/pages/config/ConfigPage.vue"),
        meta: { order: TAB_ORDER.indexOf("config"), title: "策略" },
      },
      {
        path: "log",
        name: "log",
        component: () => import("@/pages/log/LogPage.vue"),
        meta: { order: TAB_ORDER.indexOf("log"), title: "日志" },
      },
      {
        path: "more",
        name: "more",
        component: () => import("@/pages/more/MorePage.vue"),
        meta: { order: TAB_ORDER.indexOf("more"), title: "我的" },
      },
    ],
  },
  {
    path: "/:pathMatch(.*)*",
    redirect: { name: "home" },
  },
];

export function isTabName(name: unknown): name is TabName {
  return typeof name === "string" && (TAB_ORDER as string[]).includes(name);
}
