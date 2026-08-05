#!/system/bin/sh
# current.jsonc 读取器（面向 Magisk 机上环境：只有 toybox/busybox awk+sed，无 jq/python）
# 流程：去 // 与尾逗号 → awk 按 JSON 取值
# 标量：qsc_jsonc_get <file> <key>
# 字符串数组：qsc_jsonc_get_strings <file> <key>  → 每行一个（仅 JSON 数组）

qsc_jsonc_strip() {
	local f="$1"
	[ -f "$f" ] || return 1
	sed -e 's|//.*||g' -e 's|/\*[^*]*\*/||g' "$f" 2>/dev/null | tr -d '\r' | sed \
		-e 's|,[[:space:]]*}|}|g' \
		-e 's|,[[:space:]]*]|]|g'
}

# mode=scalar|array
qsc_jsonc_get_via_awk() {
	local f="$1"
	local key="$2"
	local mode="${3:-scalar}"
	local cleaned
	cleaned="$(qsc_jsonc_strip "$f")" || return 1
	printf '%s\n' "$cleaned" | awk -v key="$key" -v mode="$mode" '
	function skip_ws(    c) {
		while (pos <= n) {
			c = substr(s, pos, 1)
			if (c == " " || c == "\t" || c == "\n" || c == "\r") { pos++; continue }
			break
		}
	}
	function parse_string(    c, out, esc) {
		out = ""
		if (substr(s, pos, 1) != "\"") return ""
		pos++
		while (pos <= n) {
			c = substr(s, pos, 1)
			if (esc) {
				out = out c
				esc = 0
				pos++
				continue
			}
			if (c == "\\") { esc = 1; pos++; continue }
			if (c == "\"") { pos++; return out }
			out = out c
			pos++
		}
		return out
	}
	function parse_atom(    c, start, out) {
		skip_ws()
		c = substr(s, pos, 1)
		if (c == "\"") return parse_string()
		start = pos
		while (pos <= n) {
			c = substr(s, pos, 1)
			if (c == "," || c == "}" || c == "]" || c == " " || c == "\t" || c == "\n" || c == "\r") break
			pos++
		}
		out = substr(s, start, pos - start)
		gsub(/[[:space:]]+$/, "", out)
		return out
	}
	function parse_array(    c, item) {
		skip_ws()
		if (substr(s, pos, 1) != "[") return
		pos++
		while (pos <= n) {
			skip_ws()
			c = substr(s, pos, 1)
			if (c == "]") { pos++; return }
			if (c == ",") { pos++; continue }
			item = parse_atom()
			if (item != "") print item
			skip_ws()
		}
	}
	BEGIN { RS = "\0" }
	{
		s = $0
		n = length(s)
		needle = "\"" key "\""
		idx = 0
		start = 1
		while (1) {
			p = index(substr(s, start), needle)
			if (p == 0) break
			idx = start + p - 1
			start = idx + length(needle)
		}
		if (idx == 0) exit 1
		pos = idx + length(needle)
		skip_ws()
		if (substr(s, pos, 1) != ":") exit 1
		pos++
		skip_ws()
		c = substr(s, pos, 1)
		if (mode == "array") {
			if (c != "[") exit 1
			parse_array()
			exit 0
		}
		if (c == "[") exit 1
		val = parse_atom()
		if (val == "") exit 1
		print val
		exit 0
	}
	'
}

qsc_jsonc_get() {
	local f="$1"
	local key="$2"
	local out
	out="$(qsc_jsonc_get_via_awk "$f" "$key" scalar)" || return 1
	printf '%s\n' "$out" | head -n 1 | tr -d '\r'
}

qsc_jsonc_get_strings() {
	local f="$1"
	local key="$2"
	local out line
	out="$(qsc_jsonc_get_via_awk "$f" "$key" array)" || return 1
	[ -n "$out" ] || return 0
	printf '%s\n' "$out" | while IFS= read -r line || [ -n "$line" ]; do
		line="$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		[ -n "$line" ] && printf '%s\n' "$line"
	done
}
