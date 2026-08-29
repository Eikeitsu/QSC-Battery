#!/system/bin/sh
# 热更新后立即拉起服务，并把模块简介从「等待开机」改成热更新状态
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
MODDIR="${0%/*}"

qsc_hot_stop_description_worker() {
	local root="$1" pid_file pid i
	pid_file="$root/data/description_worker.pid"
	pid="$(cat "$pid_file" 2>/dev/null | tr -d ' \r\n')"
	case "$pid" in
		""|*[!0-9]*) ;;
		*)
			kill "$pid" 2>/dev/null || true
			i=0
			while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 5 ]; do
				sleep 1
				i=$((i + 1))
			done
			kill -9 "$pid" 2>/dev/null || true
			;;
	esac
	rm -f "$pid_file" 2>/dev/null
	rm -rf "$root/data/.description_worker.lock" "$root/data/.description.lock" 2>/dev/null
}

# 先停止旧 worker，避免它在热更新过渡文案之后又用旧代码覆盖 module.prop。
qsc_hot_stop_description_worker "$MODDIR"
rm -f "$MODDIR/update" 2>/dev/null

# 先给出即时反馈：管理器列表不会停留在「等待开机就绪」
if [ -f "$MODDIR/bin/common.sh" ]; then
	# shellcheck disable=SC1090
	. "$MODDIR/bin/common.sh" 2>/dev/null || true
fi
if type qsc_write_module_description >/dev/null 2>&1; then
	qsc_write_module_description "♻️已热更新" "正在重启服务" \
		"无需重启；稍后自动显示实时充电状态"
fi
mkdir -p "$MODDIR/data" 2>/dev/null
date '+%Y-%m-%d %H:%M:%S' >"$MODDIR/data/hot_update_at" 2>/dev/null

# 结束旧的 service 循环与单次 switch
for _pat in \
	"$MODDIR/service.sh" \
	"$MODDIR/bin/qsc_switch.sh" \
	"/data/adb/modules/QSC_Battery/service.sh" \
	"/data/adb/modules/QSC_Battery/bin/qsc_switch.sh"
do
	pkill -f "$_pat" 2>/dev/null || true
done
sleep 1

if [ -f "$MODDIR/service.sh" ]; then
	# 安装器结束时可能连带清理当前会话；让常驻服务先脱离该会话。
	if command -v setsid >/dev/null 2>&1; then
		setsid sh "$MODDIR/service.sh" </dev/null >/dev/null 2>&1 &
	else
		nohup sh "$MODDIR/service.sh" </dev/null >/dev/null 2>&1 &
	fi
fi

echo "qsc: hotinstall done" >>/dev/kmsg 2>/dev/null || true
