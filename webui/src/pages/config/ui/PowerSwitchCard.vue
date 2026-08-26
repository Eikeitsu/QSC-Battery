<script setup lang="ts">
import { computed, ref } from "vue";
import { showConfirmDialog } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import CodeEditorPopup from "@/shared/ui/CodeEditorPopup.vue";
import { highlightPowerSwitch } from "@/shared";
import { looksLikePolicySwitch } from "@/shared/lib/policySwitch";
import { useConfigFormContext } from "@/composables";

const { powerSwitchText, savePowerSwitches } = useConfigFormContext();
const editorOpen = ref(false);

const previewHtml = computed(() => highlightPowerSwitch(powerSwitchText.value));
const empty = computed(() => !String(powerSwitchText.value || "").trim());
const tapY = ref(0);
const policyWarn = computed(() =>
  String(powerSwitchText.value || "")
    .split(/\r?\n/)
    .some((l) => looksLikePolicySwitch(l)),
);

function onPreviewClick(e: MouseEvent) {
  if (Math.abs(e.clientY - tapY.value) > 8) return;
  editorOpen.value = true;
}

async function onConfirm(text: string) {
  const hasPolicy = String(text || "")
    .split(/\r?\n/)
    .some((l) => looksLikePolicySwitch(l));
  if (hasPolicy) {
    try {
      await showConfirmDialog({
        title: "策略类节点警告",
        message:
          "内容含 night_charging / cool_mode 等策略节点，小米等机型易闪充。确认仍要保存？",
      });
    } catch {
      return;
    }
  }
  powerSwitchText.value = text;
  await savePowerSwitches();
}
</script>

<template>
  <SectionHead title="自定义供电开关" hint="自动扫描无效时可按下列格式填写，每行一个" />
  <ThemedCard>
    <div
      class="preview"
      role="button"
      tabindex="0"
      @pointerdown="tapY = $event.clientY"
      @click="onPreviewClick"
      @keydown.enter.prevent="editorOpen = true"
    >
      <!-- eslint-disable-next-line vue/no-v-html -->
      <pre v-if="!empty" class="preview-code qsc-code" v-html="previewHtml"></pre>
      <span v-else class="ph">/sys/.../node start=1 stop=0</span>
      <span class="preview-tag">点击编辑</span>
    </div>
    <p class="field-hint pad-x">
      格式：路径 start=开值 stop=关值。空格可用
      ::。保存后优先于全量扫描；留空则仅用自动探测。
    </p>
    <p v-if="policyWarn" class="field-hint pad-x warn">
      当前含策略类节点，可能引起闪充；优先用「首选停充开关」或测开关结果。
    </p>
    <p class="field-hint pad-x warn">
      升级后若闪充或停充无效：到下方「测开关与缓存」清除并重启，或插电后 Action
      音量下测开关。
    </p>
  </ThemedCard>

  <CodeEditorPopup
    v-model:show="editorOpen"
    title="自定义供电开关"
    hint="每行一个节点 · 完成即保存"
    :text="powerSwitchText"
    :highlight="highlightPowerSwitch"
    @confirm="onConfirm"
  />
</template>

<style scoped lang="scss">
.preview {
  position: relative;
  width: 100%;
  margin: 4px 0 0;
  padding: 10px 16px 28px;
  min-height: 7.5em;
  max-height: 7.5em;
  overflow-x: hidden;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  color: var(--qsc-text);
  cursor: pointer;
  box-sizing: border-box;
}

.preview-code {
  margin: 0;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13px;
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-all;
}

.ph {
  color: var(--qsc-text-3);
  font-size: 14px;
  line-height: 1.5;
}

.preview-tag {
  position: absolute;
  right: 12px;
  bottom: 6px;
  font-size: 11px;
  color: var(--qsc-primary);
  pointer-events: none;
}

.field-hint {
  margin: 4px 0 8px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.4;
}

.field-hint.warn {
  color: var(--van-warning-color, #ff976a);
}

.pad-x {
  padding: 0 var(--qsc-cell-pad-x, 16px) 12px;
}
</style>
