<script setup lang="ts">
import { onMounted, ref } from "vue";
import { showConfirmDialog, showToast, showSuccessToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";
import { useAppStore } from "@/stores";

const store = useAppStore();
const profiles = ref<api.NamedProfile[]>([]);
const saving = ref(false);
const testing = ref(false);
const nameDraft = ref("");

async function reload() {
  profiles.value = await api.loadProfiles();
}

async function saveAsProfile() {
  const name = String(nameDraft.value || "").trim();
  if (!name) {
    showToast("请输入配置档名称");
    return;
  }
  saving.value = true;
  try {
    const list = [...profiles.value];
    const id = `${Date.now()}`;
    const bundle = await store.snapshotBundleAsync();
    list.push({
      ...bundle,
      id,
      name,
    });
    if (!(await api.saveProfiles(list))) {
      showToast("保存配置档失败");
      return;
    }
    nameDraft.value = "";
    showSuccessToast(`已保存「${name}」`);
    await reload();
  } finally {
    saving.value = false;
  }
}

async function applyProfile(p: api.NamedProfile) {
  try {
    await showConfirmDialog({
      title: "应用配置档",
      message: `确认用「${p.name}」覆盖当前停充配置？`,
    });
  } catch {
    return;
  }
  await store.applyBundle(p);
}

async function removeProfile(p: api.NamedProfile) {
  try {
    await showConfirmDialog({
      title: "删除配置档",
      message: `确认删除「${p.name}」？`,
    });
  } catch {
    return;
  }
  const list = profiles.value.filter((x) => x.id !== p.id);
  if (!(await api.saveProfiles(list))) {
    showToast("删除失败");
    return;
  }
  showSuccessToast("已删除");
  await reload();
}

async function onExport() {
  await store.exportConfig();
}

async function onImport() {
  try {
    await showConfirmDialog({
      title: "导入配置",
      message:
        "将读取 Download/qsc_battery_config.json（含 preferred/MCA 档案）并覆盖当前配置",
    });
  } catch {
    return;
  }
  await store.importConfig();
}

async function onClearCache() {
  try {
    await showConfirmDialog({
      title: "清除开关缓存",
      message:
        "将删除 list_switch / device.profile，重启后重新探测。用于升级后闪充或停充无效。",
    });
  } catch {
    return;
  }
  if (await api.clearSwitchCache()) showSuccessToast("已清除，请重启设备");
  else showToast("清除失败");
}

async function onTestSwitch(full: boolean) {
  try {
    await showConfirmDialog({
      title: full ? "完整测开关" : "快速测开关",
      message: full
        ? "请保持插电。将逐条测试候选节点，耗时可能较长，测完会恢复充电。"
        : "请保持插电。快速模式最多测约 12 条候选；完整测试请选下方完整测开关。",
    });
  } catch {
    return;
  }
  testing.value = true;
  showToast("已后台启动测开关，请保持插电…");
  try {
    const r = await api.runTestSwitch(full);
    if (!r.ok && !/started|already/.test(r.output)) {
      showToast("启动测开关失败");
      return;
    }
    const { status, summary } = await api.waitSwitchTestDone(full ? 300_000 : 120_000);
    const msg = (summary || status || "").slice(0, 900);
    try {
      await showConfirmDialog({
        title: /^done/.test(status) ? "测开关完成" : "测开关状态",
        message: msg || status || "无详细输出，可查看 data/switch_test.log",
        confirmButtonText: "知道了",
        showCancelButton: false,
      });
    } catch {
      /* closed */
    }
  } finally {
    testing.value = false;
  }
}

onMounted(() => {
  void reload();
});
</script>

<template>
  <SectionHead title="配置档与备份" hint="命名切换、导入导出、测开关" />
  <ThemedCard>
    <van-field
      v-model="nameDraft"
      label="新配置档"
      placeholder="如：日常 / 旅行"
      input-align="right"
    />
    <van-cell
      title="保存当前为配置档"
      is-link
      :disabled="saving"
      @click="saveAsProfile"
    />
    <van-cell
      v-for="p in profiles"
      :key="p.id"
      :title="p.name"
      label="点按应用"
      is-link
      @click="applyProfile(p)"
    >
      <template #right-icon>
        <button type="button" class="del" @click.stop="removeProfile(p)">删</button>
      </template>
    </van-cell>
    <van-cell
      title="导出配置"
      label="含 preferred / MCA → Download/qsc_battery_config.json"
      is-link
      @click="onExport"
    />
    <van-cell
      title="导入配置"
      label="← Download/qsc_battery_config.json"
      is-link
      @click="onImport"
    />
    <van-cell
      title="快速测开关"
      label="插电 · 约 12 条候选"
      is-link
      :disabled="testing"
      @click="onTestSwitch(false)"
    />
    <van-cell
      title="完整测开关"
      label="插电 · 全部候选（较慢）"
      is-link
      :disabled="testing"
      @click="onTestSwitch(true)"
    />
    <van-cell
      title="清除开关缓存并提示重启"
      label="升级后闪充 / 停充无效时用"
      is-link
      @click="onClearCache"
    />
  </ThemedCard>
</template>

<style scoped lang="scss">
.del {
  border: none;
  background: transparent;
  color: var(--van-danger-color, #ee0a24);
  font-size: 13px;
  padding: 8px 4px;
}
</style>
