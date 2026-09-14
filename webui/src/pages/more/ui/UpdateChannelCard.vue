<script setup lang="ts">
import { computed, ref } from "vue";
import { showToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import {
  STORAGE_KEYS,
  UPDATE_CHANNELS,
  UPDATE_CHANNEL_HINT,
  UPDATE_CHANNEL_LABEL,
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
const result = ref<ChannelCheckResult | null>(null);

const hint = computed(() => UPDATE_CHANNEL_HINT[channel.value]);

function selectChannel(next: UpdateChannel) {
  channel.value = next;
  writeStorage(STORAGE_KEYS.updateChannel, next);
  result.value = null;
}

async function check() {
  busy.value = true;
  result.value = null;
  try {
    const r = await checkUpdateChannel(channel.value);
    result.value = r;
    if (r.error) showToast(r.error);
    else if (!r.module && !r.app && !r.daemon) showToast("未获取到远端信息");
    else showToast("检查完成");
  } catch (e) {
    showToast(e instanceof Error ? e.message : String(e));
  } finally {
    busy.value = false;
  }
}

function openUrl(url?: string) {
  if (!url) {
    showToast("无下载链接");
    return;
  }
  window.open(url, "_blank", "noopener,noreferrer");
}
</script>

<template>
  <SectionHead
    title="更新通道"
    hint="正式 / 预发布 / CI · 读 updates 分支；Magisk 仍用 Pages"
  />
  <ThemedCard>
    <div class="channel-wrap">
      <div class="seg" role="tablist" aria-label="更新通道">
        <button
          v-for="id in UPDATE_CHANNELS"
          :key="id"
          type="button"
          class="seg-item"
          :class="{ on: channel === id }"
          role="tab"
          :aria-selected="channel === id"
          @click="selectChannel(id)"
        >
          {{ UPDATE_CHANNEL_LABEL[id] }}
        </button>
      </div>
      <p class="hint">{{ hint }}</p>
      <van-button
        block
        type="primary"
        size="small"
        :loading="busy"
        :disabled="busy"
        @click="check"
      >
        {{ busy ? "检查中…" : "检查更新" }}
      </van-button>

      <div
        v-if="
          result?.stableModuleNewer || result?.stableAppNewer || result?.stableDaemonNewer
        "
        class="stable-banner"
      >
        <p>
          正式通道有新版本
          <template v-if="result.stableModuleNewer">
            · 模块 {{ result.stableModuleNewer.version }} ({{
              result.stableModuleNewer.versionCode
            }})
          </template>
          <template v-if="result.stableAppNewer">
            · APP {{ result.stableAppNewer.version }} ({{
              result.stableAppNewer.versionCode
            }})
          </template>
          <template v-if="result.stableDaemonNewer">
            · 守护 {{ result.stableDaemonNewer.version }} ({{
              result.stableDaemonNewer.versionCode
            }})
          </template>
        </p>
        <van-button size="mini" plain type="primary" @click="selectChannel('stable')">
          切换到正式
        </van-button>
      </div>

      <div v-if="result" class="result">
        <div class="row">
          <span class="k">模块远端</span>
          <span class="v">
            {{
              result.module
                ? `${result.module.version} (${result.module.versionCode})`
                : "--"
            }}
          </span>
        </div>
        <div class="row">
          <span class="k">APP 远端</span>
          <span class="v">
            {{ result.app ? `${result.app.version} (${result.app.versionCode})` : "--" }}
          </span>
        </div>
        <div class="row">
          <span class="k">守护远端</span>
          <span class="v">
            {{
              result.daemon
                ? `${result.daemon.version} (${result.daemon.versionCode})`
                : "--"
            }}
          </span>
        </div>
        <div class="actions">
          <van-button
            v-if="result.module?.zipUrl"
            size="small"
            plain
            type="primary"
            @click="openUrl(result.module.zipUrl)"
          >
            打开模块 zip
          </van-button>
          <van-button
            v-if="result.app?.apkUrl || result.module?.apkUrl"
            size="small"
            plain
            type="primary"
            @click="openUrl(result.app?.apkUrl || result.module?.apkUrl)"
          >
            打开 APP
          </van-button>
          <van-button
            v-if="result.daemon?.manifestUrl || result.daemon?.baseUrl"
            size="small"
            plain
            type="primary"
            @click="openUrl(result.daemon?.manifestUrl || result.daemon?.baseUrl)"
          >
            打开守护清单
          </van-button>
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

.seg {
  display: flex;
  gap: 4px;
  padding: 4px;
  border-radius: 14px;
  background: var(--qsc-fill-2, rgba(0, 0, 0, 0.06));
}

.seg-item {
  flex: 1;
  border: 0;
  border-radius: 10px;
  padding: 10px 0;
  font-size: 13px;
  color: var(--qsc-text-2);
  background: transparent;
  cursor: pointer;
}

.seg-item.on {
  background: color-mix(in srgb, var(--van-primary-color, #1989fa) 16%, transparent);
  color: var(--van-primary-color, #1989fa);
  font-weight: 600;
}

.hint {
  margin: 10px 0 12px;
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

.stable-banner p {
  margin: 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--qsc-text);
}

.result {
  margin-top: 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  font-size: 13px;
}

.k {
  color: var(--qsc-text-2);
}

.v {
  color: var(--qsc-text);
  text-align: right;
  word-break: break-all;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 4px;
}

.err {
  margin: 0;
  font-size: 12px;
  color: var(--van-danger-color, #ee0a24);
}
</style>
