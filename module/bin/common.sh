#!/system/bin/sh

qsc_resolve_moddir() {
	local script="${1:-$0}"
	local base="${script%/*}"
	case "$base" in
		*/bin) echo "${base%/*}" ;;
		*) echo "$base" ;;
	esac
}

qsc_init_paths() {
	MODDIR="${MODDIR:-$(qsc_resolve_moddir "$1")}"
	BINDIR="$MODDIR/bin"
	CONFDIR="$MODDIR/config"
	DATADIR="$MODDIR/data"
	ASSETDIR="$MODDIR/assets"
	CONF="$CONFDIR/config.conf"
	LIST_SWITCH="$DATADIR/list_switch"
	LOG_FILE="$DATADIR/log.log"
	OFF_FLAG="$DATADIR/off_qsc"
}

qsc_init_paths "$0"
