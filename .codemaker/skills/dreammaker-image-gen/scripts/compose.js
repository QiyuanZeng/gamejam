#!/usr/bin/env node
/**
 * compose.js - 把"原件素材"（如 IP 卡牌、Logo、立绘）按指定坐标贴到 AI 生成的底图上
 *
 * 用途：解决"AI 不能稳定重画 IP 角色，但可以画容器"的工作流。
 *   流程：AI 生 UI 容器 → 这个脚本把原件贴上去 → 出最终成品
 *
 * 零外部依赖：只用 Node 内置 zlib + 自写 PNG 编解码（仅支持 RGBA8 / RGB8 PNG）。
 * 大型项目建议用 sharp，但本仓库为了零依赖先用纯 Node。
 *
 * 使用：
 *   node compose.js <底图.png> <原件.png> <x,y> [--scale=0.6] [--out=最终.png]
 *
 * 例：
 *   node compose.js base_A.png card.png 60,180 --scale=0.55 --out=final_A.png
 *
 * 注意：
 *   - x,y 是原件左上角在底图上的坐标
 *   - scale = 1 表示原件按原尺寸贴，0.5 表示缩到一半
 *   - 缩放用最近邻（够用，IP 卡牌本来就清晰）
 */
const fs = require('fs');
const zlib = require('zlib');

function crc32(buf) {
  let c, table = [];
  for (let n = 0; n < 256; n++) {
    c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    table[n] = c;
  }
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function readPng(filePath) {
  const data = fs.readFileSync(filePath);
  if (data.readUInt32BE(0) !== 0x89504e47) throw new Error('not png: ' + filePath);
  let pos = 8;
  let width = 0, height = 0, bitDepth = 8, colorType = 6;
  const idatChunks = [];
  while (pos < data.length) {
    const len = data.readUInt32BE(pos);
    const type = data.slice(pos + 4, pos + 8).toString('ascii');
    const chunkData = data.slice(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      width = chunkData.readUInt32BE(0);
      height = chunkData.readUInt32BE(4);
      bitDepth = chunkData[8];
      colorType = chunkData[9];
    } else if (type === 'IDAT') {
      idatChunks.push(chunkData);
    } else if (type === 'IEND') break;
    pos += 12 + len;
  }
  if (bitDepth !== 8) throw new Error('only 8-bit png supported');
  if (colorType !== 6 && colorType !== 2) throw new Error('only RGBA / RGB png supported');
  const channels = colorType === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idatChunks));
  const stride = width * channels;
  const px = Buffer.alloc(width * height * 4);
  let prevRow = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const row = raw.slice(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride);
    const cur = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const left = x >= channels ? cur[x - channels] : 0;
      const up = prevRow[x];
      const upLeft = x >= channels ? prevRow[x - channels] : 0;
      let v;
      switch (filter) {
        case 0: v = row[x]; break;
        case 1: v = (row[x] + left) & 0xff; break;
        case 2: v = (row[x] + up) & 0xff; break;
        case 3: v = (row[x] + ((left + up) >> 1)) & 0xff; break;
        case 4: {
          const p = left + up - upLeft;
          const pa = Math.abs(p - left), pb = Math.abs(p - up), pc = Math.abs(p - upLeft);
          let pr;
          if (pa <= pb && pa <= pc) pr = left;
          else if (pb <= pc) pr = up;
          else pr = upLeft;
          v = (row[x] + pr) & 0xff;
          break;
        }
        default: throw new Error('bad filter ' + filter);
      }
      cur[x] = v;
    }
    prevRow = cur;
    for (let x = 0; x < width; x++) {
      const si = x * channels;
      const di = (y * width + x) * 4;
      px[di] = cur[si];
      px[di + 1] = cur[si + 1];
      px[di + 2] = cur[si + 2];
      px[di + 3] = channels === 4 ? cur[si + 3] : 255;
    }
  }
  return { width, height, px };
}

function writePng(filePath, width, height, px) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0;
    px.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const idat = zlib.deflateSync(raw);
  function chunk(type, data) {
    const buf = Buffer.alloc(12 + data.length);
    buf.writeUInt32BE(data.length, 0);
    buf.write(type, 4, 'ascii');
    data.copy(buf, 8);
    const crcBuf = Buffer.concat([Buffer.from(type), data]);
    buf.writeUInt32BE(crc32(crcBuf), 8 + data.length);
    return buf;
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  fs.writeFileSync(filePath, Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]));
}

function scaleNearest(src, sw, sh, dw, dh) {
  const dst = Buffer.alloc(dw * dh * 4);
  for (let y = 0; y < dh; y++) {
    for (let x = 0; x < dw; x++) {
      const sx = Math.min(sw - 1, Math.floor(x * sw / dw));
      const sy = Math.min(sh - 1, Math.floor(y * sh / dh));
      const si = (sy * sw + sx) * 4;
      const di = (y * dw + x) * 4;
      dst[di] = src[si];
      dst[di + 1] = src[si + 1];
      dst[di + 2] = src[si + 2];
      dst[di + 3] = src[si + 3];
    }
  }
  return dst;
}

function compose(basePx, bw, bh, overPx, ow, oh, x, y) {
  for (let oy = 0; oy < oh; oy++) {
    const by = y + oy;
    if (by < 0 || by >= bh) continue;
    for (let ox = 0; ox < ow; ox++) {
      const bx = x + ox;
      if (bx < 0 || bx >= bw) continue;
      const oi = (oy * ow + ox) * 4;
      const bi = (by * bw + bx) * 4;
      const a = overPx[oi + 3] / 255;
      if (a < 0.001) continue;
      basePx[bi] = Math.round(overPx[oi] * a + basePx[bi] * (1 - a));
      basePx[bi + 1] = Math.round(overPx[oi + 1] * a + basePx[bi + 1] * (1 - a));
      basePx[bi + 2] = Math.round(overPx[oi + 2] * a + basePx[bi + 2] * (1 - a));
      basePx[bi + 3] = Math.max(basePx[bi + 3], overPx[oi + 3]);
    }
  }
}

function main() {
  const args = process.argv.slice(2);
  if (args.length < 3) {
    console.error('用法: node compose.js <底图.png> <原件.png> <x,y> [--scale=0.6] [--out=...]');
    process.exit(1);
  }
  const basePath = args[0];
  const overPath = args[1];
  const [x, y] = args[2].split(',').map(Number);
  let scale = 1, out = 'composed.png';
  for (const a of args.slice(3)) {
    if (a.startsWith('--scale=')) scale = parseFloat(a.slice(8));
    else if (a.startsWith('--out=')) out = a.slice(6);
  }
  console.log(`📦 底图 : ${basePath}`);
  console.log(`📦 原件 : ${overPath} (scale=${scale})`);
  console.log(`📍 坐标 : ${x},${y}`);

  const base = readPng(basePath);
  const over = readPng(overPath);
  let overPx = over.px, ow = over.width, oh = over.height;
  if (Math.abs(scale - 1) > 1e-3) {
    const dw = Math.round(ow * scale);
    const dh = Math.round(oh * scale);
    overPx = scaleNearest(overPx, ow, oh, dw, dh);
    ow = dw; oh = dh;
  }
  compose(base.px, base.width, base.height, overPx, ow, oh, x, y);
  writePng(out, base.width, base.height, base.px);
  console.log(`✅ 已写入: ${out}`);
}

main();
