import DefaultTheme from "vitepress/theme";
import { watch, onMounted, nextTick } from "vue";
import { useData, withBase } from "vitepress";
import "./custom.css";

function syncHeroMark(isDark) {
  const img = document.querySelector(".VPHero .image .image-src");
  if (!img) return;
  const next = withBase(isDark ? "/icon-mark.png" : "/icon-mark-light.png");
  if (img.getAttribute("src") !== next) {
    img.setAttribute("src", next);
  }
}

export default {
  extends: DefaultTheme,
  setup() {
    const { isDark } = useData();
    onMounted(async () => {
      await nextTick();
      syncHeroMark(isDark.value);
      watch(isDark, (v) => syncHeroMark(v));
    });
  },
};
