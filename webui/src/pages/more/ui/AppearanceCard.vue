<script setup lang="ts">
import ChipGroup from "@/shared/ui/ChipGroup.vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import {
  MD3_SEED_PRESETS,
  PACK_PRESETS,
  THEME_DEFAULTS,
  THEME_MODE_PRESETS,
  ThemeMode,
  ThemePack,
} from "@/shared";
import { useAppearanceForm } from "../composables/useAppearanceForm";
import Md3SeedPanel from "./Md3SeedPanel.vue";

const {
  theme,
  packLabel,
  fontDraft,
  md3ChipValue,
  md3CustomSeed,
  seedInput,
  seedHexDraft,
  onMd3Chip,
  openSeedPicker,
  onSeedInput,
  onSeedHexCommit,
  onFontDrag,
  onFontCommit,
} = useAppearanceForm();
</script>

<template>
  <SectionHead title="显示" hint="主题包切换控件形态；进阶项请开启自定义" />
  <ThemedCard>
    <van-cell title="主题包" :label="packLabel" />
    <div class="pad">
      <ChipGroup
        :options="PACK_PRESETS"
        :model-value="theme.themePack"
        @update:model-value="(id) => theme.setThemePack(id)"
      />
    </div>
    <van-cell
      title="深浅模式"
      :label="
        theme.themeMode === ThemeMode.System
          ? `跟随系统（当前${theme.resolved === ThemeMode.Dark ? '深色' : '浅色'}）`
          : ''
      "
    />
    <div class="pad">
      <ChipGroup
        :options="THEME_MODE_PRESETS"
        :model-value="theme.themeMode"
        @update:model-value="(id) => theme.setThemeMode(id)"
      />
    </div>

    <SwitchCell
      title="自定义外观"
      label="开启后显示颜色与底栏等进阶项"
      :model-value="theme.uiCustom"
      @update:model-value="(v) => theme.setUiCustom(v)"
    />

    <template v-if="theme.uiCustom && theme.themePack === ThemePack.Default">
      <van-cell title="颜色主题" label="默认色板，不跟随莫奈" />
      <div class="pad">
        <ChipGroup
          :options="theme.accentOptions"
          :model-value="theme.accentId"
          @update:model-value="(id) => theme.setAccent(id)"
        />
      </div>
    </template>

    <template v-if="theme.uiCustom && theme.themePack === ThemePack.Md3">
      <van-cell title="MD3 色值" :label="theme.md3Seed" />
      <div class="pad">
        <ChipGroup
          :options="MD3_SEED_PRESETS"
          :model-value="md3ChipValue"
          @update:model-value="onMd3Chip"
        />
      </div>
      <Md3SeedPanel
        v-if="md3CustomSeed"
        :seed="theme.md3Seed"
        :seed-hex="seedHexDraft"
        @update:seed-hex="seedHexDraft = $event"
        @pick="openSeedPicker"
        @commit="onSeedHexCommit"
      />
      <input
        v-if="md3CustomSeed"
        ref="seedInput"
        class="seed-input-hidden"
        type="color"
        :value="theme.md3Seed"
        @input="onSeedInput"
        @change="onSeedInput"
      />
    </template>

    <template v-if="theme.uiCustom && theme.themePack === ThemePack.Miuix">
      <SwitchCell
        title="莫奈取色"
        label="跟随系统壁纸色"
        :model-value="theme.monetOn"
        @update:model-value="(v) => theme.setMonet(v)"
      />
      <SwitchCell
        title="悬浮底栏"
        label="底栏浮于内容之上"
        :model-value="theme.floatDock"
        @update:model-value="(v) => theme.setFloatDock(v)"
      />
      <SwitchCell
        v-if="theme.floatDock"
        title="液态玻璃"
        label="底栏毛玻璃高亮"
        :model-value="theme.dockGlass"
        @update:model-value="(v) => theme.setDockGlass(v)"
      />
      <SwitchCell
        title="栏位模糊"
        label="顶栏与底栏磨砂"
        :model-value="theme.barBlur"
        @update:model-value="(v) => theme.setBarBlur(v)"
      />
    </template>

    <SwitchCell
      title="紧凑显示"
      label="卡片间距更紧"
      :model-value="theme.compactOn"
      @update:model-value="(v) => theme.setCompact(v)"
    />
    <van-cell title="字体大小" :value="`${Math.round(fontDraft * 100)}%`" />
    <div class="pad slider">
      <van-slider
        :model-value="fontDraft"
        :min="THEME_DEFAULTS.fontMin"
        :max="THEME_DEFAULTS.fontMax"
        :step="THEME_DEFAULTS.fontStep"
        @update:model-value="onFontDrag"
        @change="onFontCommit"
      />
    </div>
  </ThemedCard>
</template>

<style scoped lang="scss">
.pad {
  padding: 0 16px 10px;
}

.slider {
  padding-bottom: 18px;
}

.seed-input-hidden {
  position: fixed;
  left: -9999px;
  top: 0;
  width: 40px;
  height: 40px;
  opacity: 0;
}
</style>
