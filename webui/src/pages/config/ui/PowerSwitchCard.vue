<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { useConfigFormContext } from "@/composables";

const { powerSwitchText, savePowerSwitches } = useConfigFormContext();
</script>

<template>
  <SectionHead title="自定义供电开关" hint="自动扫描无效时可按下列格式填写，每行一个" />
  <ThemedCard>
    <van-field
      v-model="powerSwitchText"
      type="textarea"
      rows="5"
      autosize
      label=""
      placeholder="/sys/.../node start=1 stop=0"
      @blur="savePowerSwitches"
    />
    <p class="field-hint pad-x">
      格式：路径 start=开值 stop=关值。空格可用
      ::。保存后优先于全量扫描；留空则仅用自动探测。
    </p>
  </ThemedCard>
</template>

<style scoped lang="scss">
.field-hint {
  margin: 4px 0 8px;
  font-size: 12px;
  color: var(--qsc-text-3);
  line-height: 1.4;
}

.pad-x {
  padding: 0 var(--qsc-cell-pad-x, 16px) 12px;
}
</style>
