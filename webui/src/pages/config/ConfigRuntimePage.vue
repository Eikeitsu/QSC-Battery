<script setup lang="ts">
import { provideConfigForm, useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";
import SectionHead from "@/shared/ui/SectionHead.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import ConfigBlock from "./ui/ConfigBlock.vue";

const AdvancedRuntimeCard = lazyComponent(() => import("./ui/AdvancedRuntimeCard.vue"));
const AdvancedBlock = lazyComponent(() => import("./ui/current/AdvancedBlock.vue"));

const { packClass } = useThemePackClass();
const form = provideConfigForm();
</script>

<template>
  <div class="page" :class="packClass">
    <AdvancedRuntimeCard />
    <template v-if="form.store.currentFeature">
      <SectionHead title="电流高级" hint="重断言、漂移步进与 sysfs 路径" />
      <ThemedCard>
        <ConfigBlock>
          <AdvancedBlock />
        </ConfigBlock>
      </ThemedCard>
    </template>
  </div>
</template>
