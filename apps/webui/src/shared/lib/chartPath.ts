/** 按时间等距降采样：沿时间轴均匀取 max 份，每份取最靠近样本时间点的数据，
 *  避免原有「按索引跨步」在采样密度不均时丢掉长放电段。首尾点必保。 */
export function downsampleByTime<T extends { ts: number }>(
  points: T[],
  maxPoints = 120,
): T[] {
  if (points.length <= maxPoints || maxPoints <= 1) {
    return points.slice();
  }
  const first = points[0]!;
  const last = points[points.length - 1]!;
  if (first.ts === last.ts) {
    return [first, last];
  }
  const step = (last.ts - first.ts) / (maxPoints - 1);
  const out: T[] = [first];
  let cursor = 1;
  for (let slot = 1; slot < maxPoints - 1; slot += 1) {
    const target = first.ts + slot * step;
    let bestIdx = cursor;
    let bestDist = Math.abs(points[cursor]!.ts - target);
    for (let i = cursor + 1; i < points.length; i += 1) {
      const d = Math.abs(points[i]!.ts - target);
      if (d <= bestDist) {
        bestDist = d;
        bestIdx = i;
      } else {
        break;
      }
    }
    if (bestIdx !== cursor || out[out.length - 1] !== points[bestIdx]) {
      out.push(points[bestIdx]!);
    }
    cursor = Math.min(bestIdx + 1, points.length - 1);
  }
  if (out[out.length - 1] !== last) out.push(last);
  return out;
}

/** 兼容旧调用：直接按索引跨步。若调用者已按时间等距或无需保形，仍可使用；
 *  新代码统一走 downsampleByTime。 */
export function downsamplePoints<T extends { ts: number }>(points: T[], max = 120): T[] {
  if (points.length <= max) return points.slice();
  if (max <= 1) return [points[points.length - 1]!];

  const out: T[] = [];
  const step = (points.length - 1) / (max - 1);
  for (let i = 0; i < max; i += 1) {
    out.push(points[Math.round(i * step)]!);
  }
  return out;
}

/** 单调三次 Hermite（Fritsch-Carlson）插值生成 SVG cubic Bezier path。
 *  默认单调性仅在 y 为单调时生效；否则退化为标准 Hermite，仍无 Catmull-Rom 的过冲。*/
export function buildSmoothPath<T>(
  list: T[],
  xAt: (point: T) => number,
  yAt: (point: T) => number,
  monotonic = true,
): string {
  if (list.length < 2) return "";

  const pts = list.map((point) => ({ x: xAt(point), y: yAt(point) }));
  if (pts.length === 2) {
    return `M${pts[0]!.x.toFixed(1)} ${pts[0]!.y.toFixed(1)} L${pts[1]!.x.toFixed(1)} ${pts[1]!.y.toFixed(1)}`;
  }

  const n = pts.length;
  const dx: number[] = new Array(n - 1);
  const dy: number[] = new Array(n - 1);
  const slope: number[] = new Array(n - 1);
  for (let i = 0; i < n - 1; i += 1) {
    dx[i] = pts[i + 1]!.x - pts[i]!.x;
    dy[i] = pts[i + 1]!.y - pts[i]!.y;
    slope[i] = dx[i] === 0 ? 0 : dy[i]! / dx[i]!;
  }

  const m: number[] = new Array(n);
  // 端点切向：单侧差商（若邻居存在则合并）
  m[0] = slope[0]!;
  m[n - 1] = slope[n - 2]!;
  for (let i = 1; i < n - 1; i += 1) {
    m[i] = (slope[i - 1]! + slope[i]!) / 2;
  }

  // Fritsch-Carlson 单调化：相邻段斜率异号则该点切向置 0；否则按 Fritsch-Carlson
  // 式 (9) 约束，保证曲线不过冲。
  if (monotonic) {
    for (let i = 0; i < n - 1; i += 1) {
      if (slope[i] === 0) {
        m[i] = 0;
        m[i + 1] = 0;
      } else if (i > 0 && slope[i - 1]! < 0 !== slope[i]! < 0) {
        m[i] = 0;
      } else if (i > 0) {
        const alpha = m[i - 1]! / slope[i - 1]!;
        const beta = m[i]! / slope[i - 1]!;
        if (alpha * alpha + beta * beta > 9) {
          const tau = 3 / Math.hypot(alpha, beta);
          m[i - 1] = tau * alpha * slope[i - 1]!;
          m[i] = tau * beta * slope[i - 1]!;
        }
      }
      if (i === n - 2 && i > 0) {
        const alpha = m[i]! / slope[i]!;
        const beta = m[i + 1]! / slope[i]!;
        if (alpha * alpha + beta * beta > 9) {
          const tau = 3 / Math.hypot(alpha, beta);
          m[i] = tau * alpha * slope[i]!;
          m[i + 1] = tau * beta * slope[i]!;
        }
      }
    }
  }

  const H3_FIX = 1 / 3; // Hermite 切向缩放到 Bezier 控制点：t=1/3 处切向量匹配
  let d = `M${pts[0]!.x.toFixed(1)} ${pts[0]!.y.toFixed(1)}`;
  for (let i = 0; i < n - 1; i += 1) {
    const p1 = pts[i]!;
    const p2 = pts[i + 1]!;
    const seg = dx[i]!;
    const cp1x = p1.x + seg * H3_FIX;
    const cp1y = p1.y + seg * H3_FIX * (m[i] ?? 0);
    const cp2x = p2.x - seg * H3_FIX;
    const cp2y = p2.y - seg * H3_FIX * (m[i + 1] ?? 0);
    d += ` C${cp1x.toFixed(1)} ${cp1y.toFixed(1)} ${cp2x.toFixed(1)} ${cp2y.toFixed(1)} ${p2.x.toFixed(1)} ${p2.y.toFixed(1)}`;
  }
  return d;
}
