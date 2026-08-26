<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { ABOUT_NAV_LINKS } from "@/shared";
import { useAboutActions } from "../composables/useAboutActions";

const { tipOpen, open, tipAuthor } = useAboutActions();
const base = import.meta.env.BASE_URL;
</script>

<template>
  <SectionHead title="链接与打赏" hint="文档、仓库与支持原作者" />
  <ThemedCard>
    <van-cell
      v-for="item in ABOUT_NAV_LINKS"
      :key="item.url"
      :title="item.title"
      :label="item.label"
      is-link
      @click="open(item.url)"
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
  </ThemedCard>
</template>

<style scoped lang="scss">
.tip-box {
  display: flex;
  justify-content: center;
  padding: 4px var(--qsc-cell-pad-x, 16px) 16px;
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
