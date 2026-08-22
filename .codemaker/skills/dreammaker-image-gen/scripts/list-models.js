// list-models.js - Query available checkpoints from DreamMaker
const fs = require('fs');
const http = require('http');
const path = require('path');

const BASE_DIR = path.dirname(__dirname);
const CONFIG = JSON.parse(fs.readFileSync(path.join(BASE_DIR, '.config.json'), 'utf8'));

// Read token from .token file or we'll need to get it
let TOKEN = '';
const tokenFile = path.join(BASE_DIR, '.token');
if (fs.existsSync(tokenFile)) TOKEN = fs.readFileSync(tokenFile, 'utf8').trim();

function proxyFetch(method, targetUrl, headers) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({ method, url: targetUrl, headers, body: null });
    const opts = {
      hostname: '127.0.0.1', port: 7788, path: '/proxy',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
    };
    const req = http.request(opts, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks).toString()));
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function main() {
  const headers = {
    'Content-Type': 'application/json',
    'x-aigw-app': CONFIG.aigwApp,
    'x-access-token': TOKEN,
    'x-auth-user': CONFIG.authUser,
    'x-group-id': CONFIG.groupId,
    'x-source': 'frontEnd',
  };
  
  // Try the checkpoints endpoint
  const urls = [
    'https://dreammaker.netease.com/sunshine_flow/COMMON/2d/checkpoints',
    'https://dreammaker.netease.com/sunshine_flow/COMMON/2d/models',
    'https://dreammaker.netease.com/aigw/api/open/sd/v2/checkpoints',
  ];
  
  for (const url of urls) {
    try {
      const res = await proxyFetch('GET', url, headers);
      if (res.includes('login') || res.includes('<!doctype')) continue;
      const data = JSON.parse(res);
      if (data.data) {
        const items = Array.isArray(data.data) ? data.data : (data.data.items || data.data.list || []);
        console.log(`\n=== ${url} ===`);
        items.forEach(m => {
          const name = m.name || m.checkpoint || m.model_name || m.id || JSON.stringify(m).substring(0, 100);
          console.log('  -', name);
        });
      }
    } catch(e) {
      // skip
    }
  }
}

main().catch(console.error);
