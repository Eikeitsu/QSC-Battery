#!/system/bin/sh
# companion APK
install_companion_app() {
	if [ "$QSC_INSTALL_AUTO" = "1" ]; then
		ui_print "- 无人值守：跳过伴侣 APP 安装（可在 APP「更新」页安装）"
		return 0
	fi
	ui_print "--------------------------------"
	ui_print " 伴侣 APP（可选）"
	ui_print " APP 可不装模块单独使用；装上后才方便控制停充"
	ui_print " 音量上：现在安装模块内嵌的 APK"
	ui_print " 音量下：跳过（可在 APP「更新」页安装）"
	ui_print " 20 秒未选择时跳过"
	qsc_volume_choice
	case "$?" in
		0) ;;
		*)
			ui_print "- 已跳过 APP 安装"
			ui_print "- 发布页: https://eikeitsu.github.io/QSC-Battery/"
			return 0
			;;
	esac

	_bundled_apk=""
	for _cand in \
		"$MODPATH/apk/QSC-Battery.apk" \
		"$MODPATH/QSC-Battery.apk" \
		"$MODPATH/apk/app-release.apk"; do
		if [ -f "$_cand" ] && [ -s "$_cand" ]; then
			_bundled_apk="$_cand"
			break
		fi
	done

	if [ -n "$_bundled_apk" ]; then
		ui_print "- 正在安装内嵌伴侣 APP..."
		if pm install -r "$_bundled_apk" >/dev/null 2>&1; then
			ui_print "- 伴侣 APP 已安装"
		else
			ui_print "- APP 安装失败（签名冲突或 pm 不可用）"
			ui_print "- 发布页安装或跳过均可；模块目录不会保留 APK"
		fi
		return 0
	fi

	ui_print "- 模块包内未找到伴侣 APK，已跳过"
	ui_print "- 请从发布页安装，或使用已编译的 release/QSC-Battery.apk 重新打包模块"

	# --- 在线下载安装（已停用，保留备查）---
	# _tmp_json="/data/local/tmp/qsc-app-update.json"
	# _tmp_apk="/data/local/tmp/QSC-Battery.apk"
	# rm -f "$_tmp_json" "$_tmp_apk" 2>/dev/null
	# ui_print "- 正在获取 APP 更新信息..."
	# if ! qsc_http_get "$APP_UPDATE_JSON" "$_tmp_json"; then
	# 	ui_print "- 无法下载 app-update.json（网络不通或超时）"
	# 	ui_print "- 请稍后在浏览器打开发布页安装"
	# 	return 0
	# fi
	# _apk_url="$(sed -n 's/.*"apkUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_tmp_json" | head -n1)"
	# if [ -z "$_apk_url" ]; then
	# 	ui_print "- 更新信息缺少 apkUrl，已跳过"
	# 	rm -f "$_tmp_json" 2>/dev/null
	# 	return 0
	# fi
	# ui_print "- 正在下载伴侣 APP..."
	# if ! qsc_http_get "$_apk_url" "$_tmp_apk"; then
	# 	ui_print "- APK 下载失败"
	# 	rm -f "$_tmp_json" 2>/dev/null
	# 	return 0
	# fi
	# ui_print "- 正在安装伴侣 APP..."
	# if pm install -r "$_tmp_apk" >/dev/null 2>&1; then
	# 	ui_print "- 伴侣 APP 已安装"
	# else
	# 	ui_print "- APP 安装失败（签名冲突或 pm 不可用）"
	# 	ui_print "- 文件保留: $_tmp_apk"
	# 	ui_print "- 可手动安装，或从发布页获取"
	# fi
	# rm -f "$_tmp_json" 2>/dev/null
}
