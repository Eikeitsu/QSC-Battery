<script setup lang="ts">
import { APP, ThemePack } from "@/shared";
import { useAppStore, useTheme } from "@/stores";

const store = useAppStore();
const theme = useTheme();
const base = import.meta.env.BASE_URL;
</script>

<template>
  <header v-if="theme.themePack === ThemePack.Md3" class="app-topbar topbar-md3">
    <div class="md3-top">
      <p class="md3-eyebrow">{{ store.deviceName || "本机" }}</p>
      <h1>{{ APP.name }}</h1>
    </div>
  </header>

  <header v-else-if="theme.themePack === ThemePack.Miuix" class="app-topbar topbar-miuix">
    <div class="titles">
      <h1>{{ APP.name }}</h1>
      <p>{{ store.deviceName }}</p>
    </div>
  </header>

  <header v-else class="app-topbar topbar-default">
    <img class="logo" :src="`${base}img/icon.png`" width="36" height="36" alt="" />
    <div class="titles">
      <h1>{{ APP.name }}</h1>
      <p>{{ store.deviceName }}</p>
    </div>
  </header>
</template>

<style scoped lang="scss">
.logo {
  border-radius: 10px;
  flex-shrink: 0;
}

.titles {
  min-width: 0;
}

.titles h1 {
  margin: 0;
  font-size: 17px;
  font-weight: 760;
  line-height: 1.2;
  letter-spacing: -0.02em;
}

.titles p {
  margin: 3px 0 0;
  font-size: 12px;
  color: var(--qsc-text-3);
  max-width: 70vw;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.topbar-md3 {
  flex-direction: column;
  align-items: stretch;
  justify-content: flex-end;
  min-height: calc(72px + var(--qsc-inset-top, 0px));
  padding-bottom: 12px;
}

.md3-top {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.md3-eyebrow {
  margin: 0;
  font-size: 12px;
  line-height: 1.35;
  color: var(--qsc-text-3);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.topbar-md3 h1 {
  margin: 0;
  font-size: 28px;
  font-weight: 650;
  letter-spacing: -0.4px;
  line-height: 1.2;
}

.topbar-miuix {
  min-height: calc(48px + var(--qsc-inset-top, 0px));
  padding-bottom: 6px;
}

.topbar-miuix .titles h1 {
  font-size: 18px;
  font-weight: 700;
}

.topbar-default .logo {
  border-radius: 12px;
  box-shadow: 0 1px 4px rgba(15, 18, 22, 0.1);
}

.topbar-default .titles h1 {
  font-size: 17px;
  font-weight: 700;
  letter-spacing: -0.01em;
}
</style>
