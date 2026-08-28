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
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

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

for (const mod of modules) {
  const hot = read(mod.hot);
  const hotinstall = read(mod.hotinstall);
  const service = read(mod.service);
  const uninstall = read(mod.uninstall);

  requireText(hotinstall, 'setsid sh "$MODDIR/service.sh"', `${mod.name} detached service`);
  requireText(hotinstall, 'nohup sh "$MODDIR/service.sh"', `${mod.name} fallback service`);
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
requireText(store, "settings[key] = value || DEFAULTS[key]", "config migration fallback");

console.log(
  `[test:hot-update] ${modules.length} module contracts and release metadata passed`,
);
