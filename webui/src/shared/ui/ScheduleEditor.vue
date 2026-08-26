<script setup lang="ts">
import { computed, ref } from "vue";

const props = withDefaults(
  defineProps<{
    modelValue?: string[];
    addTitle?: string;
    editTitle?: string;
  }>(),
  {
    modelValue: () => [],
    addTitle: "添加旁路时段",
    editTitle: "编辑旁路时段",
  },
);

const emit = defineEmits<{
  "update:modelValue": [v: string[]];
  change: [];
}>();

const show = ref(false);
const editIndex = ref(-1);
const startTime = ref<string[]>(["22", "00"]);
const endTime = ref<string[]>(["08", "00"]);

const ranges = computed(() => props.modelValue || []);

function parseRange(s: string): { start: string[]; end: string[] } {
  const m = String(s || "")
    .trim()
    .match(/^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$/);
  if (!m) return { start: ["22", "00"], end: ["08", "00"] };
  const pad = (n: string) => n.padStart(2, "0");
  return {
    start: [pad(m[1]), m[2]],
    end: [pad(m[3]), m[4]],
  };
}

function formatRange(start: string[], end: string[]) {
  return `${start[0].padStart(2, "0")}:${start[1].padStart(2, "0")}-${end[0].padStart(2, "0")}:${end[1].padStart(2, "0")}`;
}

function openAdd() {
  editIndex.value = -1;
  startTime.value = ["22", "00"];
  endTime.value = ["08", "00"];
  show.value = true;
}

function openEdit(i: number) {
  editIndex.value = i;
  const parsed = parseRange(ranges.value[i] || "");
  startTime.value = [...parsed.start];
  endTime.value = [...parsed.end];
  show.value = true;
}

function removeAt(i: number) {
  const next = ranges.value.filter((_, idx) => idx !== i);
  emit("update:modelValue", next);
  emit("change");
}

function onConfirm() {
  const text = formatRange(startTime.value, endTime.value);
  const next = [...ranges.value];
  if (editIndex.value >= 0) next[editIndex.value] = text;
  else next.push(text);
  emit("update:modelValue", next);
  emit("change");
  show.value = false;
}

function onCancel() {
  show.value = false;
}
</script>

<template>
  <div class="schedule">
    <div v-if="!ranges.length" class="schedule-empty">暂无时段，点击下方添加</div>
    <div v-for="(item, i) in ranges" :key="`${item}-${i}`" class="schedule-row">
      <button type="button" class="schedule-time" @click="openEdit(i)">{{ item }}</button>
      <button type="button" class="schedule-del" @click="removeAt(i)">删除</button>
    </div>
    <van-button
      size="small"
      block
      round
      type="primary"
      plain
      class="schedule-add"
      @click="openAdd"
    >
      添加时段
    </van-button>

    <van-popup v-model:show="show" position="bottom" round>
      <van-picker-group
        :title="editIndex >= 0 ? props.editTitle : props.addTitle"
        :tabs="['开始', '结束']"
        next-step-text="下一步"
        @confirm="onConfirm"
        @cancel="onCancel"
      >
        <van-time-picker v-model="startTime" :columns-type="['hour', 'minute']" />
        <van-time-picker v-model="endTime" :columns-type="['hour', 'minute']" />
      </van-picker-group>
    </van-popup>
  </div>
</template>

<style scoped lang="scss">
.schedule {
  padding: 4px 0 8px;
}

.schedule-empty {
  font-size: 12px;
  color: var(--qsc-text-3);
  padding: 4px 0 10px;
}

.schedule-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}

.schedule-time {
  flex: 1;
  border: none;
  text-align: left;
  padding: 10px 14px;
  border-radius: 12px;
  background: var(--qsc-surface-2, var(--qsc-chip-bg));
  color: var(--qsc-text);
  font-size: 14px;
  font-variant-numeric: tabular-nums;
}

.schedule-del {
  border: none;
  background: transparent;
  color: var(--van-danger-color, #ee0a24);
  font-size: 13px;
  padding: 8px 4px;
}

.schedule-add {
  margin-top: 4px;
}
</style>
