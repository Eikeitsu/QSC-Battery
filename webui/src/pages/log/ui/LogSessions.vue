<script setup lang="ts">
import { ref, watch } from "vue";
import type { LogSession } from "@/shared";
import LogLines from "./LogLines.vue";

const props = defineProps<{
  sessions: LogSession[];
  filtered?: boolean;
}>();

const openNames = ref<string[]>([]);

watch(
  () => props.sessions,
  (list) => {
    // 默认展开未恢复的会话 + 最近一轮
    const next: string[] = [];
    for (const s of list) {
      if (s.open) next.push(s.id);
    }
    if (!next.length && list[0]) next.push(list[0].id);
    openNames.value = next;
  },
  { immediate: true },
);

function badge(s: LogSession): string {
  if (s.open) return "停充中";
  if (s.id === "orphan") return "杂项";
  return "已恢复";
}
</script>

<template>
  <div v-if="sessions.length" class="sessions">
    <van-collapse v-model="openNames">
      <van-collapse-item v-for="s in sessions" :key="s.id" :name="s.id">
        <template #title>
          <div class="sess-title">
            <span
              class="sess-badge"
              :class="{ open: s.open, err: s.hasError, warn: s.hasWarn && !s.hasError }"
            >
              {{ badge(s) }}
            </span>
            <span class="sess-text">{{ s.title }}</span>
            <span class="sess-n">{{ s.entries.length }}</span>
          </div>
        </template>
        <LogLines :lines="s.entries" :filtered="filtered" />
      </van-collapse-item>
    </van-collapse>
  </div>
  <p v-else class="log-empty">
    {{ filtered ? "没有该等级的日志" : "暂无日志（触发功能后才会写入）" }}
  </p>
</template>

<style scoped lang="scss">
.sessions {
  min-height: 42vh;

  :deep(.van-collapse-item__content) {
    padding: 8px 0 4px;
  }

  :deep(.van-cell) {
    padding-left: 0;
    padding-right: 0;
    background: transparent;
  }

  :deep(.log) {
    min-height: 0;
  }
}

.sess-title {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  padding-right: 4px;
}

.sess-badge {
  flex-shrink: 0;
  font-size: 11px;
  padding: 2px 6px;
  border-radius: 6px;
  background: var(--qsc-surface-2, var(--qsc-chip-bg));
  color: var(--qsc-text-2);
}

.sess-badge.open {
  color: var(--qsc-warn);
  background: color-mix(in srgb, var(--qsc-warn) 14%, transparent);
}

.sess-badge.err {
  color: var(--qsc-danger);
  background: color-mix(in srgb, var(--qsc-danger) 14%, transparent);
}

.sess-badge.warn {
  color: var(--qsc-warn);
}

.sess-text {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sess-n {
  flex-shrink: 0;
  font-size: 11px;
  color: var(--qsc-text-3);
}

.log-empty {
  margin: 0;
  min-height: 42vh;
  font-size: 13px;
  color: var(--qsc-text-3);
  line-height: 1.55;
}
</style>
