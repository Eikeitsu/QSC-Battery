<script setup lang="ts">
import { showConfirmDialog, showToast } from "vant";
import ChipGroup from "../ui/ChipGroup.vue";
import { DOCS_URL, ORIGIN_URL, PATHS, REPO_URL, WX_PAY_URL } from "../shared";
import { openUrl, openWxPay } from "../bridge";
import { useAppStore, useTheme } from "../stores";

const store = useAppStore();
const theme = useTheme();

const themePresets = [
  { id: "light", l: "浅色" },
  { id: "dark", l: "深色" },
  { id: "system", l: "跟随系统" },
];

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
      <p class="hint">主题、莫奈取色与阅读舒适度</p>
    </div>
    <section class="card">
      <van-cell
        title="外观主题"
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
      <van-cell center title="莫奈取色" label="跟随系统色相；关闭则用电弧青绿">
        <template #right-icon>
          <van-switch
            :model-value="theme.monetOn"
            size="22px"
            @update:model-value="(v) => theme.setMonet(v)"
          />
        </template>
      </van-cell>
      <van-cell center title="紧凑显示" label="卡片与列表间距更紧凑">
        <template #right-icon>
          <van-switch
            :model-value="theme.compactOn"
            size="22px"
            @update:model-value="(v) => theme.setCompact(v)"
          />
        </template>
      </van-cell>
      <van-cell title="字体大小" :value="`${Math.round(theme.fontScale * 100)}%`" />
      <div class="pad slider">
        <van-slider
          :model-value="theme.fontScale"
          :min="0.85"
          :max="1.3"
          :step="0.05"
          @update:model-value="(v) => theme.setFontScale(v)"
          @change="() => theme.setFontScale(theme.fontScale, true)"
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
    <section class="card about">
      <img class="logo" src="/img/icon.png" alt="" width="56" height="56" />
      <div class="name">充电控制</div>
      <div class="ver">{{ store.status.version }}</div>
    </section>
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

.about {
  padding: 22px 16px;
  text-align: center;
  margin-bottom: 10px;
}

.logo {
  border-radius: 14px;
}

.name {
  margin-top: 10px;
  font-size: 18px;
  font-weight: 750;
}

.ver {
  margin-top: 4px;
  font-size: 13px;
  color: var(--qsc-text-3);
}
</style>
