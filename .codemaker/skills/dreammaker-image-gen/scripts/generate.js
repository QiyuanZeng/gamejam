/**
 * DreamMaker 通用生图脚本
 *
 * 用法:
 *   node generate.js "" "<prompt>" "<prefix>" "<checkpoint>" "<count>" "<ref_image_path>" [--background]
 *
 * 参数说明（均可留空 "" 使用默认值）:
 *   argv[2]  x-access-token   留空自动读 .token 文件
 *   argv[3]  prompt           生图描述（推荐中文，对 G99 任务必须中文）
 *   argv[4]  输出文件名前缀    多张时自动加 -1 -2 后缀，默认 dm-<时间戳>
 *   argv[5]  checkpoint       模型名，默认从 .config.json 的 defaultCheckpoint 读取
 *   argv[6]  count            生成张数，默认 1
 *   argv[7]  参考图参数        三种写法：
 *                                - 单张：  "C:/input.png"
 *                                - 多张：  "C:/a.png;C:/b.png"  (分号或竖线分隔)
 *                                - 自动：  "auto" 或 "auto:N"  (取 F:\codemaker\参考图\ 下最新 N 张)
 *
 * 标志位（出现在任意位置即生效）:
 *   --background  后台子代理模式：spawn detached 子进程跑生图，主进程立刻退出
 *                 返回 task_id + 日志路径，配合 status.js 查询结果
 *   --4K          生成 2048×2048 高清图
 *   --check       仅检查环境（代理 + token），不生图
 *
 * 示例:
 *   node generate.js "" "一只蓝色猫咪" "cat" "" "4"
 *   node generate.js "" "..." "out" "" "4" "auto:2"
 *   node generate.js "" "..." "out" "" "4" "auto:2" --background
 *
 * 前提: proxy.js 已在 127.0.0.1:7788 运行
 */

const http   = require('http');
const fs     = require('fs');
const path   = require('path');
const { spawn } = require('child_process');

// ══════════════════════════════════════════════════════════════
//  ⚙️  配置区（默认值均为空，请通过 .config.json 填写个人信息）
// ══════════════════════════════════════════════════════════════
const CONFIG = {
  aigwApp:  '',   // 内部应用 ID，通过 .config.json 配置
  authUser: '',   // 你的工号/用户名，通过 .config.json 配置
  groupId:  '',   // 你的项目 Group ID，通过 .config.json 配置
  defaultToken: '',
};

// ── 从 .config.json 加载用户配置（优先级高于 CONFIG 默认值）──────
const CONFIG_FILE = path.join(__dirname, '..', '.config.json');
if (fs.existsSync(CONFIG_FILE)) {
  try {
    const userCfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    if (userCfg.aigwApp)  CONFIG.aigwApp  = userCfg.aigwApp;
    if (userCfg.authUser) CONFIG.authUser = userCfg.authUser;
    if (userCfg.groupId)  CONFIG.groupId  = userCfg.groupId;
    if (userCfg.authKey)  CONFIG.authKey  = userCfg.authKey;
    if (userCfg.authKeyUser) CONFIG.authKeyUser = userCfg.authKeyUser;
    if (userCfg.defaultCheckpoint) CONFIG.defaultCheckpoint = userCfg.defaultCheckpoint;
  } catch (e) {
    console.warn('⚠️  .config.json 解析失败:', e.message);
  }
}
// ══════════════════════════════════════════════════════════════

const DM_BASE    = 'https://dreammaker.netease.com';
const AUTH_API   = 'http://auth.nie.netease.com/api/v2/tokens';
const OUT_DIR    = process.env.DM_OUTPUT_DIR || 'F:\\codemaker\\设计生成';
const TOKEN_FILE = path.join(__dirname, '..', '.token');

// ── 通过 auth key 自动生成 access token ───────────────────────
function fetchTokenByAuthKey(authKeyUser, authKey, ttl) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ user: authKeyUser, key: authKey, ttl: ttl || 86400 });
    const url  = new URL(AUTH_API);
    const options = {
      hostname: url.hostname,
      port:     url.port || 80,
      path:     url.pathname,
      method:   'POST',
      headers:  { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    };
    const req = http.request(options, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        try {
          const data = JSON.parse(Buffer.concat(chunks).toString());
          if (data.token) resolve(data.token);
          else reject(new Error('auth key 换取 token 失败: ' + JSON.stringify(data)));
        } catch (e) { reject(e); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ── Token 读取（优先级：命令行参数 > .token 文件 > CONFIG.defaultToken）──
// 注意：auth key 自动生成的 token 在 main() 中异步处理，这里只做同步读取
function loadToken() {
  // 1. 命令行参数
  if (process.argv[2] && process.argv[2].trim()) return process.argv[2].trim();
  // 2. .token 文件（存放在 skill 根目录）
  if (fs.existsSync(TOKEN_FILE)) {
    const t = fs.readFileSync(TOKEN_FILE, 'utf8').trim();
    if (t) { console.log('🔑 已从 .token 文件加载 token'); return t; }
  }
  // 3. CONFIG 内置默认值
  return CONFIG.defaultToken;
}

// 命令行参数（TOKEN 可能在 main() 中被 auth key 覆盖，用 let）
let TOKEN        = loadToken();
const PROMPT     = process.argv[3] || 'pure black background, 4 wide white radial beams from right side, minimal manga style, flat graphic';
const OUT_PREFIX = process.argv[4] || ('dm-' + Date.now());  // 多张时作为文件名前缀
const CHECKPOINT = process.argv[5] || CONFIG.defaultCheckpoint || 'nano-banana-pro';
const COUNT      = Math.max(1, parseInt(process.argv[6]) || 1);  // 生成张数
const REF_IMAGE  = process.argv[7] || '';  // 参考图路径（可选）
const IS_4K      = process.argv[8] === '4K' || process.argv[8] === '4k';  // 是否 4K

// ── 工具函数 ──────────────────────────────────────────────────

function getDmHeaders() {
  return {
    'Content-Type':   'application/json',
    'x-aigw-app':     CONFIG.aigwApp,
    'x-access-token': TOKEN,
    'x-auth-user':    CONFIG.authUser,
    'x-group-id':     CONFIG.groupId,
    'x-source':       'frontEnd',
  };
}

/** 通过本地代理发请求，返回 { status, body: Buffer } */
function proxyFetch(method, targetUrl, headers, bodyStr) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({ method, url: targetUrl, headers, body: bodyStr || null });
    const options = {
      hostname: '127.0.0.1', port: 7788, path: '/proxy', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
    };
    const req = http.request(options, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks) }));
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function checkProxy() {
  return new Promise(resolve => {
    http.get('http://127.0.0.1:7788/health', () => resolve(true)).on('error', () => resolve(false));
  });
}

/** 自动在后台启动 proxy.js，等待最多 5 秒直到代理上线 */
async function autoStartProxy() {
  const proxyScript = path.join(__dirname, 'proxy.js');
  console.log('🚀 正在自动启动代理...');
  spawn(process.execPath, [proxyScript], {
    detached: true, stdio: 'ignore', windowsHide: true,
  }).unref();
  // 等待代理就绪（最多 5 秒）
  for (let i = 0; i < 10; i++) {
    await sleep(500);
    if (await checkProxy()) {
      console.log('✅ 代理已自动启动 (127.0.0.1:7788)');
      return true;
    }
  }
  return false;
}

/** 检测 token 是否过期，返回 { valid, expired, daysLeft, expireStr } */
function checkTokenExpiry(token) {
  try {
    const payload = token.split('.')[1];
    const decoded = JSON.parse(Buffer.from(payload, 'base64').toString('utf8'));
    if (!decoded.exp) return { valid: true, expired: false, daysLeft: null, expireStr: '无过期时间' };
    const now      = Math.floor(Date.now() / 1000);
    const daysLeft = Math.floor((decoded.exp - now) / 86400);
    const expireStr = new Date(decoded.exp * 1000).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' });
    return { valid: true, expired: decoded.exp < now, daysLeft, expireStr };
  } catch (_) {
    return { valid: false, expired: false, daysLeft: null, expireStr: '无法解析' };
  }
}

// ── 核心步骤 ──────────────────────────────────────────────────

/** 读取本地图片并转为 base64 data URL */
function loadRefImage(imgPath) {
  if (!imgPath || !fs.existsSync(imgPath)) return null;
  const ext  = path.extname(imgPath).toLowerCase().replace('.', '') || 'png';
  const mime = ext === 'jpg' ? 'image/jpeg' : `image/${ext}`;
  const b64  = fs.readFileSync(imgPath).toString('base64');
  return `data:${mime};base64,${b64}`;
}

/**
 * 解析参考图参数为多个本地路径数组
 * 支持：单张路径 / 多张分号分隔 / "auto" / "auto:N"
 */
const REF_INBOX = process.env.DM_REF_INBOX || 'F:\\codemaker\\参考图';

function resolveRefPaths(arg) {
  if (!arg) return [];
  const raw = String(arg).trim();
  if (!raw) return [];

  // auto 模式：取参考图收件箱里最新 N 张
  const autoMatch = raw.match(/^auto(?::(\d+))?$/i);
  if (autoMatch) {
    if (!fs.existsSync(REF_INBOX)) {
      console.warn('⚠️  参考图收件箱不存在: ' + REF_INBOX);
      return [];
    }
    const n = autoMatch[1] ? parseInt(autoMatch[1]) : 99;
    const exts = new Set(['.png', '.jpg', '.jpeg', '.webp']);
    const files = fs.readdirSync(REF_INBOX)
      .map(f => path.join(REF_INBOX, f))
      .filter(p => {
        try { return fs.statSync(p).isFile() && exts.has(path.extname(p).toLowerCase()); }
        catch (_) { return false; }
      })
      .map(p => ({ p, mtime: fs.statSync(p).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime)
      .slice(0, n)
      .map(x => x.p);
    if (!files.length) console.warn('⚠️  参考图收件箱为空: ' + REF_INBOX);
    return files;
  }

  // 显式路径：支持分号或竖线分隔
  return raw.split(/[;|]/).map(s => s.trim()).filter(Boolean);
}

async function submitTask(prompt, count, refImageArg, is4K) {
  const refPaths = resolveRefPaths(refImageArg);

  // 尺寸：4K = 2048×2048，普通 = 1024×768
  const w = is4K ? 2048 : 1024;
  const h = is4K ? 2048 : 768;
  const sizeStr = is4K ? '2K' : '1K';

  // control 数组：每张参考图一个条目
  const control = refPaths.map((p, idx) => {
    const b64 = loadRefImage(p);
    if (!b64) {
      console.warn('⚠️  参考图读取失败: ' + p);
      return null;
    }
    console.log('🖼️  参考图 [' + (idx + 1) + '/' + refPaths.length + ']: ' + p);
    return {
      name:            '参考原图' + (refPaths.length > 1 ? ('_' + (idx + 1)) : ''),
      annotator:       'i2i',
      cn_type:         '参考原图',
      image:           b64,
      key:             '',
      mask:            '',
      model_version:   'nano-banana',
      original_basemap:'',
      resize_height:   h,
      resize_width:    w,
      value:           'i2i',
      area_mask:       '',
      can_draw:        true,
    };
  }).filter(Boolean);

  const hasRef = control.length > 0;

  const reqBody = {
    prompt, negative_prompt: '',
    cfg_scale: 7, seed: -1, steps: 25,
    checkpoint: CHECKPOINT,
    width: w, height: h,
    ar: is4K ? '1:1' : '4:3',
    size_str: sizeStr,
    n_iter:     count,
    batch_size: 1,
    clip_skip:  2,
    client_id:  '475966792',
    enable_hr:  false,
    enable_multi_diffusion: false,
    prompt_upsampling: false,
    denoising_strength: hasRef ? 0.7 : undefined,
    lora: [],
    control,
    miniConImgs: [],
    command_system: '',
    vae: '',
    overlap: 64,
    ...(CHECKPOINT.includes('gpt-image') ? { background: 'opaque' } : {}),
  };
  // 移除 undefined 字段
  Object.keys(reqBody).forEach(k => reqBody[k] === undefined && delete reqBody[k]);

  const res  = await proxyFetch('POST', DM_BASE + '/sunshine_flow/COMMON/2d/generate', getDmHeaders(), JSON.stringify(reqBody));
  const data = JSON.parse(res.body.toString());
  if (data.code !== 0) throw new Error('提交失败: ' + JSON.stringify(data));
  return data.data.task_id;
}

async function pollTask(taskId, maxWaitMs = 600000) {
  const deadline = Date.now() + maxWaitMs;
  while (Date.now() < deadline) {
    await sleep(4000);
    const res   = await proxyFetch('GET',
      DM_BASE + '/sunshine_flow/COMMON/2d/records?group_id=' + CONFIG.groupId + '&pageNum=1&pageSize=20',
      getDmHeaders(), null
    );
    const data  = JSON.parse(res.body.toString());
    const items = (data.data && data.data.items) || [];
    const item  = items.find(i => i.task_id === taskId);
    if (!item) { process.stdout.write('.'); continue; }
    if (item.status === 'success') {
      // 返回全部图片路径（batch 多张）
      const imgPaths = (item.images || []).filter(p => p && p.length > 5);
      if (!imgPaths.length) throw new Error('任务成功但无图片路径');
      return imgPaths;
    }
    if (item.status === 'failed' || item.status === 'error') {
      throw new Error('生图失败: ' + (item.message || '未知'));
    }
    process.stdout.write('⏳');
  }
  throw new Error('生图超时（180s）');
}

async function downloadImage(imgPath, outFile) {
  const targetUrl = imgPath.startsWith('http') ? imgPath : DM_BASE + '/' + imgPath;
  const headers = {
    'x-access-token': TOKEN,
    'x-aigw-app':     CONFIG.aigwApp,
    'x-proxy-cookie': 'ACCESS_TOKEN=' + TOKEN + '; AUTH_USER=' + CONFIG.authUser,
  };
  const res = await proxyFetch('GET', targetUrl, headers, null);
  if (res.body[0] !== 0x89 && res.body[0] !== 0xFF) {
    throw new Error('下载内容非图片，可能 token 已过期。响应前200字节:\n' + res.body.slice(0, 200).toString());
  }
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(outFile, res.body);
  console.log('\n✅ 已保存: ' + outFile + '  (' + Math.round(res.body.length / 1024) + ' KB)');
}

// ── 首次配置引导 ──────────────────────────────────────────────

/** 读取一行用户输入（标准输入） */
function readLine(prompt) {
  return new Promise(resolve => {
    process.stdout.write(prompt);
    let buf = '';
    const onData = chunk => {
      buf += chunk.toString();
      const idx = buf.indexOf('\n');
      if (idx !== -1) {
        process.stdin.removeListener('data', onData);
        process.stdin.pause();
        resolve(buf.slice(0, idx).replace(/\r$/, '').trim());
      }
    };
    process.stdin.resume();
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', onData);
  });
}

/**
 * 检查是否缺少必要配置，若缺少则打印引导并交互式收集，写入 .config.json
 * 只在非 --check 模式下触发
 */
async function ensureConfig() {
  const missing = !CONFIG.authKey || !CONFIG.authUser || !CONFIG.aigwApp;
  if (!missing) return;

  console.log('\n╔══════════════════════════════════════════════════════════╗');
  console.log('║              🎨  DreamMaker 首次配置引导                 ║');
  console.log('╚══════════════════════════════════════════════════════════╝\n');
  console.log('我将通过网易 DreamMaker 为你生成图片，');
  console.log('需要先完成一次认证配置。请按以下步骤提供三项信息');
  console.log('（只需配置一次，后续会自动读取）：\n');

  console.log('─────────────────────────────────────────────────────────');
  console.log('1. AUTH_KEY  （Auth 平台密钥）');
  console.log('─────────────────────────────────────────────────────────');
  console.log('   • 打开: https://console-auth.nie.netease.com/');
  console.log('   • 登录后，复制页面上的 v2 token（即 Auth Key）\n');

  const authKey = await readLine('   请输入 AUTH_KEY: ');

  console.log('\n─────────────────────────────────────────────────────────');
  console.log('2. AUTH_USER  （用户名）');
  console.log('─────────────────────────────────────────────────────────');
  console.log('   • 就是你的网易企业邮箱 @ 前面的部分');
  console.log('   • 例如邮箱是 zhangsan01@corp.netease.com，则填写 zhangsan01\n');

  const authUser = await readLine('   请输入 AUTH_USER: ');

  console.log('\n─────────────────────────────────────────────────────────');
  console.log('3. APP_CODE  （用户组 App Code）');
  console.log('─────────────────────────────────────────────────────────');
  console.log('   • 打开: https://dreammaker.netease.com/permission');
  console.log('   • 在用户组管理页面，找到你所在用户组对应的 app_code');
  console.log('   • 格式通常类似 _dm_prod_xxxxxxxxxxxxxxxx\n');

  const aigwApp = await readLine('   请输入 APP_CODE: ');

  // 读取现有配置（避免覆盖其他字段）
  let existing = {};
  if (fs.existsSync(CONFIG_FILE)) {
    try { existing = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')); } catch (_) {}
  }

  const newCfg = Object.assign({}, existing, {
    authKey:     authKey     || existing.authKey     || '',
    authKeyUser: authUser    || existing.authKeyUser || '',
    authUser:    authUser    || existing.authUser    || '',
    aigwApp:     aigwApp     || existing.aigwApp     || '',
  });

  fs.writeFileSync(CONFIG_FILE, JSON.stringify(newCfg, null, 2), 'utf8');

  // 同步到内存 CONFIG
  CONFIG.authKey     = newCfg.authKey;
  CONFIG.authKeyUser = newCfg.authKeyUser;
  CONFIG.authUser    = newCfg.authUser;
  CONFIG.aigwApp     = newCfg.aigwApp;

  console.log('\n✅ 配置已保存到 .config.json，后续运行无需重复填写！\n');
  console.log('══════════════════════════════════════════════════════════\n');
}

// ── 后台子代理模式 ────────────────────────────────────────────
// 当出现 --background 标志时，spawn 一个 detached 子进程跑完整生图流程。
// 主进程立刻返回 task_id 和日志路径，调用方不再被 ⏳ 阻塞。
const TASK_DIR = path.join(__dirname, '..', 'tasks');

function spawnBackgroundChild() {
  if (!fs.existsSync(TASK_DIR)) fs.mkdirSync(TASK_DIR, { recursive: true });
  const ts       = new Date().toISOString().replace(/[:.]/g, '-');
  const jobId    = 'job-' + ts + '-' + Math.random().toString(36).slice(2, 8);
  const logFile  = path.join(TASK_DIR, jobId + '.log');
  const metaFile = path.join(TASK_DIR, jobId + '.json');

  // 子进程参数 = 当前参数去掉 --background
  const childArgs = process.argv.slice(1).filter(a => a !== '--background');
  const out = fs.openSync(logFile, 'a');
  const err = fs.openSync(logFile, 'a');
  const child = spawn(process.execPath, childArgs, {
    detached: true,
    stdio: ['ignore', out, err],
    windowsHide: true,
  });
  child.unref();

  fs.writeFileSync(metaFile, JSON.stringify({
    jobId,
    pid: child.pid,
    logFile,
    startedAt: new Date().toISOString(),
    argv: childArgs,
  }, null, 2));

  console.log('🛰️  后台子代理已启动');
  console.log('   jobId  :', jobId);
  console.log('   pid    :', child.pid);
  console.log('   log    :', logFile);
  console.log('   meta   :', metaFile);
  console.log('   查询   : node "' + path.join(__dirname, 'status.js') + '" ' + jobId);
  return { jobId, logFile, metaFile, pid: child.pid };
}

// ── 主流程 ────────────────────────────────────────────────────

async function main() {
  // ── --background 模式：fork 子进程后立即退出 ────────────────
  if (process.argv.includes('--background')) {
    spawnBackgroundChild();
    return;
  }

  // ── --check 模式：只做环境检查，不生图 ──────────────────────
  if (process.argv.includes('--check')) {
    console.log('=== DreamMaker 环境检查 ===\n');

    // 1. 检查代理
    const proxyOk = await checkProxy();
    if (proxyOk) {
      console.log('✅ 代理在线 (127.0.0.1:7788)');
    } else {
      console.log('❌ 代理未启动');
    }

    // 2. 检查 auth key 或 token
    if (CONFIG.authKey && CONFIG.authKeyUser) {
      process.stdout.write('🔑 检测到 auth key，正在验证...');
      try {
        const tok = await fetchTokenByAuthKey(CONFIG.authKeyUser, CONFIG.authKey);
        console.log(' ✅ auth key 有效，可自动生成 token');
      } catch (e) {
        console.log(' ❌ auth key 无效: ' + e.message);
      }
    } else {
      const tok = loadToken();
      if (!tok) {
        console.log('❌ Token 文件不存在（请运行更新Token.bat 或配置 authKey）');
      } else {
        const { expired, daysLeft, expireStr } = checkTokenExpiry(tok);
        if (expired) {
          console.log('❌ Token 已过期（过期时间: ' + expireStr + '）');
        } else if (daysLeft !== null && daysLeft <= 2) {
          console.log('⚠️  Token 将在 ' + daysLeft + ' 天后过期（' + expireStr + '），建议配置 authKey');
        } else {
          const dayStr = daysLeft !== null ? '，还有 ' + daysLeft + ' 天过期' : '';
          console.log('✅ Token 有效（' + expireStr + dayStr + '）');
        }
      }
    }

    process.exit(0);
    return;
  }

  // ── 正常生图流程 ─────────────────────────────────────────────

  // 0. 首次配置引导（缺少必要配置时交互式收集）
  await ensureConfig();

  console.log('=== DreamMaker 生图工具 ===');

  // 1. 获取 token：优先用 auth key 自动生成，其次用 .token 文件
  let tokenFromAuthKey = false;
  if (CONFIG.authKey && CONFIG.authKeyUser) {
    try {
      process.stdout.write('🔑 使用 auth key 自动获取 token...');
      TOKEN = await fetchTokenByAuthKey(CONFIG.authKeyUser, CONFIG.authKey);
      console.log(' ✅');
      tokenFromAuthKey = true;
    } catch (e) {
      console.log(' ❌');
      console.warn('⚠️  auth key 获取 token 失败，回退到 .token 文件: ' + e.message);
    }
  }

  if (!TOKEN) {
    console.error('❌ 未找到有效 token，请配置 authKey 或更新 .token 文件：');
    console.error('   配置 authKey: 在 .config.json 中填写 authKey 和 authKeyUser');
    console.error('   手动更新: 双击 ' + path.join(__dirname, '更新Token.bat'));
    process.exit(1);
  }

  // 只在没有 auth key 的情况下才检查 token 过期并提示用户手动操作
  if (!tokenFromAuthKey) {
    const tokenStatus = checkTokenExpiry(TOKEN);
    if (tokenStatus.expired) {
      console.error('❌ Token 已过期（' + tokenStatus.expireStr + '），请重新配置 authKey 或更新 .token 文件：');
      console.error('   手动更新: 双击 ' + path.join(__dirname, '更新Token.bat'));
      process.exit(1);
    }
    if (tokenStatus.daysLeft !== null && tokenStatus.daysLeft <= 2) {
      console.warn('⚠️  Token 将在 ' + tokenStatus.daysLeft + ' 天后过期，请及时更新：');
      console.warn('   手动更新: 双击 ' + path.join(__dirname, '更新Token.bat'));
    }
  }

  // 2. 检查代理，未启动则自动拉起
  let proxyOk = await checkProxy();
  if (!proxyOk) {
    proxyOk = await autoStartProxy();
    if (!proxyOk) {
      console.error('❌ 代理自动启动失败，请手动运行: node ' + path.join(__dirname, 'proxy.js'));
      process.exit(1);
    }
  } else {
    console.log('✅ 代理在线 (127.0.0.1:7788)');
  }

  console.log('🤖 模型:', CHECKPOINT);
  console.log('📊 张数:', COUNT);
  console.log('� 分辨率:', IS_4K ? '4K (2048×2048)' : '普通 (1024×768)');
  console.log('�📝 Prompt:', PROMPT.slice(0, 80) + (PROMPT.length > 80 ? '...' : ''));
  if (REF_IMAGE) console.log('🖼️  参考图:', REF_IMAGE);

  // 1. 提交任务（一次提交，n_iter = COUNT，可选参考图）
  console.log('\n🚀 提交生图任务...');
  const taskId = await submitTask(PROMPT, COUNT, REF_IMAGE, IS_4K);
  console.log('   task_id =', taskId);

  // 2. 轮询（等待所有图完成）
  console.log('⏳ 等待 AI 生图（约 15-40 秒）');
  const imgPaths = await pollTask(taskId);
  console.log('\n   共返回', imgPaths.length, '张图片');

  // 3. 下载全部图片
  console.log('⬇️  下载图片...');
  for (let i = 0; i < imgPaths.length; i++) {
    const suffix  = imgPaths.length > 1 ? `-${i + 1}` : '';
    const ext     = path.extname(OUT_PREFIX) || '.png';
    const base    = path.extname(OUT_PREFIX) ? OUT_PREFIX.replace(ext, '') : OUT_PREFIX;
    const outFile = path.join(OUT_DIR, base + suffix + ext);
    await downloadImage(imgPaths[i], outFile);
  }

  console.log('\n🎉 完成！共保存', imgPaths.length, '张图片到', OUT_DIR);
}

main().catch(err => {
  console.error('\n❌ 出错:', err.message);
  process.exit(1);
});
