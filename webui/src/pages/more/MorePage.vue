<script setup lang="ts">
import { useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";
import HubNavCard from "@/shared/ui/HubNavCard.vue";
import { SubRouteName } from "@/shared";

const AppearanceCard = lazyComponent(() => import("./ui/AppearanceCard.vue"));
const ProfilesCard = lazyComponent(() => import("./ui/ProfilesCard.vue"));
const UpdateChannelCard = lazyComponent(() => import("./ui/UpdateChannelCard.vue"));

const { packClass } = useThemePackClass();

const navItems = [
  {
    name: SubRouteName.MoreDevice,
    title: "机型与社区",
    label: "节点分享、仓库预制档、多设备档案库",
  },
  {
    name: SubRouteName.MoreTools,
    title: "快捷入口与说明",
    label: "脚本路径、使用说明",
  },
  {
    name: SubRouteName.MoreAbout,
    title: "关于",
    label: "版本、链接与致谢",
  },
];
</script>

<template>
  <div class="page" :class="packClass">
    <AppearanceCard />
    <UpdateChannelCard />
    <ProfilesCard />
    <HubNavCard title="更多" hint="机型、工具与关于" :items="navItems" />
  </div>
</template>
