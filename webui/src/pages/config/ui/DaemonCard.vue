<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
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
const progress = ref<api.DaemonDownloadProgress>({ percent: 0, stage: "" });
const updateStatus = ref<api.DaemonUpdateStatus | null>(null);
const updateError = ref("");
let progressTimer: ReturnType<typeof setInterval> | null = null;

const installed = computed(() => status.value?.installed === true);
const archOk = computed(
  () => !!status.value && status.value.arch !== "" && status.value.arch !== "unsupported",
);
/** 没有二进制就不允许打开开关：开了也没效果，反而让人误以为在省电 */
const switchDisabled = computed(() => !installed.value || busy.value !== "");
const switchOn = computed(() => installed.value && store.settings.native_daemon !== "0");
const actionBusy = computed(() => busy.value === "rust" || busy.value === "c");
const checkBusy = computed(() => busy.value === "check");

const updateLabel = computed(() => {
  if (checkBusy.value) return "检查中…";
  if (updateStatus.value?.updateAvailable) return "有更新";
  if (updateStatus.value?.versionState === "same" && updateStatus.value.hashMatch)
    return "已是最新";
  if (updateStatus.value?.versionState === "same" && !updateStatus.value.hashMatch)
    return "校验异常";
  if (updateError.value) return "检查失败";
  return "检查更新";
});

const updateHint = computed(() => {
  const checked = updateStatus.value;
  if (checked?.updateAvailable) {
    return `本地 ${checked.localVersion || "未知"} · 远程 ${checked.remoteVersion}`;
  }
  if (checked?.versionState === "same" && !checked.hashMatch) {
    return `版本 ${checked.remoteVersion}，但本地文件校验不一致`;
  }
  if (checked?.versionState === "same") {
    return `版本 ${checked.remoteVersion}，版本号与文件校验一致`;
  }
  if (checked?.versionState === "local_newer") {
    return `本地 ${checked.localVersion} · 远程 ${checked.remoteVersion}`;
  }
  if (checked?.remoteVersion) {
    return `远程 ${checked.remoteVersion} · 本地版本未知`;
  }
  return updateError.value || "点击检查远程版本与本地文件";
});

const progressStageLabel = computed(() => {
  const labels: Record<string, string> = {
    prepare: "正在准备安全安装环境…",
    manifest: "正在获取版本清单…",
    binary: "正在下载二进制文件…",
    verify: "正在校验 SHA-256…",
    activate: "正在切换并重启服务…",
    done: "已完成",
    failed: "操作失败",
  };
  return labels[progress.value.stage] || "正在处理，请稍候…";
});

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
  if (src === "inherited") return "升级继承";
  return "";
});

const diagnosticsLabel = computed(() => {
  if (!status.value?.installed) return "未安装";
  const checks = [
    `netlink ${status.value.selftestNetlink || status.value.probeOk ? "正常" : "失败"}`,
    `电源节点 ${status.value.selftestSysfs ? "可读" : "未确认"}`,
  ];
  if (status.value.features.length > 0) {
    checks.push(`能力：${status.value.features.join("、")}`);
  } else if (status.value.impl === "c") {
    checks.push("基础事件唤醒");
  }
  if (status.value.lastWakeReason) {
    checks.push(`最近等待：${status.value.lastWakeReason}`);
  }
  return checks.join(" · ");
});

const stateLabel = computed(() => {
  if (!status.value) return "读取中…";
  if (!archOk.value) return "本机 CPU 架构不支持（仅 arm64 / armv7）";
  if (!installed.value) return "未安装：请在下方选择一个实现下载";
  const parts = [implLabel.value ? `${implLabel.value} 版` : "已安装"];
  if (srcLabel.value) parts.push(srcLabel.value);
  parts.push(
    status.value.probeOk
      ? status.value.selftestOk
        ? "基础与 Rust 自检通过"
        : "基础自检通过"
      : "自检未通过，实际仍用定时轮询",
  );
  // C 版已冻结，装了它就用不到阈值过滤与原生进程检测，这里明确讲出来，
  // 免得对着「插电间隔·有守护」等设置项纳闷为什么没效果
  if (status.value.impl === "c") parts.push("不含阈值过滤与原生进程检测");
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
  if (status.value?.impl === impl) {
    const source = srcLabel.value ? ` · ${srcLabel.value}` : "";
    bits.push(`当前使用${source} · 版本 ${status.value.localVersion || "未知"}`);
  }
  bits.push(
    impl === "rust"
      ? "推荐：含阈值过滤与原生进程检测，最省电"
      : "仅基础事件唤醒，体积最小，功能已冻结",
  );
  return bits.join(" · ");
}

async function reload() {
  status.value = await api.loadDaemonStatus();
}

async function reloadProgress() {
  progress.value = await api.loadDaemonDownloadProgress();
}

async function checkUpdate(silent = false) {
  if (busy.value || !status.value?.impl) return;
  busy.value = "check";
  updateError.value = "";
  try {
    const result = await api.checkDaemonUpdate(status.value.impl);
    updateStatus.value = result.value;
    updateError.value = result.value ? "" : api.daemonErrorText(result.error);
    if (!silent && result.value) {
      showToast(result.value.updateAvailable ? "发现远程二进制更新" : "当前已是最新版本");
    } else if (!silent && !result.value) {
      showToast(updateError.value);
    }
  } finally {
    busy.value = "";
  }
}

function startProgress() {
  if (progressTimer) clearInterval(progressTimer);
  progress.value = { percent: 0, stage: "prepare" };
  void reloadProgress();
  progressTimer = setInterval(() => {
    void reloadProgress();
  }, 500);
}

function stopProgress() {
  if (progressTimer) clearInterval(progressTimer);
  progressTimer = null;
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
  startProgress();
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
    stopProgress();
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

onMounted(async () => {
  await reload();
  void checkUpdate(true);
});
onUnmounted(stopProgress);
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
      <div v-if="actionBusy" class="daemon-progress" role="status" aria-live="polite">
        <div class="daemon-progress__head">
          <span>{{ progressStageLabel }}</span>
          <span>{{ progress.percent }}%</span>
        </div>
        <div class="daemon-progress__track">
          <span :style="{ width: `${progress.percent}%` }"></span>
        </div>
        <div class="daemon-progress__hint">下载、校验和切换期间请不要重复点击</div>
      </div>
      <van-cell
        title="Rust 版"
        :label="implRowLabel('rust')"
        is-link
        :value="busy === 'rust' ? '处理中…' : status?.impl === 'rust' ? '使用中' : '选用'"
        @click="pick('rust')"
      />
      <van-cell
        title="C 版"
        :label="implRowLabel('c')"
        is-link
        :value="busy === 'c' ? '处理中…' : status?.impl === 'c' ? '使用中' : '选用'"
        @click="pick('c')"
      />
      <van-cell
        v-if="installed"
        title="远程版本"
        :label="updateHint"
        :value="updateLabel"
        is-link
        @click="checkUpdate()"
      />
      <van-cell v-if="installed" title="运行自检" :label="diagnosticsLabel" />
      <van-cell
        v-if="installed"
        title="删除守护文件"
        label="回到纯脚本定时轮询"
        :value="busy === 'remove' ? '处理中…' : '删除'"
        is-link
        @click="onRemove"
      />
      <p class="warn">
        两套实现只能选其一，选另一个会自动替换掉当前的。安装包未自带时从模块官网下载，
        落盘前会校验 sha256，校验或自检不通过一律回滚。
      </p>
      <p class="warn">
        两版能力已经不同：Rust 版是主力，除了事件唤醒还能按阈值过滤电池事件（充电中离
        停充阈值还远时不叫醒脚本）和用原生方式做进程检测（替代
        <code>ps</code> 全量快照）； C 版冻结在基础事件唤醒上，只修
        bug、不再跟进新能力。装 C 版一切照常工作，
        只是用不上上面两项，对应场景自动退回原有做法。
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

.daemon-progress {
  padding: 12px var(--qsc-cell-pad-x, 16px) 14px;
  color: var(--qsc-text-2);
  font-size: 12px;
}

.daemon-progress__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 7px;
}

.daemon-progress__track {
  height: 6px;
  overflow: hidden;
  border-radius: 999px;
  background: color-mix(in srgb, var(--qsc-text) 12%, transparent);
}

.daemon-progress__track span {
  display: block;
  height: 100%;
  min-width: 2px;
  border-radius: inherit;
  background: var(--qsc-primary);
  transition: width 240ms ease;
}

.daemon-progress__hint {
  margin-top: 6px;
  color: var(--qsc-text-3);
}

:deep(.van-cell) {
  background: transparent;
}
</style>
