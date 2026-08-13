<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import { PATHS } from "@/shared";
</script>

<template>
  <SectionHead title="使用说明" hint="路径与常见用法" />
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
</template>

<style scoped lang="scss">
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
</style>
