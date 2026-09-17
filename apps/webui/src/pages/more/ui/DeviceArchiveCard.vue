<script setup lang="ts">
import { onMounted, ref } from "vue";
import { showConfirmDialog, showToast, showSuccessToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";
import type { DeviceArchiveItem } from "@/shared/api/deviceArchive";
import { useAppStore } from "@/stores";

const archives = ref<DeviceArchiveItem[]>([]);
const archiveNameDraft = ref("");
const archiveBusy = ref(false);
const archiveLoading = ref(false);
const store = useAppStore();

async function reloadArchives() {
  archiveLoading.value = true;
  try {
    archives.value = await api.listDeviceArchives();
  } finally {
    archiveLoading.value = false;
  }
}

async function saveArchive() {
  const slug = String(archiveNameDraft.value || "").trim();
  if (!slug) {
    showToast("请输入档案名");
    return;
  }
  archiveBusy.value = true;
  try {
    const ok = await api.saveDeviceArchive(slug);
    if (!ok) {
      showToast("保存档案失败（需 device.profile 已就绪）");
      return;
    }
    archiveNameDraft.value = "";
    showSuccessToast("已保存设备档案");
    await reloadArchives();
  } finally {
    archiveBusy.value = false;
  }
}

async function applyArchive(a: DeviceArchiveItem) {
  try {
    await showConfirmDialog({
      title: "应用设备档案",
      message: `用「${a.name}」覆盖本机 device.profile（已测出的首选开关会保留）`,
    });
  } catch {
    return;
  }
  archiveBusy.value = true;
  try {
    const ok = await api.applyDeviceArchive(a.id);
    if (!ok) {
      showToast("应用失败");
      return;
    }
    showSuccessToast("已应用，下一轮主循环生效");
    await store.refreshStatus(true);
  } finally {
    archiveBusy.value = false;
  }
}

async function deleteArchive(a: DeviceArchiveItem) {
  try {
    await showConfirmDialog({
      title: "删除设备档案",
      message: `确认删除「${a.name}」？`,
    });
  } catch {
    return;
  }
  archiveBusy.value = true;
  try {
    const ok = await api.deleteDeviceArchive(a.id);
    if (!ok) {
      showToast("删除失败");
      return;
    }
    showSuccessToast("已删除");
    await reloadArchives();
  } finally {
    archiveBusy.value = false;
  }
}

function archiveSubtitle(a: DeviceArchiveItem): string {
  const parts: string[] = [];
  if (a.model) parts.push(a.model);
  if (a.marketName) parts.push(a.marketName);
  if (a.mca) parts.push("MCA 兼容");
  if (a.preferredSwitch) parts.push("已保存首选开关");
  if (a.savedAt) parts.push(a.savedAt);
  return parts.join(" · ");
}

onMounted(() => {
  void reloadArchives();
});

defineExpose({
  reload: () => {
    void reloadArchives();
  },
});
</script>

<template>
  <SectionHead
    title="多设备档案库"
    :hint="archiveLoading ? '读取中…' : `已保存 ${archives.length} 份设备档案`"
  />
  <ThemedCard>
    <van-field
      v-model="archiveNameDraft"
      label="设备档案名"
      placeholder="如：K90U / 小米17"
      input-align="right"
    />
    <van-cell
      title="归档当前 device.profile"
      label="含首选开关、MCA 路径、机型名"
      is-link
      :disabled="archiveBusy"
      @click="saveArchive"
    />
    <van-cell
      v-for="a in archives"
      :key="a.id"
      :title="a.name"
      :label="archiveSubtitle(a)"
      is-link
      :disabled="archiveBusy"
      @click="applyArchive(a)"
    >
      <template #right-icon>
        <button type="button" class="del" @click.stop="deleteArchive(a)">删</button>
      </template>
    </van-cell>
    <div v-if="!archives.length" class="archive-empty">
      暂无档案。归档后可在同型号不同设备、或重装模块后一键还原 device.profile。
    </div>
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

.archive-empty {
  padding: 16px 16px 12px;
  font-size: 13px;
  color: var(--qsc-text-3);
  line-height: 1.5;
}
</style>
