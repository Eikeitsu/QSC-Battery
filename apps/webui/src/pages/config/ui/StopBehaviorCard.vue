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
const lowBattOpen = ref<string[]>([]);

async function setLowBatt(
  key:
    | "low_batt_warn"
    | "low_batt_shutdown"
    | "low_batt_shutdown_delay_sec"
    | "low_batt_shutdown_min_uptime_sec"
    | "low_batt_temp_shutdown",
  raw: string,
) {
  store.settings[key] = raw;
  await store.saveSettings();
}

function applyLowBattSuggested() {
  store.settings.low_batt_warn = "15";
  store.settings.low_batt_shutdown = "5";
  store.settings.low_batt_temp_shutdown = "55";
  store.settings.low_batt_shutdown_delay_sec = "60";
  store.settings.low_batt_shutdown_min_uptime_sec = "900";
  void store.saveSettings();
}

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
    <van-cell
      title="停充持锁"
      label="自动：仅息屏/夜间持锁，亮屏释放以利 Doze；强制开会持续挡深睡（魅族/MCA）"
    >
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
      label="例：停充后协议卡死、充不进电时，模拟拔插重新握手快充（日常建议关）"
      :model-value="store.settings.power_reset === '1'"
      @update:model-value="(v) => onSwitch('power_reset', v)"
    />
    <SwitchCell
      title="拔线立刻还原节点"
      label="例：80%停充后拔线——开=节点立刻恢复可充；关=再插上仍停到恢复电量（如70%）"
      :model-value="store.settings.unplug_restore !== '0'"
      @update:model-value="(v) => onSwitch('unplug_restore', v)"
    />
    <SwitchCell
      title="兼容模式"
      label="与其它快充 / 限流模块同装时建议开启"
      :model-value="store.settings.compatibility_mode === '1'"
      @update:model-value="(v) => onSwitch('compatibility_mode', v)"
    />
    <SwitchCell
      title="停充/恢复通知"
      label="系统通知总开关（默关）"
      :model-value="notifyOn"
      @update:model-value="(v) => onSwitch('notify_charge_event', v)"
    />
    <SwitchCell
      title="常显功耗通知"
      label="状态栏常驻显示电量、温度与实时电流（默关）"
      :model-value="store.settings.notify_power_status === '1'"
      @update:model-value="(v) => onSwitch('notify_power_status', v)"
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
    <van-collapse v-model="lowBattOpen" accordion>
      <van-collapse-item name="lowbatt" title="低电防护（冷门）">
        <p class="field-hint">
          默认全关（0），关闭无额外开销。建议启用值：提醒 15% / 关机 5% / 过温
          55°C。低电仅未插电；过温插电也生效。
        </p>
        <van-cell title="一键填入建议值" is-link @click="applyLowBattSuggested" />
        <van-field
          :model-value="store.settings.low_batt_warn"
          type="digit"
          label="低电提醒 %"
          placeholder="0=关，建议 15"
          input-align="right"
          @update:model-value="(v) => (store.settings.low_batt_warn = String(v ?? '0'))"
          @change="setLowBatt('low_batt_warn', store.settings.low_batt_warn)"
        />
        <van-field
          :model-value="store.settings.low_batt_shutdown"
          type="digit"
          label="自动关机 %"
          placeholder="0=关，建议 5"
          input-align="right"
          @update:model-value="
            (v) => (store.settings.low_batt_shutdown = String(v ?? '0'))
          "
          @change="setLowBatt('low_batt_shutdown', store.settings.low_batt_shutdown)"
        />
        <van-field
          :model-value="store.settings.low_batt_temp_shutdown"
          type="digit"
          label="过温关机 °C"
          placeholder="0=关，建议 55"
          input-align="right"
          @update:model-value="
            (v) => (store.settings.low_batt_temp_shutdown = String(v ?? '0'))
          "
          @change="
            setLowBatt('low_batt_temp_shutdown', store.settings.low_batt_temp_shutdown)
          "
        />
        <van-field
          :model-value="store.settings.low_batt_shutdown_delay_sec"
          type="digit"
          label="关机倒计时秒"
          placeholder="10–300，默认 60"
          input-align="right"
          @update:model-value="
            (v) => (store.settings.low_batt_shutdown_delay_sec = String(v ?? '60'))
          "
          @change="
            setLowBatt(
              'low_batt_shutdown_delay_sec',
              store.settings.low_batt_shutdown_delay_sec,
            )
          "
        />
        <van-field
          :model-value="store.settings.low_batt_shutdown_min_uptime_sec"
          type="digit"
          label="开机满秒才关"
          placeholder="默认 900（15 分钟），0=不限"
          input-align="right"
          @update:model-value="
            (v) => (store.settings.low_batt_shutdown_min_uptime_sec = String(v ?? '900'))
          "
          @change="
            setLowBatt(
              'low_batt_shutdown_min_uptime_sec',
              store.settings.low_batt_shutdown_min_uptime_sec,
            )
          "
        />
        <p class="field-hint">
          低电关机：插电可取消；过温：降温可取消。关机阈值须低于提醒。
        </p>
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
