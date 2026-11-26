#!/system/bin/sh
# 现场核对 XP 事实总线（刷机/重启注入后跑）。
# 用法：sh /data/adb/modules/QSC_Battery/bin/xp_bus_check.sh
# 无 Root 管理器终端 / adb shell su -c 均可。不停充、不改配置。

MODDIR=${0%/*}
[ -f "$MODDIR/common.sh" ] || MODDIR="${0%/*}/.."
# shellcheck disable=SC1090
[ -f "$MODDIR/bin/common.sh" ] && . "$MODDIR/bin/common.sh"
[ -f "$MODDIR/common.sh" ] && . "$MODDIR/common.sh"

echo "======== QSC · XP 总线自检 ========"

_ok=0
_warn=0
_fail=0

_note() { echo "[$1] $2"; }

# —— alive ——
_alive_path=
for _p in /data/system/qsc_xp_alive /data/local/tmp/qsc_xp_alive \
	/cache/qsc_xp_alive "${DATADIR:-/data/adb/modules/QSC_Battery/data}/xp_alive"; do
	if [ -s "$_p" ] && grep -q alive "$_p" 2>/dev/null; then
		_alive_path="$_p"
		break
	fi
done

if [ -f /data/system/qsc_xp_off ]; then
	_note WARN "qsc_xp_off 存在：XP 软关闭，Magisk 走 dumpsys 回退（充电控制仍可用）"
	_warn=$((_warn + 1))
fi

if [ -n "$_alive_path" ]; then
	_line="$(head -n1 "$_alive_path" 2>/dev/null)"
	_ver="$(printf '%s' "$_line" | sed -n 's/.*v=\([0-9][0-9]*\).*/\1/p' | head -n1)"
	_mt="$(stat -c %Y "$_alive_path" 2>/dev/null || echo 0)"
	_now="$(date +%s 2>/dev/null || echo 0)"
	_age=$((_now - _mt))
	if [ "$_age" -ge 0 ] 2>/dev/null && [ "$_age" -le 172800 ] 2>/dev/null; then
		_note OK "alive 新鲜 age=${_age}s path=$_alive_path${_ver:+ v=$_ver}"
		_ok=$((_ok + 1))
		_injected=1
	else
		_note FAIL "alive 过期 age=${_age}s（>172800s）→ Magisk 应回退 dumpsys"
		_fail=$((_fail + 1))
		_injected=0
	fi
else
	_note WARN "无 alive：未注入或未勾选 system 并重启；充电控制应仍可用（无 XP 回退）"
	_warn=$((_warn + 1))
	_injected=0
fi

_show_bus() {
	local name="$1" f="$2" line mt now age st
	if [ ! -f "$f" ]; then
		_note WARN "$name 缺失 $f"
		_warn=$((_warn + 1))
		return
	fi
	mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
	now="$(date +%s 2>/dev/null || echo 0)"
	age=$((now - mt))
	IFS= read -r line <"$f" 2>/dev/null || line=
	st="$(printf '%s' "$line" | tr '\t' ' ' | cut -c1-64)"
	if [ -z "$st" ]; then
		_note WARN "$name 空占位 age=${age}s（注入后应有事实；未操作过则正常）"
		_warn=$((_warn + 1))
	else
		_note OK "$name age=${age}s :: $st"
		_ok=$((_ok + 1))
	fi
}

echo "-------- 事实文件 --------"
_show_bus plug /data/system/qsc_xp_plug
_show_bus screen /data/system/qsc_xp_screen
_show_bus doze /data/system/qsc_xp_doze
_show_bus fg /data/system/qsc_xp_fg
_show_bus viewer /data/system/qsc_xp_viewer

if [ -f /data/system/qsc_xp_fg_policy ]; then
	_note OK "fg_policy: $(tr '\n' ' ' </data/system/qsc_xp_fg_policy | cut -c1-80)"
	_ok=$((_ok + 1))
else
	_note WARN "尚无 fg_policy（服务跑过一轮后应出现）"
	_warn=$((_warn + 1))
fi

echo "-------- 建议操作 --------"
if [ "${_injected:-0}" = "1" ]; then
	echo "1) 拔插一次，再跑本脚本，看 plug 是否更新"
	echo "2) 灭屏/亮屏一次，看 screen"
	echo "3) APP「我的 → LSPosed / XP」打开总线快照对照"
	echo "4) Action：音量下→上 写诊断；插电后再音量下→下 测开关"
else
	echo "1) LSPosed 勾选系统框架 (system)，启用本模块，重启"
	echo "2) 无 XP 也可：Action 音量下→上 写 /sdcard/qsc_diagnose.txt 反馈适配"
fi

echo "======== 汇总 OK=$_ok WARN=$_warn FAIL=$_fail ========"
[ "$_fail" -eq 0 ] 2>/dev/null
exit $?
