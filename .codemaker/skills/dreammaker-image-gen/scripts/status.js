#!/usr/bin/env node
/**
 * DreamMaker 后台任务状态查询
 *
 * 用法:
 *   node status.js                    列出最近 10 个任务
 *   node status.js <jobId>            查看指定任务的状态 + 日志尾部
 *   node status.js <jobId> --tail=N   显示最后 N 行日志（默认 30）
 *   node status.js <jobId> --full     显示完整日志
 *   node status.js --watch <jobId>    持续刷新（每 3 秒）
 */

const fs   = require('fs');
const path = require('path');

const TASK_DIR = path.join(__dirname, '..', 'tasks');
const OUT_DIR_DEFAULT = process.env.DM_OUTPUT_DIR || 'F:\\codemaker\\设计生成';

function listJobs() {
  if (!fs.existsSync(TASK_DIR)) return [];
  return fs.readdirSync(TASK_DIR)
    .filter(f => f.endsWith('.json'))
    .map(f => {
      const meta = JSON.parse(fs.readFileSync(path.join(TASK_DIR, f), 'utf8'));
      return meta;
    })
    .sort((a, b) => (b.startedAt || '').localeCompare(a.startedAt || ''));
}

function readLog(logFile, tail) {
  if (!fs.existsSync(logFile)) return '';
  const buf = fs.readFileSync(logFile, 'utf8');
  if (!tail || tail === 'full') return buf;
  const lines = buf.split(/\r?\n/);
  return lines.slice(-tail).join('\n');
}

function processAlive(pid) {
  if (!pid) return false;
  try { process.kill(pid, 0); return true; } catch (_) { return false; }
}

function inferStatus(meta) {
  const log = fs.existsSync(meta.logFile) ? fs.readFileSync(meta.logFile, 'utf8') : '';
  if (/🎉 完成/.test(log)) return 'success';
  if (/❌ 出错|生图失败|FATAL/.test(log)) return 'failed';
  if (processAlive(meta.pid)) return 'running';
  // 进程死了但没成功 → 可能崩了
  if (log.length > 0) return 'dead';
  return 'unknown';
}

function listSavedImages(log) {
  const lines = log.split(/\r?\n/);
  return lines
    .filter(l => /✅ 已保存:/.test(l))
    .map(l => l.replace(/.*✅ 已保存:\s*/, '').replace(/\s*\(.*$/, ''));
}

function showJob(jobId, opts) {
  const metaFile = path.join(TASK_DIR, jobId + '.json');
  if (!fs.existsSync(metaFile)) {
    console.error('未找到任务: ' + jobId);
    process.exit(1);
  }
  const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
  const status = inferStatus(meta);
  const log = readLog(meta.logFile, opts.full ? 'full' : (opts.tail || 30));
  const fullLog = fs.existsSync(meta.logFile) ? fs.readFileSync(meta.logFile, 'utf8') : '';
  const images = listSavedImages(fullLog);

  console.log('=== ' + jobId + ' ===');
  console.log('  状态  :', status);
  console.log('  pid   :', meta.pid, processAlive(meta.pid) ? '(存活)' : '(已退出)');
  console.log('  开始  :', meta.startedAt);
  console.log('  log   :', meta.logFile);
  console.log('  argv  :', meta.argv.slice(1).join(' '));
  if (images.length) {
    console.log('  生成图:');
    images.forEach(p => console.log('    -', p));
  }
  console.log('--- 日志 (' + (opts.full ? '完整' : ('尾部 ' + (opts.tail || 30) + ' 行')) + ') ---');
  console.log(log);
}

function main() {
  const args = process.argv.slice(2);
  const watch = args.includes('--watch');
  const full  = args.includes('--full');
  const tailArg = args.find(a => a.startsWith('--tail='));
  const tail = tailArg ? parseInt(tailArg.slice(7)) : 30;
  const jobId = args.find(a => !a.startsWith('--'));

  if (!jobId) {
    const jobs = listJobs().slice(0, 10);
    if (!jobs.length) { console.log('暂无后台任务'); return; }
    console.log('=== 最近 10 个任务 ===');
    for (const j of jobs) {
      const status = inferStatus(j);
      console.log(['  ', status.padEnd(8), j.jobId, j.startedAt].join('  '));
    }
    console.log('\n查看详情: node status.js <jobId>');
    return;
  }

  if (watch) {
    const refresh = () => {
      console.clear();
      showJob(jobId, { tail, full });
      const meta = JSON.parse(fs.readFileSync(path.join(TASK_DIR, jobId + '.json'), 'utf8'));
      const status = inferStatus(meta);
      if (status === 'success' || status === 'failed' || status === 'dead') {
        console.log('\n[最终状态: ' + status + ']');
        process.exit(0);
      }
    };
    refresh();
    setInterval(refresh, 3000);
  } else {
    showJob(jobId, { tail, full });
  }
}

main();
