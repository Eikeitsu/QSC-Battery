#!/system/bin/sh
# 学习与统计：充电习惯汇总（从 charge_events.log 提取），供 WebUI 概览
# 单文件、可重复调用，避免 WebUI 端重跑多次 awk

QSC_STATS_FILE="${QSC_STATS_FILE:-$DATADIR/learn_stats.txt}"
QSC_EVENT_LOG_SRC="${QSC_EVENT_LOG_SRC:-$DATADIR/charge_events.log}"

qsc_learn_stats() {
	[ -f "$QSC_EVENT_LOG_SRC" ] || {
		: >"$QSC_STATS_FILE" 2>/dev/null
		return 0
	}
	local avg_level stop_count hold_count peak_temp avg_temp
	# awk 提取 level / temp / 次数。失败即写空，不影响主流程。
	awk '
		BEGIN { cnt=0; stop=0; hold=0; lsum=0; lcnt=0; tsum=0; tcnt=0; pmax=-1 }
		{
			type=""; level=""; temp=""
			if (match($0, /\[EVENT\][ \t]+[^ \t]+/, a)) type=a[0]; sub(/^\[EVENT\][ \t]+/, "", type)
			if (match($0, /[ \t]+([0-9]+)%/, b)) level=b[1]
			if (match($0, /[ \t]+([0-9]+)°C/, c)) temp=c[1]
			if (type == "CHARGE_STOP") stop++
			if (type == "MAINTAIN") hold++
			if (level ~ /^[0-9]+$/) { lsum += level; lcnt++ }
			if (temp  ~ /^[0-9]+$/) { tsum += temp; tcnt++; if (temp+0 > pmax) pmax = temp+0 }
			cnt++
		}
		END {
			L = (lcnt>0) ? int(lsum/lcnt) : "--"
			T = (tcnt>0) ? int(tsum/tcnt) : "--"
			P = (pmax>=0) ? pmax : "--"
			printf "events=%d\nstop=%d\nhold=%d\navg_level=%s\navg_temp=%s\npeak_temp=%s\n", cnt, stop, hold, L, T, P
		}
	' "$QSC_EVENT_LOG_SRC" >"$QSC_STATS_FILE" 2>/dev/null || {
		: >"$QSC_STATS_FILE" 2>/dev/null
		return 1
	}
	return 0
}
