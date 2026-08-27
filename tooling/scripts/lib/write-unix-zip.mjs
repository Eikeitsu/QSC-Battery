import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { crc32, deflateRawSync, inflateRawSync } from "node:zlib";

function walkFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const abs = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walkFiles(abs));
    else out.push(abs);
  }
  return out;
}

function toUnixPath(root, abs) {
  return relative(root, abs).split(sep).join("/");
}

function unixFileMode(unixPath) {
  const base = unixPath.split("/").pop() || "";
  const exec =
    unixPath.endsWith(".sh") ||
    base === "update-binary" ||
    base === "updater-script" ||
    // 原生事件等待器：qscd/qscdc + 可选 ABI 后缀，安装时改名为 bin/qscd
    /^qscdc?(-[a-z0-9]+)?$/.test(base);
  return exec ? 0o100755 : 0o100644;
}

function dosDateTime(date) {
  const year = Math.max(date.getFullYear() - 1980, 0);
  const dosDate = (year << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
  const dosTime =
    (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
  return { dosDate, dosTime };
}

/**
 * 写出带 Unix 权限的 Deflate zip（Win/Linux 同一格式，避免 Compress-Archive）。
 * @returns {string[]} 归档内路径
 */
export function writeUnixZip(rootDir, zipPath) {
  const files = walkFiles(rootDir)
    .map((abs) => ({ abs, name: toUnixPath(rootDir, abs) }))
    .filter((item) => item.name && !item.name.endsWith("/"))
    .sort((a, b) => a.name.localeCompare(b.name));

  const now = dosDateTime(new Date());
  const locals = [];
  const records = [];
  let offset = 0;

  for (const { abs, name } of files) {
    const data = readFileSync(abs);
    const deflated = data.length ? deflateRawSync(data) : data;
    const store = !data.length || deflated.length >= data.length;
    const payload = store ? data : deflated;
    const method = store ? 0 : 8;
    const crc = crc32(data) >>> 0;
    const nameBuf = Buffer.from(name, "utf8");
    const mode = unixFileMode(name);

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(now.dosTime, 10);
    local.writeUInt16LE(now.dosDate, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(payload.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);

    const block = Buffer.concat([local, nameBuf, payload]);
    locals.push(block);
    records.push({
      name,
      nameBuf,
      method,
      crc,
      comp: payload.length,
      uncomp: data.length,
      offset,
      mode,
      payload,
      data,
    });
    offset += block.length;
  }

  const cdStart = offset;
  const cdParts = [];
  for (const r of records) {
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(0x0314, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(r.method, 10);
    central.writeUInt16LE(now.dosTime, 12);
    central.writeUInt16LE(now.dosDate, 14);
    central.writeUInt32LE(r.crc, 16);
    central.writeUInt32LE(r.comp, 20);
    central.writeUInt32LE(r.uncomp, 24);
    central.writeUInt16LE(r.nameBuf.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE((r.mode << 16) >>> 0, 38);
    central.writeUInt32LE(r.offset, 42);
    cdParts.push(central, r.nameBuf);
  }
  const cd = Buffer.concat(cdParts);

  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(records.length, 8);
  eocd.writeUInt16LE(records.length, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(cdStart, 16);

  writeFileSync(zipPath, Buffer.concat([...locals, cd, eocd]));
  return records;
}

export function verifyUnixZip(zipPath, requiredNames) {
  const buf = readFileSync(zipPath);
  if (buf.length < 22) throw new Error("zip too small");
  const eocd = buf.length - 22;
  if (buf.readUInt32LE(eocd) !== 0x06054b50) {
    throw new Error("zip EOCD not found (comment not supported in verifier)");
  }
  const count = buf.readUInt16LE(eocd + 10);
  const cdSize = buf.readUInt32LE(eocd + 12);
  const cdOff = buf.readUInt32LE(eocd + 16);
  const names = [];
  let p = cdOff;
  const cdEnd = cdOff + cdSize;
  for (let i = 0; i < count; i++) {
    if (p + 46 > cdEnd || buf.readUInt32LE(p) !== 0x02014b50) {
      throw new Error("zip central directory corrupt");
    }
    const method = buf.readUInt16LE(p + 10);
    const crc = buf.readUInt32LE(p + 16);
    const comp = buf.readUInt32LE(p + 20);
    const uncomp = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const localOff = buf.readUInt32LE(p + 42);
    const name = buf.subarray(p + 46, p + 46 + nameLen).toString("utf8");
    if (name.includes("\\")) throw new Error(`zip entry has backslash: ${name}`);
    names.push(name);

    const localSig = buf.readUInt32LE(localOff);
    if (localSig !== 0x04034b50) throw new Error(`bad local header: ${name}`);
    const localNameLen = buf.readUInt16LE(localOff + 26);
    const localExtraLen = buf.readUInt16LE(localOff + 28);
    const dataStart = localOff + 30 + localNameLen + localExtraLen;
    const payload = buf.subarray(dataStart, dataStart + comp);
    const raw = method === 0 ? payload : inflateRawSync(payload);
    if (raw.length !== uncomp) throw new Error(`size mismatch: ${name}`);
    if (crc32(raw) >>> 0 !== crc) throw new Error(`crc mismatch: ${name}`);

    p += 46 + nameLen + extraLen + commentLen;
  }

  for (const need of requiredNames) {
    if (!names.includes(need)) throw new Error(`zip missing ${need}`);
  }
  return names;
}
