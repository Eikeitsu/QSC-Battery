<script setup lang="ts">
import { computed } from "vue";
import PresetValue from "@/shared/ui/PresetValue.vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import ScheduleEditor from "@/shared/ui/ScheduleEditor.vue";
import { POWER_START_PRESETS, POWER_STOP_PRESETS } from "@/shared";
import { useConfigFormContext } from "@/composables";
import ConfigBlock from "./ConfigBlock.vue";

const { store, setPower, onSwitch, savePowerStopSchedule, saveNotifyQuietSchedule } =
  useConfigFormContext();

const holdOptions = [
  { name: "关", value: "0" },
  { name: "自动", value: "auto" },
  { name: "开", value: "1" },
];

const notifyOn = computed(() => store.settings.notify_charge_event === "1");

const kindSet = computed(() => {
  const raw = String(store.settings.notify_charge_kinds || "stop,resume,fail");
  return new Set(
    raw
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  );
});

async function onHoldChange(v: string) {
  store.settings.stop_hold_wakelock = v;
  await store.saveSettings();
}

async function toggleKind(kind: "stop" | "resume" | "fail", on: boolean) {
  const next = new Set(kindSet.value);
  if (on) next.add(kind);
  else next.delete(kind);
  if (!next.size) {
    next.add(kind);
  }
  store.settings.notify_charge_kinds = ["stop", "resume", "fail"]
    .filter((k) => next.has(k))
    .join(",");
  await store.saveSettings();
}
</script>

<template>
  <SectionHead title="电量停充" hint="到达阈值后停止充电，掉到恢复值再继续" />
  <ThemedCard>
    <ConfigBlock :label="`停止电量 · ${store.powerPlan}`">
      <PresetValue
        :options="POWER_STOP_PRESETS"
        :model-value="store.settings.power_stop"
        label="停止电量 %"
        placeholder="1–100，110=关闭"
        :min-display="1"
        :max-display="110"
        @update:model-value="(id) => setPower('power_stop', id)"
      />
      <div class="block-label">恢复电量</div>
      <PresetValue
        :options="POWER_START_PRESETS"
        :model-value="store.settings.power_start"
        label="恢复电量 %"
        placeholder="须小于停止电量"
        :min-display="1"
        :max-display="100"
        @update:model-value="(id) => setPower('power_start', id)"
      />
      <van-field
        v-model="store.settings.power_stop_time"
        type="digit"
        label="延时秒数"
        placeholder="1–120"
        input-align="right"
        @change="store.saveSettings()"
      />
    </ConfigBlock>
    <ConfigBlock label="停充时段（可选）">
      <p class="field-hint">留空全天生效；填写后仅在时段内按电量停充</p>
      <ScheduleEditor
        v-model="store.powerStopSchedule"
        add-title="添加停充时段"
        edit-title="编辑停充时段"
        @change="savePowerStopSchedule"
      />
    </ConfigBlock>
    <van-cell title="停充持锁" label="息屏深睡改回节点时建议开或自动（魅族/MCA）">
      <template #value>
        <van-radio-group
          :model-value="store.settings.stop_hold_wakelock"
          direction="horizontal"
          @update:model-value="onHoldChange"
        >
          <van-radio
            v-for="opt in holdOptions"
            :key="opt.value"
            :name="opt.value"
            icon-size="16px"
          >
            {{ opt.name }}
          </van-radio>
        </van-radio-group>
      </template>
    </van-cell>
    <SwitchCell
      title="充满再停"
      label="100% 时等涓流结束再停充"
      :model-value="store.settings.charge_full === '1'"
      @update:model-value="(v) => onSwitch('charge_full', v)"
    />
    <SwitchCell
      title="自动拔插"
      label="插电时模拟拔插以激活快充"
      :model-value="store.settings.power_reset === '1'"
      @update:model-value="(v) => onSwitch('power_reset', v)"
    />
    <SwitchCell
      title="兼容模式"
      label="与其它快充 / 限流模块同装时建议开启"
      :model-value="store.settings.Compatibility_mode === '1'"
      @update:model-value="(v) => onSwitch('Compatibility_mode', v)"
    />
    <SwitchCell
      title="停充/恢复通知"
      label="系统通知总开关（默关）"
      :model-value="notifyOn"
      @update:model-value="(v) => onSwitch('notify_charge_event', v)"
    />
    <template v-if="notifyOn">
      <SwitchCell
        title="通知 · 停充"
        :model-value="kindSet.has('stop')"
        @update:model-value="(v) => toggleKind('stop', v)"
      />
      <SwitchCell
        title="通知 · 恢复"
        :model-value="kindSet.has('resume')"
        @update:model-value="(v) => toggleKind('resume', v)"
      />
      <SwitchCell
        title="通知 · 失败"
        label="勿扰时段内仍会发送"
        :model-value="kindSet.has('fail')"
        @update:model-value="(v) => toggleKind('fail', v)"
      />
      <ConfigBlock label="通知勿扰时段">
        <p class="field-hint">时段内不发停充/恢复通知；失败仍发</p>
        <ScheduleEditor
          v-model="store.notifyQuietSchedule"
          add-title="添加勿扰时段"
          edit-title="编辑勿扰时段"
          @change="saveNotifyQuietSchedule"
        />
      </ConfigBlock>
    </template>
  </ThemedCard>
</template>

<style scoped lang="scss">
.block-label {
  font-size: 13px;
  color: var(--qsc-text-2);
  margin: 6px 0 2px;
}

.field-hint {
  margin: 0 0 8px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.4;
  padding: 0 var(--qsc-cell-pad-x, 4px);
}
</style>
