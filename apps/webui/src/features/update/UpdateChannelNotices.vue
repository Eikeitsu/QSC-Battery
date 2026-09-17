<script setup lang="ts">
import type { ChannelCheckResult, UpdateChannel } from "@/shared";

defineProps<{
  channel: UpdateChannel;
  result: ChannelCheckResult | null;
  busy: boolean;
  actionBusy: boolean;
}>();

const emit = defineEmits<{
  selectChannel: [id: UpdateChannel];
}>();
</script>

<template>
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
      :disabled="busy || actionBusy"
      @click="emit('selectChannel', 'stable')"
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
</template>

<style scoped lang="scss">
@use "./update-channel";
</style>
