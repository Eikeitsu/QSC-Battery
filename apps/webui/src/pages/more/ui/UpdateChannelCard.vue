<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import UpdateActionProgress from "@/features/update/UpdateActionProgress.vue";
import UpdateChannelNotices from "@/features/update/UpdateChannelNotices.vue";
import UpdateChannelToolbar from "@/features/update/UpdateChannelToolbar.vue";
import UpdateResultPanel from "@/features/update/UpdateResultPanel.vue";
import { useUpdateChannelCard } from "@/features/update/useUpdateChannelCard";

const {
  channel,
  preferCdn,
  busy,
  actionBusy,
  result,
  showTech,
  actionError,
  hint,
  tech,
  daemonTitle,
  actionBusyLabelText,
  progressPct,
  selectChannel,
  onPreferCdn,
  check,
  updateModule,
  updateApp,
  updateDaemon,
} = useUpdateChannelCard();
</script>

<template>
  <SectionHead title="更新通道" hint="正式 / 预发布 / CI 三通道检测与安装" />
  <ThemedCard>
    <div class="channel-wrap">
      <UpdateChannelToolbar
        :channel="channel"
        :prefer-cdn="preferCdn"
        :busy="busy"
        :action-busy="!!actionBusy"
        :hint="hint"
        :tech="tech"
        :show-tech="showTech"
        @select-channel="selectChannel"
        @check="check"
        @prefer-cdn="onPreferCdn"
        @toggle-tech="showTech = !showTech"
      />

      <UpdateChannelNotices
        :channel="channel"
        :result="result"
        :busy="busy"
        :action-busy="!!actionBusy"
        @select-channel="selectChannel"
      />

      <div v-if="busy && !result" class="loading" role="status">
        <span class="loading-spin" aria-hidden="true"></span>
        <span>正在检查更新…</span>
      </div>

      <UpdateActionProgress
        v-if="actionBusy"
        :label="actionBusyLabelText"
        :progress-pct="progressPct"
      />

      <UpdateResultPanel
        v-if="result"
        :result="result"
        :daemon-title="daemonTitle"
        :action-busy="actionBusy"
        :action-error="actionError"
        @update-module="updateModule"
        @update-app="updateApp"
        @update-daemon="updateDaemon"
      />
    </div>
  </ThemedCard>
</template>

<style scoped lang="scss">
@use "@/features/update/update-channel";
</style>
