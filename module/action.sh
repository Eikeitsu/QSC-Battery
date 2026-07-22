#!/system/bin/sh

MODDIR=${0%/*}

echo "========================================"
echo " QSC 定量停充 · Action"
echo "========================================"

if [ ! -f "$MODDIR/bin/common.sh" ]; then
	echo "[错误] 缺少 bin/common.sh，请重新安装模块"
	exit 1
fi

. "$MODDIR/bin/common.sh"
mkdir -p "$DATADIR" 2>/dev/null
chmod 0755 "$BINDIR"/*.sh 2>/dev/null

if [ -f "$BINDIR/.qsc_debug" ] || [ -f "$BINDIR/testing.sh" ] || [ -f "$BINDIR/diag2.sh" ]; then
	echo " 当前为调试包（含写入类工具）"
else
	echo " 当前为正式包（仅只读诊断；testing/diag2 需刷 debug zip）"
fi

qsc_action_refresh() {
	echo "----------------------------------------"
	echo "[刷新] 权限与状态检查"
	echo "----------------------------------------"
	echo "[1/4] 刷新脚本权限..."
	chmod 0755 "$BINDIR"/*.sh 2>/dev/null
	echo "  bin/*.sh -> 0755"

	echo "[2/4] 刷新配置权限..."
	if [ -f "$CONF" ]; then
		chmod 0644 "$CONF" 2>/dev/null
		echo "  config.conf -> 0644"
	else
		echo "  警告: 未找到 config.conf"
	fi

	echo "[3/4] 刷新 WebUI 文件权限..."
	if [ -d "$MODDIR/webroot" ]; then
		find "$MODDIR/webroot" -type f -exec chmod 0644 {} \; 2>/dev/null
		find "$MODDIR/webroot" -type d -exec chmod 0755 {} \; 2>/dev/null
		echo "  webroot 已处理"
	else
		echo "  webroot 未安装（核心停充功能不受影响）"
	fi

	echo "[4/4] 检查关键文件..."
	[ -f "$BINDIR/qsc_switch.sh" ] && echo "  qsc_switch.sh: OK" || echo "  qsc_switch.sh: 缺失"
	[ -f "$CONF" ] && echo "  config.conf: OK" || echo "  config.conf: 缺失"
	[ -f "$MODDIR/webroot/index.html" ] && echo "  webroot/index.html: OK" || echo "  webroot/index.html: 未安装"
	[ -f "$OFF_FLAG" ] && echo "  模块状态: 已关闭 (存在 off_qsc)" || echo "  模块状态: 开启"
	if [ -f "$DEVICE_PROFILE" ]; then
		echo "  device.profile: mca=$(qsc_profile_get mca) path=$(qsc_profile_get mca_path)"
	else
		echo "  device.profile: 尚未生成"
	fi
	[ -f "$BINDIR/diagnose.sh" ] && echo "  diagnose.sh: OK" || echo "  diagnose.sh: 缺失"
	[ -f "$BINDIR/testing.sh" ] && echo "  testing.sh: 已安装（调试）" || echo "  testing.sh: 未打包（正式包正常）"
	[ -f "$BINDIR/diag2.sh" ] && echo "  diag2.sh: 已安装（调试）" || echo "  diag2.sh: 未打包（正式包正常）"
	echo "----------------------------------------"
	echo " 刷新完成"
}

qsc_action_run_script() {
	local name="$1"
	local script="$BINDIR/$name"
	echo "----------------------------------------"
	echo "[执行] $name"
	echo "----------------------------------------"
	if [ ! -f "$script" ]; then
		echo "[错误] 缺少 $name"
		echo " 正式包不含写入类工具；请安装同版本 debug zip："
		echo "  QSC-Battery_v<version>-debug.zip"
		return 1
	fi
	chmod 0755 "$script" 2>/dev/null
	sh "$script"
	echo "----------------------------------------"
	echo " $name 执行结束"
}

qsc_action_redetect() {
	echo "----------------------------------------"
	echo "[探测] 本机充电控制节点"
	echo "----------------------------------------"
	if [ -f "$BINDIR/detect_device.sh" ]; then
		chmod 0755 "$BINDIR/detect_device.sh" 2>/dev/null
		sh "$BINDIR/detect_device.sh"
	else
		qsc_detect_and_write_profile
	fi
	echo " 已写入: $DEVICE_PROFILE"
	echo "----------------------------------------"
}

# 逐项：音量上=执行，音量下=跳过，超时=跳过
qsc_action_ask() {
	local title="$1"
	echo ""
	echo "----------------------------------------"
	echo " $title"
	echo " 音量上：执行　　音量下：跳过"
	echo " 本轮 20 秒未选择则跳过"
	echo "----------------------------------------"
	qsc_volume_choice 20
	case "$?" in
		0) return 0 ;;
		1) echo " 已跳过"; return 1 ;;
		*) echo " 本轮选择超时，已跳过"; return 1 ;;
	esac
}

qsc_action_diag_menu() {
	echo ""
	echo "========================================"
	echo " 诊断菜单"
	echo " 逐项询问：上=执行，下=跳过"
	echo "========================================"

	if [ -f "$BINDIR/diagnose.sh" ]; then
		if qsc_action_ask "是否运行 diagnose（只读节点诊断）？"; then
			qsc_action_run_script diagnose.sh
		else
			echo " 已跳过 diagnose"
		fi
	fi

	if [ -f "$BINDIR/testing.sh" ]; then
		if qsc_action_ask "是否运行 testing（适配检测，调试包）？"; then
			qsc_action_run_script testing.sh
		else
			echo " 已跳过 testing"
		fi
	fi

	if [ -f "$BINDIR/diag2.sh" ]; then
		if qsc_action_ask "是否运行 diag2（写入测试，调试包）？"; then
			echo "注意: diag2 会尝试写入部分充电节点做测试"
			qsc_action_run_script diag2.sh
		else
			echo " 已跳过 diag2"
		fi
	fi

	if qsc_action_ask "是否重新探测设备配置？"; then
		qsc_action_redetect
	else
		echo " 已跳过重新探测"
	fi
}

# 第一级：上=刷新（默认），下=诊断菜单，超时=刷新
echo ""
echo "========================================"
echo " 请选择"
echo " 音量上：刷新权限与状态（默认）"
echo " 音量下：进入诊断菜单"
echo " 本轮 20 秒未选择将执行刷新"
echo "========================================"
qsc_volume_choice 20
case "$?" in
	1)
		echo "已选择：诊断菜单"
		qsc_action_diag_menu
		;;
	2)
		echo "本轮选择超时，执行刷新"
		qsc_action_refresh
		;;
	*)
		echo "已选择：刷新权限"
		qsc_action_refresh
		;;
esac

echo "========================================"
echo " Action 结束"
echo "========================================"
