<script setup lang="ts">
import { ref, watch } from "vue";
import type { LogSession } from "@/shared";
import LogLines from "./LogLines.vue";

const props = defineProps<{
  sessions: LogSession[];
  filtered?: boolean;
}>();

const openIds = ref<Set<string>>(new Set());

watch(
  () => props.sessions,
  (list) => {
    const next = new Set<string>();
    for (const s of list) {
      if (s.open) next.add(s.id);
    }
    if (!next.size && list[0]) next.add(list[0].id);
    openIds.value = next;
  },
  { immediate: true },
);

function badge(s: LogSession): string {
  if (s.open) return "停充中";
  if (s.id === "orphan") return "杂项";
  return "已恢复";
}

function isOpen(id: string): boolean {
  return openIds.value.has(id);
}

function toggle(id: string) {
  const next = new Set(openIds.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  openIds.value = next;
}

function toneClass(s: LogSession): string {
  if (s.hasError) return "tone-err";
  if (s.open) return "tone-open";
  if (s.hasWarn) return "tone-warn";
  if (s.id === "orphan") return "tone-mute";
  return "tone-ok";
}
</script>

<template>
  <div v-if="sessions.length" class="sessions">
    <article
      v-for="s in sessions"
      :key="s.id"
      class="sess"
      :class="[toneClass(s), { expanded: isOpen(s.id) }]"
    >
      <button type="button" class="sess-head" @click="toggle(s.id)">
        <span class="rail" aria-hidden="true"></span>
        <span class="sess-badge">{{ badge(s) }}</span>
        <span class="sess-text">{{ s.title }}</span>
        <span class="sess-meta">
          <span class="sess-n">{{ s.entries.length }}</span>
          <span class="chev" :class="{ open: isOpen(s.id) }" aria-hidden="true"></span>
        </span>
      </button>
      <div v-show="isOpen(s.id)" class="sess-body">
        <LogLines :lines="s.entries" :filtered="filtered" dense />
      </div>
    </article>
  </div>
  <p v-else class="log-empty">
    {{ filtered ? "没有该等级的日志" : "暂无日志（触发功能后才会写入）" }}
  </p>
</template>

<style scoped lang="scss">
.sessions {
  display: flex;
  flex-direction: column;
  gap: 10px;
  min-height: 42vh;
}

.sess {
  border-radius: 12px;
  background: var(--qsc-surface);
  border: 1px solid var(--qsc-hairline);
  overflow: hidden;
}

.sess-head {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  border: none;
  background: transparent;
  color: inherit;
  text-align: left;
  padding: 10px 12px 10px 0;
  cursor: pointer;
  min-width: 0;
}

.rail {
  width: 3px;
  align-self: stretch;
  margin: 2px 0;
  border-radius: 0 3px 3px 0;
  background: var(--qsc-text-3);
  flex-shrink: 0;
}

.tone-open .rail {
  background: var(--qsc-warn);
}

.tone-err .rail {
  background: var(--qsc-danger);
}

.tone-warn .rail {
  background: var(--qsc-warn);
}

.tone-ok .rail {
  background: var(--qsc-success);
}

.tone-mute .rail {
  background: var(--qsc-text-3);
}

.sess-badge {
  flex-shrink: 0;
  font-size: 11px;
  font-weight: 650;
  padding: 3px 7px;
  border-radius: 6px;
  background: var(--qsc-surface-2, var(--qsc-chip-bg));
  color: var(--qsc-text-2);
}

.tone-open .sess-badge {
  color: var(--qsc-warn);
  background: color-mix(in srgb, var(--qsc-warn) 14%, transparent);
}

.tone-err .sess-badge {
  color: var(--qsc-danger);
  background: color-mix(in srgb, var(--qsc-danger) 14%, transparent);
}

.tone-ok .sess-badge {
  color: var(--qsc-success);
  background: color-mix(in srgb, var(--qsc-success) 12%, transparent);
}

.sess-text {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  font-weight: 550;
  color: var(--qsc-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sess-meta {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.sess-n {
  font-size: 11px;
  font-variant-numeric: tabular-nums;
  color: var(--qsc-text-3);
  min-width: 1.5em;
  text-align: right;
}

.chev {
  width: 7px;
  height: 7px;
  border-right: 1.5px solid var(--qsc-text-3);
  border-bottom: 1.5px solid var(--qsc-text-3);
  transform: rotate(-45deg);
  transition: transform 0.18s ease;
  margin-top: -2px;
}

.chev.open {
  transform: rotate(45deg);
  margin-top: 0;
}

.sess-body {
  margin: 0 10px 10px;
  padding: 8px 10px;
  border-radius: 10px;
  background: var(--qsc-surface-2, color-mix(in srgb, var(--qsc-text) 4%, transparent));
  border: 1px solid color-mix(in srgb, var(--qsc-text) 6%, transparent);
}

.sess-body :deep(.log) {
  min-height: 0;
}

.log-empty {
  margin: 0;
  min-height: 42vh;
  font-size: 13px;
  color: var(--qsc-text-3);
  line-height: 1.55;
}

html.pack-md3 .sess {
  border: none;
  border-radius: 16px;
  background: var(--qsc-surface-2);
}

html.pack-md3 .sess-body {
  background: var(--qsc-surface);
  border: none;
}

html.pack-miuix .sess {
  border-radius: 12px;
  border: none;
  background: color-mix(in srgb, var(--qsc-text) 4%, var(--qsc-surface));
}
</style>
