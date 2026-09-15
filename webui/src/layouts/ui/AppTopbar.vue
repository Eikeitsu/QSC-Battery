<script setup lang="ts">
import { APP, ThemePack } from "@/shared";
import { useAppStore, useTheme } from "@/stores";

defineProps<{
  subPage?: boolean;
  pageTitle?: string;
}>();

defineEmits<{
  back: [];
}>();

const store = useAppStore();
const theme = useTheme();
const base = import.meta.env.BASE_URL;
</script>

<template>
  <header
    v-if="theme.themePack === ThemePack.Md3"
    class="app-topbar topbar-md3"
    :class="{ 'is-sub': subPage }"
  >
    <button
      v-if="subPage"
      type="button"
      class="back"
      aria-label="返回"
      @click="$emit('back')"
    >
      <svg class="back-ico" viewBox="0 0 24 24" aria-hidden="true">
        <path
          d="M15.5 5.5 9 12l6.5 6.5"
          fill="none"
          stroke="currentColor"
          stroke-width="2.2"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
    </button>
    <div class="md3-top">
      <p v-if="!subPage" class="md3-eyebrow">{{ store.deviceName || "本机" }}</p>
      <h1>{{ subPage ? pageTitle || APP.name : APP.name }}</h1>
    </div>
  </header>

  <header
    v-else-if="theme.themePack === ThemePack.Miuix"
    class="app-topbar topbar-miuix"
    :class="{ 'is-sub': subPage }"
  >
    <button
      v-if="subPage"
      type="button"
      class="back"
      aria-label="返回"
      @click="$emit('back')"
    >
      <svg class="back-ico" viewBox="0 0 24 24" aria-hidden="true">
        <path
          d="M15.5 5.5 9 12l6.5 6.5"
          fill="none"
          stroke="currentColor"
          stroke-width="2.2"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
    </button>
    <div class="titles">
      <h1>{{ subPage ? pageTitle || APP.name : APP.name }}</h1>
      <p v-if="!subPage">{{ store.deviceName }}</p>
    </div>
  </header>

  <header v-else class="app-topbar topbar-default" :class="{ 'is-sub': subPage }">
    <button
      v-if="subPage"
      type="button"
      class="back"
      aria-label="返回"
      @click="$emit('back')"
    >
      <svg class="back-ico" viewBox="0 0 24 24" aria-hidden="true">
        <path
          d="M15.5 5.5 9 12l6.5 6.5"
          fill="none"
          stroke="currentColor"
          stroke-width="2.2"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
    </button>
    <img v-else class="logo" :src="`${base}img/icon.png`" width="36" height="36" alt="" />
    <div class="titles">
      <h1>{{ subPage ? pageTitle || APP.name : APP.name }}</h1>
      <p v-if="!subPage">{{ store.deviceName }}</p>
    </div>
  </header>
</template>

<style scoped lang="scss">
.back {
  flex-shrink: 0;
  box-sizing: border-box;
  width: 40px;
  height: 40px;
  margin: 0 0 0 -10px;
  padding: 0;
  border: 0;
  border-radius: 12px;
  background: transparent;
  color: var(--qsc-text);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s ease;
}

.back:active {
  background: color-mix(in srgb, var(--qsc-text) 8%, transparent);
}

.back-ico {
  width: 22px;
  height: 22px;
  display: block;
}

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

.topbar-md3.is-sub {
  flex-direction: row;
  align-items: center;
  gap: 2px;
  padding-bottom: 10px;
}

.topbar-md3.is-sub .back {
  margin-left: -8px;
  border-radius: 999px;
}

.topbar-md3.is-sub .md3-top {
  width: auto;
  flex: 1;
  min-width: 0;
}

.md3-top {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
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

.topbar-md3.is-sub h1 {
  font-size: 20px;
  font-weight: 650;
  letter-spacing: -0.3px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.topbar-miuix {
  min-height: calc(48px + var(--qsc-inset-top, 0px));
  padding-bottom: 6px;
}

.topbar-miuix.is-sub,
.topbar-default.is-sub {
  align-items: center;
  gap: 2px;
}

.topbar-miuix.is-sub .back {
  width: 36px;
  height: 36px;
  margin-left: -8px;
  border-radius: 10px;
}

.topbar-miuix.is-sub .back-ico {
  width: 20px;
  height: 20px;
}

.topbar-miuix .titles h1 {
  font-size: 18px;
  font-weight: 700;
}

.topbar-default.is-sub .back {
  margin-left: -8px;
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
