#!/usr/bin/env node
/**
 * 热更新安全契约测试。
 *
 * 这组门禁不依赖 Android 或 POSIX shell，专门防止以后重构时误删：
 * 1. 外部完整副本；
 * 2. 复制后的关键文件校验；
 * 3. 失败时保留标准重启更新；
 * 4. 成功与卸载时的临时资源清理。
 */
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const modules = [
  {
    name: "QSC-Battery",
    hot: join(root, "module/bin/lib/hot_update.sh"),
    hotinstall: join(root, "module/hotinstall.sh"),
    service: join(root, "module/service.sh"),
    uninstall: join(root, "module/uninstall.sh"),
    payload: "/data/adb/.qsc_hot_update_payload",
    lock: "/data/adb/.QSC_Battery.hot_update.lock",
    worker: "/data/adb/.qsc_hot_update.sh",
    staged: "/data/adb/modules_update/QSC_Battery",
  },
];

function read(path) {
  return readFileSync(path, "utf8");
}

function requireText(text, pattern, label) {
  if (!text.includes(pattern)) {
    throw new Error(`${label}: missing ${JSON.stringify(pattern)}`);
  }
}

function requireOrder(text, first, second, label) {
  if (text.indexOf(first) >= text.indexOf(second)) {
    throw new Error(`${label}: ${first} must precede ${second}`);
  }
}

function simulateHotUpdateContract() {
  const root = mkdtempSync(join(tmpdir(), "qsc-release-contract-"));
  const oldDir = join(root, "modules/QSC-Battery");
  const pendingDir = join(root, "modules_update/QSC-Battery");
  const payloadDir = join(root, "payload/QSC-Battery");
  const required = ["module.prop", "service.sh", "bin/common.sh", "hotinstall.sh"];
  const writeTree = (dir, files) => {
    for (const [rel, text] of Object.entries(files)) {
      const path = join(dir, rel);
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, text);
    }
  };
  try {
    writeTree(oldDir, Object.fromEntries(required.map((file) => [file, "old"])));
    writeTree(payloadDir, Object.fromEntries(required.map((file) => [file, "new"])));
    writeFileSync(join(oldDir, "update"), "");
    cpSync(payloadDir, pendingDir, { recursive: true });
    cpSync(payloadDir, oldDir, { recursive: true, force: true });
    if (required.some((file) => readFileSync(join(oldDir, file), "utf8") !== "new")) {
      throw new Error("successful install did not replace every required file");
    }
    rmSync(pendingDir, { recursive: true, force: true });
    rmSync(join(oldDir, "update"), { force: true });
    rmSync(payloadDir, { recursive: true, force: true });
    if (
      existsSync(pendingDir) ||
      existsSync(join(oldDir, "update")) ||
      existsSync(payloadDir)
    ) {
      throw new Error("successful install left temporary release state");
    }

    writeTree(oldDir, Object.fromEntries(required.map((file) => [file, "old"])));
    writeTree(payloadDir, { "module.prop": "new" });
    writeFileSync(join(oldDir, "update"), "");
    if (required.some((file) => !existsSync(join(payloadDir, file)))) {
      if (!existsSync(join(oldDir, "update")))
        throw new Error("failed install lost update marker");
      if (readFileSync(join(oldDir, "module.prop"), "utf8") !== "old") {
        throw new Error("failed install modified active module");
      }
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

for (const mod of modules) {
  const hot = read(mod.hot);
  const hotinstall = read(mod.hotinstall);
  const service = read(mod.service);
  const uninstall = read(mod.uninstall);

  requireText(
    hotinstall,
    'setsid sh "$MODDIR/service.sh"',
    `${mod.name} detached service`,
  );
  requireText(
    hotinstall,
    'nohup sh "$MODDIR/service.sh"',
    `${mod.name} fallback service`,
  );
  requireText(hot, mod.payload, `${mod.name} external payload`);
  requireText(hot, `LOCK="/data/adb/.`, `${mod.name} lock`);
  requireText(hot, `echo "$$" >"$LOCK/pid"`, `${mod.name} lock owner`);
  requireText(hot, "hu_verify_file", `${mod.name} post-copy verification`);
  requireText(hot, "保留标准更新标记", `${mod.name} failure fallback`);
  requireText(hot, `rm -rf "$PAYLOAD"`, `${mod.name} payload cleanup`);
  requireText(hot, mod.worker, `${mod.name} worker cleanup`);
  requireOrder(
    hot,
    "hu_verify_file",
    'rm -f "$OLD/update"',
    `${mod.name} verification before marker cleanup`,
  );

  requireText(uninstall, mod.payload, `${mod.name} uninstall payload cleanup`);
  requireText(uninstall, mod.lock, `${mod.name} uninstall lock cleanup`);
  requireText(uninstall, mod.worker, `${mod.name} uninstall worker cleanup`);
  requireText(uninstall, mod.staged, `${mod.name} uninstall staged cleanup`);
  requireText(service, mod.lock, `${mod.name} service stale-lock cleanup`);
  requireText(service, "QSC_SCAN_LOCK", `${mod.name} scan lock`);
  requireText(service, "QSC_SCAN_STATE", `${mod.name} scan state`);
  requireText(service, "failed:$rc", `${mod.name} scan failure state`);
  requireText(service, "service_heartbeat", `${mod.name} service heartbeat`);
  requireText(service, "service_metrics", `${mod.name} service metrics`);
  requireText(service, "diagnostic_on", `${mod.name} optional diagnostic sampling`);
  requireText(service, "history_pending", `${mod.name} history pending metric`);
}

const update = JSON.parse(read(join(root, "docs/public/update.json")));
const manifest = JSON.parse(read(join(root, "docs/public/qscd/manifest.json")));
if (update.version !== manifest.version) {
  throw new Error(
    `update.json version ${update.version} != manifest ${manifest.version}`,
  );
}
for (const key of ["qscd-c-arm", "qscd-c-arm64", "qscd-rust-arm", "qscd-rust-arm64"]) {
  if (!/^[0-9a-f]{64}$/.test(manifest[key] || "")) {
    throw new Error(`manifest.json: invalid sha256 for ${key}`);
  }
}

const defaults = read(join(root, "webui/src/shared/config/defaults.ts"));
const configTemplate = read(join(root, "module/config/config.conf"));
const customize = read(join(root, "module/customize.sh"));
const qscdFetch = read(join(root, "module/bin/qscd_fetch.sh"));
const qscdSource = read(join(root, "native/qscd/src/main.rs"));
const powerSaver = read(join(root, "module/bin/lib/power_saver.sh"));
const status = read(join(root, "module/bin/lib/status.sh"));
const serviceSource = read(join(root, "module/service.sh"));
const daemonApi = read(join(root, "webui/src/shared/api/daemon.ts"));
const daemonCard = read(join(root, "webui/src/pages/config/ui/DaemonCard.vue"));
const batterySnapshotApi = read(join(root, "webui/src/shared/api/batterySnapshot.ts"));
const historyApi = read(join(root, "webui/src/shared/api/history.ts"));
const chart = read(join(root, "webui/src/pages/home/ui/HomeChargeChart.vue"));
const indexSource = read(join(root, "webui/index.html"));
const appSource = read(join(root, "webui/src/app/App.vue"));
const appShell = read(join(root, "webui/src/layouts/AppShell.vue"));
const appShellComposable = read(
  join(root, "webui/src/layouts/composables/useAppShell.ts"),
);
const appDock = read(join(root, "webui/src/layouts/ui/AppDock.vue"));
const routes = read(join(root, "webui/src/router/routes.ts"));
const batteryStore = read(join(root, "webui/src/stores/battery.ts"));
const installGuide = read(join(root, "docs/guide/install.md"));
const webuiGuide = read(join(root, "docs/guide/webui.md"));
const configGuide = read(join(root, "docs/guide/config.md"));
const keysBlock = defaults.match(/CONFIG_KEYS:[\s\S]*?\n\] as const;/)?.[0] || "";
const configKeys = [...keysBlock.matchAll(/^\s+"([^"]+)",$/gm)].map((match) => match[1]);
for (const key of configKeys) {
  const inTemplate = new RegExp(`^#?${key}=`, "m").test(configTemplate);
  const migrated = customize.includes(key);
  if (!inTemplate && !migrated) {
    throw new Error(`config.conf: missing default key ${key}`);
  }
}
const store = read(join(root, "webui/src/stores/battery.ts"));
requireText(
  store,
  "settings[key] = values[key] || DEFAULTS[key]",
  "config migration fallback",
);
requireText(qscdFetch, "qscd.new.$$", "native temporary candidate");
requireText(qscdFetch, 'mv -f "$_candidate" "$BINDIR/qscd"', "native atomic replacement");
requireText(qscdFetch, 'rm -rf "$TMPDIR"', "native temporary cleanup");
requireText(qscdFetch, "qscd_progress", "native download progress");
requireText(qscdFetch, "qscd_valid_version", "native version validation");
requireText(
  qscdFetch,
  "qscd_version_compare",
  "component-wise native version comparison",
);
requireText(qscdFetch, "manifest_invalid_sha256", "remote hash validation");
requireText(qscdFetch, "cmd_check", "remote native version check");
requireText(qscdFetch, "native_version", "local native version record");
requireText(qscdFetch, "remote_version", "remote native version output");
requireText(customize, "data/native_version", "upgrade native version preservation");
requireText(customize, "qscd_try_candidate", "candidate version recording");
const history = read(join(root, "module/bin/lib/history.sh"));
requireText(history, "QSC_HISTORY_BATCH", "batched history sampling");
requireText(history, "QSC_HISTORY_BUFFER", "history pending buffer");
requireText(history, "qsc_history_flush_pending", "history pending flush");
requireText(serviceSource, "qsc_history_flush_pending", "unplugged history flush");
requireText(status, "if ! mv -f", "description atomic write result");
requireText(powerSaver, 'QSC_PS_DESC_SIG=""', "description write retry");
requireText(powerSaver, "qsc_battery_snapshot_read", "status snapshot fallback");
requireText(historyApi, ".pending", "WebUI pending history read");
requireText(chart, "setInterval", "WebUI chart refresh timer");
requireText(chart, "当前 ${currentLevel}%", "WebUI live chart summary");
requireText(chart, "正在读取曲线数据", "WebUI chart loading state");
requireText(chart, "Promise.all", "WebUI parallel history loading");
requireText(chart, "mergeHistory", "WebUI unified history merge");
requireText(chart, 'dataSource.value === "merged"', "WebUI merged chart mode");
requireText(chart, "loadSystemBatteryHistory", "WebUI unplugged history source");
requireText(chart, "chartNow", "WebUI moving time axis");
requireText(chart, "onDeactivated", "WebUI inactive chart pause");
requireText(chart, "chartActive", "WebUI chart active lifecycle state");
requireText(historyApi, "RESET:TIME", "system history reset anchor");
requireText(historyApi, "count < 1200", "system history bounded tail");
requireText(appShell, "PageLoading", "WebUI page loading state");
requireText(appShell, "<Suspense", "WebUI async page fallback");
requireText(appShell, "route-loading-page", "WebUI route loading replacement");
requireText(appShell, ':aria-busy="store.initializing"', "WebUI non-blocking data state");
requireText(appShell, "正在读取设备信息", "WebUI device information loading text");
requireText(appShell, "position: fixed", "WebUI viewport route loading");
requireText(appShell, "<KeepAlive", "WebUI loaded page cache");
requireText(appShell, "display: none", "WebUI hidden route content leaves layout");
requireText(appSource, "<Suspense", "WebUI startup page fallback");
requireText(appSource, "router.isReady", "WebUI initial route readiness state");
requireText(appSource, "app-start-loading", "WebUI centered startup loading");
requireText(indexSource, "app-loading", "WebUI static startup loading state");
requireText(
  routes,
  'component: () => import("@/layouts/AppShell.vue")',
  "WebUI lazy root layout",
);
requireText(routes, "preloadTab", "WebUI route chunk preloading");
if (/<Transition/.test(appShell)) {
  throw new Error("WebUI route transition must not animate heavy pages");
}
requireText(appShell, "routeLoading", "WebUI immediate navigation feedback");
requireText(appShellComposable, "pendingTab", "WebUI single pending navigation state");
requireText(appShellComposable, "navigationId", "WebUI latest navigation wins");
requireText(appShellComposable, "drainNavigation", "WebUI serialized navigation queue");
requireText(appShellComposable, "scrollMainToTop", "WebUI navigation scroll reset");
requireText(appShellComposable, "requestIdleCallback", "WebUI idle route preloading");
requireText(appDock, ':model-value="tab"', "WebUI dock controlled by shell state");
requireText(
  batteryStore,
  "const initializing = ref(false)",
  "WebUI bootstrap loading state",
);
requireText(batteryStore, "refreshInFlight", "WebUI refresh single flight");
requireText(batteryStore, "duration: 1200", "WebUI bounded refresh toast");
requireText(batteryStore, "loadConfigValues(CONFIG_KEYS)", "batched config loading");
requireText(powerSaver, "QSC_PS_WAIT_FAILURES", "native wait failure backoff");
requireText(powerSaver, "reason=%s", "native wait failure reason");
requireText(powerSaver, "QSC_PS_WAIT_NEXT_RETRY", "native wait retry deadline");
requireText(powerSaver, "native_wait_reason", "native wait reason trace");
requireText(serviceSource, '>>"$DATADIR/debug.log"', "persistent debug log");
requireText(serviceSource, "service_start", "service start trace");
requireText(serviceSource, "qscd_unusable", "native wait failure state");
requireText(serviceSource, '"level":"%s"', "debug log severity");
requireText(serviceSource, '"category":"%s"', "debug log category");
requireText(serviceSource, "qscd 等待结果及错误原因", "Chinese debug explanation");
requireText(serviceSource, "switch_enter", "bounded decision round start");
requireText(serviceSource, "switch_exit", "bounded decision round result");
requireText(serviceSource, "qsc_ps_native_exec 45", "bounded decision round timeout");
requireText(
  serviceSource,
  "post_switch_description",
  "post-decision description refresh",
);
requireText(
  serviceSource,
  "qsc_description_refresh_worker",
  "independent description refresh worker",
);
requireText(
  serviceSource,
  "description_worker.pid",
  "description worker lifecycle marker",
);
requireText(powerSaver, "description_file", "description write verification");
requireText(powerSaver, "fallback_sleep_exit", "native failure fallback completion");
requireText(serviceSource, "正在读取实时充电状态", "hot update live status");
requireText(
  serviceSource,
  'qsc_ps_refresh_desc "${QSC_PS_NOW:-0}"',
  "hot update early status refresh",
);
requireText(daemonApi, "snapshotFailure", "WebUI snapshot failure status");
requireText(daemonApi, "waitFailure", "WebUI native wait failure status");
requireText(daemonApi, "waitFailureTime", "WebUI native wait failure time");
requireText(daemonCard, "等待器退避重试", "WebUI native wait recovery hint");
requireText(daemonCard, "updateDaemon", "WebUI remote repair action");
requireText(batterySnapshotApi, "MODDIR='${PATHS.MODDIR}'", "WebUI snapshot module path");
requireText(installGuide, "Rust 版额外提供阈值事件过滤", "install guide Rust capability");
requireText(webuiGuide, "只读快照与诊断", "WebUI guide snapshot capability");
requireText(webuiGuide, "升级继承", "WebUI guide inherited source");
requireText(configGuide, "native_version", "config guide native version");
if (installGuide.includes("两套实现功能、命令行、行为完全一致")) {
  throw new Error("install guide still claims Rust and C are behaviorally identical");
}
if (webuiGuide.includes("不写任何充电节点、不做阈值判定")) {
  throw new Error("WebUI guide still claims qscd never performs threshold filtering");
}
requireText(qscdSource, "struct BatterySnapshot", "Rust snapshot layer");
requireText(qscdSource, "snapshot_source=", "Rust snapshot diagnostics");
requireText(qscdSource, "snapshot_failure=", "Rust snapshot failure diagnostics");
requireText(qscdSource, "libc::poll", "Rust bounded netlink wait");
requireText(qscdSource, "libc::MSG_DONTWAIT", "Rust non-blocking netlink receive");
requireText(qscdSource, "reason=netlink_open", "Rust netlink failure reason");
simulateHotUpdateContract();

console.log(
  `[test:hot-update] ${modules.length} module contracts and release metadata passed`,
);
