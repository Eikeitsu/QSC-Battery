<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { showToast } from "vant";
import type { ChipOption } from "../shared";
import ChipGroup from "./ChipGroup.vue";

const props = withDefaults(
  defineProps<{
    options?: ChipOption[];
    modelValue?: string | number;
    label?: string;
    placeholder?: string;
    /** 以 number 回传（电流控制字段） */
    asNumber?: boolean;
    /**
     * 显示换算：存储值 ÷ scale = 界面值。
     * 电流常用 1000（µA ↔ mA）；快捷 id 仍为存储单位。
     */
    unitScale?: number;
    /** 自定义输入下限（显示单位） */
    minDisplay?: number;
    /** 自定义输入上限（显示单位） */
    maxDisplay?: number;
  }>(),
  {
    options: () => [],
    modelValue: "",
    label: "自定义数值",
    placeholder: "",
    asNumber: false,
    unitScale: 1,
    minDisplay: undefined,
    maxDisplay: undefined,
  },
);

const emit = defineEmits<{
  "update:modelValue": [v: string | number];
  change: [];
}>();

const CUSTOM_ID = "__custom__";

const forceCustom = ref(false);
const draft = ref(toDisplay(props.modelValue));

function scale() {
  const s = Number(props.unitScale);
  return s > 0 ? s : 1;
}

function toDisplay(v: string | number | undefined) {
  const raw = String(v ?? "").trim();
  if (!raw) return "";
  const s = scale();
  if (s === 1) return raw;
  const n = Number(raw);
  if (!Number.isFinite(n)) return raw;
  return String(Math.round(n / s));
}

function toStored(display: string) {
  const trimmed = String(display ?? "").trim();
  const s = scale();
  if (s === 1) return trimmed;
  const n = Number(trimmed);
  if (!Number.isFinite(n)) return "0";
  return String(Math.round(n * s));
}

function clampDisplay(raw: string): string {
  const trimmed = String(raw ?? "").trim();
  if (!trimmed) return trimmed;
  let n = Number(trimmed);
  if (!Number.isFinite(n)) return trimmed;
  let clamped = false;
  if (props.minDisplay != null && n < props.minDisplay) {
    n = props.minDisplay;
    clamped = true;
  }
  if (props.maxDisplay != null && n > props.maxDisplay) {
    n = props.maxDisplay;
    clamped = true;
  }
  if (clamped) {
    showToast(
      props.minDisplay != null && props.maxDisplay != null
        ? `请输入 ${props.minDisplay}–${props.maxDisplay}`
        : "数值已限制在有效范围",
    );
  }
  return String(Math.round(n));
}

watch(
  () => props.modelValue,
  (v) => {
    draft.value = toDisplay(v);
    const hit = props.options.some((o) => String(o.id) === String(v));
    if (hit) forceCustom.value = false;
  },
);

const chipOptions = computed<ChipOption[]>(() => [
  ...props.options,
  { id: CUSTOM_ID, l: "自定义" },
]);

const chipValue = computed(() => {
  const v = String(props.modelValue ?? "");
  const hit = props.options.some((o) => String(o.id) === v);
  if (forceCustom.value || !hit) return CUSTOM_ID;
  return v;
});

const showField = computed(() => chipValue.value === CUSTOM_ID);

function emitValue(rawStored: string) {
  const trimmed = String(rawStored ?? "").trim();
  if (props.asNumber) {
    const n = Number(trimmed);
    emit("update:modelValue", Number.isFinite(n) ? n : 0);
  } else {
    emit("update:modelValue", trimmed);
  }
  emit("change");
}

function onChip(id: string | number) {
  const raw = String(id);
  if (raw === CUSTOM_ID) {
    forceCustom.value = true;
    draft.value = toDisplay(props.modelValue);
    return;
  }
  forceCustom.value = false;
  emitValue(raw);
}

function onFieldChange() {
  const clamped = clampDisplay(draft.value);
  draft.value = clamped;
  emitValue(toStored(clamped));
}
</script>

<template>
  <div class="preset-value">
    <ChipGroup
      :options="chipOptions"
      :model-value="chipValue"
      @update:model-value="onChip"
    />
    <van-field
      v-if="showField"
      v-model="draft"
      type="digit"
      :label="label"
      :placeholder="placeholder"
      input-align="right"
      class="preset-field"
      @change="onFieldChange"
      @blur="onFieldChange"
    />
  </div>
</template>

<style scoped lang="scss">
.preset-field {
  margin-top: 2px;
  padding-left: 0;
  padding-right: 0;
  background: transparent;
}
</style>
