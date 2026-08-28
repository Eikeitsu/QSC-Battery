import { ref } from "vue";

/** 页面切换方向，单独放置以避免路由表同步加载时形成循环依赖 */
export const slideDir = ref<"forward" | "back">("forward");
