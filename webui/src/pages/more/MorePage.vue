<script setup lang="ts">
import { useThemePackClass } from "@/composables";
import AppearanceCard from "./ui/AppearanceCard.vue";
import ProfilesCard from "./ui/ProfilesCard.vue";
import CommunityShareCard from "./ui/CommunityShareCard.vue";
import ShortcutsCard from "./ui/ShortcutsCard.vue";
import GuideCard from "./ui/GuideCard.vue";
import AboutBrand from "./ui/AboutBrand.vue";
import AboutLinks from "./ui/AboutLinks.vue";
import CreditsCard from "./ui/CreditsCard.vue";

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
