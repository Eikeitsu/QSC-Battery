<script setup lang="ts">
import { computed } from "vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import { APP, ThemeMode, ThemePack } from "@/shared";
import { useAppStore, useTheme } from "@/stores";

const store = useAppStore();
const theme = useTheme();
const base = import.meta.env.BASE_URL;

const brandMark = computed(() =>
  theme.resolved === ThemeMode.Dark
    ? `${base}img/icon-mark.png`
    : `${base}img/icon-mark-light.png`,
);
</script>

<template>
  <SectionHead title="关于" />

  <template v-if="theme.themePack === ThemePack.Md3">
    <section class="md3-tonal about-md3">
      <img class="about-mark" :src="brandMark" alt="" width="80" height="80" />
      <div class="name">{{ APP.name }}</div>
      <div class="sub">{{ APP.id }} · {{ store.status.version }}</div>
      <p class="about-note-inline">
        基于 top大佬 QSC 定量停充，补充 WebUI 与可选电流控制。
      </p>
    </section>
  </template>

  <template v-else-if="theme.themePack === ThemePack.Miuix">
    <section class="miuix-card about-brand">
      <img class="about-mark" :src="brandMark" alt="" width="72" height="72" />
      <div class="about-text">
        <div class="name">{{ APP.name }}</div>
        <div class="sub">{{ APP.id }}</div>
        <div class="ver">{{ store.status.version }}</div>
      </div>
    </section>
    <p class="about-note">
      本模块基于 <b>top大佬</b> 的 QSC 定量停充，补充了 WebUI
      与可选电流控制，感谢原作者开源贡献。
    </p>
  </template>

  <template v-else>
    <section class="card about-brand">
      <img class="about-mark" :src="brandMark" alt="" width="72" height="72" />
      <div class="about-text">
        <div class="name">{{ APP.name }}</div>
        <div class="sub">{{ APP.id }}</div>
        <div class="ver">{{ store.status.version }}</div>
      </div>
    </section>
    <p class="about-note">
      本模块基于 <b>top大佬</b> 的 QSC 定量停充，补充了 WebUI
      与可选电流控制，感谢原作者开源贡献。
    </p>
  </template>
</template>

<style scoped lang="scss">
.about-brand {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 16px;
  margin-bottom: 10px;
}

.about-md3 {
  padding: 28px 20px 22px;
  text-align: center;
  margin-bottom: 12px;

  .about-mark {
    margin: 0 auto 12px;
  }

  .name {
    font-size: 20px;
    font-weight: 650;
  }

  .sub {
    margin-top: 4px;
    font-size: 13px;
    color: var(--qsc-text-2);
  }

  .about-note-inline {
    margin: 14px auto 0;
    max-width: 28em;
    font-size: 12px;
    color: var(--qsc-text-2);
    line-height: 1.5;
  }
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
</style>
