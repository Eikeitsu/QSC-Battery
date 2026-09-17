/**
 * 机型 / 系统文案：参考 fastfetch、APatch 等对厂商 market name 的兜底。
 * 注意：getprop 属性不存在时仍 exit 0 且输出空串，不能用 `||` 串联。
 */

/** 一次 shell 输出：`机型\t系统`（系统可为空） */
export const DEVICE_INFO_SHELL = `
model=
for k in \
  ro.product.marketname \
  ro.vendor.oplus.market.name \
  ro.oplus.market.name \
  ro.vendor.oplus.market.enname \
  ro.oppo.market.name \
  ro.product.oppo_model \
  ro.vivo.market.name \
  ro.vendor.product.display \
  ro.config.marketing_name \
  ro.config.devicename \
  ro.product.vendor.model \
  ro.product.model
do
  v=$(getprop "$k" 2>/dev/null)
  if [ -n "$v" ]; then
    model=$v
    break
  fi
done
if [ -z "$model" ]; then
  model=$(getprop ro.product.brand 2>/dev/null)
fi
if [ -z "$model" ]; then
  model=Android
fi

os=
if v=$(getprop ro.mi.os.version.name 2>/dev/null); [ -n "$v" ]; then
  v=$(printf '%s' "$v" | sed 's/^OS//')
  os="HyperOS $v"
elif v=$(getprop ro.mi.os.version.incremental 2>/dev/null); [ -n "$v" ]; then
  v=$(printf '%s' "$v" | sed 's/^OS//')
  os="HyperOS $v"
elif v=$(getprop ro.miui.ui.version.name 2>/dev/null); [ -n "$v" ]; then
  os="MIUI $v"
elif v=$(getprop ro.oxygen.version 2>/dev/null); [ -n "$v" ]; then
  os="OxygenOS $v"
elif v=$(getprop ro.build.version.oplusrom 2>/dev/null); [ -n "$v" ]; then
  v=$(printf '%s' "$v" | sed 's/^V//')
  os="ColorOS $v"
elif v=$(getprop ro.rom.version 2>/dev/null); [ -n "$v" ]; then
  os=$v
elif v=$(getprop ro.vivo.os.build.display.id 2>/dev/null); [ -n "$v" ]; then
  os=$v
elif v=$(getprop ro.vivo.os.version 2>/dev/null); [ -n "$v" ]; then
  os="OriginOS $v"
elif v=$(getprop ro.build.version.release 2>/dev/null); [ -n "$v" ]; then
  os="Android $v"
fi

printf '%s\\t%s\\n' "$model" "$os"
`.trim();

export function formatDeviceLabel(stdout: string): string {
  const line = String(stdout || "")
    .split(/\r?\n/)
    .map((s) => s.trim())
    .find(Boolean);
  if (!line) return "Android";
  const tab = line.indexOf("\t");
  const model = (tab >= 0 ? line.slice(0, tab) : line).trim() || "Android";
  const os = (tab >= 0 ? line.slice(tab + 1) : "").trim();
  return os ? `${model} · ${os}` : model;
}
