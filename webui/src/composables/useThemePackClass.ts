import { computed } from "vue";
import { useTheme } from "@/stores";

/** 页面根节点的主题 class：page-md3 / page-miuix / page-default */
export function useThemePackClass(prefix = "page") {
  const theme = useTheme();

  const packClass = computed(() => ({
    [`${prefix}-md3`]: theme.themePack === "md3",
    [`${prefix}-miuix`]: theme.themePack === "miuix",
    [`${prefix}-default`]: theme.themePack === "default",
  }));

  return { theme, packClass };
}
