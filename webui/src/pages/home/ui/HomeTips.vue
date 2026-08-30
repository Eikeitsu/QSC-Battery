<script setup lang="ts">
withDefaults(
  defineProps<{
    variant?: "default" | "md3" | "miuix";
  }>(),
  {
    variant: "default",
  },
);
</script>

<template>
  <section class="home-tips" :class="`home-tips--${variant}`">
    <p><b>过夜</b>：停止 80–90%，恢复间隔 5–10%。</p>
    <p v-if="variant !== 'miuix'"><b>游戏 / 导航</b>：开启温控，高温自动停充。</p>
    <p v-else>游戏导航请开温控，高温自动停充。</p>
  </section>
</template>

<style scoped lang="scss">
.home-tips {
  color: var(--qsc-text-2);

  p {
    margin: 0 0 8px;

    &:last-child {
      margin-bottom: 0;
    }
  }
}

.home-tips--default {
  margin-top: 14px;
  padding: 14px 16px;
  font-size: 13px;
  line-height: 1.55;
  background: var(--qsc-surface-2);
  border-radius: var(--qsc-card-radius, 14px);
}

.home-tips--md3 {
  padding: 14px 16px;
  font-size: 13px;
  line-height: 1.5;
  background: var(--qsc-surface);
  border-radius: var(--qsc-card-radius, 14px);
  border: 1px solid var(--qsc-hairline);
}

.home-tips--miuix {
  margin-top: 12px;
  padding: 12px 14px;
  font-size: 12px;
  line-height: 1.45;
  background: var(--qsc-surface);
  border-radius: var(--qsc-card-radius, 14px);
  border: 1px solid var(--qsc-hairline);

  p {
    margin-bottom: 0;
  }
}
</style>
