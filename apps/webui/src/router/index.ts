import { createRouter, createWebHashHistory } from "vue-router";
import { STORAGE_KEYS, removeStorage } from "@/shared";
import { routes } from "./routes";

export const router = createRouter({
  history: createWebHashHistory(),
  routes,
});

removeStorage(STORAGE_KEYS.legacyDockPage);

export default router;
