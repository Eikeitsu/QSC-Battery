<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { showToast } from "vant";
import { listInstalledApps } from "../../bridge";
import type { AppEntry } from "../../shared/types";
import { hueFromPackage, initialFromName, sortAppsSelectedFirst } from "./helpers";

const props = defineProps<{
  show?: boolean;
  modelValue?: string[];
}>();
const emit = defineEmits<{
  "update:show": [value: boolean];
  "update:modelValue": [value: string[]];
  saved: [];
}>();

const search = ref("");
const loading = ref(false);
const entries = ref<AppEntry[]>([]);
const selected = ref<Set<string>>(new Set());
const manualOpen = ref(false);
const manualText = ref("");
const listEl = ref<HTMLElement | null>(null);
const failedIcons = ref<Set<string>>(new Set());
let observer: IntersectionObserver | null = null;

watch(
  () => props.show,
  (v) => {
    if (v) {
      selected.value = new Set(props.modelValue || []);
      manualText.value = [...selected.value].join("\n");
      failedIcons.value = new Set();
      void nextTick(() => setupObserver());
    } else {
      teardownObserver();
    }
  },
);

watch(selected, (set) => {
  if (!manualOpen.value) manualText.value = [...set].join("\n");
});

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  let list = entries.value;
  if (q) {
    list = list.filter(
      (e) =>
        e.package.toLowerCase().includes(q) || (e.name || "").toLowerCase().includes(q),
    );
  }
  return sortAppsSelectedFirst(list, selected.value).slice(0, 300);
});

function setupObserver() {
  teardownObserver();
  if (!listEl.value) return;
  observer = new IntersectionObserver(
    (obsEntries) => {
      for (const entry of obsEntries) {
        if (!entry.isIntersecting) continue;
        const el = entry.target as HTMLElement;
        const img = el.querySelector<HTMLImageElement>("img.app-icon[data-src]");
        if (img?.dataset.src) {
          img.src = img.dataset.src;
          img.removeAttribute("data-src");
        }
        observer?.unobserve(el);
      }
    },
    { root: listEl.value, rootMargin: "120px", threshold: 0.01 },
  );
  listEl.value
    .querySelectorAll<HTMLElement>(".app-row")
    .forEach((row) => observer?.observe(row));
}

function teardownObserver() {
  observer?.disconnect();
  observer = null;
}

watch(filtered, async () => {
  await nextTick();
  if (props.show) setupObserver();
});

async function load() {
  loading.value = true;
  try {
    entries.value = await listInstalledApps();
    showToast(`已加载 ${entries.value.length} 个应用`);
    await nextTick();
    setupObserver();
  } catch {
    entries.value = [];
    showToast("读取应用失败");
  }
  loading.value = false;
}

function toggle(pkg: string, on: boolean) {
  const next = new Set(selected.value);
  if (on) next.add(pkg);
  else next.delete(pkg);
  selected.value = next;
}

function onManualInput() {
  const pkgs = manualText.value
    .split(/\n+/)
    .map((s) => s.trim())
    .filter(Boolean);
  selected.value = new Set(pkgs);
}

function onIconError(pkg: string) {
  const next = new Set(failedIcons.value);
  next.add(pkg);
  failedIcons.value = next;
}

function confirm() {
  if (manualOpen.value) onManualInput();
  emit("update:modelValue", [...selected.value]);
  emit("update:show", false);
  emit("saved");
}

function close() {
  emit("update:show", false);
}

function selectedName(pkg: string) {
  return entries.value.find((e) => e.package === pkg)?.name || pkg;
}
</script>

<template>
  <van-popup
    :show="show"
    position="bottom"
    round
    :style="{ height: '90%' }"
    @update:show="(v: boolean) => emit('update:show', v)"
  >
    <div class="picker">
      <div class="picker-head">
        <button type="button" class="link" @click="close">取消</button>
        <div class="title">游戏应用</div>
        <button type="button" class="link primary" @click="confirm">完成</button>
      </div>

      <van-search v-model="search" placeholder="搜索应用名或包名" shape="round" />

      <div class="toolbar">
        <van-button size="small" type="primary" plain :loading="loading" @click="load">
          加载已安装应用
        </van-button>
        <span class="hint">已选 {{ selected.size }}</span>
      </div>

      <div v-if="selected.size" class="selected">
        <van-tag
          v-for="pkg in selected"
          :key="pkg"
          closeable
          type="primary"
          class="tag"
          @close="toggle(pkg, false)"
        >
          {{ selectedName(pkg) }}
        </van-tag>
      </div>

      <div ref="listEl" class="list">
        <button
          v-for="e in filtered"
          :key="e.package"
          type="button"
          class="app-row"
          :class="{ on: selected.has(e.package) }"
          @click="toggle(e.package, !selected.has(e.package))"
        >
          <div
            class="icon-wrap"
            :style="{
              background: `hsl(${hueFromPackage(e.package)} 42% 42%)`,
            }"
          >
            <span v-if="failedIcons.has(e.package)" class="fallback">{{
              initialFromName(e.name)
            }}</span>
            <img
              v-else
              class="app-icon"
              alt=""
              :data-src="e.iconUrl"
              @error="onIconError(e.package)"
            />
          </div>
          <div class="meta">
            <div class="name">{{ e.name || e.package }}</div>
            <div class="pkg">{{ e.package }}</div>
          </div>
          <van-checkbox
            :model-value="selected.has(e.package)"
            @click.stop
            @update:model-value="(v: boolean) => toggle(e.package, v)"
          />
        </button>

        <van-empty
          v-if="!loading && !filtered.length"
          :description="
            entries.length ? '无匹配应用' : '先加载应用列表，或下方手动填写包名'
          "
        />
      </div>

      <div class="manual">
        <button type="button" class="manual-toggle" @click="manualOpen = !manualOpen">
          {{ manualOpen ? "收起手动编辑" : "高级：手动编辑包名" }}
        </button>
        <van-field
          v-if="manualOpen"
          v-model="manualText"
          rows="4"
          autosize
          type="textarea"
          placeholder="一行一个包名"
          @update:model-value="onManualInput"
        />
      </div>
    </div>
  </van-popup>
</template>

<style scoped lang="scss">
.picker {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: var(--qsc-bg);
}

.picker-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px 6px;
}

.title {
  font-weight: 700;
  font-size: 16px;
}

.link {
  border: none;
  background: transparent;
  color: var(--qsc-text-2);
  font-size: 15px;
  padding: 4px 2px;
}

.link.primary {
  color: var(--qsc-primary);
  font-weight: 600;
}

.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 16px 8px;
}

.hint {
  font-size: 12px;
  color: var(--qsc-text-3);
}

.selected {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  padding: 0 16px 10px;
}

.tag {
  max-width: 100%;
}

.list {
  flex: 1;
  overflow: auto;
  -webkit-overflow-scrolling: touch;
  padding: 0 8px 8px;
}

.app-row {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  background: var(--qsc-surface);
  border-radius: 14px;
  padding: 10px 12px;
  margin-bottom: 6px;
  text-align: left;
  color: inherit;
  border: 1px solid transparent;
  transition:
    transform 0.12s ease,
    border-color 0.12s ease,
    background 0.12s ease;

  &:active {
    transform: scale(0.985);
  }

  &.on {
    border-color: color-mix(in srgb, var(--qsc-primary) 35%, transparent);
    background: var(--qsc-primary-soft);
  }
}

.icon-wrap {
  width: 42px;
  height: 42px;
  border-radius: 11px;
  overflow: hidden;
  flex-shrink: 0;
  display: grid;
  place-items: center;
}

.app-icon {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
  background: transparent;
}

.fallback {
  color: #fff;
  font-weight: 700;
  font-size: 16px;
}

.meta {
  flex: 1;
  min-width: 0;
}

.name {
  font-size: 15px;
  font-weight: 600;
  line-height: 1.25;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pkg {
  margin-top: 2px;
  font-size: 11px;
  color: var(--qsc-text-3);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.manual {
  border-top: 1px solid var(--qsc-hairline);
  padding: 8px 12px calc(10px + env(safe-area-inset-bottom));
  background: var(--qsc-surface);
}

.manual-toggle {
  border: none;
  background: transparent;
  color: var(--qsc-primary);
  font-size: 13px;
  font-weight: 600;
  padding: 6px 4px 8px;
}
</style>
