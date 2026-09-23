<script setup lang="ts">
import * as api from "@/shared/api";
import { versionLine, type ChannelCheckResult } from "@/shared";

defineProps<{
  result: ChannelCheckResult;
  daemonTitle: string;
  actionBusy: "" | "module" | "app" | "daemon";
  actionError: string;
}>();

const emit = defineEmits<{
  updateModule: [];
  updateApp: [];
  updateDaemon: [];
}>();
</script>

<template>
  <div class="result">
    <div class="item">
      <div class="item-top">
        <span class="name">模块</span>
        <span
          class="chip"
          :data-tone="
            !result.module
              ? 'warn'
              : result.moduleHasUpdate || result.moduleCanSwitch
                ? 'update'
                : 'ok'
          "
        >
          {{
            !result.module
              ? "无数据"
              : result.moduleHasUpdate
                ? "可更新"
                : result.moduleCanSwitch
                  ? "可切换"
                  : "最新"
          }}
        </span>
        <button
          v-if="result.module?.changelog"
          type="button"
          class="link"
          @click="api.openUrl(result.module.changelog!)"
        >
          说明
        </button>
        <button
          v-if="
            result.module?.zipUrl && (result.moduleHasUpdate || result.moduleCanSwitch)
          "
          type="button"
          class="action"
          :disabled="!!actionBusy"
          :aria-busy="actionBusy === 'module'"
          @click="emit('updateModule')"
        >
          <span v-if="actionBusy === 'module'" class="action-spin" aria-hidden="true" />
          <span>{{
            result.moduleCanSwitch && !result.moduleHasUpdate ? "切换" : "更新"
          }}</span>
        </button>
      </div>
      <p class="ver">
        {{ versionLine(result.moduleLocalVersion, result.module?.version) }}
      </p>
    </div>

    <div class="item">
      <div class="item-top">
        <span class="name">APP</span>
        <span
          class="chip"
          :data-tone="
            !result.app
              ? 'warn'
              : result.appHasUpdate || result.appCanSwitch
                ? 'update'
                : 'ok'
          "
        >
          {{
            !result.app
              ? "无数据"
              : result.appMissing
                ? "未安装"
                : result.appHasUpdate
                  ? "可更新"
                  : result.appCanSwitch
                    ? "可切换"
                    : "最新"
          }}
        </span>
        <button
          v-if="result.app?.changelog"
          type="button"
          class="link"
          @click="api.openUrl(result.app.changelog!)"
        >
          说明
        </button>
        <button
          v-if="result.app?.apkUrl && (result.appHasUpdate || result.appCanSwitch)"
          type="button"
          class="action"
          :disabled="!!actionBusy"
          :aria-busy="actionBusy === 'app'"
          @click="emit('updateApp')"
        >
          <span v-if="actionBusy === 'app'" class="action-spin" aria-hidden="true" />
          <span>{{
            result.appMissing
              ? "安装"
              : result.appCanSwitch && !result.appHasUpdate
                ? "切换"
                : "更新"
          }}</span>
        </button>
      </div>
      <p class="ver">
        {{
          versionLine(
            result.appMissing ? "" : result.appLocalVersion,
            result.app?.version,
          )
        }}
      </p>
    </div>

    <div class="item">
      <div class="item-top">
        <span class="name">{{ daemonTitle }}</span>
        <span
          class="chip"
          :data-tone="
            !result.daemon
              ? 'warn'
              : result.daemonHasUpdate || result.daemonCanSwitch
                ? 'update'
                : 'ok'
          "
        >
          {{
            !result.daemon
              ? "无数据"
              : result.daemonMissing
                ? "未安装"
                : result.daemonHasUpdate
                  ? "可更新"
                  : result.daemonCanSwitch
                    ? "可切换"
                    : "最新"
          }}
        </span>
        <button
          v-if="result.daemonHasUpdate || result.daemonCanSwitch"
          type="button"
          class="action"
          :disabled="!!actionBusy"
          :aria-busy="actionBusy === 'daemon'"
          @click="emit('updateDaemon')"
        >
          <span v-if="actionBusy === 'daemon'" class="action-spin" aria-hidden="true" />
          <span>{{
            result.daemonMissing
              ? "安装"
              : result.daemonCanSwitch && !result.daemonHasUpdate
                ? "切换"
                : "更新"
          }}</span>
        </button>
      </div>
      <p class="ver">
        {{ versionLine(result.daemonLocalVersion, result.daemon?.version) }}
      </p>
      <p v-if="actionError" class="row-err">{{ actionError }}</p>
    </div>

    <p v-if="result.error" class="err">{{ result.error }}</p>
  </div>
</template>

<style scoped lang="scss">
@use "./update-channel";
</style>
