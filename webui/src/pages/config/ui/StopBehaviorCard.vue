<script setup lang="ts">
import { computed, ref } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import ScheduleEditor from "@/shared/ui/ScheduleEditor.vue";
import { useConfigFormContext } from "@/composables";
import ConfigBlock from "./ConfigBlock.vue";

const { store, onSwitch, saveNotifyQuietSchedule } = useConfigFormContext();
const notifyDetailOpen = ref<string[]>([]);

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
  <SectionHead title="停充行为" hint="持锁、拔插、兼容与系统通知" />
  <ThemedCard>
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
    <van-collapse v-if="notifyOn" v-model="notifyDetailOpen" accordion>
      <van-collapse-item name="notify" title="通知种类与勿扰（可选）">
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
      </van-collapse-item>
    </van-collapse>
  </ThemedCard>
</template>

<style scoped lang="scss">
.field-hint {
  margin: 0 0 8px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.4;
  padding: 0 var(--qsc-cell-pad-x, 4px);
}

:deep(.van-collapse-item__content) {
  padding: 0;
}
</style>
