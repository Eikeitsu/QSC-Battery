<script setup lang="ts">
import { ref } from "vue";
import { showConfirmDialog } from "vant";
import { useAppStore, useTheme } from "../stores";

const store = useAppStore();
const theme = useTheme();
const pullLoading = ref(false);

async function doRefresh(showTip: boolean) {
  await store.refreshLog(showTip);
  theme.syncStatusBar();
  requestAnimationFrame(() => theme.syncStatusBar());
}

async function onPullRefresh() {
  pullLoading.value = true;
  try {
    await doRefresh(true);
  } finally {
    pullLoading.value = false;
  }
}

async function onButtonRefresh() {
  // 不驱动 van-pull-refresh，避免按钮刷新把顶栏间距撑乱
  await doRefresh(true);
}

async function onClear() {
  try {
    await showConfirmDialog({
      title: "清空日志",
      message: "确认清空运行日志？",
    });
    await store.clearLog();
    theme.syncStatusBar();
  } catch {
    /* cancelled */
  }
}
</script>

<template>
  <van-pull-refresh
    v-model="pullLoading"
    success-text="日志已刷新"
    @refresh="onPullRefresh"
  >
    <div
      class="page"
      :class="{
        'page-md3': theme.themePack === 'md3',
        'page-miuix': theme.themePack === 'miuix',
      }"
    >
      <!-- MD3 -->
      <template v-if="theme.themePack === 'md3'">
        <section class="md3-tonal log-md3-meta">
          <div class="log-md3-meta__row">
            <div>
              <div class="log-md3-meta__title">运行日志</div>
              <div class="log-md3-meta__sub">
                最近 {{ store.logLines }} 行 · {{ store.logSize }}
              </div>
            </div>
            <div class="log-md3-meta__actions">
              <van-button size="small" round type="primary" @click="onButtonRefresh">
                刷新
              </van-button>
              <van-button size="small" round plain type="danger" @click="onClear">
                清空
              </van-button>
            </div>
          </div>
        </section>
        <section class="md3-tonal log-md3-body">
          <pre class="log">{{ store.logText }}</pre>
        </section>
      </template>

      <!-- MIUIX -->
      <template v-else-if="theme.themePack === 'miuix'">
        <div class="miuix-label">日志</div>
        <section class="miuix-card log-miuix-meta">
          <div class="miuix-pref-static">
            <span>最近行数</span>
            <b>{{ store.logLines }}</b>
          </div>
          <div class="miuix-pref-static">
            <span>文件大小</span>
            <b>{{ store.logSize }}</b>
          </div>
          <div class="miuix-actions">
            <button type="button" class="miuix-btn" @click="onButtonRefresh">刷新</button>
            <button type="button" class="miuix-btn danger" @click="onClear">清空</button>
          </div>
        </section>
        <div class="miuix-label">内容</div>
        <section class="miuix-card log-miuix-body">
          <pre class="log">{{ store.logText }}</pre>
        </section>
      </template>

      <!-- 默认 -->
      <template v-else>
        <div class="section-head">
          <p class="title">运行日志</p>
          <p class="hint">模块触发停充 / 恢复时写入</p>
        </div>
        <section class="card meta">
          <div class="row">
            <span>最近 {{ store.logLines }} 行</span>
            <span>{{ store.logSize }}</span>
          </div>
          <div class="actions">
            <van-button size="small" type="primary" plain @click="onButtonRefresh">
              刷新
            </van-button>
            <van-button size="small" type="danger" plain @click="onClear">
              清空
            </van-button>
          </div>
        </section>
        <section class="card log-card">
          <pre class="log">{{ store.logText }}</pre>
        </section>
      </template>
    </div>
  </van-pull-refresh>
</template>

<style scoped lang="scss">
.page {
  min-height: calc(100dvh - 56px - var(--qsc-inset-top, 0px) - var(--dock-pad, 72px));
}

.meta {
  padding: 14px 16px;
  margin-bottom: 12px;
}

.row {
  display: flex;
  justify-content: space-between;
  font-size: 13px;
  color: var(--qsc-text-2);
  margin-bottom: 12px;
}

.actions {
  display: flex;
  gap: 8px;
}

.log-card {
  padding: 14px;
  background: var(--qsc-surface-2);
}

.log {
  margin: 0;
  white-space: pre-wrap;
  word-break: break-all;
  font-size: 12px;
  line-height: 1.55;
  color: var(--qsc-text);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  min-height: 42vh;
}

.log-md3-meta {
  padding: 16px 18px;
  margin-bottom: 12px;
}

.log-md3-meta__row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.log-md3-meta__title {
  font-size: 17px;
  font-weight: 600;
}

.log-md3-meta__sub {
  margin-top: 4px;
  font-size: 12px;
  color: var(--qsc-text-2);
}

.log-md3-meta__actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

.log-md3-body {
  padding: 14px 16px;
}

.miuix-label {
  margin: 12px 10px 8px;
  font-size: 13px;
  font-weight: 600;
  color: var(--qsc-text-2);
}

.log-miuix-meta {
  margin-bottom: 0;
}

.miuix-pref-static {
  display: flex;
  justify-content: space-between;
  padding: 13px 14px;
  font-size: 15px;
  border-bottom: 1px solid var(--qsc-hairline);

  b {
    font-weight: 550;
    color: var(--qsc-text-2);
  }
}

.miuix-actions {
  display: flex;
  gap: 10px;
  padding: 12px 14px;
}

.miuix-btn {
  flex: 1;
  border: none;
  border-radius: 10px;
  padding: 10px 12px;
  font-size: 14px;
  font-weight: 550;
  background: var(--qsc-surface-2);
  color: var(--qsc-text);

  &.danger {
    color: var(--qsc-danger);
  }

  &:active {
    opacity: 0.85;
  }
}

.log-miuix-body {
  padding: 12px;
}
</style>
