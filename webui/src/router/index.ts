import { createRouter, createWebHashHistory } from "vue-router";
import { ref } from "vue";
import { STORAGE_KEYS, removeStorage } from "@/shared";
import { routes, isTabName } from "./routes";

/** 与原先 App.vue slideDir 行为一致，供 AppShell Transition 使用 */
export const slideDir = ref<"forward" | "back">("forward");

export const router = createRouter({
  history: createWebHashHistory(),
  routes,
});

router.beforeEach((to, from) => {
  if (!isTabName(to.name) || !isTabName(from.name)) {
    slideDir.value = "forward";
    return true;
  }
  const fromOrder = Number(from.meta.order ?? 0);
  const toOrder = Number(to.meta.order ?? 0);
  slideDir.value = toOrder >= fromOrder ? "forward" : "back";
  return true;
});

removeStorage(STORAGE_KEYS.legacyDockPage);

export default router;
