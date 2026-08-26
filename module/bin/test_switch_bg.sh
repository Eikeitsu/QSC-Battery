#!/system/bin/sh
# 后台测开关：避免 Magisk/SukiSU Action / WebUI 桥接超时被杀
# 用法：QSC_TEST_MAX=12 sh bin/test_switch_bg.sh
# 状态：data/switch_test_status（running|done|error…）

. "${0%/*}/common.sh"

mkdir -p "$DATADIR" 2>/dev/null
PIDF="$DATADIR/switch_test_pid"
STF="$DATADIR/switch_test_status"
LOGF="$DATADIR/switch_test_bg.log"

if [ -f "$PIDF" ]; then
	old="$(cat "$PIDF" 2>/dev/null | tr -d ' \r\n')"
	if [ -n "$old" ] && [ -d "/proc/$old" ]; then
		echo "already_running pid=$old"
		echo "running pid=$old ts=$(date +%s)" >"$STF"
		exit 0
	fi
fi

[ -f "$BINDIR/test_switch.sh" ] || {
	echo "missing test_switch.sh"
	echo "error missing ts=$(date +%s)" >"$STF"
	exit 1
}

chmod 0755 "$BINDIR/test_switch.sh" 2>/dev/null
echo "starting ts=$(date +%s)" >"$STF"
: >"$LOGF"

# 子进程脱离当前 shell，管理器杀 Action 也不中断测试
(
	QSC_TEST_MAX="${QSC_TEST_MAX:-}" sh "$BINDIR/test_switch.sh" >>"$LOGF" 2>&1
	ec=$?
	if [ ! -f "$STF" ] || grep -q '^running\|^starting' "$STF" 2>/dev/null; then
		echo "done exit=$ec ts=$(date +%s)" >"$STF"
	fi
	rm -f "$PIDF" 2>/dev/null
) &
echo $! >"$PIDF"
echo "started pid=$(cat "$PIDF") log=$LOGF"
