#!/system/bin/sh
# current: hardware bypass
qsc_bypass_probe_node() {
	local node cur
	QSC_BYPASS_NODE=""
	QSC_BYPASS_ON_VAL=1
	for node in $QSC_BYPASS_NODE_CANDIDATES; do
		[ -f "$node" ] || continue
		cur="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
		case "$cur" in
			0|1) QSC_BYPASS_NODE="$node"; QSC_BYPASS_ON_VAL=1; return 0 ;;
		esac
	done
	for node in $QSC_BYPASS_INV_CANDIDATES; do
		[ -f "$node" ] || continue
		cur="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
		case "$cur" in
			0|1) QSC_BYPASS_NODE="$node"; QSC_BYPASS_ON_VAL=0; return 0 ;;
		esac
	done
	return 1
}

qsc_bypass_hw_on() {
	local node="$1"
	local prev cur
	[ -n "$node" ] && [ -f "$node" ] || return 1
	prev="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
	case "$prev" in
		0|1) ;;
		*) return 1 ;;
	esac
	echo "$prev" >"$DATADIR/bypass_node_prev" 2>/dev/null
	echo "$node" >"$DATADIR/bypass_node_path" 2>/dev/null
	[ -n "$QSC_BYPASS_ON_VAL" ] || QSC_BYPASS_ON_VAL=1
	echo "$QSC_BYPASS_ON_VAL" >"$DATADIR/bypass_node_onval" 2>/dev/null
	chmod 0644 "$node" 2>/dev/null
	echo "$QSC_BYPASS_ON_VAL" >"$node" 2>/dev/null || return 1
	cur="$(cat "$node" 2>/dev/null | tr -d ' \r\n')"
	[ "$cur" = "$QSC_BYPASS_ON_VAL" ]
}

qsc_bypass_hw_off() {
	local node prev
	node="$(cat "$DATADIR/bypass_node_path" 2>/dev/null)"
	prev="$(cat "$DATADIR/bypass_node_prev" 2>/dev/null)"
	[ -z "$node" ] && node="$QSC_BYPASS_NODE"
	[ -n "$node" ] && [ -f "$node" ] || {
		rm -f "$DATADIR/bypass_node_path" "$DATADIR/bypass_node_prev" "$DATADIR/bypass_node_onval"
		return 0
	}
	case "$prev" in
		0|1) ;;
		*) prev=0 ;;
	esac
	chmod 0644 "$node" 2>/dev/null
	echo "$prev" >"$node" 2>/dev/null
	rm -f "$DATADIR/bypass_node_path" "$DATADIR/bypass_node_prev" "$DATADIR/bypass_node_onval"
	return 0
}

# 是否需要强制重申 / 可否整轮跳过写节点
# $1=目标 µA
# 副作用：QSC_CW_FORCE / QSC_CW_FORCE_REASON / QSC_CW_NOW_UA / QSC_CW_OVER / QSC_CW_SKIP_IO
