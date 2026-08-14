<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch } from "vue";
import { readStorageFlag, STORAGE_KEYS, writeStorageFlag } from "@/shared";

const props = withDefaults(
  defineProps<{
    show?: boolean;
    title?: string;
    hint?: string;
    text?: string;
    /** 行尾 ↵；默认开 */
    showEol?: boolean;
    highlight?: (text: string, opts?: { eol?: boolean }) => string;
  }>(),
  {
    show: false,
    title: "编辑",
    hint: "",
    text: "",
    showEol: true,
    highlight: (t: string) =>
      t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"),
  },
);

const emit = defineEmits<{
  "update:show": [v: boolean];
  confirm: [text: string];
}>();

const LINE_H = 22;

type GutterItem = { key: string; kind: "num" | "wrap"; n: number };

const draft = ref("");
const wrapOn = ref(readStorageFlag(STORAGE_KEYS.codeEditorWrap, false));
const taRef = ref<HTMLTextAreaElement | null>(null);
const hlRef = ref<HTMLElement | null>(null);
const gutterRef = ref<HTMLElement | null>(null);
const paneRef = ref<HTMLElement | null>(null);
const measureRef = ref<HTMLElement | null>(null);
const caretLine = ref(1);
const caretCol = ref(1);
const scrollTop = ref(0);
/** 自动换行时每逻辑行的视觉行数 */
const wrapRows = ref<number[]>([]);
const wrapHeights = ref<number[]>([]);

const draftLines = computed(() => {
  const parts = draft.value.split("\n");
  return parts.length ? parts : [""];
});

const lineNos = computed(() => draftLines.value.map((_, i) => i + 1));

const gutterItems = computed((): GutterItem[] => {
  const nos = lineNos.value;
  if (!wrapOn.value) {
    return nos.map((n) => ({ key: `n-${n}`, kind: "num" as const, n }));
  }
  const items: GutterItem[] = [];
  nos.forEach((n, i) => {
    const rows = wrapRows.value[i] ?? 1;
    items.push({ key: `n-${n}`, kind: "num", n });
    for (let r = 1; r < rows; r++) {
      items.push({ key: `w-${n}-${r}`, kind: "wrap", n });
    }
  });
  return items;
});

const hlHtml = computed(() => props.highlight(draft.value, { eol: props.showEol }));

const status = computed(() => {
  const lines = Math.max(1, draftLines.value.length);
  return `${caretLine.value}:${caretCol.value} · ${lines} 行`;
});

const currentStyle = computed(() => {
  const pad = 10;
  if (!wrapOn.value || wrapHeights.value.length === 0) {
    return {
      top: `${pad + (caretLine.value - 1) * LINE_H - scrollTop.value}px`,
      height: `${LINE_H}px`,
    };
  }
  let top = pad;
  for (let i = 0; i < caretLine.value - 1; i++) {
    top += wrapHeights.value[i] ?? LINE_H;
  }
  return {
    top: `${top - scrollTop.value}px`,
    height: `${wrapHeights.value[caretLine.value - 1] ?? LINE_H}px`,
  };
});

let resizeObs: ResizeObserver | null = null;

watch(
  () => props.show,
  async (v) => {
    if (!v) {
      resizeObs?.disconnect();
      resizeObs = null;
      return;
    }
    draft.value = props.text || "";
    caretLine.value = 1;
    caretCol.value = 1;
    await nextTick();
    taRef.value?.focus();
    bindResize();
    await relayout();
    syncCaret();
  },
);

watch([draft, wrapOn], () => {
  if (!props.show) return;
  void relayout();
});

onBeforeUnmount(() => {
  resizeObs?.disconnect();
});

function bindResize() {
  resizeObs?.disconnect();
  if (!paneRef.value || typeof ResizeObserver === "undefined") return;
  resizeObs = new ResizeObserver(() => {
    void relayout();
  });
  resizeObs.observe(paneRef.value);
}

function measureWrap() {
  if (!wrapOn.value) {
    wrapRows.value = [];
    wrapHeights.value = [];
    return;
  }
  const root = measureRef.value;
  if (!root) return;
  const nodes = root.querySelectorAll<HTMLElement>(".ml");
  const rows: number[] = [];
  const heights: number[] = [];
  nodes.forEach((el) => {
    const h = el.offsetHeight || LINE_H;
    const r = Math.max(1, Math.round(h / LINE_H));
    rows.push(r);
    heights.push(r * LINE_H);
  });
  wrapRows.value = rows;
  wrapHeights.value = heights;
}

async function relayout() {
  await nextTick();
  measureWrap();
  if (wrapOn.value && taRef.value) taRef.value.scrollLeft = 0;
  syncScroll();
}

function toggleWrap() {
  wrapOn.value = !wrapOn.value;
  writeStorageFlag(STORAGE_KEYS.codeEditorWrap, wrapOn.value);
}

function close() {
  emit("update:show", false);
}

function confirm() {
  emit("confirm", draft.value);
  emit("update:show", false);
}

function syncScroll() {
  const ta = taRef.value;
  if (!ta) return;
  scrollTop.value = ta.scrollTop;
  if (hlRef.value) {
    hlRef.value.scrollTop = ta.scrollTop;
    hlRef.value.scrollLeft = wrapOn.value ? 0 : ta.scrollLeft;
  }
  if (gutterRef.value) gutterRef.value.scrollTop = ta.scrollTop;
}

function syncCaret() {
  const ta = taRef.value;
  if (!ta) return;
  const pos = ta.selectionStart ?? 0;
  const before = draft.value.slice(0, pos);
  const nl = before.lastIndexOf("\n");
  caretLine.value = before.split("\n").length;
  caretCol.value = pos - nl;
  syncScroll();
}
</script>

<template>
  <van-popup
    :show="show"
    position="bottom"
    round
    class="code-editor-popup"
    :style="{ height: '88%' }"
    :z-index="3000"
    teleport="body"
    @update:show="(v: boolean) => emit('update:show', v)"
  >
    <div class="ed" :class="{ 'wrap-on': wrapOn }">
      <header class="ed-head">
        <button type="button" class="link" @click="close">取消</button>
        <div class="titles">
          <div class="title">{{ title }}</div>
          <div v-if="hint" class="sub">{{ hint }}</div>
        </div>
        <button type="button" class="link primary" @click="confirm">完成</button>
      </header>

      <div class="ed-body">
        <div ref="gutterRef" class="gutter" aria-hidden="true">
          <span
            v-for="item in gutterItems"
            :key="item.key"
            class="gutter-n"
            :class="{
              on: item.kind === 'num' && item.n === caretLine,
              wrap: item.kind === 'wrap',
            }"
            v-text="item.kind === 'wrap' ? '↳' : item.n"
          ></span>
        </div>
        <div ref="paneRef" class="pane">
          <div class="cur" :style="currentStyle"></div>
          <div v-show="wrapOn" ref="measureRef" class="measure" aria-hidden="true">
            <div v-for="(line, i) in draftLines" :key="i" class="ml">
              {{ line || "\u00a0" }}
            </div>
          </div>
          <!-- eslint-disable vue/no-v-html -->
          <pre
            ref="hlRef"
            class="hl qsc-code"
            :class="{ 'is-wrap': wrapOn }"
            v-html="hlHtml"
          ></pre>
          <!-- eslint-enable vue/no-v-html -->
          <textarea
            ref="taRef"
            v-model="draft"
            class="ta"
            spellcheck="false"
            autocapitalize="off"
            autocorrect="off"
            autocomplete="off"
            :wrap="wrapOn ? 'soft' : 'off'"
            enterkeyhint="enter"
            @scroll="syncScroll"
            @keyup="syncCaret"
            @click="syncCaret"
            @select="syncCaret"
            @input="syncCaret"
          ></textarea>
        </div>
      </div>

      <footer class="ed-foot">
        <span>{{ status }}</span>
        <button
          type="button"
          class="wrap-toggle"
          :class="{ on: wrapOn }"
          :aria-pressed="wrapOn"
          @click="toggleWrap"
        >
          自动换行
        </button>
      </footer>
    </div>
  </van-popup>
</template>

<style scoped lang="scss">
.ed {
  --ed-line: 22px;
  --ed-font: 13px;

  display: flex;
  flex-direction: column;
  height: 100%;
  background: var(--qsc-bg);
  color: var(--qsc-text);
}

.ed-head {
  display: grid;
  grid-template-columns: 56px 1fr 56px;
  align-items: center;
  padding: 14px 12px 10px;
  flex-shrink: 0;
  border-bottom: 1px solid var(--qsc-hairline);
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
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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
}

.ed-body {
  display: flex;
  flex: 1 1 auto;
  min-height: 0;
  background: var(--qsc-surface);
  margin: 10px 12px 0;
  border: 1px solid var(--qsc-hairline);
  border-radius: 14px;
  overflow: hidden;
  box-shadow: 0 1px 0 rgba(15, 18, 22, 0.04);
}

.gutter {
  flex: 0 0 auto;
  min-width: 2.6em;
  overflow: hidden;
  text-align: right;
  padding: 10px 8px 10px 10px;
  background: color-mix(in srgb, var(--qsc-surface-2) 88%, var(--qsc-bg));
  border-right: 1px solid var(--qsc-hairline);
  user-select: none;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: var(--ed-font);
  line-height: var(--ed-line);
  font-variant-numeric: tabular-nums;
}

.gutter-n {
  display: block;
  color: var(--qsc-text-3);
  height: var(--ed-line);

  &.on {
    color: var(--qsc-primary);
    font-weight: 650;
  }

  &.wrap {
    color: color-mix(in srgb, var(--qsc-text-3) 78%, var(--qsc-primary));
    font-weight: 400;
    font-variant-numeric: normal;
  }
}

.pane {
  position: relative;
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
}

.cur {
  position: absolute;
  left: 0;
  right: 0;
  height: var(--ed-line);
  background: color-mix(in srgb, var(--qsc-primary) 9%, transparent);
  pointer-events: none;
  z-index: 0;
}

.measure {
  position: absolute;
  inset: 0;
  margin: 0;
  padding: 10px 12px;
  border: 0;
  box-sizing: border-box;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: var(--ed-font);
  line-height: var(--ed-line);
  tab-size: 2;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  word-break: break-all;
  visibility: hidden;
  pointer-events: none;
  overflow: hidden;
  scrollbar-gutter: stable;
}

.ml {
  min-height: var(--ed-line);
  line-height: var(--ed-line);
}

.hl,
.ta {
  position: absolute;
  inset: 0;
  margin: 0;
  padding: 10px 12px;
  border: 0;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: var(--ed-font);
  line-height: var(--ed-line);
  tab-size: 2;
  white-space: pre;
  overflow: auto;
  box-sizing: border-box;
  scrollbar-gutter: stable;
}

.hl {
  pointer-events: none;
  overflow: hidden;
  color: var(--qsc-text);
  z-index: 1;
}

.ta {
  z-index: 2;
  resize: none;
  background: transparent;
  color: transparent;
  caret-color: var(--qsc-primary);
  outline: none;
  -webkit-text-fill-color: transparent;

  &::selection {
    background: color-mix(in srgb, var(--qsc-primary) 28%, transparent);
    color: transparent;
  }
}

.wrap-on .hl,
.wrap-on .ta {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  word-break: break-all;
  overflow-x: hidden;
}

.ed-foot {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  flex-shrink: 0;
  padding: 8px 16px calc(10px + var(--qsc-inset-bottom, 0px));
  font-size: 11px;
  font-variant-numeric: tabular-nums;
  color: var(--qsc-text-3);
}

.wrap-toggle {
  flex-shrink: 0;
  border: none;
  border-radius: 999px;
  padding: 5px 12px;
  font-size: 12px;
  font-weight: 550;
  color: var(--qsc-text-2);
  background: var(--qsc-chip-bg);
  transition:
    background 0.15s ease,
    color 0.15s ease;

  &:active {
    opacity: 0.88;
  }

  &.on {
    color: var(--qsc-primary);
    background: var(--qsc-primary-soft);
    font-weight: 650;
  }
}
</style>

<style lang="scss">
.code-editor-popup.van-popup {
  background: var(--qsc-bg) !important;
  color: var(--qsc-text);
  overflow: hidden;
}

html.pack-md3 .code-editor-popup.van-popup--bottom {
  height: calc(88% - 10px) !important;
  max-height: calc(100dvh - var(--qsc-inset-top, 0px) - 84px) !important;
}

html.float-dock .code-editor-popup.van-popup--bottom {
  border-bottom-left-radius: 0 !important;
  border-bottom-right-radius: 0 !important;
  height: 90% !important;
  max-height: calc(100dvh - var(--qsc-inset-top, 0px) - 8px) !important;
}

.qsc-code {
  .tok-line {
    display: block;
    height: 22px;
    line-height: 22px;
    white-space: pre;
  }

  .tok-line.has-eol::after {
    content: "↵";
    margin-left: 3px;
    color: color-mix(in srgb, var(--qsc-text-3) 72%, transparent);
    font-size: 0.9em;
    user-select: none;
    pointer-events: none;
  }

  &.is-wrap .tok-line {
    height: auto;
    min-height: 22px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    word-break: break-all;
  }

  &.is-wrap .tok-line.has-eol::after {
    display: none;
  }

  .tok-path {
    color: var(--qsc-primary);
  }

  .tok-pref {
    color: var(--qsc-text-2);
    font-weight: 600;
  }

  .tok-start {
    color: #0d9488;
    font-weight: 650;
  }

  .tok-stop {
    color: #c2410c;
    font-weight: 650;
  }

  .tok-num {
    color: var(--qsc-success);
    font-variant-numeric: tabular-nums;
  }

  .tok-val {
    color: #2563eb;
  }

  .tok-eq,
  .tok-sep {
    color: var(--qsc-text-3);
  }

  .tok-bracket {
    color: #a16207;
    font-weight: 650;
  }

  .tok-cmt {
    color: var(--qsc-text-3);
    font-style: italic;
  }

  .tok-bad {
    color: var(--qsc-danger);
    text-decoration: underline wavy color-mix(in srgb, var(--qsc-danger) 55%, transparent);
    text-underline-offset: 2px;
  }

  .tok-line-warn {
    border-radius: 3px;
    box-decoration-break: clone;
    background: color-mix(in srgb, var(--qsc-warn) 12%, transparent);
  }
}

html[data-theme="dark"] .qsc-code {
  .tok-start {
    color: #2dd4bf;
  }

  .tok-stop {
    color: #fb923c;
  }

  .tok-val {
    color: #93c5fd;
  }

  .tok-bracket {
    color: #fbbf24;
  }
}
</style>
