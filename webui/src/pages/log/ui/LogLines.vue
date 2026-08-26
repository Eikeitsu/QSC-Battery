<script setup lang="ts">
import type { LogEntry } from "@/shared";

withDefaults(
  defineProps<{
    lines: LogEntry[];
    filtered?: boolean;
    dense?: boolean;
  }>(),
  { filtered: false, dense: false },
);
</script>

<template>
  <div v-if="lines.length" class="log" :class="{ dense }">
    <span
      v-for="(line, i) in lines"
      :key="i"
      class="log-line"
      :class="`lv-${line.level}`"
      v-text="line.raw"
    ></span>
  </div>
  <p v-else class="log-empty">
    {{ filtered ? "没有该等级的日志" : "暂无日志（触发功能后才会写入）" }}
  </p>
</template>

<style scoped lang="scss">
.log {
  margin: 0;
  font-size: 12px;
  line-height: 1.55;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  min-height: 42vh;
}

.log.dense {
  min-height: 0;
  font-size: 11.5px;
  line-height: 1.5;
}

.log-line {
  display: block;
  white-space: pre-wrap;
  word-break: break-all;
  padding: 1px 0;
}

.log.dense .log-line + .log-line {
  border-top: 1px solid color-mix(in srgb, var(--qsc-text) 5%, transparent);
  padding-top: 4px;
  margin-top: 3px;
}

.lv-info {
  color: var(--qsc-text);
}

.lv-debug {
  color: var(--qsc-text-3);
}

.lv-warn {
  color: var(--qsc-warn);
}

.lv-error {
  color: var(--qsc-danger);
}

.log-empty {
  margin: 0;
  min-height: 42vh;
  font-size: 13px;
  color: var(--qsc-text-3);
  line-height: 1.55;
}
</style>
