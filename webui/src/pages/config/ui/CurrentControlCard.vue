<script setup lang="ts">
import AppPicker from "@/features/app-picker/AppPicker.vue";
import SectionHead from "@/shared/ui/SectionHead.vue";
import SwitchCell from "@/shared/ui/SwitchCell.vue";
import ThemedCard from "@/shared/ui/ThemedCard.vue";
import { BinaryFlag } from "@/shared";
import { useConfigFormContext } from "@/composables";
import ConfigBlock from "./ConfigBlock.vue";
import BypassBlock from "./current/BypassBlock.vue";
import SlowChargeBlock from "./current/SlowChargeBlock.vue";
import TempCurrentBlock from "./current/TempCurrentBlock.vue";
import AppLimitBlock from "./current/AppLimitBlock.vue";

const { store, currentOpen, showApps, onCurrentSwitch, onAppsSaved } =
  useConfigFormContext();
</script>

<template>
  <template v-if="store.currentFeature">
    <SectionHead title="电流控制" hint="旁路、慢充与游戏限流（可选安装）" />
    <ThemedCard>
      <SwitchCell
        title="电流控制总开关"
        :label="store.currentPlan"
        :model-value="!!Number(store.current.current_control)"
        @update:model-value="(v) => onCurrentSwitch('current_control', v)"
      />
      <Transition name="cfg-reveal">
        <van-collapse v-if="Number(store.current.current_control)" v-model="currentOpen">
          <van-collapse-item :name="BinaryFlag.On" title="旁路 / 慢充 / 限流">
            <ConfigBlock nested>
              <BypassBlock />
              <SlowChargeBlock />
              <TempCurrentBlock />
              <AppLimitBlock />
            </ConfigBlock>
          </van-collapse-item>
        </van-collapse>
      </Transition>
    </ThemedCard>

    <AppPicker
      v-model:show="showApps"
      v-model="store.current.app_list"
      @saved="onAppsSaved"
    />
  </template>
</template>
