# DreamMaker 一键复制 Token 书签工具

## 使用效果

在 DreamMaker 页面点一下浏览器书签：
- ✅ Token 自动复制到剪贴板
- ✅ Token 自动同步到本地 `.token` 文件（如果代理在运行）
- ✅ 弹窗提示成功 + 显示 token 前30字符确认

**全程不需要打开 DevTools，不需要找请求。**

---

## 安装步骤（只做一次）

### 第一步：复制书签代码

把下面这段代码**完整复制**：

```
javascript:(function(){var r=document.cookie.match(/ACCESS_TOKEN=([^;]+)/);var t=r?decodeURIComponent(r[1]):'';if(!t){alert('❌ 未找到 Token，请确认已登录 DreamMaker');return;}navigator.clipboard.writeText(t).then(function(){var msg='✅ Token 已复制到剪贴板！\n前30字符: '+t.substring(0,30)+'...\n\n正在同步到本地文件...';fetch('http://127.0.0.1:7788/save-token',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:t})}).then(function(res){return res.json();}).then(function(data){alert(data.ok?'✅ Token 已复制 + 已同步到本地文件！\n前30字符: '+t.substring(0,30)+'...':'✅ Token 已复制到剪贴板\n⚠️ 未能同步到本地（代理未启动？）\n前30字符: '+t.substring(0,30)+'...');}).catch(function(){alert('✅ Token 已复制到剪贴板\n⚠️ 未能同步到本地（代理未启动？）\n前30字符: '+t.substring(0,30)+'...');});});})();
```

### 第二步：创建书签

1. 在浏览器书签栏**右键** → 「添加页面」或「新建书签」
2. 名称填：`🔑 复制DM Token`
3. 网址/URL 栏：**粘贴上面的代码**（以 `javascript:` 开头）
4. 保存

### 第三步：使用

1. 打开 https://dreammaker.netease.com（确保已登录）
2. 点击书签栏的 `🔑 复制DM Token`
3. 弹窗提示成功，token 已在剪贴板 + 自动写入本地文件

---

## 代码说明

```javascript
// 1. 从 Cookie 里提取 ACCESS_TOKEN
var r = document.cookie.match(/ACCESS_TOKEN=([^;]+)/);
var t = r ? decodeURIComponent(r[1]) : '';

// 2. 复制到剪贴板
navigator.clipboard.writeText(t);

// 3. 同时 POST 到本地代理的 /save-token 接口，自动写入 .token 文件
fetch('http://127.0.0.1:7788/save-token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ token: t })
});
```

---

## 注意事项

- 必须在 **dreammaker.netease.com** 页面上点击才能读到 Cookie
- 「同步到本地文件」需要**代理正在运行**（`proxy.js` 在后台跑）
- 代理未运行时，token 仍然会复制到剪贴板，只是不会自动写文件
- Token 约 7 天过期，到期重新点一次书签即可
