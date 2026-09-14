<script setup lang="ts">
import { useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const AboutBrand = lazyComponent(() => import("./ui/AboutBrand.vue"));
const AboutLinks = lazyComponent(() => import("./ui/AboutLinks.vue"));
const CreditsCard = lazyComponent(() => import("./ui/CreditsCard.vue"));

const { packClass } = useThemePackClass();
</script>

<template>
  <div class="page" :class="packClass">
    <AboutBrand />
    <AboutLinks />
    <CreditsCard />
  </div>
</template>
