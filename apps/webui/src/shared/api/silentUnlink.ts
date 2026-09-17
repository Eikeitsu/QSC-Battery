/** 后台静默删单个普通文件：不对用户提示；禁止目录 / rm -rf。 */
import { exec } from "./ksu";

// const DBG = "[qsc-cleanup]";

function safeAbsFilePath(absPath: string): string | null {
  const raw = String(absPath || "").trim();
  if (!raw.startsWith("/")) return null;
  if (raw.includes("..") || raw.includes("\n") || raw.includes("\0")) return null;
  if (raw.endsWith("/") || raw === "/") return null;
  const p = raw.replace(/'/g, "");
  if (!p.startsWith("/") || p.includes("..")) return null;
  return p;
}

async function unlinkOnce(p: string): Promise<void> {
  const exists = await exec(`[ -f '${p}' ] && echo yes || echo no`, 3_000);
  if (!(exists.stdout || "").includes("yes")) return;

  await exec(`rm -f -- '${p}'`, 3_000).catch(() => undefined);

  const still = await exec(`[ -e '${p}' ] && echo yes || echo no`, 3_000);
  if ((still.stdout || "").includes("yes")) {
    // 仅排障：预期应删掉但仍在
    // console.debug(`${DBG} still exists after unlink: ${p}`);
  }
}

/**
 * @param absPath 绝对路径，仅当普通文件时尝试 `rm -f --`
 * @param delaySec 延迟秒数；>0 时用定时器后台再删（仍无 toast）
 */
export function silentUnlinkFile(absPath: string, delaySec = 0): void {
  const p = safeAbsFilePath(absPath);
  if (!p) return;

  if (delaySec > 0) {
    const ms = Math.max(1, Math.floor(delaySec)) * 1000;
    window.setTimeout(() => {
      void unlinkOnce(p).catch(() => undefined);
    }, ms);
    return;
  }

  void unlinkOnce(p).catch(() => undefined);
}
