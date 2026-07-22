#!/system/bin/sh
# 公共入口：路径初始化 + 按功能加载 lib/*
# 其它脚本统一：. "$MODDIR/bin/common.sh" 或 . "${0%/*}/common.sh"

qsc_resolve_moddir() {
	local script="${1:-$0}"
	local base="${script%/*}"
	case "$base" in
		*/bin) echo "${base%/*}" ;;
		*/bin/lib) echo "${base%/bin/lib}" ;;
		*) echo "$base" ;;
	esac
}

qsc_init_paths() {
	MODDIR="${MODDIR:-$(qsc_resolve_moddir "$1")}"
	BINDIR="$MODDIR/bin"
	LIBDIR="$BINDIR/lib"
	CONFDIR="$MODDIR/config"
	DATADIR="$MODDIR/data"
	ASSETDIR="$MODDIR/assets"
	CONF="$CONFDIR/config.conf"
	LIST_SWITCH="$DATADIR/list_switch"
	LOG_FILE="$DATADIR/log.log"
	OFF_FLAG="$DATADIR/off_qsc"
	DEVICE_PROFILE="$DATADIR/device.profile"
}

qsc_init_paths "$0"

# 防止重复 source
if [ -n "$QSC_LIBS_LOADED" ]; then
	return 0 2>/dev/null || exit 0
fi
QSC_LIBS_LOADED=1

if [ ! -d "$LIBDIR" ]; then
	echo "[QSC] 缺少 bin/lib，请重新安装模块" >&2
	return 1 2>/dev/null || exit 1
fi

. "$LIBDIR/util.sh"
. "$LIBDIR/keys.sh"
. "$LIBDIR/profile.sh"
. "$LIBDIR/charge.sh"
