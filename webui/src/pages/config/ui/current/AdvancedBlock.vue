<script setup lang="ts">
import { computed, ref } from "vue";
import CodeEditorPopup from "@/shared/ui/CodeEditorPopup.vue";
import { LIMITS } from "@/shared";
import { useConfigFormContext } from "@/composables";
import ConfigBlock from "../ConfigBlock.vue";

const { store } = useConfigFormContext();
const pathEditorOpen = ref(false);

const pathText = computed({
  get: () => (store.current.battery_current || []).map(String).join("\n"),
  set: (v: string) => {
    store.current.battery_current = String(v || "")
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter(Boolean);
  },
});

async function saveAdvanced() {
  await store.saveCurrent();
}

async function onPathsConfirm(text: string) {
  pathText.value = text;
  await saveAdvanced();
}
</script>

<template>
  <ConfigBlock nested label="进阶（重申 / 节点）">
    <van-field
      v-model.number="store.current.current_reaffirm_sec"
      type="digit"
      label="重申间隔秒"
      :placeholder="`0–${LIMITS.reaffirmSecMax}，0=关`"
      input-align="right"
      @change="saveAdvanced"
    />
    <van-field
      v-model.number="store.current.current_drift_ua"
      type="digit"
      label="漂移裕量 µA"
      placeholder="偏高超过此值才强制重申"
      input-align="right"
      @change="saveAdvanced"
    />
    <van-field
      v-model.number="store.current.current_step_ua"
      type="digit"
      label="降流台阶 µA"
      placeholder="0=直接写目标"
      input-align="right"
      @change="saveAdvanced"
    />
    <van-cell
      title="电流节点路径"
      :label="`${(store.current.battery_current || []).length} 条 · 点按编辑`"
      is-link
      @click="pathEditorOpen = true"
    />
  </ConfigBlock>

  <CodeEditorPopup
    v-model:show="pathEditorOpen"
    title="电流节点路径"
    hint="每行一个 /sys 或 /proc 路径"
    :text="pathText"
    @confirm="onPathsConfirm"
  />
</template>
