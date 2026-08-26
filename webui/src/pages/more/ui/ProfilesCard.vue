<script setup lang="ts">
import { onMounted, ref } from "vue";
import { showConfirmDialog, showToast, showSuccessToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";
import { useAppStore } from "@/stores";
import { useAboutActions } from "../composables/useAboutActions";

const store = useAppStore();
const { resetConfig } = useAboutActions();
const profiles = ref<api.NamedProfile[]>([]);
const saving = ref(false);
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

onMounted(() => {
  void reload();
});
</script>

<template>
  <SectionHead title="配置档与备份" hint="命名切换、导入导出、恢复默认" />
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
      title="恢复默认配置"
      label="电量 / 温控 / 电流控制恢复初始值"
      is-link
      @click="resetConfig"
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
