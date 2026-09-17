#!/system/bin/sh
# CLI install
install_qsc_cli() {
	ui_print "--------------------------------"
	ui_print " 命令行 CLI"
	_abi="$(getprop ro.product.cpu.abi 2>/dev/null)"
	case "$_abi" in
		arm64* | *arm64*) _cli_src="$MODPATH/bin/qsc-arm64" ;;
		*) _cli_src="$MODPATH/bin/qsc-arm" ;;
	esac
	mkdir -p /data/adb/qsc/bin 2>/dev/null
	_installed=0
	if [ -f "$_cli_src" ] && [ -s "$_cli_src" ]; then
		cp -f "$_cli_src" /data/adb/qsc/bin/qsc 2>/dev/null && _installed=1
		cp -f "$_cli_src" "$MODPATH/bin/qsc" 2>/dev/null || true
	fi
	if [ "$_installed" != "1" ]; then
		cat >/data/adb/qsc/bin/qsc <<'QSC_CLI_EOF'
#!/system/bin/sh
exec sh "${QSC_MODDIR:-/data/adb/modules/QSC_Battery}/bin/qsc.sh" "$@"
QSC_CLI_EOF
		cp -f /data/adb/qsc/bin/qsc "$MODPATH/bin/qsc" 2>/dev/null || true
		ui_print "- 已安装 shell 版 CLI（包内无原生二进制）"
	else
		ui_print "- 已安装原生 CLI"
	fi
	chmod 0755 /data/adb/qsc/bin/qsc "$MODPATH/bin/qsc" 2>/dev/null
	rm -f "$MODPATH/bin/qsc-arm64" "$MODPATH/bin/qsc-arm" 2>/dev/null
	ui_print "- 用法: /data/adb/qsc/bin/qsc status"
}
