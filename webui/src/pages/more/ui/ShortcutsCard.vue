<script setup lang="ts">
import { ref } from "vue";
import { showSuccessToast, showToast } from "vant";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { PATHS } from "@/shared";

const openScript = `${PATHS.MODDIR}/打开充电控制.sh`;
const closeScript = `${PATHS.MODDIR}/关闭充电控制.sh`;
const open = ref<string[]>([]);

async function copy(text: string) {
  try {
    await navigator.clipboard.writeText(text);
    showSuccessToast("已复制路径");
  } catch {
    showToast("复制失败，请手动长按选择");
  }
}
</script>

<template>
  <SectionHead title="快捷开关" hint="自动化 / 第三方磁贴用，日常可忽略" />
  <ThemedCard>
    <van-collapse v-model="open" accordion>
      <van-collapse-item name="paths" title="脚本路径（点按复制）">
        <van-cell
          title="打开充电控制"
          :label="openScript"
          is-link
          @click="copy(openScript)"
        />
        <van-cell
          title="关闭充电控制"
          :label="closeScript"
          is-link
          @click="copy(closeScript)"
        />
        <p class="hint">
          模块无法注册系统磁贴。路径填入 Tasker / Anywhere 等即可；多数用户用 WebUI
          开关即可。
        </p>
      </van-collapse-item>
    </van-collapse>
  </ThemedCard>
</template>

<style scoped lang="scss">
.hint {
  margin: 0;
  padding: 10px var(--qsc-cell-pad-x, 16px) 14px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.45;
}

:deep(.van-collapse-item__content) {
  padding: 0;
}
</style>
