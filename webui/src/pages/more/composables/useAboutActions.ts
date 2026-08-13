import { ref } from "vue";
import { showConfirmDialog, showToast } from "vant";
import { WX_PAY_URL } from "@/shared";
import { openUrl, openWxPay } from "@/shared/api";
import { useAppStore } from "@/stores";

export function useAboutActions() {
  const store = useAppStore();
  const tipOpen = ref(false);

  async function resetConfig() {
    try {
      await showConfirmDialog({
        title: "恢复默认",
        message: "确认恢复停充与电流控制默认配置？",
      });
      await store.resetDefaults();
    } catch {
      /* cancelled */
    }
  }

  async function open(url: string) {
    await openUrl(url);
  }

  async function tipAuthor() {
    showToast("正在打开原作者投币页…");
    await openWxPay(WX_PAY_URL);
  }

  return { store, tipOpen, resetConfig, open, tipAuthor };
}
