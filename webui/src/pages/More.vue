<script setup lang="ts">
import { computed, ref } from "vue";
import { showConfirmDialog, showToast } from "vant";
import ChipGroup from "../ui/ChipGroup.vue";
import ThemeSwitch from "../ui/ThemeSwitch.vue";
import { DOCS_URL, ORIGIN_URL, PATHS, REPO_URL, WX_PAY_URL } from "../shared";
import { openUrl, openWxPay } from "../bridge";
import { useAppStore, useTheme } from "../stores";

const store = useAppStore();
const theme = useTheme();
const tipOpen = ref(false);
const base = import.meta.env.BASE_URL;

const themePresets = [
  { id: "light", l: "浅色" },
  { id: "dark", l: "深色" },
  { id: "system", l: "跟随系统" },
];

const packPresets = [
  { id: "default", l: "默认" },
  { id: "md3", l: "MD3" },
  { id: "miuix", l: "MIUIX" },
];

const md3Presets = [
  { id: "#6750A4", l: "紫" },
  { id: "#0D9488", l: "青" },
  { id: "#1B6EF3", l: "蓝" },
  { id: "#E11D48", l: "玫" },
  { id: "#D97706", l: "橙" },
  { id: "#059669", l: "绿" },
];

const brandMark = computed(() =>
  theme.resolved === "dark"
    ? `${base}img/icon-mark.png`
    : `${base}img/icon-mark-light.png`,
);

const packLabel = computed(() => {
  if (theme.themePack === "md3") return "Material You：开关 / 底栏 / 芯片形态";
  if (theme.themePack === "miuix") return "HyperOS：粗开关、悬浮底栏与玻璃";
  return "充电控制默认控件";
});

function onSeedInput(e: Event) {
  const v = (e.target as HTMLInputElement).value;
  theme.setMd3Seed(v, false);
}

async function resetConfig() {
  try {
    await showConfirmDialog({
      title: "恢复默认",
      message: "确认恢复停充与电流控制默认配置？",
    });
    await store.resetDefaults();
  } catch {
    /* cancelled */
  }
}

async function open(url: string) {
  await openUrl(url);
}

async function tipAuthor() {
  showToast("正在打开原作者投币页…");
  await openWxPay(WX_PAY_URL);
}
</script>

<template>
  <div class="page">
    <div class="section-head">
      <p class="title">显示</p>
      <p class="hint">主题包会切换控件形态与布局，不只是换色</p>
    </div>
    <section class="card">
      <van-cell title="主题包" :label="packLabel" />
      <div class="pad">
        <ChipGroup
          :options="packPresets"
          :model-value="theme.themePack"
          @update:model-value="(id) => theme.setThemePack(id)"
        />
      </div>
      <van-cell
        title="深浅模式"
        :label="
          theme.themeMode === 'system'
            ? `跟随系统（当前${theme.resolved === 'dark' ? '深色' : '浅色'}）`
            : ''
        "
      />
      <div class="pad">
        <ChipGroup
          :options="themePresets"
          :model-value="theme.themeMode"
          @update:model-value="(id) => theme.setThemeMode(id)"
        />
      </div>

      <template v-if="theme.themePack === 'default'">
        <van-cell title="颜色主题" label="默认主题色板，不跟随莫奈" />
        <div class="pad">
          <ChipGroup
            :options="theme.accentOptions"
            :model-value="theme.accentId"
            @update:model-value="(id) => theme.setAccent(id)"
          />
        </div>
      </template>

      <template v-if="theme.themePack === 'md3'">
        <van-cell title="MD3 色值" :label="theme.md3Seed" />
        <div class="pad">
          <ChipGroup
            :options="md3Presets"
            :model-value="theme.md3Seed.toUpperCase()"
            @update:model-value="(id) => theme.setMd3Seed(id)"
          />
        </div>
        <div class="pad seed-row">
          <label class="seed-label">自定义</label>
          <input
            class="seed-input"
            type="color"
            :value="theme.md3Seed"
            @input="onSeedInput"
          />
        </div>
      </template>

      <template v-if="theme.themePack === 'miuix'">
        <van-cell center title="莫奈取色" label="跟随系统壁纸色">
          <template #right-icon>
            <ThemeSwitch
              :model-value="theme.monetOn"
              @update:model-value="(v) => theme.setMonet(v)"
            />
          </template>
        </van-cell>
        <van-cell center title="悬浮底栏" label="底栏浮于内容之上">
          <template #right-icon>
            <ThemeSwitch
              :model-value="theme.floatDock"
              @update:model-value="(v) => theme.setFloatDock(v)"
            />
          </template>
        </van-cell>
        <van-cell v-if="theme.floatDock" center title="液态玻璃" label="底栏毛玻璃高亮">
          <template #right-icon>
            <ThemeSwitch
              :model-value="theme.dockGlass"
              @update:model-value="(v) => theme.setDockGlass(v)"
            />
          </template>
        </van-cell>
        <van-cell center title="栏位模糊" label="顶栏与底栏磨砂">
          <template #right-icon>
            <ThemeSwitch
              :model-value="theme.barBlur"
              @update:model-value="(v) => theme.setBarBlur(v)"
            />
          </template>
        </van-cell>
      </template>

      <van-cell center title="紧凑显示" label="卡片间距更紧">
        <template #right-icon>
          <ThemeSwitch
            :model-value="theme.compactOn"
            @update:model-value="(v) => theme.setCompact(v)"
          />
        </template>
      </van-cell>
      <van-cell title="字体大小" :value="`${Math.round(theme.fontScale * 100)}%`" />
      <div class="pad slider">
        <van-slider
          :model-value="Number(theme.fontScale)"
          :min="0.85"
          :max="1.3"
          :step="0.05"
          @update:model-value="(v) => theme.setFontScale(v)"
          @change="(v) => theme.setFontScale(v, true)"
        />
      </div>
    </section>

    <div class="section-head">
      <p class="title">配置</p>
    </div>
    <section class="card">
      <van-cell
        title="恢复默认配置"
        label="电量 / 温控 / 电流控制恢复初始值"
        is-link
        @click="resetConfig"
      />
    </section>

    <div class="section-head">
      <p class="title">使用说明</p>
      <p class="hint">路径与常见用法</p>
    </div>
    <section class="card guide">
      <p>
        配置目录：
        <code>{{ PATHS.MODDIR }}/config/</code>
      </p>
      <p>
        运行数据：
        <code>{{ PATHS.DATADIR }}</code>
      </p>
      <p>过夜建议停止 80–90%；与其它限流模块同装时开启兼容模式。</p>
      <p>详细说明见在线文档。</p>
    </section>

    <div class="section-head">
      <p class="title">关于</p>
    </div>
    <section class="card about-brand">
      <img class="about-mark" :src="brandMark" alt="" width="72" height="72" />
      <div class="about-text">
        <div class="name">充电控制</div>
        <div class="sub">QSC-Battery</div>
        <div class="ver">{{ store.status.version }}</div>
      </div>
    </section>
    <p class="about-note">
      本模块基于 <b>top大佬</b> 的 QSC 定量停充，补充了 WebUI
      与可选电流控制，感谢原作者开源贡献。
    </p>
    <section class="card">
      <van-cell
        title="本仓库"
        label="GitHub · Releases"
        is-link
        @click="open(REPO_URL)"
      />
      <van-cell
        title="使用文档"
        label="安装、配置与常见问题"
        is-link
        @click="open(DOCS_URL)"
      />
      <van-cell
        title="原作项目"
        label="top大佬 · GitHub"
        is-link
        @click="open(ORIGIN_URL)"
      />
      <van-cell
        title="投币捐赠"
        label="支持原作者 top大佬（微信）"
        is-link
        @click="tipAuthor"
      />
      <van-cell
        title="打赏"
        label="许小墨"
        is-link
        :arrow-direction="tipOpen ? 'up' : 'down'"
        @click="tipOpen = !tipOpen"
      />
      <div v-show="tipOpen" class="tip-box">
        <img class="tip-qr" :src="`${base}assets/tip.png`" alt="打赏码" />
      </div>
    </section>

    <div class="section-head">
      <p class="title">致谢</p>
    </div>
    <section class="card">
      <van-cell
        title="top大佬"
        label="原作者"
        is-link
        @click="open('https://www.coolapk.com/u/1373784')"
      />
      <van-cell
        title="许小墨"
        label="WebUI 维护"
        is-link
        @click="open('https://www.coolapk.com/u/7602666')"
      />
    </section>
  </div>
</template>

<style scoped lang="scss">
.pad {
  padding: 0 16px 10px;
}

.slider {
  padding-bottom: 18px;
}

.seed-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding-bottom: 14px;
}

.seed-label {
  font-size: 13px;
  color: var(--qsc-text-2);
}

.seed-input {
  width: 42px;
  height: 32px;
  padding: 0;
  border: 1px solid var(--qsc-hairline);
  border-radius: 10px;
  background: transparent;
}

.guide {
  padding: 14px 16px;
  font-size: 13px;
  color: var(--qsc-text-2);
  line-height: 1.55;
}

.guide p {
  margin: 0 0 8px;
}

.guide p:last-child {
  margin-bottom: 0;
}

.guide code {
  font-size: 11px;
  word-break: break-all;
  color: var(--qsc-text);
}

.about-brand {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 16px;
  margin-bottom: 10px;
}

.about-mark {
  width: 72px;
  height: 72px;
  flex-shrink: 0;
  object-fit: contain;
  border: none;
  border-radius: 0;
  background: transparent;
}

.about-text {
  min-width: 0;
  text-align: left;
}

.name {
  font-size: 17px;
  font-weight: 700;
  letter-spacing: -0.2px;
}

.sub {
  margin-top: 2px;
  font-size: 12px;
  color: var(--qsc-text-3);
}

.ver {
  margin-top: 4px;
  font-size: 12px;
  color: var(--qsc-text-3);
}

.about-note {
  margin: 0 6px 12px;
  padding: 12px 14px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--qsc-primary) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--qsc-primary) 18%, transparent);
  font-size: 12px;
  color: var(--qsc-text-2);
  line-height: 1.55;
}

.about-note b {
  color: var(--qsc-text);
  font-weight: 650;
}

.tip-box {
  display: flex;
  justify-content: center;
  padding: 4px 16px 16px;
}

.tip-qr {
  width: min(220px, 70vw);
  height: auto;
  border-radius: 12px;
  background: var(--qsc-surface);
  box-shadow: 0 6px 18px rgba(15, 18, 22, 0.12);
  padding: 8px;
}
</style>
