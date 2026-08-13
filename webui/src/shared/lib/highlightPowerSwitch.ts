function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const TOKEN = /(\/[\w./-]+)|(::)|(\bstart\b|\bstop\b)|(=)|(\s+)|([^\s:]+)/g;

function highlightLine(line: string): string {
  if (!line) return "";
  const trimmed = line.trimStart();
  if (trimmed.startsWith("#")) {
    return `<span class="tok-cmt">${escapeHtml(line)}</span>`;
  }
  let out = "";
  TOKEN.lastIndex = 0;
  let m: RegExpExecArray | null;
  let last = 0;
  while ((m = TOKEN.exec(line))) {
    if (m.index > last) out += escapeHtml(line.slice(last, m.index));
    const [full, path, sep, key, eq, ws, other] = m;
    if (path) out += `<span class="tok-path">${escapeHtml(path)}</span>`;
    else if (sep) out += `<span class="tok-sep">${escapeHtml(sep)}</span>`;
    else if (key) out += `<span class="tok-key">${escapeHtml(key)}</span>`;
    else if (eq) out += `<span class="tok-eq">=</span>`;
    else if (ws) out += escapeHtml(ws);
    else out += `<span class="tok-val">${escapeHtml(other)}</span>`;
    last = m.index + full.length;
  }
  if (last < line.length) out += escapeHtml(line.slice(last));
  return out;
}

/** 自定义供电开关：路径 / start= / stop= / :: */
export function highlightPowerSwitch(text: string): string {
  const lines = String(text || "").split("\n");
  return lines.map(highlightLine).join("\n");
}
