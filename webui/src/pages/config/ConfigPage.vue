<script setup lang="ts">
import { provideConfigForm, useThemePackClass } from "@/composables";
import { lazyComponent } from "@/shared/lib/lazyComponent";
import HubNavCard from "@/shared/ui/HubNavCard.vue";
import { SubRouteName } from "@/shared";

const PowerStopCard = lazyComponent(() => import("./ui/PowerStopCard.vue"));
const StopBehaviorCard = lazyComponent(() => import("./ui/StopBehaviorCard.vue"));
const TempStopCard = lazyComponent(() => import("./ui/TempStopCard.vue"));
const CurrentControlCard = lazyComponent(() => import("./ui/CurrentControlCard.vue"));

const { packClass } = useThemePackClass();
provideConfigForm();

const navItems = [
  {
    name: SubRouteName.ConfigSwitches,
    title: "供电开关与排障",
    label: "首选 / 自定义开关 / 测开关与缓存",
  },
  {
    name: SubRouteName.ConfigRuntime,
    title: "运行与采样",
    label: "省电间隔、图表、电流高级路径、冷门选项",
  },
  {
    name: SubRouteName.ConfigDaemon,
    title: "事件唤醒守护",
    label: "Rust / C 守护安装与更新",
  },
];
</script>

<template>
  <div class="page" :class="packClass">
    <PowerStopCard />
    <TempStopCard />
    <StopBehaviorCard />
    <CurrentControlCard />
    <HubNavCard title="更多策略" hint="不常用项已移到子页" :items="navItems" />
  </div>
</template>
