#!/usr/bin/env node
/**
 * register-lobsterai.js
 *
 * 把 g99-ui-design / dreammaker-image-gen / image-view / clipboard-to-ref / web-fetch
 * 这 5 个 skill 注册到 LobsterAI 的 skills.config.json。
 *
 * LobsterAI 不会自动扫描 SKILLs 目录，必须在此配置里显式注册 + enabled=true
 * 才会被 Agent 读取。
 *
 * 用法：
 *   node register-lobsterai.js              # 默认注册到 %APPDATA%\LobsterAI\SKILLs\skills.config.json
 *   node register-lobsterai.js <config_path>
 *
 * 特性：
 *   - 幂等：已存在的条目不覆盖（保留用户自定义 order 和 enabled 状态）
 *   - 自动备份原文件到 .bak-<timestamp>
 *   - 配置不存在时自动创建最小可用配置
 */
const fs = require('fs');
const path = require('path');

const SKILLS_TO_REGISTER = [
  { name: 'g99-ui-design',        order: 400 },
  { name: 'dreammaker-image-gen', order: 401 },
  { name: 'image-view',           order: 402 },
  { name: 'clipboard-to-ref',     order: 403 },
  { name: 'web-fetch',            order: 404 },
];

function resolveConfigPath() {
  if (process.argv[2]) return process.argv[2];
  const appdata = process.env.APPDATA;
  if (!appdata) {
    console.error('[X] %APPDATA% 环境变量不存在（非 Windows？）');
    process.exit(1);
  }
  return path.join(appdata, 'LobsterAI', 'SKILLs', 'skills.config.json');
}

function loadOrCreate(p) {
  if (!fs.existsSync(p)) {
    console.log(`[!] 配置文件不存在，创建最小配置: ${p}`);
    const dir = path.dirname(p);
    fs.mkdirSync(dir, { recursive: true });
    return {
      version: 1,
      description: 'LobsterAI skill configuration (auto-created by G99 installer)',
      defaults: {},
    };
  }
  const raw = fs.readFileSync(p, 'utf8');
  try {
    return JSON.parse(raw);
  } catch (e) {
    console.error(`[X] 配置文件不是合法 JSON: ${e.message}`);
    process.exit(2);
  }
}

function backup(p) {
  if (!fs.existsSync(p)) return;
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const bak = `${p}.bak-${ts}`;
  fs.copyFileSync(p, bak);
  console.log(`[OK] 已备份到 ${path.basename(bak)}`);
}

function main() {
  const configPath = resolveConfigPath();
  console.log(`[..] 目标配置: ${configPath}`);

  // 检查父目录（是否 LobsterAI 已安装）
  const parent = path.resolve(configPath, '..', '..'); // ...\LobsterAI\
  if (!fs.existsSync(parent)) {
    console.log(`[--] LobsterAI 未安装，跳过注册`);
    process.exit(0);
  }

  backup(configPath);
  const cfg = loadOrCreate(configPath);
  if (!cfg.defaults || typeof cfg.defaults !== 'object') cfg.defaults = {};

  let added = 0, kept = 0;
  for (const s of SKILLS_TO_REGISTER) {
    if (cfg.defaults[s.name]) {
      console.log(`    [=] ${s.name} 已存在，保留现有配置`);
      kept++;
    } else {
      cfg.defaults[s.name] = { order: s.order, enabled: true };
      console.log(`    [+] ${s.name} 已注册`);
      added++;
    }
  }

  fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2), 'utf8');
  console.log(`[OK] 完成：新增 ${added} 条，保留 ${kept} 条，总计 ${Object.keys(cfg.defaults).length} 个 skill`);
  console.log('[!] 重启 LobsterAI 后生效');
}

main();
