<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { showConfirmDialog, showToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";
import {
  STORAGE_KEYS,
  UPDATE_CHANNELS,
  UPDATE_CHANNEL_HINT,
  UPDATE_CHANNEL_LABEL,
  UPDATE_CHANNEL_TECH,
  checkUpdateChannel,
  isPreferCdn,
  parseUpdateChannel,
  readStorage,
  setPreferCdn,
  versionLine,
  writeStorage,
  type ChannelCheckResult,
  type UpdateChannel,
} from "@/shared";

const channel = ref<UpdateChannel>(
  parseUpdateChannel(readStorage(STORAGE_KEYS.updateChannel)),
);
const preferCdn = ref(isPreferCdn());
const busy = ref(false);
const actionBusy = ref<"module" | "daemon" | "">("");
const result = ref<ChannelCheckResult | null>(null);
const showTech = ref(false);
const bootstrapped = ref(false);
const actionError = ref("");
const progress = ref<api.DaemonDownloadProgress>({ percent: 0, stage: "" });
let progressTimer: ReturnType<typeof setInterval> | null = null;

const hint = computed(() => UPDATE_CHANNEL_HINT[channel.value]);
const tech = computed(() => UPDATE_CHANNEL_TECH[channel.value]);
const daemonTitle = computed(() => {
  const impl = result.value?.daemonImpl === "c" ? "C" : "Rust";
  return `守护 · ${impl}`;
});
const actionBusyLabel = computed(() => {
  if (actionBusy.value === "module") return "正在下载模块…";
  if (actionBusy.value === "daemon") {
    const labels: Record<string, string> = {
      prepare: "正在准备…",
      manifest: "正在获取通道清单…",
      binary: "正在下载守护…",
      verify: "正在校验…",
      activate: "正在切换服务…",
      done: "已完成",
      failed: "失败",
    };
    return labels[progress.value.stage] || "正在更新守护…";
  }
  return "";
});

async function selectChannel(next: UpdateChannel) {
  if (next === channel.value) return;
  if (next === "ci") {
    try {
      await showConfirmDialog({
        title: "切换到 CI？",
        message: "开发构建可能不稳定，仅建议排查问题或尝鲜时使用。确认切换？",
      });
    } catch {
      return;
    }
  }
  channel.value = next;
  writeStorage(STORAGE_KEYS.updateChannel, next);
}

function onPreferCdn(on: boolean) {
  preferCdn.value = on;
  setPreferCdn(on);
  void check(true);
}

async function check(silent = false) {
  busy.value = true;
  actionError.value = "";
  try {
    const r = await checkUpdateChannel(channel.value);
    result.value = r;
    if (r.error) showToast(r.error);
    else if (!silent) {
      if (!r.module && !r.daemon) showToast("未获取到远端信息");
      else showToast("检查完成");
    }
  } catch (e) {
    showToast(e instanceof Error ? e.message : String(e));
  } finally {
    busy.value = false;
  }
}

function startProgress(seed: api.DaemonDownloadProgress) {
  if (progressTimer) clearInterval(progressTimer);
  progress.value = seed;
  progressTimer = setInterval(() => {
    void api.loadDaemonDownloadProgress().then((p) => {
      if (p.stage || p.percent > 0) progress.value = p;
    });
  }, 400);
}

function stopProgress() {
  if (progressTimer) clearInterval(progressTimer);
  progressTimer = null;
  progress.value = { percent: 0, stage: "" };
}

async function updateModule() {
  const url = result.value?.module?.zipUrl;
  if (!url) {
    showToast("无模块下载地址");
    return;
  }
  actionBusy.value = "module";
  actionError.value = "";
  progress.value = { percent: 15, stage: "binary" };
  startProgress({ percent: 20, stage: "binary" });
  try {
    const r = await api.downloadAndOpenModuleInstaller(url);
    if (r.ok) {
      progress.value = { percent: 100, stage: "done" };
      showToast("已打开模块管理器，请确认刷写");
      await check(true);
    } else {
      showToast(api.moduleInstallErrorText(r.error));
    }
  } catch (e) {
    showToast(e instanceof Error ? e.message : String(e));
  } finally {
    stopProgress();
    actionBusy.value = "";
  }
}

async function updateDaemon() {
  const d = result.value?.daemon;
  if (!d?.manifestUrl && !d?.baseUrl) {
    showToast("无守护清单");
    return;
  }
  actionBusy.value = "daemon";
  actionError.value = "";
  startProgress({ percent: 5, stage: "prepare" });
  try {
    const st = await api.loadDaemonStatus().catch(() => null);
    const impl = st?.impl === "c" ? "c" : result.value?.daemonImpl === "c" ? "c" : "rust";
    const r = await api.installDaemon(impl, {
      manifestUrl: d.manifestUrl,
      pagesBase: d.baseUrl,
    });
    if (r.ok) {
      progress.value = { percent: 100, stage: "done" };
      showToast(r.version ? `守护已更新至 ${r.version}` : "守护已更新");
      await check(true);
    } else {
      const msg = api.daemonErrorText(r.error);
      actionError.value = msg;
      showToast(msg);
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    actionError.value = msg;
    showToast(msg);
  } finally {
    stopProgress();
    actionBusy.value = "";
  }
}

onMounted(async () => {
  await check(true);
  bootstrapped.value = true;
});

onUnmounted(stopProgress);

watch(channel, async () => {
  if (!bootstrapped.value) return;
  await check(true);
});
</script>

<template>
  <SectionHead
    title="更新通道"
    hint="检测读 updates · 正式下载 Pages · 预发布下载 Release · CI 下载 ci-dist"
  />
  <ThemedCard>
    <div class="channel-wrap">
      <div class="toolbar">
        <div class="seg" role="tablist" aria-label="更新通道">
          <button
            v-for="id in UPDATE_CHANNELS"
            :key="id"
            type="button"
            class="seg-item"
            :class="{ on: channel === id }"
            role="tab"
            :aria-selected="channel === id"
            :disabled="busy || !!actionBusy"
            @click="selectChannel(id)"
          >
            {{ UPDATE_CHANNEL_LABEL[id] }}
          </button>
        </div>
        <button
          type="button"
          class="refresh"
          :disabled="busy || !!actionBusy"
          aria-label="刷新"
          @click="check(false)"
        >
          {{ busy ? "…" : "刷新" }}
        </button>
      </div>

      <SwitchCell
        title="使用 CDN"
        label="开启后 updates/ci-dist 元数据走 jsDelivr；关闭则走 GitHub raw。正式 Pages / 预发布 Release 链接不受影响"
        :model-value="preferCdn"
        :disabled="busy || !!actionBusy"
        @update:model-value="onPreferCdn"
      />

      <div class="meta">
        <p class="hint">{{ hint }}</p>
        <button type="button" class="tech-toggle" @click="showTech = !showTech">
          {{ showTech ? "收起" : "了解通道" }}
        </button>
      </div>
      <p v-if="showTech" class="tech">{{ tech }}</p>

      <div v-if="channel === 'prerelease'" class="notice soft">
        <p>预发布通道：功能可能不完整，重要设备建议用正式版。</p>
      </div>

      <div v-if="result?.stableModuleNewer || result?.stableDaemonNewer" class="notice">
        <p>
          正式通道有新版本
          <template v-if="result.stableModuleNewer">
            · 模块 {{ result.stableModuleNewer.version }}
          </template>
          <template v-if="result.stableDaemonNewer">
            · 守护 {{ result.stableDaemonNewer.version }}
          </template>
        </p>
        <button
          type="button"
          class="notice-action"
          :disabled="busy || !!actionBusy"
          @click="selectChannel('stable')"
        >
          切换到正式
        </button>
      </div>

      <div v-if="busy && !result" class="loading" role="status">
        <span class="loading-spin" aria-hidden="true"></span>
        <span>正在检查更新…</span>
      </div>

      <div v-if="actionBusy" class="progress" role="status" aria-live="polite">
        <div class="progress-head">
          <span>{{ actionBusyLabel }}</span>
          <span>{{ progress.percent }}%</span>
        </div>
        <div class="progress-track">
          <span :style="{ width: `${Math.max(progress.percent, 8)}%` }"></span>
        </div>
      </div>

      <div v-if="result" class="result">
        <div class="item">
          <div class="item-top">
            <span class="name">模块</span>
            <span
              class="chip"
              :data-tone="
                !result.module ? 'warn' : result.moduleHasUpdate ? 'update' : 'ok'
              "
            >
              {{ !result.module ? "无数据" : result.moduleHasUpdate ? "可更新" : "最新" }}
            </span>
            <button
              v-if="result.module?.changelog"
              type="button"
              class="link"
              @click="api.openUrl(result.module.changelog!)"
            >
              说明
            </button>
            <van-button
              v-if="result.module?.zipUrl && result.moduleHasUpdate"
              size="mini"
              type="primary"
              :loading="actionBusy === 'module'"
              :disabled="!!actionBusy"
              @click="updateModule"
            >
              更新
            </van-button>
          </div>
          <p class="ver">
            {{ versionLine(result.moduleLocalVersion, result.module?.version) }}
          </p>
        </div>

        <div class="item">
          <div class="item-top">
            <span class="name">{{ daemonTitle }}</span>
            <span
              class="chip"
              :data-tone="
                !result.daemon ? 'warn' : result.daemonHasUpdate ? 'update' : 'ok'
              "
            >
              {{
                !result.daemon
                  ? "无数据"
                  : result.daemonMissing
                    ? "未安装"
                    : result.daemonHasUpdate
                      ? "可更新"
                      : "最新"
              }}
            </span>
            <van-button
              v-if="result.daemonHasUpdate"
              size="mini"
              type="primary"
              :loading="actionBusy === 'daemon'"
              :disabled="!!actionBusy"
              @click="updateDaemon"
            >
              {{ result.daemonMissing ? "安装" : "更新" }}
            </van-button>
          </div>
          <p class="ver">
            {{ versionLine(result.daemonLocalVersion, result.daemon?.version) }}
          </p>
          <p v-if="actionError" class="row-err">{{ actionError }}</p>
        </div>

        <p v-if="result.error" class="err">{{ result.error }}</p>
      </div>
    </div>
  </ThemedCard>
</template>

<style scoped lang="scss">
.channel-wrap {
  padding: 14px var(--qsc-cell-pad-x, 16px) 16px;
}

.toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}

.seg {
  flex: 1;
  display: flex;
  gap: 2px;
  padding: 3px;
  border-radius: 10px;
  background: color-mix(in srgb, var(--qsc-fill-2, rgba(0, 0, 0, 0.06)) 85%, transparent);
}

.seg-item {
  flex: 1;
  border: 0;
  border-radius: 8px;
  padding: 8px 0;
  font-size: 13px;
  color: var(--qsc-text-2);
  background: transparent;
  cursor: pointer;
}

.seg-item.on {
  background: var(--qsc-card, #fff);
  color: var(--van-primary-color, #1989fa);
  font-weight: 600;
  box-shadow: 0 0 0 1px
    color-mix(in srgb, var(--van-primary-color, #1989fa) 18%, transparent);
}

.seg-item:disabled {
  opacity: 0.55;
}

.refresh {
  border: 0;
  background: transparent;
  color: var(--van-primary-color, #1989fa);
  font-size: 13px;
  font-weight: 600;
  padding: 6px 4px;
  cursor: pointer;
  flex-shrink: 0;
}

.refresh:disabled {
  color: var(--qsc-text-2);
}

.meta {
  margin-top: 10px;
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
}

.hint {
  margin: 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text-2);
}

.tech-toggle {
  border: 0;
  background: transparent;
  padding: 0;
  font-size: 12px;
  font-weight: 600;
  color: var(--van-primary-color, #1989fa);
  cursor: pointer;
  flex-shrink: 0;
}

.tech {
  margin: 6px 0 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text-2);
}

.notice {
  margin-top: 12px;
  padding: 10px 12px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--van-primary-color, #1989fa) 12%, transparent);
  display: flex;
  align-items: center;
  gap: 10px;
}

.notice.soft {
  background: color-mix(in srgb, var(--qsc-fill-2, rgba(0, 0, 0, 0.06)) 80%, transparent);
}

.notice p {
  margin: 0;
  flex: 1;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text);
}

.notice-action {
  border: 0;
  background: transparent;
  color: var(--van-primary-color, #1989fa);
  font-size: 12px;
  font-weight: 700;
  padding: 4px 0;
  cursor: pointer;
  flex-shrink: 0;
}

.notice-action:disabled {
  opacity: 0.5;
}

.loading {
  margin-top: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 18px 16px;
  border-radius: 12px;
  border: 1px solid var(--qsc-border, rgba(0, 0, 0, 0.06));
  background: color-mix(in srgb, var(--qsc-fill-2, rgba(0, 0, 0, 0.04)) 80%, transparent);
  font-size: 13px;
  color: var(--qsc-text-2);
}

.loading-spin {
  width: 16px;
  height: 16px;
  border: 2px solid color-mix(in srgb, var(--qsc-accent, #3b82f6) 25%, transparent);
  border-top-color: var(--qsc-accent, #3b82f6);
  border-radius: 50%;
  animation: qsc-spin 0.8s linear infinite;
}

@keyframes qsc-spin {
  to {
    transform: rotate(360deg);
  }
}

.progress {
  margin-top: 12px;
  padding: 10px 12px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--qsc-fill-2, rgba(0, 0, 0, 0.05)) 90%, transparent);
}

.progress-head {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  font-size: 12px;
  color: var(--qsc-text-2);
  margin-bottom: 8px;
}

.progress-track {
  height: 6px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--qsc-border, rgba(0, 0, 0, 0.08)) 80%, transparent);
  overflow: hidden;
}

.progress-track span {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: var(--van-primary-color, #1989fa);
  transition: width 0.25s ease;
}

.result {
  margin-top: 14px;
  display: flex;
  flex-direction: column;
}

.item {
  padding: 12px 0;
  border-top: 1px solid var(--qsc-border, rgba(0, 0, 0, 0.06));
}

.item:first-child {
  border-top: 0;
  padding-top: 2px;
}

.item-top {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.name {
  font-size: 14px;
  font-weight: 600;
  color: var(--qsc-text);
  margin-right: auto;
}

.ver {
  margin: 6px 0 0;
  font-size: 12px;
  line-height: 1.4;
  color: var(--qsc-text-2);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.chip {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 999px;
  flex-shrink: 0;
}

.chip[data-tone="ok"] {
  color: var(--van-success-color, #07c160);
  background: color-mix(in srgb, var(--van-success-color, #07c160) 14%, transparent);
}

.chip[data-tone="update"] {
  color: var(--van-primary-color, #1989fa);
  background: color-mix(in srgb, var(--van-primary-color, #1989fa) 14%, transparent);
}

.chip[data-tone="warn"] {
  color: var(--van-danger-color, #ee0a24);
  background: color-mix(in srgb, var(--van-danger-color, #ee0a24) 12%, transparent);
}

.link {
  border: 0;
  background: transparent;
  color: var(--van-primary-color, #1989fa);
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  padding: 0;
  flex-shrink: 0;
}

.row-err,
.err {
  margin: 8px 0 0;
  font-size: 12px;
  line-height: 1.4;
  color: var(--van-danger-color, #ee0a24);
}
</style>
