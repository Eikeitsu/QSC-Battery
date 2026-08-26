import { PATHS } from "@/shared/config/paths";
import { exec } from "./ksu";

export interface DeviceProfileExport {
  preferred_switch?: string;
  preferred_start?: string;
  preferred_stop?: string;
  reassert?: string;
  mca?: string;
  mca_path?: string;
}

export async function loadDeviceProfileExport(): Promise<DeviceProfileExport | null> {
  const result = await exec(`cat '${PATHS.DEVICE_PROFILE}' 2>/dev/null`);
  if (!result.stdout.trim()) return null;
  const out: DeviceProfileExport = {};
  for (const line of result.stdout.split(/\r?\n/)) {
    const i = line.indexOf("=");
    if (i <= 0 || line.startsWith("#")) continue;
    const k = line.slice(0, i).trim();
    const v = line.slice(i + 1).trim();
    if (
      k === "preferred_switch" ||
      k === "preferred_start" ||
      k === "preferred_stop" ||
      k === "reassert" ||
      k === "mca" ||
      k === "mca_path"
    ) {
      out[k] = v;
    }
  }
  return Object.keys(out).length ? out : null;
}

export async function applyDeviceProfileExport(
  profile: DeviceProfileExport | null | undefined,
): Promise<boolean> {
  if (!profile) return true;
  const keys: (keyof DeviceProfileExport)[] = [
    "preferred_switch",
    "preferred_start",
    "preferred_stop",
    "reassert",
    "mca",
    "mca_path",
  ];
  const cmds: string[] = [
    `mkdir -p '${PATHS.DATADIR}' 2>/dev/null`,
    `[ -f '${PATHS.DEVICE_PROFILE}' ] || echo '# QSC device.profile' > '${PATHS.DEVICE_PROFILE}'`,
  ];
  for (const k of keys) {
    const v = String(profile[k] ?? "").replace(/'/g, "");
    cmds.push(
      `if grep -q '^${k}=' '${PATHS.DEVICE_PROFILE}' 2>/dev/null; then sed -i 's|^${k}=.*|${k}=${v}|' '${PATHS.DEVICE_PROFILE}'; else echo '${k}=${v}' >> '${PATHS.DEVICE_PROFILE}'; fi`,
    );
  }
  const result = await exec(cmds.join("; "));
  return result.errno === 0;
}

export async function savePreferredSwitch(opts: {
  path: string;
  start: string;
  stop: string;
  reassert: boolean;
}): Promise<boolean> {
  const path = String(opts.path || "")
    .trim()
    .replace(/'/g, "");
  const start = String(opts.start || "")
    .trim()
    .replace(/'/g, "");
  const stop = String(opts.stop || "")
    .trim()
    .replace(/'/g, "");
  if (!path.startsWith("/") || !start || !stop) return false;
  return applyDeviceProfileExport({
    preferred_switch: path,
    preferred_start: start,
    preferred_stop: stop,
    reassert: opts.reassert ? "1" : "0",
  });
}

export async function clearPreferredSwitch(): Promise<boolean> {
  return applyDeviceProfileExport({
    preferred_switch: "",
    preferred_start: "",
    preferred_stop: "",
    reassert: "0",
  });
}
