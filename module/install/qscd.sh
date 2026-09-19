#!/system/bin/sh
# qscd install helpers
qscd_conf_pref() {
	_cf="$MODPATH/config/power.conf"
	[ -f "$_cf" ] || _cf="$MODPATH/config/config.conf"
	[ -f "$_cf" ] || return 0
	grep -E '^[[:space:]]*native_impl[[:space:]]*=' "$_cf" 2>/dev/null \
		| tail -1 | sed 's/^[^=]*=//' | tr -d ' \t\r\n'
}

qscd_cleanup_candidates() {
	rm -f "$MODPATH/bin/qscd-arm64" "$MODPATH/bin/qscd-arm" \
		"$MODPATH/bin/qscdc-arm64" "$MODPATH/bin/qscdc-arm" 2>/dev/null
}

qscd_try_candidate() {
	# $1=源文件 $2=实现名（用于提示） $3=来源 $4=版本
	[ -f "$1" ] || return 1
	cp -f "$1" "$MODPATH/bin/qscd" 2>/dev/null || return 1
	chmod 0755 "$MODPATH/bin/qscd" 2>/dev/null
	if "$MODPATH/bin/qscd" probe >/dev/null 2>&1; then
		if [ "$3" = "download" ]; then
			ui_print "- 沿用已下载的守护（$2 版）：未插电时零定时唤醒"
		else
			ui_print "- 守护可用（$2 版）：未插电时零定时唤醒"
		fi
		case "$2" in
			Rust|rust) _used_impl=rust ;;
			C|c) _used_impl=c ;;
			*) _used_impl="$2" ;;
		esac
		echo "$_used_impl" >"$MODPATH/data/native_impl_used" 2>/dev/null
		echo "$3" >"$MODPATH/data/native_src" 2>/dev/null
		_version="$4"
		[ -n "$_version" ] || _version="$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n1 | tr -d ' \r\n')"
		[ -n "$_version" ] && echo "$_version" >"$MODPATH/data/native_version" 2>/dev/null
		case "$_used_impl" in
			c) [ -n "$_version" ] && echo "$_version" >"$MODPATH/data/native_version_c" 2>/dev/null ;;
			*) [ -n "$_version" ] && echo "$_version" >"$MODPATH/data/native_version_rust" 2>/dev/null ;;
		esac
		return 0
	fi
	ui_print "- 守护自检未通过（$2 版）"
	rm -f "$MODPATH/bin/qscd" 2>/dev/null
	return 1
}

install_qscd() {
	_suffix=""
	case "$ARCH" in
		arm64) _suffix="arm64" ;;
		arm) _suffix="arm" ;;
	esac

	# 上一版里 WebUI 下载好的守护已由 preserve 带过来，先挪开：
	# 本包自带候选时优先用自带的，都不可用再拿它兜底。
	_inherited=""
	if [ -f "$MODPATH/bin/qscd" ]; then
		_inherited="$MODPATH/data/.qscd_inherited"
		mv -f "$MODPATH/bin/qscd" "$_inherited" 2>/dev/null || _inherited=""
	fi
	_inherited_impl="$(cat "$MODPATH/data/native_impl_used" 2>/dev/null | tr -d ' \r\n')"
	_inherited_version="$(cat "$MODPATH/data/native_version" 2>/dev/null | tr -d ' \r\n')"
	case "$_inherited_impl" in
		c) _inherited_name="C" ;;
		*) _inherited_name="Rust" ;;
	esac
	rm -f "$MODPATH/bin/qscd" "$MODPATH/data/native_impl_used" \
		"$MODPATH/data/native_src" "$MODPATH/data/native_version" 2>/dev/null

	if [ -z "$_suffix" ]; then
		ui_print "- 本机架构($ARCH)无可用守护：使用定时轮询"
		rm -f "$_inherited" 2>/dev/null
		qscd_cleanup_candidates
		return 0
	fi

	_pref="$(qscd_conf_pref)"
	case "$_pref" in
		off)
			ui_print "- 已按配置禁用守护：使用定时轮询"
			rm -f "$_inherited" 2>/dev/null
			qscd_cleanup_candidates
			return 0
			;;
		c) _order="qscdc qscd" ;;
		*) _order="qscd qscdc" ;;
	esac

	for _impl in $_order; do
		case "$_impl" in
			qscd) _name="Rust" ;;
			*) _name="C" ;;
		esac
		if qscd_try_candidate "$MODPATH/bin/${_impl}-${_suffix}" "$_name" bundled; then
			rm -f "$_inherited" 2>/dev/null
			qscd_cleanup_candidates
			return 0
		fi
	done

	if [ -n "$_inherited" ] && [ -f "$_inherited" ]; then
		if qscd_try_candidate "$_inherited" "$_inherited_name" inherited "$_inherited_version"; then
			rm -f "$_inherited" 2>/dev/null
			qscd_cleanup_candidates
			return 0
		fi
		rm -f "$_inherited" 2>/dev/null
	fi

	qscd_cleanup_candidates
	qscd_offer_download "$_pref"
}
