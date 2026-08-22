/**
 * DreamMaker Token 更新工具
 * 将新的 x-access-token 保存到 .token 文件
 *
 * 运行方式:
 *   node update-token.js          ← 交互模式（命令行粘贴）
 *   node update-token.js "eyJ..."  ← 直接传入 token
 */

const fs       = require('fs');
const path     = require('path');
const readline = require('readline');

const TOKEN_FILE = path.join(__dirname, '..', '.token');
const DM_BASE    = 'https://dreammaker.netease.com';

// ── 工具函数 ──────────────────────────────────────────────────

/** 简单解析 JWT payload，读取过期时间 */
function parseJwtExpiry(token) {
  try {
    const payload = token.split('.')[1];
    const decoded = JSON.parse(Buffer.from(payload, 'base64').toString('utf8'));
    if (decoded.exp) {
      const date = new Date(decoded.exp * 1000);
      return date.toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' });
    }
  } catch (_) {}
  return null;
}

/** 保存 token 到文件 */
function saveToken(token) {
  const dir = path.dirname(TOKEN_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(TOKEN_FILE, token.trim(), 'utf8');
}

/** 读取现有 token（如果有） */
function readExistingToken() {
  if (fs.existsSync(TOKEN_FILE)) {
    const t = fs.readFileSync(TOKEN_FILE, 'utf8').trim();
    return t || null;
  }
  return null;
}

/** 打印分隔线 */
function hr() { console.log('─'.repeat(50)); }

// ── 主流程 ────────────────────────────────────────────────────

async function main() {
  console.clear();
  console.log('╔══════════════════════════════════════════════════╗');
  console.log('║       DreamMaker Token 更新工具  🔑              ║');
  console.log('╚══════════════════════════════════════════════════╝');
  console.log();

  // 显示当前 token 状态
  const existing = readExistingToken();
  if (existing) {
    const expiry = parseJwtExpiry(existing);
    console.log('📄 当前 .token 文件状态：');
    console.log('   Token 前30字符: ' + existing.slice(0, 30) + '...');
    console.log('   过期时间: ' + (expiry || '无法解析'));
    console.log();
  } else {
    console.log('⚠️  当前没有保存的 token（.token 文件不存在）');
    console.log();
  }

  hr();
  console.log('📋 如何获取新 Token：');
  console.log('   1. 打开 https://dreammaker.netease.com');
  console.log('   2. 按 F12 → Network 标签');
  console.log('   3. 随便点一个操作（如切换风格）');
  console.log('   4. 找任意一个请求 → Headers → 找到 x-access-token');
  console.log('   5. 复制完整值（eyJ 开头的长字符串）');
  hr();
  console.log();

  // 如果命令行直接传了 token
  if (process.argv[2] && process.argv[2].startsWith('eyJ')) {
    handleToken(process.argv[2]);
    return;
  }

  // 交互模式：等待用户粘贴
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  rl.question('请粘贴新的 x-access-token（直接粘贴后按回车）：\n> ', (answer) => {
    rl.close();
    handleToken(answer.trim());
  });
}

function handleToken(token) {
  console.log();

  if (!token) {
    console.error('❌ Token 为空，未保存。');
    waitExit(1);
    return;
  }

  if (!token.startsWith('eyJ')) {
    console.error('❌ 看起来不是有效的 JWT Token（应以 eyJ 开头）');
    console.error('   你粘贴的内容: ' + token.slice(0, 50));
    waitExit(1);
    return;
  }

  // 解析并展示 token 信息
  const expiry = parseJwtExpiry(token);
  console.log('✅ Token 验证通过！');
  console.log('   长度: ' + token.length + ' 字符');
  if (expiry) console.log('   过期时间: ' + expiry);

  // 保存
  saveToken(token);
  console.log();
  console.log('💾 已保存到: ' + TOKEN_FILE);
  console.log();
  console.log('🎉 完成！下次运行 generate.js 将自动使用新 token。');

  waitExit(0);
}

/** 等待3秒后退出（给双击 bat 的用户时间看结果） */
function waitExit(code) {
  console.log();
  console.log('（窗口将在 3 秒后关闭...）');
  setTimeout(() => process.exit(code), 3000);
}

main().catch(err => {
  console.error('❌ 出错:', err.message);
  waitExit(1);
});
