<script setup lang="ts">
import {
  UPDATE_CHANNELS,
  UPDATE_CHANNEL_LABEL,
  type UpdateChannel,
} from "@/shared";

defineProps<{
  channel: UpdateChannel;
  preferCdn: boolean;
  busy: boolean;
  actionBusy: boolean;
  hint: string;
  tech: string;
  showTech: boolean;
}>();

const emit = defineEmits<{
  selectChannel: [id: UpdateChannel];
  check: [silent: boolean];
  preferCdn: [on: boolean];
  toggleTech: [];
}>();
</script>

<template>
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
        :disabled="busy || actionBusy"
        @click="emit('selectChannel', id)"
      >
        {{ UPDATE_CHANNEL_LABEL[id] }}
      </button>
    </div>
    <button
      type="button"
      class="refresh"
      :disabled="busy || actionBusy"
      aria-label="刷新"
      @click="emit('check', false)"
    >
      {{ busy ? "…" : "刷新" }}
    </button>
  </div>

  <div v-if="channel === 'ci'" class="cdn-row">
    <div class="cdn-text">
      <p class="cdn-title">使用 CDN</p>
      <p class="cdn-desc">
        开启后 CI 元数据/产物走 jsDelivr（有缓存，刚发版若检不到可关闭或稍后再试）；关闭则走 GitHub
        raw
      </p>
    </div>
    <van-switch
      :model-value="preferCdn"
      :disabled="busy || actionBusy"
      size="20px"
      @update:model-value="emit('preferCdn', $event)"
    />
  </div>

  <div class="meta">
    <p class="hint">{{ hint }}</p>
    <button type="button" class="tech-toggle" @click="emit('toggleTech')">
      {{ showTech ? "收起" : "了解通道" }}
    </button>
  </div>
  <p v-if="showTech" class="tech">{{ tech }}</p>
</template>

<style scoped lang="scss">
@use "./update-channel.scss";
</style>
