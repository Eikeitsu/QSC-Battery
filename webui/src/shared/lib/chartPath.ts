/** 等距降采样，保留首尾点，供 SVG 渲染 */
export function downsamplePoints<T extends { ts: number }>(points: T[], max = 120): T[] {
  if (points.length <= max) return points;
  if (max <= 1) return [points[points.length - 1]!];

  const out: T[] = [];
  const step = (points.length - 1) / (max - 1);
  for (let i = 0; i < max; i += 1) {
    out.push(points[Math.round(i * step)]!);
  }
  return out;
}

/** Catmull-Rom 转 cubic Bezier，生成平滑 SVG path */
export function buildSmoothPath<T>(
  list: T[],
  xAt: (point: T) => number,
  yAt: (point: T) => number,
): string {
  if (list.length < 2) return "";

  const pts = list.map((point) => ({ x: xAt(point), y: yAt(point) }));

  if (pts.length === 2) {
    return `M${pts[0]!.x.toFixed(1)} ${pts[0]!.y.toFixed(1)} L${pts[1]!.x.toFixed(1)} ${pts[1]!.y.toFixed(1)}`;
  }

  let d = `M${pts[0]!.x.toFixed(1)} ${pts[0]!.y.toFixed(1)}`;
  for (let i = 0; i < pts.length - 1; i += 1) {
    const p0 = pts[Math.max(0, i - 1)]!;
    const p1 = pts[i]!;
    const p2 = pts[i + 1]!;
    const p3 = pts[Math.min(pts.length - 1, i + 2)]!;
    const cp1x = p1.x + (p2.x - p0.x) / 6;
    const cp1y = p1.y + (p2.y - p0.y) / 6;
    const cp2x = p2.x - (p3.x - p1.x) / 6;
    const cp2y = p2.y - (p3.y - p1.y) / 6;
    d += ` C${cp1x.toFixed(1)} ${cp1y.toFixed(1)} ${cp2x.toFixed(1)} ${cp2y.toFixed(1)} ${p2.x.toFixed(1)} ${p2.y.toFixed(1)}`;
  }
  return d;
}
