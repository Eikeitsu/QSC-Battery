<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";

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

const draft = ref("");
const taRef = ref<HTMLTextAreaElement | null>(null);
const hlRef = ref<HTMLElement | null>(null);
const gutterRef = ref<HTMLElement | null>(null);
const caretLine = ref(1);
const caretCol = ref(1);
const scrollTop = ref(0);

const lineNos = computed(() => {
  const n = Math.max(1, draft.value.split("\n").length);
  return Array.from({ length: n }, (_, i) => i + 1);
});

const hlHtml = computed(() => props.highlight(draft.value, { eol: props.showEol }));

const status = computed(() => {
  const lines = Math.max(1, draft.value.split("\n").length);
  return `${caretLine.value}:${caretCol.value} · ${lines} 行`;
});

const currentTop = computed(
  () => `${10 + (caretLine.value - 1) * LINE_H - scrollTop.value}px`,
);

watch(
  () => props.show,
  async (v) => {
    if (!v) return;
    draft.value = props.text || "";
    caretLine.value = 1;
    caretCol.value = 1;
    await nextTick();
    taRef.value?.focus();
    syncCaret();
  },
);

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
    hlRef.value.scrollLeft = ta.scrollLeft;
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
    <div class="ed">
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
            v-for="n in lineNos"
            :key="n"
            class="gutter-n"
            :class="{ on: n === caretLine }"
            v-text="n"
          ></span>
        </div>
        <div class="pane">
          <div class="cur" :style="{ top: currentTop }"></div>
          <!-- eslint-disable-next-line vue/no-v-html -->
          <pre ref="hlRef" class="hl qsc-code" v-html="hlHtml"></pre>
          <textarea
            ref="taRef"
            v-model="draft"
            class="ta"
            spellcheck="false"
            autocapitalize="off"
            autocorrect="off"
            autocomplete="off"
            wrap="off"
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
        <span class="foot-hint">↵ 换行 · 左右滑动</span>
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

.foot-hint {
  opacity: 0.85;
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
