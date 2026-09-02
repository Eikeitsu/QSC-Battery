import { PATHS } from "@/shared/config/paths";
import { exec } from "./index";

export interface DeviceArchiveItem {
  id: string;
  name: string;
  savedAt: string;
  model: string;
  device: string;
  marketName: string;
  mca: number;
  mcaPath: string;
  preferredSwitch: string;
  reassert: number;
}

function parseKv(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of String(text || "").split(/\r?\n/)) {
    const idx = line.indexOf("=");
    if (idx <= 0) continue;
    const k = line.slice(0, idx).trim();
    const v = line.slice(idx + 1).trim();
    if (k) out[k] = v;
  }
  return out;
}

function num(v: string | undefined): number {
  if (v == null) return 0;
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

async function archiveExec(cmd: string): Promise<{
  errno: number;
  stdout: string;
}> {
  return exec(
    `set -- 2>/dev/null; [ -f '${PATHS.MODDIR}/bin/lib/archive.sh' ] && . '${PATHS.MODDIR}/bin/lib/archive.sh'; DATADIR='${PATHS.DATADIR}' DEVICE_PROFILE='${PATHS.DEVICE_PROFILE}' QSC_ARCHIVE_DIR='${PATHS.PROFILES_DIR}' ${cmd}`,
  );
}

export async function listDeviceArchives(): Promise<DeviceArchiveItem[]> {
  const list = await archiveExec("qsc_archive_list 2>/dev/null");
  const names = String(list.stdout || "")
    .split(/\r?\n/)
    .map((s) => s.trim())
    .filter(Boolean);
  const out: DeviceArchiveItem[] = [];
  for (const id of names) {
    const result = await archiveExec(
      `qsc_archive_peek '${id.replace(/'/g, "'\\''")}' 2>/dev/null`,
    );
    const kv = parseKv(result.stdout);
    out.push({
      id,
      name: kv.slug || id,
      savedAt: kv.saved_at || "",
      model: kv.model || "",
      device: kv.device || "",
      marketName: kv.marketname || "",
      mca: num(kv.mca),
      mcaPath: kv.mca_path || "",
      preferredSwitch: kv.preferred_switch || "",
      reassert: num(kv.reassert),
    });
  }
  return out;
}

export async function saveDeviceArchive(slug: string): Promise<boolean> {
  const safe = slug.replace(/'/g, "'\\''");
  const r = await archiveExec(`qsc_archive_init 2>/dev/null; qsc_archive_save '${safe}'`);
  return r.errno === 0;
}

export async function applyDeviceArchive(id: string): Promise<boolean> {
  const safe = id.replace(/'/g, "'\\''");
  const r = await archiveExec(`qsc_archive_apply '${safe}'`);
  return r.errno === 0;
}

export async function deleteDeviceArchive(id: string): Promise<boolean> {
  const safe = id.replace(/'/g, "'\\''");
  const r = await archiveExec(`qsc_archive_delete '${safe}'`);
  return r.errno === 0;
}
