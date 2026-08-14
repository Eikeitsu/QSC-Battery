export type HighlightOptions = {
  /** 行尾显示 ↵（编辑器用块级行 + ::after，避免光标错位） */
  eol?: boolean;
};

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** 路径：以 / 开头，直到空白、逗号、] 或行尾 */
const RE_PATH = /^(\/[^\s,\]]*)/;

function highlightKv(key: string, val: string): string {
  const keyCls = key === "start" ? "tok-start" : "tok-stop";
  const valCls = /^-?\d+(\.\d+)?$/.test(val) ? "tok-num" : "tok-val";
  return (
    `<span class="${keyCls}">${key}</span>` +
    `<span class="tok-eq">=</span>` +
    `<span class="${valCls}">${escapeHtml(val)}</span>`
  );
}

function highlightBody(body: string): string {
  if (!body) return "";

  let out = "";
  let rest = body;

  if (rest.startsWith("[")) {
    out += `<span class="tok-bracket">[</span>`;
    rest = rest.slice(1);
  }

  const pref = rest.match(/^power_switch=/i);
  if (pref) {
    out += `<span class="tok-pref">${escapeHtml(pref[0].slice(0, -1))}</span>`;
    out += `<span class="tok-eq">=</span>`;
    rest = rest.slice(pref[0].length);
    if (rest.startsWith("[")) {
      out += `<span class="tok-bracket">[</span>`;
      rest = rest.slice(1);
    }
  }

  const pathM = rest.match(RE_PATH);
  if (pathM) {
    out += `<span class="tok-path">${escapeHtml(pathM[1])}</span>`;
    rest = rest.slice(pathM[1].length);
  }

  let hasStart = false;
  let hasStop = false;

  while (rest.length) {
    const ws = rest.match(/^\s+/);
    if (ws) {
      out += escapeHtml(ws[0]);
      rest = rest.slice(ws[0].length);
      continue;
    }
    const sep = rest.match(/^(::|,|\])/);
    if (sep) {
      const s = sep[1];
      if (s === "]") out += `<span class="tok-bracket">]</span>`;
      else out += `<span class="tok-sep">${escapeHtml(s)}</span>`;
      rest = rest.slice(s.length);
      continue;
    }
    const kv = rest.match(/^(start|stop)=([^\s,\]]*)/);
    if (kv) {
      if (kv[1] === "start") hasStart = true;
      else hasStop = true;
      out += highlightKv(kv[1], kv[2]);
      rest = rest.slice(kv[0].length);
      continue;
    }
    const junk = rest.match(/^[^\s,\]]+/);
    if (junk) {
      out += `<span class="tok-bad">${escapeHtml(junk[0])}</span>`;
      rest = rest.slice(junk[0].length);
      continue;
    }
    out += escapeHtml(rest[0]);
    rest = rest.slice(1);
  }

  if (pathM && (!hasStart || !hasStop)) {
    return `<span class="tok-line-warn">${out}</span>`;
  }
  return out;
}

function highlightLine(line: string): string {
  if (!line) return "";
  const trimmed = line.trimStart();
  if (trimmed.startsWith("#")) {
    return `<span class="tok-cmt">${escapeHtml(line)}</span>`;
  }
  return highlightBody(line);
}

/**
 * 自定义供电开关高亮：
 * `/sys/.../node start=1 stop=0` · `::` · `power_switch=[...]` · 逗号格式
 */
export function highlightPowerSwitch(
  text: string,
  options: HighlightOptions = {},
): string {
  const raw = String(text || "");
  const lines = raw.split("\n");
  const { eol = false } = options;

  if (!eol) {
    return lines.map(highlightLine).join("\n");
  }

  // 块级行 + ::after 画 ↵，不占用与 textarea 对齐的字符位
  return lines
    .map((line, i) => {
      const body = highlightLine(line) || "\u200b";
      const cls = i < lines.length - 1 ? "tok-line has-eol" : "tok-line";
      return `<span class="${cls}">${body}</span>`;
    })
    .join("");
}
