<script setup lang="ts">
import { ref } from "vue";
import { showConfirmDialog, showToast, showSuccessToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";

const testing = ref(false);

async function onClearCache() {
  try {
    await showConfirmDialog({
      title: "清除开关缓存",
      message:
        "将删除 list_switch / device.profile，重启后重新探测。用于升级后闪充或停充无效。",
    });
  } catch {
    return;
  }
  if (await api.clearSwitchCache()) showSuccessToast("已清除，请重启设备");
  else showToast("清除失败");
}

async function onTestSwitch(full: boolean) {
  try {
    await showConfirmDialog({
      title: full ? "完整测开关" : "快速测开关",
      message: full
        ? "请保持插电。将逐条测试候选节点，耗时可能较长，测完会恢复充电。"
        : "请保持插电。快速模式最多测约 12 条候选；完整测试请选下方完整测开关。",
    });
  } catch {
    return;
  }
  testing.value = true;
  showToast("已后台启动测开关，请保持插电…");
  try {
    const r = await api.runTestSwitch(full);
    if (!r.ok && !/started|already/.test(r.output)) {
      showToast("启动测开关失败");
      return;
    }
    const { status, summary } = await api.waitSwitchTestDone(full ? 300_000 : 120_000);
    const msg = (summary || status || "").slice(0, 900);
    try {
      await showConfirmDialog({
        title: /^done/.test(status) ? "测开关完成" : "测开关状态",
        message: msg || status || "无详细输出，可查看 data/switch_test.log",
        confirmButtonText: "知道了",
        showCancelButton: false,
      });
    } catch {
      /* closed */
    }
  } finally {
    testing.value = false;
  }
}
</script>

<template>
  <SectionHead title="测开关与缓存" hint="排障用；日常用上方首选开关即可" />
  <ThemedCard>
    <van-cell
      title="快速测开关"
      label="插电 · 约 12 条候选"
      is-link
      :disabled="testing"
      @click="onTestSwitch(false)"
    />
    <van-cell
      title="完整测开关"
      label="插电 · 全部候选（较慢）"
      is-link
      :disabled="testing"
      @click="onTestSwitch(true)"
    />
    <van-cell
      title="清除开关缓存并提示重启"
      label="删除 list_switch / device.profile"
      is-link
      @click="onClearCache"
    />
  </ThemedCard>
</template>
