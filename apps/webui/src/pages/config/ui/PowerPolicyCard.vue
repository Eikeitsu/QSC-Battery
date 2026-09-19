<script setup lang="ts">
import { computed } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import ScheduleEditor from "@/shared/ui/ScheduleEditor.vue";
import { useConfigFormContext } from "@/composables";

const { store, onSwitch, saveNightSchedule } = useConfigFormContext();

async function persist() {
  await store.saveSettings(false);
}

const profile = computed({
  get: () => store.settings.power_profile || "balanced",
  set: (v: string) => {
    store.settings.power_profile = v;
    if (v === "aggressive") {
      store.settings.loop_interval_idle_native_sec = "900";
      store.settings.heartbeat_sec = "600";
    } else if (v === "balanced") {
      store.settings.loop_interval_idle_native_sec = "600";
      store.settings.heartbeat_sec = "180";
    }
    void persist();
  },
});

const customOpen = computed(() => store.settings.power_profile === "custom");
</script>

<template>
  <SectionHead
    title="省电策略"
    hint="未插电事件驱动驻停；插拔仍即时响应。模块进程仍有基线功耗，不是绝对零耗电。"
  />
  <ThemedCard>
    <SwitchCell
      title="省电模式"
      label="关则全程最短间隔，最费电"
      :model-value="store.settings.power_saver !== '0'"
      @update:model-value="(v) => onSwitch('power_saver', v)"
    />

    <div class="profile-row">
      <span class="label">档位</span>
      <van-radio-group v-model="profile" direction="horizontal">
        <van-radio name="balanced">均衡</van-radio>
        <van-radio name="aggressive">强力</van-radio>
        <van-radio name="custom">自定义</van-radio>
      </van-radio-group>
    </div>
    <p class="hint">
      均衡≈现网；强力拉长未插电兜底与心跳、强制静态简介；自定义展开下方秒数。
    </p>

    <SwitchCell
      title="息屏加强"
      label="未插电息屏时放大 idle、暂停动态简介"
      :model-value="store.settings.screen_off_saver !== '0'"
      @update:model-value="(v) => onSwitch('screen_off_saver', v)"
    />
    <SwitchCell
      title="夜间省电"
      label="命中时段进入深驻停（DeepPark）"
      :model-value="store.settings.night_saver === '1'"
      @update:model-value="(v) => onSwitch('night_saver', v)"
    />
    <template v-if="store.settings.night_saver === '1'">
      <ScheduleEditor v-model="store.nightSchedule" @change="saveNightSchedule" />
    </template>
    <SwitchCell
      title="深睡"
      label="息屏持续一段时间或夜间时用更深 idle / 满轮间隔"
      :model-value="store.settings.deep_idle_enable !== '0'"
      @update:model-value="(v) => onSwitch('deep_idle_enable', v)"
    />
    <SwitchCell
      title="动态简介"
      label="关后列表固定文案并停 worker；强力/深睡也会强制静态"
      :model-value="store.settings.description_enable !== '0'"
      @update:model-value="(v) => onSwitch('description_enable', v)"
    />

    <template v-if="customOpen || store.settings.deep_idle_enable !== '0'">
      <van-field
        v-model="store.settings.deep_after_sec"
        type="digit"
        label="深睡等待(秒)"
        placeholder="息屏多久后深睡"
        input-align="right"
        @change="persist"
      />
      <van-field
        v-model="store.settings.deep_idle_sec"
        type="digit"
        label="深睡 idle(秒)"
        placeholder="60–900"
        input-align="right"
        @change="persist"
      />
      <van-field
        v-model="store.settings.deep_full_gap_sec"
        type="digit"
        label="深睡满轮间隔"
        placeholder="秒"
        input-align="right"
        @change="persist"
      />
      <van-field
        v-model="store.settings.heartbeat_sec"
        type="digit"
        label="心跳间隔(秒)"
        placeholder="60–900"
        input-align="right"
        @change="persist"
      />
    </template>

    <van-collapse v-if="customOpen" :model-value="['custom']">
      <van-collapse-item name="custom" title="自定义间隔">
        <van-field
          v-model="store.settings.loop_interval_idle_sec"
          type="digit"
          label="未插电间隔"
          input-align="right"
          @change="persist"
        />
        <van-field
          v-model="store.settings.loop_interval_idle_native_sec"
          type="digit"
          label="未插电·有守护"
          input-align="right"
          @change="persist"
        />
        <van-field
          v-model="store.settings.loop_interval_plugged_sec"
          type="digit"
          label="插电远阈值"
          input-align="right"
          @change="persist"
        />
        <van-field
          v-model="store.settings.loop_interval_plugged_native_sec"
          type="digit"
          label="插电·有守护"
          input-align="right"
          @change="persist"
        />
        <van-field
          v-model="store.settings.loop_interval_sec"
          type="digit"
          label="近阈值间隔"
          input-align="right"
          @change="persist"
        />
        <van-field
          v-model="store.settings.loop_interval_maintain_sec"
          type="digit"
          label="停充维持"
          placeholder="基线；息屏/夜间非 MCA 会再拉长"
          input-align="right"
          @change="persist"
        />
        <van-field
          v-model="store.settings.loop_interval_near_window"
          type="digit"
          label="近窗口(%)"
          input-align="right"
          @change="persist"
        />
      </van-collapse-item>
    </van-collapse>

    <p class="hint">
      有 Rust 守护时未插电靠插拔 uevent 唤醒；无守护时最长延迟约等于未插电/深睡 idle。
    </p>
  </ThemedCard>
</template>

<style scoped>
.profile-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 16px;
}

.profile-row .label {
  font-size: 14px;
  color: var(--van-text-color);
}

.hint {
  margin: 0 16px 12px;
  font-size: 12px;
  color: var(--van-text-color-2);
  line-height: 1.45;
}
</style>
