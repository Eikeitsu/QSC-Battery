<script setup lang="ts">
import { useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const CommunityShareCard = lazyComponent(() => import("./ui/CommunityShareCard.vue"));
const DeviceArchiveCard = lazyComponent(() => import("./ui/DeviceArchiveCard.vue"));

const { packClass } = useThemePackClass();
</script>

<template>
  <div class="page" :class="packClass">
    <CommunityShareCard />
    <DeviceArchiveCard />
  </div>
</template>
