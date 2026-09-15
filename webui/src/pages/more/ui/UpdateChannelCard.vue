<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { showConfirmDialog, showToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
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
const actionBusy = ref<"module" | "app" | "daemon" | "">("");
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
  if (actionBusy.value === "app") return "正在下载 APP…";
  if (actionBusy.value === "daemon") {
    const labels: Record<string, string> = {
      prepare: "正在准备…",
      manifest: "正在获取清单…",
      binary: "正在下载守护…",
      verify: "正在校验…",
      activate: "正在切换服务…",
      done: "已完成",
    };
    const stage = progress.value.stage;
    if (stage === "failed") return "正在更新守护…";
    return labels[stage] || "正在更新守护…";
  }
  return "";
});
const progressPct = computed(() =>
  Math.max(0, Math.min(100, progress.value.percent || 0)),
);

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
      if (!r.module && !r.app && !r.daemon) showToast("未获取到远端信息");
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
      if (!actionBusy.value) return;
      // 忽略上次失败残留，避免一闪「失败」
      if (p.stage === "failed") return;
      if (!p.stage && p.percent <= 0) return;
      // 进度只前进，避免抖动回退
      const nextPct = Math.max(progress.value.percent, p.percent);
      progress.value = { percent: nextPct, stage: p.stage || progress.value.stage };
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
  if (result.value?.moduleCanSwitch) {
    try {
      await showConfirmDialog({
        title: "切回通道模块？",
        message: `本地模块高于当前通道，将刷入 ${result.value.module?.version || "通道版"}，需在模块管理器中确认。`,
      });
    } catch {
      return;
    }
  }
  actionBusy.value = "module";
  actionError.value = "";
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

async function updateApp() {
  const url = result.value?.app?.apkUrl;
  if (!url) {
    showToast("无 APP 下载地址");
    return;
  }
  if (result.value?.appCanSwitch) {
    try {
      await showConfirmDialog({
        title: "切回通道 APP？",
        message: `本地 APP 高于当前通道。系统可能拒绝降级，失败请先卸载再装（${result.value.app?.version || "通道版"}）。`,
      });
    } catch {
      return;
    }
  }
  actionBusy.value = "app";
  actionError.value = "";
  startProgress({ percent: 25, stage: "binary" });
  try {
    const r = await api.downloadAndInstallApp(url);
    if (r.ok) {
      progress.value = { percent: 100, stage: "done" };
      showToast(r.mode === "pm" ? "APP 已安装" : "已打开系统安装界面，请完成安装");
      await check(true);
    } else {
      const msg = api.appInstallErrorText(r.error);
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

async function updateDaemon() {
  const d = result.value?.daemon;
  if (!d?.manifestUrl && !d?.baseUrl) {
    showToast("无守护清单");
    return;
  }
  if (result.value?.daemonCanSwitch) {
    try {
      await showConfirmDialog({
        title: "切回通道守护？",
        message: `本地守护高于当前通道，将热切换为 ${d.version || "通道版"}。`,
      });
    } catch {
      return;
    }
  }
  actionBusy.value = "daemon";
  actionError.value = "";
  await api.clearDaemonDownloadProgress().catch(() => undefined);
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
      showToast(r.version ? `守护已切换至 ${r.version}` : "守护已切换");
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
  <SectionHead title="更新通道" hint="正式 / 预发布 / CI 三通道检测与安装" />
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

      <div v-if="channel === 'ci'" class="cdn-row">
        <div class="cdn-text">
          <p class="cdn-title">使用 CDN</p>
          <p class="cdn-desc">
            开启后 CI 元数据/产物走
            jsDelivr（有缓存，刚发版若检不到可关闭或稍后再试）；关闭则走 GitHub raw
          </p>
        </div>
        <van-switch
          :model-value="preferCdn"
          :disabled="busy || !!actionBusy"
          size="20px"
          @update:model-value="onPreferCdn"
        />
      </div>

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

      <div
        v-if="
          result?.stableModuleNewer || result?.stableAppNewer || result?.stableDaemonNewer
        "
        class="notice"
      >
        <p>
          正式通道有新版本
          <template v-if="result.stableModuleNewer">
            · 模块 {{ result.stableModuleNewer.version }}
          </template>
          <template v-if="result.stableAppNewer">
            · APP {{ result.stableAppNewer.version }}
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

      <div
        v-if="result?.moduleCanSwitch || result?.appCanSwitch || result?.daemonCanSwitch"
        class="notice soft"
      >
        <p>
          本地高于本通道
          <template v-if="result.moduleCanSwitch">· 模块可刷回</template>
          <template v-if="result.appCanSwitch">· APP 可切换</template>
          <template v-if="result.daemonCanSwitch">· 守护可热切换</template>
        </p>
      </div>

      <div v-if="busy && !result" class="loading" role="status">
        <span class="loading-spin" aria-hidden="true"></span>
        <span>正在检查更新…</span>
      </div>

      <div v-if="actionBusy" class="progress" role="status" aria-live="polite">
        <div class="progress-head">
          <span>{{ actionBusyLabel }}</span>
          <span class="progress-pct">{{ progressPct }}%</span>
        </div>
        <div class="progress-track">
          <span :style="{ width: `${Math.max(progressPct, 6)}%` }"></span>
        </div>
      </div>

      <div v-if="result" class="result">
        <div class="item">
          <div class="item-top">
            <span class="name">模块</span>
            <span
              class="chip"
              :data-tone="
                !result.module
                  ? 'warn'
                  : result.moduleHasUpdate || result.moduleCanSwitch
                    ? 'update'
                    : 'ok'
              "
            >
              {{
                !result.module
                  ? "无数据"
                  : result.moduleHasUpdate
                    ? "可更新"
                    : result.moduleCanSwitch
                      ? "可切换"
                      : "最新"
              }}
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
              v-if="
                result.module?.zipUrl &&
                (result.moduleHasUpdate || result.moduleCanSwitch)
              "
              size="mini"
              type="primary"
              round
              :loading="actionBusy === 'module'"
              :disabled="!!actionBusy"
              @click="updateModule"
            >
              {{ result.moduleCanSwitch && !result.moduleHasUpdate ? "切换" : "更新" }}
            </van-button>
          </div>
          <p class="ver">
            {{ versionLine(result.moduleLocalVersion, result.module?.version) }}
          </p>
        </div>

        <div class="item">
          <div class="item-top">
            <span class="name">APP</span>
            <span
              class="chip"
              :data-tone="
                !result.app
                  ? 'warn'
                  : result.appHasUpdate || result.appCanSwitch
                    ? 'update'
                    : 'ok'
              "
            >
              {{
                !result.app
                  ? "无数据"
                  : result.appMissing
                    ? "未安装"
                    : result.appHasUpdate
                      ? "可更新"
                      : result.appCanSwitch
                        ? "可切换"
                        : "最新"
              }}
            </span>
            <button
              v-if="result.app?.changelog"
              type="button"
              class="link"
              @click="api.openUrl(result.app.changelog!)"
            >
              说明
            </button>
            <van-button
              v-if="result.app?.apkUrl && (result.appHasUpdate || result.appCanSwitch)"
              size="mini"
              type="primary"
              round
              :loading="actionBusy === 'app'"
              :disabled="!!actionBusy"
              @click="updateApp"
            >
              {{
                result.appMissing
                  ? "安装"
                  : result.appCanSwitch && !result.appHasUpdate
                    ? "切换"
                    : "更新"
              }}
            </van-button>
          </div>
          <p class="ver">
            {{
              versionLine(
                result.appMissing ? "" : result.appLocalVersion,
                result.app?.version,
              )
            }}
          </p>
        </div>

        <div class="item">
          <div class="item-top">
            <span class="name">{{ daemonTitle }}</span>
            <span
              class="chip"
              :data-tone="
                !result.daemon
                  ? 'warn'
                  : result.daemonHasUpdate || result.daemonCanSwitch
                    ? 'update'
                    : 'ok'
              "
            >
              {{
                !result.daemon
                  ? "无数据"
                  : result.daemonMissing
                    ? "未安装"
                    : result.daemonHasUpdate
                      ? "可更新"
                      : result.daemonCanSwitch
                        ? "可切换"
                        : "最新"
              }}
            </span>
            <van-button
              v-if="result.daemonHasUpdate || result.daemonCanSwitch"
              size="mini"
              type="primary"
              round
              :loading="actionBusy === 'daemon'"
              :disabled="!!actionBusy"
              @click="updateDaemon"
            >
              {{
                result.daemonMissing
                  ? "安装"
                  : result.daemonCanSwitch && !result.daemonHasUpdate
                    ? "切换"
                    : "更新"
              }}
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
  padding: 12px var(--qsc-cell-pad-x, 16px) 14px;
}

.toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
}

.cdn-row {
  margin-top: 12px;
  display: flex;
  align-items: flex-start;
  gap: 12px;
}

.cdn-text {
  flex: 1;
  min-width: 0;
}

.cdn-title {
  margin: 0;
  font-size: 14px;
  font-weight: 650;
  color: var(--qsc-text);
}

.cdn-desc {
  margin: 4px 0 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text-2);
}

.seg {
  flex: 1;
  display: flex;
  gap: 2px;
  padding: 3px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--qsc-fill-2, rgba(0, 0, 0, 0.06)) 90%, transparent);
}

.seg-item {
  flex: 1;
  border: 0;
  border-radius: 9px;
  padding: 9px 0;
  font-size: 13px;
  letter-spacing: 0.01em;
  color: var(--qsc-text-2);
  background: transparent;
  cursor: pointer;
  transition:
    background 0.15s ease,
    color 0.15s ease,
    box-shadow 0.15s ease;
}

.seg-item.on {
  background: var(--qsc-card, #fff);
  color: var(--van-primary-color, #1989fa);
  font-weight: 650;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
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
  padding: 6px 2px;
  cursor: pointer;
  flex-shrink: 0;
}

.refresh:disabled {
  color: var(--qsc-text-2);
}

.meta {
  margin-top: 12px;
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
  background: color-mix(in srgb, var(--van-primary-color, #1989fa) 10%, transparent);
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
  padding: 16px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--qsc-fill-2, rgba(0, 0, 0, 0.04)) 85%, transparent);
  font-size: 13px;
  color: var(--qsc-text-2);
}

.loading-spin {
  width: 15px;
  height: 15px;
  border: 2px solid color-mix(in srgb, var(--van-primary-color, #1989fa) 22%, transparent);
  border-top-color: var(--van-primary-color, #1989fa);
  border-radius: 50%;
  animation: qsc-spin 0.75s linear infinite;
}

@keyframes qsc-spin {
  to {
    transform: rotate(360deg);
  }
}

.progress {
  margin-top: 12px;
  padding: 12px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--van-primary-color, #1989fa) 6%, transparent);
}

.progress-head {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  font-size: 12px;
  color: var(--qsc-text-2);
  margin-bottom: 8px;
}

.progress-pct {
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  color: var(--van-primary-color, #1989fa);
}

.progress-track {
  height: 5px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--van-primary-color, #1989fa) 14%, transparent);
  overflow: hidden;
}

.progress-track span {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: var(--van-primary-color, #1989fa);
  transition: width 0.28s ease;
}

.result {
  margin-top: 8px;
  display: flex;
  flex-direction: column;
}

.item {
  padding: 12px 0;
  border-top: 1px solid var(--qsc-border, rgba(0, 0, 0, 0.06));
}

.item:first-child {
  border-top: 0;
  padding-top: 4px;
}

.item-top {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.name {
  font-size: 14px;
  font-weight: 650;
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
  background: color-mix(in srgb, var(--van-success-color, #07c160) 12%, transparent);
}

.chip[data-tone="update"] {
  color: var(--van-primary-color, #1989fa);
  background: color-mix(in srgb, var(--van-primary-color, #1989fa) 12%, transparent);
}

.chip[data-tone="warn"] {
  color: var(--van-danger-color, #ee0a24);
  background: color-mix(in srgb, var(--van-danger-color, #ee0a24) 10%, transparent);
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
