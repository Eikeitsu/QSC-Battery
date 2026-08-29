<script setup lang="ts">
import { useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";

const AppearanceCard = lazyComponent(() => import("./ui/AppearanceCard.vue"));
const ProfilesCard = lazyComponent(() => import("./ui/ProfilesCard.vue"));
const CommunityShareCard = lazyComponent(() => import("./ui/CommunityShareCard.vue"));
const ShortcutsCard = lazyComponent(() => import("./ui/ShortcutsCard.vue"));
const GuideCard = lazyComponent(() => import("./ui/GuideCard.vue"));
const AboutBrand = lazyComponent(() => import("./ui/AboutBrand.vue"));
const AboutLinks = lazyComponent(() => import("./ui/AboutLinks.vue"));
const CreditsCard = lazyComponent(() => import("./ui/CreditsCard.vue"));

const { packClass } = useThemePackClass();
</script>

<template>
  <div class="page" :class="packClass">
    <AppearanceCard />
    <ProfilesCard />
    <CommunityShareCard />
    <ShortcutsCard />
    <GuideCard />
    <AboutBrand />
    <AboutLinks />
    <CreditsCard />
  </div>
</template>
