<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { showConfirmDialog, showToast, showSuccessToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import * as api from "@/shared/api";
import { useAppStore } from "@/stores";
import { looksLikePolicySwitch } from "@/shared/lib/policySwitch";
import {
  filterPresetsByModel,
  loadLocalDevicePresets,
  loadRepoPresetCache,
  resolveRepoPresetsForDisplay,
  saveLocalDevicePresets,
  updateRepoPresetsFromRemote,
  type DevicePreset,
  type RepoPresetCacheMeta,
} from "@/shared/data/devicePresets";

interface CommunitySharePayload {
  v: 1;
  model?: string;
  device_profile?: api.DeviceProfileExport | null;
}

const store = useAppStore();

const shareText = ref("");
const sharePlaceholder =
  '示例：{"v":1,"model":"Xiaomi","device_profile":{"preferred_switch":"...","preferred_start":"1","preferred_stop":"0","reassert":"1"}}';
const parsedShare = ref<CommunitySharePayload | null>(null);
const parseError = ref<string | null>(null);
const shareLoading = ref(false);
const repoUpdating = ref(false);

const localPresets = ref<DevicePreset[]>([]);
const repoPresets = ref<DevicePreset[]>([]);
const repoMeta = ref<RepoPresetCacheMeta>({});
const presetNameDraft = ref("");

function extractModelFromDeviceName(deviceName: string): string {
  const first = String(deviceName || "")
    .split(" · ")[0]
    ?.trim();
  return first || "Android";
}

const currentModel = computed(() => extractModelFromDeviceName(store.deviceName));

const modelMatchDraft = computed(() => {
  const m = parsedShare.value?.model || currentModel.value;
  return String(m || "Android").trim();
});

const repoDisplayPresets = computed(() =>
  resolveRepoPresetsForDisplay(repoPresets.value),
);

const matchingRepo = computed(() =>
  filterPresetsByModel(repoDisplayPresets.value, modelMatchDraft.value),
);

const matchingLocal = computed(() =>
  filterPresetsByModel(localPresets.value, modelMatchDraft.value),
);

const repoStatusLabel = computed(() => {
  const m = repoMeta.value;
  if (!repoPresets.value.length) {
    return "尚未从仓库同步（当前显示模块内兜底）";
  }
  const when = m.fetched_at
    ? m.fetched_at.replace("T", " ").slice(0, 19)
    : m.updated_at || "未知";
  return `已缓存 ${repoPresets.value.length} 条 · 同步于 ${when}`;
});

function reloadPresetCaches() {
  localPresets.value = loadLocalDevicePresets();
  const cached = loadRepoPresetCache();
  repoPresets.value = cached.presets;
  repoMeta.value = cached.meta;
}

async function loadCurrentShareText(): Promise<void> {
  shareLoading.value = true;
  parseError.value = null;
  try {
    const model = currentModel.value;
    const profile = await api.loadDeviceProfileExport();
    if (!profile) {
      shareText.value = "";
      parsedShare.value = null;
      return;
    }
    const payload: CommunitySharePayload = {
      v: 1,
      model,
      device_profile: profile,
    };
    shareText.value = JSON.stringify(payload, null, 2);
    parsedShare.value = payload;
  } catch (e: unknown) {
    parseError.value = String((e as Error)?.message || e || "读取失败");
  } finally {
    shareLoading.value = false;
  }
}

async function onCopy(): Promise<void> {
  const text = String(shareText.value || "");
  if (!text.trim()) {
    showToast("没有可复制的分享文本");
    return;
  }
  try {
    await navigator.clipboard.writeText(text);
    showSuccessToast("已复制");
  } catch {
    showToast("复制失败：请手动长按文本复制");
  }
}

function parseShareText(text: string): CommunitySharePayload | null {
  const raw = String(text || "").trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as CommunitySharePayload;
    if (
      parsed &&
      parsed.v === 1 &&
      parsed.device_profile &&
      typeof parsed.device_profile === "object"
    ) {
      return parsed;
    }
    return null;
  } catch {
    try {
      const parsed = api.parseJsonc(raw) as unknown as CommunitySharePayload;
      if (
        parsed &&
        parsed.v === 1 &&
        parsed.device_profile &&
        typeof parsed.device_profile === "object"
      ) {
        return parsed;
      }
      return null;
    } catch {
      return null;
    }
  }
}

async function warnIfPolicyPreferred(preferred: string): Promise<boolean> {
  if (!preferred || !looksLikePolicySwitch(preferred)) return true;
  try {
    await showConfirmDialog({
      title: "策略类节点警告",
      message:
        "该路径可能是策略/温控节点（如 night_charging），易与系统互抢导致充电反复启停。确认仍要保存为 preferred？",
    });
    return true;
  } catch {
    return false;
  }
}

async function onParseAndApply(): Promise<void> {
  const payload = parseShareText(shareText.value);
  if (!payload?.device_profile) {
    showToast("分享文本解析失败（需要包含 device_profile）");
    parsedShare.value = null;
    return;
  }

  const preferred = String(payload.device_profile.preferred_switch || "");
  if (!(await warnIfPolicyPreferred(preferred))) return;

  shareLoading.value = true;
  try {
    const ok = await api.applyDeviceProfileExport(payload.device_profile);
    if (!ok) {
      showToast("应用失败");
      return;
    }
    parsedShare.value = payload;
    await store.refreshStatus(true);
    showSuccessToast("已应用分享节点");
  } finally {
    shareLoading.value = false;
  }
}

async function onApplyPreset(preset: DevicePreset) {
  const preferred = String(preset.profile?.preferred_switch || "");
  if (!(await warnIfPolicyPreferred(preferred))) return;

  shareLoading.value = true;
  try {
    const ok = await api.applyDeviceProfileExport(preset.profile);
    if (!ok) {
      showToast("应用预制档失败");
      return;
    }
    await store.refreshStatus(true);
    showSuccessToast(`已应用：${preset.name}`);
  } finally {
    shareLoading.value = false;
  }
}

function buildLocalPresetFromParsedShare(
  payload: CommunitySharePayload,
): DevicePreset | null {
  const profile = payload?.device_profile;
  if (!profile || typeof profile !== "object") return null;

  const model =
    String(payload.model || modelMatchDraft.value || "Android").trim() || "Android";
  const name = String(presetNameDraft.value || "").trim() || `本机预制 · ${model}`;
  return {
    id: `local_${Date.now()}`,
    name,
    matches: [model],
    profile,
    source: "local",
    note: "由社区分享文本保存",
  };
}

async function onSaveAsLocalPreset() {
  const payload = parsedShare.value || parseShareText(shareText.value);
  if (!payload?.device_profile) {
    showToast("请先填入有效分享文本（含 device_profile）");
    return;
  }
  parsedShare.value = payload;
  const preferred = String(payload.device_profile.preferred_switch || "");
  if (!(await warnIfPolicyPreferred(preferred))) return;

  const preset = buildLocalPresetFromParsedShare(payload);
  if (!preset) {
    showToast("无法保存预制档");
    return;
  }
  const next = [...localPresets.value, preset];
  saveLocalDevicePresets(next);
  localPresets.value = next;
  showSuccessToast("已保存到本机预制档");
}

async function onRemoveLocalPreset(preset: DevicePreset) {
  try {
    await showConfirmDialog({
      title: "删除本机预制档",
      message: `确认删除「${preset.name}」？`,
    });
  } catch {
    return;
  }
  const next = localPresets.value.filter((p) => p.id !== preset.id);
  saveLocalDevicePresets(next);
  localPresets.value = next;
  showSuccessToast("已删除");
}

async function onUpdateFromRepo() {
  repoUpdating.value = true;
  try {
    const r = await updateRepoPresetsFromRemote();
    reloadPresetCaches();
    showSuccessToast(`已同步仓库 ${r.count} 条`);
  } catch (e: unknown) {
    showToast(String((e as Error)?.message || e || "同步失败"));
  } finally {
    repoUpdating.value = false;
  }
}

function sourceLabel(p: DevicePreset): string {
  if (p.source === "local") return "本机";
  if (p.source === "repo") return "仓库缓存";
  return "内置兜底";
}

onMounted(async () => {
  reloadPresetCaches();
  presetNameDraft.value = "";
  await loadCurrentShareText();
});
</script>

<template>
  <SectionHead
    title="机型节点分享"
    hint="复制/粘贴 preferred · MCA 档案；可保存为本机预制档"
  />
  <ThemedCard>
    <van-cell
      title="生成当前机型分享文本"
      label="含 device_profile（preferred / MCA）"
      is-link
      @click="loadCurrentShareText"
    />
    <div class="pad">
      <van-field
        v-model="shareText"
        type="textarea"
        rows="5"
        autosize
        :placeholder="sharePlaceholder"
        input-align="left"
        :disabled="shareLoading"
      />
      <p v-if="parseError" class="err">{{ parseError }}</p>
    </div>
    <div class="actions">
      <van-button
        size="small"
        type="primary"
        block
        round
        :loading="shareLoading"
        @click="onCopy"
      >
        复制分享文本
      </van-button>
      <van-button
        size="small"
        block
        round
        :loading="shareLoading"
        @click="onParseAndApply"
      >
        解析并应用
      </van-button>
    </div>
    <van-field
      v-model="presetNameDraft"
      label="本机名称"
      placeholder="如：小米共享 · 稳定停充"
      input-align="right"
      :disabled="shareLoading"
    />
    <van-field
      :model-value="modelMatchDraft"
      label="机型匹配"
      placeholder="来自分享文本 model"
      input-align="right"
      disabled
    />
    <div class="actions actions-last">
      <van-button
        size="small"
        plain
        block
        round
        :disabled="shareLoading"
        @click="onSaveAsLocalPreset"
      >
        保存到本机预制档
      </van-button>
    </div>
  </ThemedCard>

  <SectionHead
    title="仓库预制档"
    hint="维护在 docs/public/device-presets.json；Pages 更新即可，不必发模块版"
  />
  <ThemedCard>
    <van-cell
      title="从仓库更新到本地缓存"
      :label="repoStatusLabel"
      is-link
      :disabled="repoUpdating"
      @click="onUpdateFromRepo"
    />
    <van-cell
      v-if="matchingRepo.length === 0"
      title="暂无匹配仓库预制档"
      :label="`当前机型：${modelMatchDraft}`"
    />
    <van-cell
      v-for="p in matchingRepo"
      :key="`repo-${p.id}`"
      :title="p.name"
      :label="p.note || sourceLabel(p)"
      is-link
      @click="onApplyPreset(p)"
    />
  </ThemedCard>

  <SectionHead title="本机预制档" hint="仅保存在本机 WebUI；与仓库缓存互不影响" />
  <ThemedCard>
    <van-cell
      v-if="matchingLocal.length === 0"
      title="暂无匹配本机预制档"
      label="可粘贴分享文本后「保存到本机预制档」"
    />
    <van-cell
      v-for="p in matchingLocal"
      :key="`local-${p.id}`"
      :title="p.name"
      :label="p.note || '本机'"
      is-link
      @click="onApplyPreset(p)"
    >
      <template #right-icon>
        <button type="button" class="del" @click.stop="onRemoveLocalPreset(p)">删</button>
      </template>
    </van-cell>
  </ThemedCard>
</template>

<style scoped lang="scss">
.pad {
  padding: 4px 0 0;
}

.err {
  margin: 6px var(--qsc-cell-pad-x, 16px) 0;
  color: var(--van-danger-color, #ee0a24);
  font-size: 12px;
}

.actions {
  display: grid;
  gap: 8px;
  padding: 10px var(--qsc-cell-pad-x, 16px) 12px;
}

.actions-last {
  padding-top: 4px;
  padding-bottom: 14px;
}

.del {
  border: none;
  background: transparent;
  color: var(--van-danger-color, #ee0a24);
  font-size: 13px;
  padding: 8px 4px;
}
</style>
