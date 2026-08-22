#!/usr/bin/env node
/**
 * preflight.js - 生图前的参考图体检
 *
 * 用途：在调 DreamMaker 之前检查参考图清单
 *   1. 文件是否存在
 *   2. 单张是否过大
 *   3. 总大小是否会超 DreamMaker 上限（≈ 15MB 安全线）
 *   4. 是否包含必备的"交互稿"（命名前缀检测）
 *
 * 使用：
 *   node preflight.js "path1;path2;path3"
 *   node preflight.js "auto:3"            # 检查参考图收件箱里最新 3 张
 *
 * 退出码：
 *   0 = 通过
 *   1 = 不存在 / 路径错
 *   2 = 总大小超限
 *   3 = 缺交互稿警告（仅警告，不阻断）
 */
const fs = require('fs');
const path = require('path');

const SAFE_TOTAL_BYTES = 15 * 1024 * 1024; // 15MB 安全线
const HARD_TOTAL_BYTES = 20 * 1024 * 1024; // 20MB 硬上限（实测）
const REF_INBOX = 'F:\\codemaker\\参考图';

function fmtMB(n) { return (n / 1024 / 1024).toFixed(2) + ' MB'; }

function resolveAuto(spec) {
  const m = /^auto(?::(\d+))?$/i.exec(spec);
  if (!m) return null;
  const limit = m[1] ? parseInt(m[1]) : Infinity;
  if (!fs.existsSync(REF_INBOX)) return [];
  return fs.readdirSync(REF_INBOX)
    .filter(f => /\.(png|jpe?g|webp)$/i.test(f))
    .map(f => ({ p: path.join(REF_INBOX, f), m: fs.statSync(path.join(REF_INBOX, f)).mtimeMs }))
    .sort((a, b) => b.m - a.m)
    .slice(0, limit)
    .map(x => x.p);
}

function main() {
  const arg = process.argv[2];
  if (!arg) {
    console.error('用法: node preflight.js "path1;path2" 或 "auto:N"');
    process.exit(1);
  }

  let files;
  if (/^auto/i.test(arg)) {
    files = resolveAuto(arg);
  } else {
    files = arg.split(/[;|]/).filter(Boolean);
  }

  if (!files || files.length === 0) {
    console.log('⚠️  没有解析到任何参考图');
    process.exit(0);
  }

  console.log('=== 参考图体检 ===');
  let total = 0;
  let hasInteraction = false;
  let hasOversize = false;
  const list = [];

  for (const f of files) {
    if (!fs.existsSync(f)) {
      console.log(`❌ 不存在: ${f}`);
      process.exit(1);
    }
    const sz = fs.statSync(f).size;
    total += sz;
    const name = path.basename(f);
    const isInter = /交互稿|wireframe|wire-?frame|prototype/i.test(name);
    if (isInter) hasInteraction = true;
    if (sz > 6 * 1024 * 1024) hasOversize = true;
    list.push({ name, sz, isInter });
  }

  list.sort((a, b) => b.sz - a.sz);
  for (const it of list) {
    const tag = it.isInter ? ' [交互稿]' : '';
    const warn = it.sz > 6 * 1024 * 1024 ? ' ⚠️大' : '';
    console.log(`  ${fmtMB(it.sz).padStart(10)}  ${it.name}${tag}${warn}`);
  }
  console.log(`  ----`);
  console.log(`  合计: ${fmtMB(total)} (安全线 ${fmtMB(SAFE_TOTAL_BYTES)} / 硬上限 ${fmtMB(HARD_TOTAL_BYTES)})`);

  // 判断
  if (total >= HARD_TOTAL_BYTES) {
    console.log(`❌ 超过硬上限 ${fmtMB(HARD_TOTAL_BYTES)}，必将 413 报错。请砍掉最大的几张。`);
    console.log(`   建议优先砍：${list[0].name} (${fmtMB(list[0].sz)})`);
    process.exit(2);
  }
  if (total >= SAFE_TOTAL_BYTES) {
    console.log(`⚠️  超过安全线 ${fmtMB(SAFE_TOTAL_BYTES)}，有失败风险。建议砍 ${list[0].name}`);
  } else {
    console.log(`✅ 体积正常`);
  }

  if (!hasInteraction) {
    console.log(`⚠️  没有检测到带"交互稿"前缀的文件。如果本次任务是 UI 界面，请确认布局蓝图是否就位。`);
  } else {
    console.log(`✅ 包含交互稿`);
  }

  process.exit(0);
}

main();
