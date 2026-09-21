#!/system/bin/sh
# switch: charge_full helper
qsc_charge_full() {
	if [ "$charge_full" = "1" -a "$battery_level" = "100" -a "$power_stop" = "100" ]; then
		if [ "$battery_status" = "5" ]; then
			rm -f "$DATADIR/now_c" "$DATADIR/charge_full_since"
			qsc_log info "电量$battery_level 触发充满再停功能 当前已充满"
			return
		fi
		full_log=1
		_cur_ok=0
		_time_ok=0
		# 电流判定（current / auto）
		if [ "$charge_full_mode" = "current" ] || [ "$charge_full_mode" = "auto" ]; then
			now_current="$(qsc_safe_cat "$PSDIR/battery/current_now")"
			if [ -n "$now_current" ]; then
				now_current="$(echo "$now_current" | sed -n 's/-//g;$p')"
				if [ "$now_current" -lt "100000" ]; then
					echo "$now_current" >> "$DATADIR/now_c"
				else
					rm -f "$DATADIR/now_c"
				fi
				now_current_n="$(wc -l <"$DATADIR/now_c" 2>/dev/null | tr -d ' ')"
				case "$now_current_n" in ""|*[!0-9]*) now_current_n=0 ;; esac
				if [ "$now_current_n" -ge "3" ]; then
					_cur_ok=1
				fi
				qsc_dbg "涓流·电流：|I|=$now_current samples=$now_current_n cur_ok=$_cur_ok（需≥3次且<100mA）"
			else
				qsc_dbg "涓流·电流：current_now 不可读"
			fi
		else
			rm -f "$DATADIR/now_c"
		fi
		# 时间判定（time / auto）；等待秒数来自配置，UI 不暴露（默认 600）
		if [ "$charge_full_mode" = "time" ] || [ "$charge_full_mode" = "auto" ]; then
			_now_ts="$(date +%s 2>/dev/null)"
			case "$_now_ts" in ""|*[!0-9]*) _now_ts=0 ;; esac
			_since=""
			qsc_read_node "$DATADIR/charge_full_since" && _since="$QSC_NODE_VAL"
			case "$_since" in ""|*[!0-9]*) _since=0 ;; esac
			if [ "$_since" -le 0 ] 2>/dev/null; then
				echo "$_now_ts" >"$DATADIR/charge_full_since" 2>/dev/null
				_since="$_now_ts"
				qsc_log debug "电量$battery_level 充满再停·计时开始，等待 ${charge_full_wait_sec}s"
			fi
			_elapsed=$((_now_ts - _since))
			if [ "$_elapsed" -ge "$charge_full_wait_sec" ] 2>/dev/null; then
				_time_ok=1
			fi
			qsc_dbg "涓流·时间：elapsed=$_elapsed need=$charge_full_wait_sec time_ok=$_time_ok"
		else
			rm -f "$DATADIR/charge_full_since"
		fi
		case "$charge_full_mode" in
			auto)
				if [ "$_cur_ok" = "1" ] || [ "$_time_ok" = "1" ]; then
					full_log=0
				fi
				;;
			time)
				[ "$_time_ok" = "1" ] && full_log=0
				;;
			*)
				[ "$_cur_ok" = "1" ] && full_log=0
				;;
		esac
		if [ "$full_log" = "0" ]; then
			rm -f "$DATADIR/now_c" "$DATADIR/charge_full_since"
			qsc_log debug "电量$battery_level 充满再停·条件满足 mode=$charge_full_mode"
			qsc_dbg "涓流·通过 mode=$charge_full_mode cur_ok=$_cur_ok time_ok=$_time_ok"
		else
			qsc_dbg "涓流·未满足 mode=$charge_full_mode cur_ok=$_cur_ok time_ok=$_time_ok"
		fi
	else
		rm -f "$DATADIR/charge_full_since"
	fi
}
