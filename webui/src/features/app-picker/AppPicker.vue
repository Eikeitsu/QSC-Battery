<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { showToast } from "vant";
import { listInstalledApps } from "@/shared/api";
import type { AppEntry } from "@/shared/types";
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
const loadedOnce = ref(false);
const entries = ref<AppEntry[]>([]);
const selected = ref<Set<string>>(new Set());
const manualOpen = ref(false);
const manualText = ref("");
const listEl = ref<HTMLElement | null>(null);
const failedIcons = ref<Set<string>>(new Set());
let observer: IntersectionObserver | null = null;
let loadSeq = 0;

watch(
  () => props.show,
  async (v) => {
    if (!v) {
      teardownObserver();
      search.value = "";
      manualOpen.value = false;
      return;
    }
    selected.value = new Set(props.modelValue || []);
    manualText.value = [...selected.value].join("\n");
    failedIcons.value = new Set();
    await nextTick();
    // 打开即自动加载；已有缓存时静默刷新
    await load({ silent: loadedOnce.value && entries.value.length > 0 });
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
  return sortAppsSelectedFirst(list, selected.value).slice(0, 400);
});

/** 已选但不在当前列表里的包（手动添加或卸载后残留） */
const orphanSelected = computed(() => {
  const known = new Set(entries.value.map((e) => e.package));
  return [...selected.value].filter((pkg) => !known.has(pkg));
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
    { root: listEl.value, rootMargin: "160px", threshold: 0.01 },
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

async function load(opts: { silent?: boolean } = {}) {
  const seq = ++loadSeq;
  loading.value = true;
  try {
    const list = await listInstalledApps();
    if (seq !== loadSeq) return;
    entries.value = list;
    loadedOnce.value = true;
    if (!opts.silent) {
      showToast(list.length ? `已加载 ${list.length} 个应用` : "未找到已安装应用");
    }
    await nextTick();
    setupObserver();
  } catch {
    if (seq !== loadSeq) return;
    if (!entries.value.length) entries.value = [];
    showToast("读取应用失败");
  } finally {
    if (seq === loadSeq) loading.value = false;
  }
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

function displayName(pkg: string, name?: string) {
  const n = name || entries.value.find((e) => e.package === pkg)?.name;
  return n && n !== pkg ? n : pkg;
}
</script>

<template>
  <van-popup
    :show="show"
    position="bottom"
    round
    class="app-picker-popup"
    :style="{ height: '88%' }"
    :z-index="3000"
    teleport="body"
    @update:show="(v: boolean) => emit('update:show', v)"
  >
    <div class="picker">
      <div class="picker-head">
        <button type="button" class="link" @click="close">取消</button>
        <div class="titles">
          <div class="title">选择游戏应用</div>
          <div class="sub">已选 {{ selected.size }} · 点选切换</div>
        </div>
        <button type="button" class="link primary" @click="confirm">完成</button>
      </div>

      <div class="search-wrap">
        <van-search
          v-model="search"
          placeholder="搜索应用名或包名"
          shape="round"
          background="transparent"
        />
      </div>

      <div ref="listEl" class="list">
        <div v-if="loading && !entries.length" class="state">
          <van-loading size="24px" vertical>正在加载应用…</van-loading>
        </div>

        <template v-else>
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
              <div class="name">{{ displayName(e.package, e.name) }}</div>
              <div class="pkg">{{ e.package }}</div>
            </div>
            <van-checkbox
              :model-value="selected.has(e.package)"
              checked-color="var(--qsc-primary)"
              @click.stop
              @update:model-value="(v: boolean) => toggle(e.package, v)"
            />
          </button>

          <div v-if="orphanSelected.length" class="orphan">
            <div class="orphan-title">已选但不在列表中</div>
            <button
              v-for="pkg in orphanSelected"
              :key="pkg"
              type="button"
              class="app-row on"
              @click="toggle(pkg, false)"
            >
              <div
                class="icon-wrap"
                :style="{
                  background: `hsl(${hueFromPackage(pkg)} 42% 42%)`,
                }"
              >
                <span class="fallback">{{ initialFromName(pkg) }}</span>
              </div>
              <div class="meta">
                <div class="name">{{ pkg }}</div>
                <div class="pkg">点按可取消选择</div>
              </div>
              <van-checkbox :model-value="true" checked-color="var(--qsc-primary)" />
            </button>
          </div>

          <van-empty
            v-if="!loading && !filtered.length && !orphanSelected.length"
            :description="entries.length ? '无匹配应用' : '未能读取应用列表'"
          >
            <van-button
              v-if="!entries.length"
              size="small"
              type="primary"
              round
              :loading="loading"
              @click="load()"
            >
              重试
            </van-button>
          </van-empty>
        </template>
      </div>

      <div class="manual">
        <button type="button" class="manual-toggle" @click="manualOpen = !manualOpen">
          {{ manualOpen ? "收起手动编辑" : "高级：手动编辑包名" }}
        </button>
        <van-field
          v-if="manualOpen"
          v-model="manualText"
          rows="3"
          autosize
          type="textarea"
          placeholder="一行一个包名，适合列表里找不到的应用"
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
  color: var(--qsc-text);
}

.picker-head {
  display: grid;
  grid-template-columns: 56px 1fr 56px;
  align-items: center;
  padding: 14px 12px 4px;
  background: var(--qsc-bg);
}

.titles {
  text-align: center;
  min-width: 0;
}

.title {
  font-weight: 720;
  font-size: 16px;
  line-height: 1.2;
}

.sub {
  margin-top: 2px;
  font-size: 11px;
  color: var(--qsc-text-3);
}

.link {
  border: none;
  background: transparent;
  color: var(--qsc-text-2);
  font-size: 15px;
  padding: 8px 4px;
  border-radius: 8px;

  &:active {
    background: var(--qsc-press);
  }
}

.link.primary {
  color: var(--qsc-primary);
  font-weight: 650;
  justify-self: end;
}

.search-wrap {
  background: var(--qsc-bg);
  padding-bottom: 4px;
  flex-shrink: 0;

  :deep(.van-search) {
    padding: 8px 12px;
  }

  :deep(.van-search__content) {
    background: var(--qsc-surface);
    min-height: 40px;
    align-items: center;
    display: flex;
  }

  :deep(.van-search__field) {
    display: flex;
    align-items: center;
    height: 40px;
    line-height: 40px;
    padding: 0 4px;
  }

  :deep(.van-field__body),
  :deep(.van-field__control) {
    display: flex;
    align-items: center;
    min-height: 40px;
    height: 40px;
    line-height: 22px;
    font-size: 15px;
  }

  :deep(.van-field__left-icon) {
    display: flex;
    align-items: center;
    height: 40px;
    margin-right: 6px;
  }

  :deep(input::placeholder) {
    line-height: 22px;
  }
}

.list {
  flex: 1;
  overflow: auto;
  -webkit-overflow-scrolling: touch;
  padding: 4px 10px 20px;
  background: var(--qsc-bg);
}

.state {
  display: grid;
  place-items: center;
  min-height: 40vh;
  color: var(--qsc-text-2);
}

.app-row {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  background: var(--qsc-surface);
  border-radius: 14px;
  padding: 10px 12px;
  margin-bottom: 8px;
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
    border-color: color-mix(in srgb, var(--qsc-primary) 40%, transparent);
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

.orphan {
  margin-top: 8px;
  padding-top: 4px;
}

.orphan-title {
  font-size: 12px;
  color: var(--qsc-text-3);
  padding: 4px 6px 8px;
}

.manual {
  flex-shrink: 0;
  border-top: 1px solid var(--qsc-hairline);
  padding: 10px 12px;
  padding-bottom: calc(12px + var(--qsc-inset-bottom, 0px));
  background: var(--qsc-surface);

  /* 底色铺进系统导航区，避免小白条 / 断层 */
  box-shadow: 0 calc(var(--qsc-inset-bottom, 0px)) 0 0 var(--qsc-surface);
}

.manual-toggle {
  border: none;
  background: transparent;
  color: var(--qsc-primary);
  font-size: 13px;
  font-weight: 600;
  padding: 8px 4px 10px;
  width: 100%;
  text-align: left;

  &:active {
    opacity: 0.7;
  }
}

.manual :deep(.van-field) {
  background: var(--qsc-bg);
  border-radius: 12px;
  overflow: hidden;
}
</style>

<style lang="scss">
/* 弹层必须实底，避免主题/毛玻璃导致「透明看穿」 */
.app-picker-popup.van-popup {
  background: var(--qsc-bg) !important;
  color: var(--qsc-text);
  overflow: hidden;
}

/* MD3：与顶栏留缝，避免贴死下边框 */
html.pack-md3 .app-picker-popup.van-popup--bottom {
  height: calc(88% - 10px) !important;
  max-height: calc(100dvh - var(--qsc-inset-top, 0px) - 84px) !important;
  margin-bottom: 0;
}

/* 默认主题搜索高度对齐其它包 */
html.pack-default .app-picker-popup .van-search__content {
  min-height: 40px !important;
}

/* 列表底部与底栏/手势条留白（MD3 / MIUIX） */
html.pack-md3 .app-picker-popup .list,
html.pack-miuix .app-picker-popup .list {
  padding-bottom: 28px;
}

/* 悬浮底栏时抽屉贴底沉浸，去掉「非悬浮」式假空白 */
html.float-dock .app-picker-popup.van-popup--bottom {
  border-bottom-left-radius: 0 !important;
  border-bottom-right-radius: 0 !important;
  height: 90% !important;
  max-height: calc(100dvh - var(--qsc-inset-top, 0px) - 8px) !important;
}

html.float-dock .app-picker-popup .manual {
  background: var(--qsc-bg);
  box-shadow: 0 calc(var(--qsc-inset-bottom, 0px)) 0 0 var(--qsc-bg);
}
</style>
