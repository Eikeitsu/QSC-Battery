<script setup lang="ts">
import { onMounted, reactive, ref } from "vue";
import { showConfirmDialog, showSuccessToast, showToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";
import { looksLikePolicySwitch } from "@/shared/lib/policySwitch";

const loading = ref(false);
const form = reactive({
  path: "",
  start: "",
  stop: "",
  reassert: true,
  mcaPath: "",
});

async function reload() {
  loading.value = true;
  try {
    const p = await api.loadDeviceProfileExport();
    form.path = p?.preferred_switch || "";
    form.start = p?.preferred_start || "";
    form.stop = p?.preferred_stop || "";
    form.reassert = p?.reassert !== "0";
    form.mcaPath = p?.mca_path || "";
  } finally {
    loading.value = false;
  }
}

async function onSave() {
  if (!form.path.trim()) {
    showToast("请填写节点路径");
    return;
  }
  if (looksLikePolicySwitch(form.path)) {
    try {
      await showConfirmDialog({
        title: "策略类节点警告",
        message:
          "该路径可能是策略/温控节点（如 night_charging），易与系统互抢导致闪充。确认仍要保存为 preferred？",
      });
    } catch {
      return;
    }
  }
  const ok = await api.savePreferredSwitch({
    path: form.path,
    start: form.start || "1",
    stop: form.stop || "0",
    reassert: form.reassert,
  });
  if (ok) {
    showSuccessToast("首选开关已保存");
    await reload();
  } else showToast("保存失败");
}

async function onClear() {
  try {
    await showConfirmDialog({
      title: "清除首选开关",
      message: "清除后将回退到 MCA / 扫描列表。",
    });
  } catch {
    return;
  }
  if (await api.clearPreferredSwitch()) {
    showSuccessToast("已清除");
    await reload();
  } else showToast("清除失败");
}

onMounted(() => {
  void reload();
});
</script>

<template>
  <SectionHead title="首选停充开关" hint="test_switch 实测结果；可手动改路径与是否重申" />
  <ThemedCard>
    <van-field
      v-model="form.path"
      label="路径"
      placeholder="/sys/.../node"
      input-align="right"
      :disabled="loading"
    />
    <van-field
      v-model="form.start"
      label="开值 start"
      placeholder="如 1"
      input-align="right"
    />
    <van-field
      v-model="form.stop"
      label="关值 stop"
      placeholder="如 0"
      input-align="right"
    />
    <SwitchCell
      title="停充后重申"
      label="系统改回节点时继续写入（MCA 机通常需要）"
      :model-value="form.reassert"
      @update:model-value="(v) => (form.reassert = v)"
    />
    <p v-if="form.mcaPath" class="hint">MCA：{{ form.mcaPath }}</p>
    <div class="actions">
      <van-button
        size="small"
        type="primary"
        block
        round
        :loading="loading"
        @click="onSave"
      >
        保存首选
      </van-button>
      <van-button size="small" plain block round :disabled="loading" @click="onClear">
        清除首选
      </van-button>
    </div>
  </ThemedCard>
</template>

<style scoped lang="scss">
.hint {
  margin: 4px var(--qsc-cell-pad-x, 16px) 8px;
  font-size: 12px;
  color: var(--qsc-text-3);
  word-break: break-all;
  line-height: 1.4;
}

.actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 8px var(--qsc-cell-pad-x, 16px) 14px;
}
</style>
