<script setup lang="ts">
import { onMounted, ref } from "vue";
import { showConfirmDialog, showToast, showSuccessToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";

const testing = ref(false);
const debugOn = ref(false);
const debugBusy = ref(false);

async function refreshDebug() {
  debugOn.value = await api.isDebugOn();
}

async function onDebugToggle(v: boolean) {
  debugBusy.value = true;
  try {
    const ok = await api.setDebugOn(v);
    if (ok) {
      debugOn.value = v;
      showToast(v ? "已开详细调试日志" : "已关详细调试日志");
    } else {
      showToast("切换失败");
      await refreshDebug();
    }
  } finally {
    debugBusy.value = false;
  }
}

async function onClearCache() {
  try {
    await showConfirmDialog({
      title: "清除开关缓存",
      message:
        "将删除 list_switch / device.profile，重启后重新探测。用于升级后出现充电反复启停或停充无效。",
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

onMounted(() => {
  void refreshDebug();
});
</script>

<template>
  <SectionHead title="测开关与缓存" hint="排障用；日常用上方首选开关即可" />
  <ThemedCard>
    <SwitchCell
      title="详细调试日志"
      label="插电/停充/涓流/电流/qscd 等写入 log.log；随开随关"
      :model-value="debugOn"
      :disabled="debugBusy"
      @update:model-value="onDebugToggle"
    />
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
