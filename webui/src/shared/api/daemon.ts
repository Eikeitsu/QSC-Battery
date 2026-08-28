import { PATHS } from "@/shared/config/paths";
import { exec } from "./ksu";

/** 守护实现：Rust 为主力，C 保持基础事件唤醒兼容 */
export type DaemonImpl = "rust" | "c";

export interface DaemonStatus {
  /** bin/qscd 存在且可执行 */
  installed: boolean;
  /** 现场 probe 通过（本机能建起 netlink 套接字） */
  probeOk: boolean;
  /** Rust selftest 通过（C 版不提供扩展自检时为 false） */
  selftestOk: boolean;
  /** Rust selftest 检查的 netlink 能力 */
  selftestNetlink: boolean;
  /** Rust selftest 检查到电源 sysfs */
  selftestSysfs: boolean;
  /** 二进制支持的扩展能力 */
  features: string[];
  /** debug_on 开启时记录的最近一次等待结果 */
  lastWakeReason: string;
  /** 当前用的是哪套实现 */
  impl: DaemonImpl | "";
  /** 本地二进制激活时记录的版本 */
  localVersion: string;
  /** 来源：模块自带 or WebUI 下载 */
  src: "bundled" | "download" | "inherited" | "";
  /** 本包自带哪些实现（sh 版为空） */
  bundled: DaemonImpl[];
  /** 本机 ABI 对应的后缀；unsupported 表示没有可用二进制 */
  arch: string;
}

const EMPTY: DaemonStatus = {
  installed: false,
  probeOk: false,
  selftestOk: false,
  selftestNetlink: false,
  selftestSysfs: false,
  features: [],
  lastWakeReason: "",
  impl: "",
  localVersion: "",
  src: "",
  bundled: [],
  arch: "",
};

/** 脚本输出统一为 KEY=VALUE 行 */
function parseKv(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split(/\r?\n/)) {
    const at = line.indexOf("=");
    if (at <= 0) continue;
    out[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return out;
}

function toImpl(value: string | undefined): DaemonImpl | "" {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  return normalized === "rust" || normalized === "c" ? normalized : "";
}

function toStatus(kv: Record<string, string>): DaemonStatus {
  return {
    installed: kv.installed === "1",
    probeOk: kv.probe === "1",
    selftestOk: kv.selftest === "1",
    selftestNetlink: kv.selftest_netlink === "1",
    selftestSysfs: kv.selftest_sysfs === "1",
    features: (kv.features || "").split(/\s+/).filter(Boolean),
    lastWakeReason: kv.last_wake || "",
    impl: toImpl(kv.impl),
    localVersion: kv.local_version || "",
    src:
      kv.src === "bundled" || kv.src === "download" || kv.src === "inherited"
        ? kv.src
        : "",
    bundled: (kv.bundled || "")
      .split(",")
      .map((s) => toImpl(s.trim()))
      .filter((s): s is DaemonImpl => s !== ""),
    arch: kv.arch || "",
  };
}

export async function loadDaemonStatus(): Promise<DaemonStatus> {
  const r = await exec(`sh '${PATHS.QSCD_FETCH}' status 2>/dev/null`, 15_000);
  const kv = parseKv(r.stdout || "");
  if (kv.ok !== "1") return EMPTY;
  return toStatus(kv);
}

export interface DaemonActionResult {
  ok: boolean;
  /** 失败原因代码，见 bin/qscd_fetch.sh */
  error: string;
  impl: DaemonImpl | "";
  version: string;
}

export interface DaemonDownloadProgress {
  percent: number;
  stage: string;
}

export interface DaemonUpdateStatus {
  impl: DaemonImpl;
  localVersion: string;
  remoteVersion: string;
  versionState: "same" | "update" | "local_newer" | "unknown";
  updateAvailable: boolean;
  hashMatch: boolean;
}

const EMPTY_PROGRESS: DaemonDownloadProgress = { percent: 0, stage: "" };

export async function loadDaemonDownloadProgress(): Promise<DaemonDownloadProgress> {
  const r = await exec(`cat '${PATHS.QSCD_PROGRESS}' 2>/dev/null`, 3000);
  if (r.errno !== 0) return EMPTY_PROGRESS;
  const kv = parseKv(r.stdout || "");
  const percent = Number.parseInt(kv.percent || "", 10);
  return {
    percent: Number.isFinite(percent) ? Math.max(0, Math.min(100, percent)) : 0,
    stage: kv.stage || "",
  };
}

export async function checkDaemonUpdate(impl: DaemonImpl): Promise<{
  value: DaemonUpdateStatus | null;
  error: string;
}> {
  const r = await exec(`sh '${PATHS.QSCD_FETCH}' check ${impl} 2>/dev/null`, 150_000);
  const kv = parseKv(r.stdout || "");
  if (kv.ok !== "1") return { value: null, error: kv.error || "exec_failed" };
  const versionState = kv.version_state;
  return {
    value: {
      impl,
      localVersion: kv.local_version || "",
      remoteVersion: kv.remote_version || "",
      versionState:
        versionState === "same" ||
        versionState === "update" ||
        versionState === "local_newer"
          ? versionState
          : "unknown",
      updateAvailable: kv.update_available === "1",
      hashMatch: kv.hash_match === "1",
    },
    error: "",
  };
}

/** 下载耗时可能较长（含 manifest + 二进制两次请求），给足超时 */
const INSTALL_TIMEOUT_MS = 180_000;

/** 从 Pages 下载指定实现；成功后会自动替换掉原来的那套并重启服务 */
export async function installDaemon(impl: DaemonImpl): Promise<DaemonActionResult> {
  const r = await exec(
    `sh '${PATHS.QSCD_FETCH}' install ${impl} 2>/dev/null`,
    INSTALL_TIMEOUT_MS,
  );
  const kv = parseKv(r.stdout || "");
  return {
    ok: kv.ok === "1",
    error: kv.error || (kv.ok === "1" ? "" : "exec_failed"),
    impl: toImpl(kv.impl),
    version: kv.version || "",
  };
}

/** 改用模块自带的该实现，不联网 */
export async function useBundledDaemon(impl: DaemonImpl): Promise<DaemonActionResult> {
  const r = await exec(`sh '${PATHS.QSCD_FETCH}' use ${impl} 2>/dev/null`, 30_000);
  const kv = parseKv(r.stdout || "");
  return {
    ok: kv.ok === "1",
    error: kv.error || (kv.ok === "1" ? "" : "exec_failed"),
    impl: toImpl(kv.impl),
    version: "",
  };
}

/** 删除守护并把 native_daemon 置 0 */
export async function removeDaemon(): Promise<DaemonActionResult> {
  const r = await exec(`sh '${PATHS.QSCD_FETCH}' remove 2>/dev/null`, 30_000);
  const kv = parseKv(r.stdout || "");
  return {
    ok: kv.ok === "1",
    error: kv.error || (kv.ok === "1" ? "" : "exec_failed"),
    impl: "",
    version: "",
  };
}

const ERROR_TEXT: Record<string, string> = {
  unsupported_arch: "本机 CPU 架构没有可用的守护文件（仅 arm64 / armv7）",
  manifest_download_failed: "取不到文件清单，检查网络后重试",
  manifest_no_entry: "清单里没有本机架构的文件，可能该版本尚未发布",
  download_failed: "下载失败，检查网络后重试",
  no_sha256_tool: "系统缺少 sha256 工具，无法校验文件，已放弃安装",
  sha256_mismatch: "文件校验不通过，已丢弃（请勿使用来源不明的文件）",
  probe_failed: "文件已下载但本机自检未通过，已回滚",
  not_bundled: "当前安装包未自带该实现，请改用下载",
  bad_impl: "参数错误",
  exec_failed: "脚本执行失败，请确认模块已正确安装",
};

export function daemonErrorText(code: string): string {
  return ERROR_TEXT[code] || `操作失败（${code || "未知原因"}）`;
}
