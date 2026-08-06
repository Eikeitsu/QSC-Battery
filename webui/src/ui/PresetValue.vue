<script setup lang="ts">
import { computed, ref, watch } from "vue";
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
  }>(),
  {
    options: () => [],
    modelValue: "",
    label: "自定义数值",
    placeholder: "",
    asNumber: false,
  },
);

const emit = defineEmits<{
  "update:modelValue": [v: string | number];
  change: [];
}>();

const CUSTOM_ID = "__custom__";

const forceCustom = ref(false);
const draft = ref(String(props.modelValue ?? ""));

watch(
  () => props.modelValue,
  (v) => {
    draft.value = String(v ?? "");
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

function emitValue(raw: string) {
  const trimmed = String(raw ?? "").trim();
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
    draft.value = String(props.modelValue ?? "");
    return;
  }
  forceCustom.value = false;
  emitValue(raw);
}

function onFieldChange() {
  emitValue(draft.value);
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
