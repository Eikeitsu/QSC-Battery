<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { showConfirmDialog, showToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { useConfigFormContext } from "@/composables";
import * as api from "@/shared/api";
import type { DaemonImpl } from "@/shared/api";

const { store, onSwitch } = useConfigFormContext();

const status = ref<api.DaemonStatus | null>(null);
const busy = ref("");

const installed = computed(() => status.value?.installed === true);
const archOk = computed(
  () => !!status.value && status.value.arch !== "" && status.value.arch !== "unsupported",
);
/** 没有二进制就不允许打开开关：开了也没效果，反而让人误以为在省电 */
const switchDisabled = computed(() => !installed.value || busy.value !== "");
const switchOn = computed(() => installed.value && store.settings.native_daemon !== "0");

const implLabel = computed(() => {
  const impl = status.value?.impl;
  if (impl === "rust") return "Rust";
  if (impl === "c") return "C";
  return "";
});

const srcLabel = computed(() => {
  const src = status.value?.src;
  if (src === "bundled") return "安装包自带";
  if (src === "download") return "已下载";
  return "";
});

const stateLabel = computed(() => {
  if (!status.value) return "读取中…";
  if (!archOk.value) return "本机 CPU 架构不支持（仅 arm64 / armv7）";
  if (!installed.value) return "未安装：请在下方选择一个实现下载";
  const parts = [implLabel.value ? `${implLabel.value} 版` : "已安装"];
  if (srcLabel.value) parts.push(srcLabel.value);
  parts.push(status.value.probeOk ? "自检通过" : "自检未通过，实际仍用定时轮询");
  return parts.join(" · ");
});

const switchLabel = computed(() => {
  if (!archOk.value) return "本机 CPU 架构没有可用的守护文件";
  if (!installed.value) return "需先下载守护文件才能开启";
  return "未插电时由内核充电事件唤醒，替代定时轮询，最省电";
});

function implRowLabel(impl: DaemonImpl) {
  const bits: string[] = [];
  if (status.value?.bundled.includes(impl)) bits.push("安装包自带");
  if (status.value?.impl === impl) bits.push("当前使用");
  bits.push(impl === "rust" ? "内存安全，体积略大" : "依赖最少，体积最小");
  return bits.join(" · ");
}

async function reload() {
  status.value = await api.loadDaemonStatus();
}

/** 自带就直接用，避免没必要的联网；否则下载 */
async function pick(impl: DaemonImpl) {
  if (busy.value) return;
  if (status.value?.impl === impl && installed.value) {
    showToast(`已在使用 ${impl === "rust" ? "Rust" : "C"} 版`);
    return;
  }
  const bundled = status.value?.bundled.includes(impl) === true;
  busy.value = impl;
  try {
    const result = bundled
      ? await api.useBundledDaemon(impl)
      : await api.installDaemon(impl);
    if (!result.ok) {
      showToast(api.daemonErrorText(result.error));
      return;
    }
    store.settings.native_impl = impl;
    store.settings.native_daemon = "1";
    showToast(bundled ? "已切换并重启服务" : "已下载校验并启用");
  } finally {
    busy.value = "";
    await reload();
  }
}

async function onRemove() {
  if (busy.value) return;
  try {
    await showConfirmDialog({
      title: "删除守护文件",
      message: "删除后「事件唤醒」将关闭并回到定时轮询，随时可以重新下载。",
    });
  } catch {
    return;
  }
  busy.value = "remove";
  try {
    const result = await api.removeDaemon();
    if (!result.ok) {
      showToast(api.daemonErrorText(result.error));
      return;
    }
    store.settings.native_daemon = "0";
    showToast("已删除");
  } finally {
    busy.value = "";
    await reload();
  }
}

onMounted(reload);
</script>

<template>
  <SectionHead title="事件唤醒（守护）" :hint="stateLabel" />
  <ThemedCard>
    <SwitchCell
      title="启用事件唤醒"
      :label="switchLabel"
      :model-value="switchOn"
      :disabled="switchDisabled"
      @update:model-value="(v) => onSwitch('native_daemon', v)"
    />

    <template v-if="archOk">
      <van-cell
        title="Rust 版"
        :label="implRowLabel('rust')"
        :is-link="status?.impl !== 'rust'"
        :value="busy === 'rust' ? '处理中…' : status?.impl === 'rust' ? '使用中' : '选用'"
        @click="pick('rust')"
      />
      <van-cell
        title="C 版"
        :label="implRowLabel('c')"
        :is-link="status?.impl !== 'c'"
        :value="busy === 'c' ? '处理中…' : status?.impl === 'c' ? '使用中' : '选用'"
        @click="pick('c')"
      />
      <van-cell
        v-if="installed"
        title="删除守护文件"
        label="回到纯脚本定时轮询"
        :value="busy === 'remove' ? '处理中…' : '删除'"
        is-link
        @click="onRemove"
      />
      <p class="warn">
        两套实现功能完全一致，只是编译语言不同，只能选其一；选另一个会自动替换掉当前的。
        安装包未自带时从模块官网下载，落盘前会校验 sha256，校验或自检不通过一律回滚。
      </p>
    </template>
    <p v-else class="warn">
      守护只提供 arm64 与 armv7 两种，本机架构不在其中。停充功能不受影响，只是待机时
      仍按定时间隔轮询。
    </p>
  </ThemedCard>
</template>

<style scoped lang="scss">
.warn {
  margin: 0;
  padding: 8px var(--qsc-cell-pad-x, 16px) 12px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.45;
}

:deep(.van-cell) {
  background: transparent;
}
</style>
