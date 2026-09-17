import { computed } from "vue";
import { ThemePack } from "@/shared";
import { useTheme } from "@/stores";

/** 页面根节点的主题 class：page-md3 / page-miuix / page-default */
export function useThemePackClass(prefix = "page") {
  const theme = useTheme();
  const packClass = computed(() => ({
    [`${prefix}-${ThemePack.Md3}`]: theme.themePack === ThemePack.Md3,
    [`${prefix}-${ThemePack.Miuix}`]: theme.themePack === ThemePack.Miuix,
    [`${prefix}-${ThemePack.Default}`]: theme.themePack === ThemePack.Default,
  }));
  return { theme, packClass };
}
