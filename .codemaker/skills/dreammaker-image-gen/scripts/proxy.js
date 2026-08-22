/**
 * DreamMaker CORS 代理服务
 * 监听 localhost:7788，转发请求到 dreammaker.netease.com
 * 绕过浏览器 CORS 限制，供 Figma 插件 / 脚本调用
 *
 * 启动方式: node proxy.js
 * 开机自启: 运行同目录的 setup-autorun.bat
 */
const http  = require('http');
const https = require('https');

const PORT        = 7788;
const TARGET_HOST = 'dreammaker.netease.com';

const server = http.createServer((req, res) => {
  // 所有请求都允许跨域（供 Figma 插件调用）
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');

  // OPTIONS 预检请求直接返回
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // 健康检查
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok');
    return;
  }

  // 收集请求体
  let body = [];
  req.on('data', chunk => body.push(chunk));
  req.on('end', () => {
    body = Buffer.concat(body);

    // ── /proxy 路由：JSON 包装模式（供 generate.js / Figma 插件调用）──────
    // 请求体格式: { method, url, headers, body }
    // url 是完整的目标 URL，如 https://dreammaker.netease.com/...
    if (req.url === '/proxy' && req.method === 'POST') {
      let parsed;
      try { parsed = JSON.parse(body.toString()); } catch(e) {
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('Bad JSON: ' + e.message);
        return;
      }
      const targetUrl    = new URL(parsed.url);
      const forwardHdrs  = Object.assign({}, parsed.headers || {});
      forwardHdrs['host']    = targetUrl.hostname;
      forwardHdrs['origin']  = targetUrl.origin;
      forwardHdrs['referer'] = targetUrl.origin + '/';
      if (forwardHdrs['x-proxy-cookie']) {
        forwardHdrs['cookie'] = forwardHdrs['x-proxy-cookie'];
        delete forwardHdrs['x-proxy-cookie'];
      }
      const pReq = https.request({
        hostname: targetUrl.hostname,
        port:     443,
        path:     targetUrl.pathname + targetUrl.search,
        method:   parsed.method || 'GET',
        headers:  forwardHdrs,
      }, pRes => {
        const respHdrs = {};
        Object.keys(pRes.headers).forEach(k => {
          if (!k.toLowerCase().startsWith('access-control')) respHdrs[k] = pRes.headers[k];
        });
        respHdrs['Access-Control-Allow-Origin'] = '*';
        res.writeHead(pRes.statusCode, respHdrs);
        pRes.pipe(res);
      });
      pReq.on('error', err => {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
        res.end('代理错误: ' + err.message);
      });
      const reqBody = parsed.body;
      if (reqBody) pReq.write(typeof reqBody === 'string' ? reqBody : JSON.stringify(reqBody));
      pReq.end();
      return;
    }

    // ── 直接转发模式（透明代理，路径原样转发）────────────────────────────
    const forwardHeaders = {};
    Object.keys(req.headers).forEach(k => {
      if (!['host', 'origin', 'referer', 'connection'].includes(k.toLowerCase())) {
        forwardHeaders[k] = req.headers[k];
      }
    });
    forwardHeaders['host']    = TARGET_HOST;
    forwardHeaders['origin']  = 'https://' + TARGET_HOST;
    forwardHeaders['referer'] = 'https://' + TARGET_HOST + '/';

    // 浏览器无法手动设置 Cookie 头，用 x-proxy-cookie 代替，代理在这里转换
    if (forwardHeaders['x-proxy-cookie']) {
      forwardHeaders['cookie'] = forwardHeaders['x-proxy-cookie'];
      delete forwardHeaders['x-proxy-cookie'];
    }

    const options = {
      hostname: TARGET_HOST,
      port:     443,
      path:     req.url,
      method:   req.method,
      headers:  forwardHeaders,
    };

    const proxyReq = https.request(options, proxyRes => {
      const responseHeaders = {};
      Object.keys(proxyRes.headers).forEach(k => {
        if (!k.toLowerCase().startsWith('access-control')) {
          responseHeaders[k] = proxyRes.headers[k];
        }
      });
      responseHeaders['Access-Control-Allow-Origin'] = '*';
      res.writeHead(proxyRes.statusCode, responseHeaders);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', err => {
      res.writeHead(502, { 'Content-Type': 'text/plain' });
      res.end('代理错误: ' + err.message);
    });

    if (body.length > 0) proxyReq.write(body);
    proxyReq.end();
  });
});

// ── /save-token 接口：供 Bookmarklet 调用，直接写入 .token 文件 ────
const TOKEN_FILE = require('path').join(__dirname, '..', '.token');
function handleSaveToken(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');
  if (req.method === 'OPTIONS') { res.writeHead(200); res.end(); return; }
  let body = [];
  req.on('data', c => body.push(c));
  req.on('end', () => {
    try {
      const data  = JSON.parse(Buffer.concat(body).toString());
      const token = (data.token || '').trim();
      if (!token || !token.startsWith('eyJ')) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: '无效的 token' }));
        return;
      }
      require('fs').writeFileSync(TOKEN_FILE, token, 'utf8');
      console.log('🔑 Token 已更新（来自 Bookmarklet）:', token.slice(0, 30) + '...');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: e.message }));
    }
  });
}

server.on('request', (req, res) => {
  if (req.url === '/save-token') handleSaveToken(req, res);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('✅ DreamMaker 代理已启动: http://127.0.0.1:' + PORT);
  console.log('   健康检查: http://127.0.0.1:' + PORT + '/health');
  console.log('   Token 更新: http://127.0.0.1:' + PORT + '/save-token  (供 Bookmarklet 调用)');
});
