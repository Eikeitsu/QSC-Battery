<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
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
  parseUpdateChannel,
  readStorage,
  writeStorage,
  type ChannelCheckResult,
  type UpdateChannel,
} from "@/shared";

const channel = ref<UpdateChannel>(
  parseUpdateChannel(readStorage(STORAGE_KEYS.updateChannel)),
);
const busy = ref(false);
const actionBusy = ref<"module" | "daemon" | "">("");
const result = ref<ChannelCheckResult | null>(null);
const showTech = ref(false);
const bootstrapped = ref(false);

const hint = computed(() => UPDATE_CHANNEL_HINT[channel.value]);
const tech = computed(() => UPDATE_CHANNEL_TECH[channel.value]);

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

async function check(silent = false) {
  busy.value = true;
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

async function updateModule() {
  const url = result.value?.module?.zipUrl;
  if (!url) {
    showToast("无模块下载地址");
    return;
  }
  actionBusy.value = "module";
  try {
    const r = await api.downloadAndOpenModuleInstaller(url);
    if (r.ok) {
      showToast("已打开模块管理器，请确认刷写");
      await check(true);
    } else {
      showToast(api.moduleInstallErrorText(r.error));
    }
  } catch (e) {
    showToast(e instanceof Error ? e.message : String(e));
  } finally {
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
  try {
    const r = await api.installDaemon("rust", {
      manifestUrl: d.manifestUrl,
      pagesBase: d.baseUrl,
    });
    if (r.ok) {
      showToast(r.version ? `守护已更新至 ${r.version}` : "守护已更新");
      await check(true);
    } else {
      showToast(api.daemonErrorText(r.error));
    }
  } catch (e) {
    showToast(e instanceof Error ? e.message : String(e));
  } finally {
    actionBusy.value = "";
  }
}

onMounted(async () => {
  await check(true);
  bootstrapped.value = true;
});

watch(channel, async () => {
  if (!bootstrapped.value) return;
  await check(true);
});
</script>

<template>
  <SectionHead title="更新通道" hint="仅检测模块与守护 · 可在本页直接安装" />
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
      <p class="hint">{{ hint }}</p>
      <button type="button" class="tech-toggle" @click="showTech = !showTech">
        {{ showTech ? "收起通道说明" : "了解通道" }}
      </button>
      <p v-if="showTech" class="tech">{{ tech }}</p>

      <div v-if="channel === 'prerelease'" class="stable-banner soft">
        <p>当前为预发布通道：功能可能不完整，重要设备建议用正式版。</p>
      </div>

      <div
        v-if="result?.stableModuleNewer || result?.stableDaemonNewer"
        class="stable-banner"
      >
        <p>
          正式通道有新版本
          <template v-if="result.stableModuleNewer">
            · 模块 {{ result.stableModuleNewer.version }}
          </template>
          <template v-if="result.stableDaemonNewer">
            · 守护 {{ result.stableDaemonNewer.version }}
          </template>
        </p>
        <van-button size="mini" plain type="primary" @click="selectChannel('stable')">
          切换到正式
        </van-button>
      </div>

      <div v-if="busy && !result" class="loading">正在检查更新…</div>

      <div v-if="result" class="result">
        <div class="item">
          <div class="item-main">
            <span class="name">模块</span>
            <span class="ver">
              {{ result.moduleLocalVersion || "--" }} →
              {{ result.module?.version || "--" }}
            </span>
            <span
              class="chip"
              :data-tone="
                !result.module ? 'warn' : result.moduleHasUpdate ? 'update' : 'ok'
              "
            >
              {{ !result.module ? "无数据" : result.moduleHasUpdate ? "可更新" : "最新" }}
            </span>
          </div>
          <div class="item-actions">
            <button
              v-if="result.module?.changelog"
              type="button"
              class="link"
              @click="api.openUrl(result.module.changelog!)"
            >
              更新说明
            </button>
            <van-button
              v-if="result.module?.zipUrl && result.moduleHasUpdate"
              size="mini"
              type="primary"
              :loading="actionBusy === 'module'"
              :disabled="!!actionBusy"
              @click="updateModule"
            >
              下载并刷入
            </van-button>
          </div>
        </div>

        <div class="item">
          <div class="item-main">
            <span class="name">守护</span>
            <span class="ver">
              {{ result.daemonLocalVersion || "--" }} →
              {{ result.daemon?.version || "--" }}
            </span>
            <span
              class="chip"
              :data-tone="
                !result.daemon ? 'warn' : result.daemonHasUpdate ? 'update' : 'ok'
              "
            >
              {{ !result.daemon ? "无数据" : result.daemonHasUpdate ? "可更新" : "最新" }}
            </span>
          </div>
          <div class="item-actions">
            <van-button
              v-if="result.daemonHasUpdate"
              size="mini"
              type="primary"
              :loading="actionBusy === 'daemon'"
              :disabled="!!actionBusy"
              @click="updateDaemon"
            >
              下载并替换
            </van-button>
          </div>
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
}

.refresh:disabled {
  color: var(--qsc-text-2);
}

.hint {
  margin: 10px 0 6px;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text-2);
}

.tech-toggle {
  border: 0;
  background: transparent;
  padding: 0;
  font-size: 12px;
  color: var(--qsc-text-2);
  cursor: pointer;
}

.tech {
  margin: 6px 0 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text-2);
}

.stable-banner {
  margin-top: 12px;
  padding: 10px 12px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--van-primary-color, #1989fa) 12%, transparent);
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.stable-banner.soft {
  background: color-mix(in srgb, var(--qsc-fill-2, rgba(0, 0, 0, 0.06)) 80%, transparent);
}

.stable-banner p {
  margin: 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text);
}

.loading {
  margin-top: 14px;
  font-size: 12px;
  color: var(--qsc-text-2);
}

.result {
  margin-top: 14px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.item {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 10px 0;
  border-top: 1px solid var(--qsc-border, rgba(0, 0, 0, 0.06));
}

.item:first-child {
  border-top: 0;
  padding-top: 0;
}

.item-main {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.name {
  font-size: 13px;
  font-weight: 600;
  color: var(--qsc-text);
  width: 2.5em;
  flex-shrink: 0;
}

.ver {
  flex: 1;
  font-size: 13px;
  color: var(--qsc-text);
  min-width: 0;
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

.item-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: flex-end;
  align-items: center;
}

.link {
  border: 0;
  background: transparent;
  color: var(--van-primary-color, #1989fa);
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  padding: 4px;
}

.err {
  margin: 0;
  font-size: 12px;
  color: var(--van-danger-color, #ee0a24);
}
</style>
