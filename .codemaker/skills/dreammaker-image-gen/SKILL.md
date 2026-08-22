---
name: dreammaker-image-gen
description: '调用网易内部 DreamMaker AI 平台生成图片的本地化命令行工具。解决 AI 对话中无法直接调用内网生图平台的问题：通过本地 Node.js 代理绕过浏览器 CORS 和 Cookie 限制，封装认证、任务提交、状态轮询、结果下载全流程。核心能力：(1) 单条命令发起生图任务并自动下载结果；(2) 后台并行子代理（--background），多方向同时生图不阻塞；(3) 参考图收件箱机制（F:\codemaker\参考图\）+ auto:N 自动取最新 N 张；(4) preflight.js 生图前体检（防上传超限 413）；(5) compose.js 原件贴合（AI 画容器 + IP 原件零风险贴上去）；(6) 【v1.1 新增】chat-gen.js 对话贴图直生图：用户在对话窗里贴的图，AI 一句话调用即可自动捞下来 + 喂给 DreamMaker 出图，不需要用户手动存盘或拼路径（前置依赖 chat-image-rescue skill）。支持模型：gpt-image-2、nano-banana-pro 等。使用场景：游戏 UI / 原画 / 运营海报 / 参考图制作 / 对话直发图生图。触发词：生图、DreamMaker、网易AI、内网生图、AI图片、Image Generation、对话贴图直生图、用我刚贴的图出图、chat to dreammaker。'
metadata:
  version: 1.0.1
---
# DreamMaker 生图 Skill

通过网易 DreamMaker AI 平台调用文生图 API，生成图片并保存到本地。
这是一个**通用生图能力**，可以独立使用，也可以与 Figma 插件等工具配合（见末尾附录）。

所有脚本位于 `{baseDir}/scripts/`，只需 Node.js 环境，**无需安装依赖**。

---

## 🤖 AI 操作规程（必读，优先于一切）

> 本节是给 AI 看的。用户触发生图需求后，AI 必须严格按以下四步执行，**全程不要让用户自己去跑命令或查文档**。

### 第一步：确认 Prompt

如果用户没有提供详细描述，**主动询问**：
- "你想生成什么风格的图？"（写实 / 卡通 / 纹理 / 信息图 / 其他）
- "有没有特别的颜色或构图要求？"

拿到描述后，**自己把它扩写成英文 prompt**，不要让用户写英文。

### 第二步：检查环境与认证

运行以下命令，同时检查代理状态和认证状态：

```bash
node {baseDir}/scripts/generate.js --check
```

**根据输出处理：**

| 输出内容 | 处理方式 |
|---------|----------|
| `✅ 代理在线` + `✅ auth key 有效` | 直接跳到第三步 |
| `✅ 代理在线` + `✅ Token 有效` | 直接跳到第三步 |
| `❌ 代理未启动` | 无需处理，生图时脚本会自动拉起代理 |
| `❌ auth key 无效` | 引导用户检查 `.config.json` 中的 `authKey`（见下方 A 方式） |
| `❌ Token 已过期` 或 `❌ Token 文件不存在` | 引导用户认证（见下方 A 或 B 方式） |

---

**A. 推荐方式：配置 Auth Key（一劳永逸，自动续期）**

向用户说：
> "需要完成一次认证配置，之后会自动续期，不会再过期。步骤很简单：
> 1. 打开 https://console-auth.nie.netease.com/ 登录，复制页面上的 Auth Key
> 2. 打开 https://dreammaker.netease.com/permission，在用户组管理页找到你所在用户组的 app_code
> 3. 把这两项连同你的用户名（企业邮箱 @ 前面的部分）一起告诉我，我来帮你写入配置"

收到后直接运行 `generate.js`，脚本会自动弹出交互式配置引导：
```bash
node {baseDir}/scripts/generate.js ""
```

**B. 备选方式：手动更新 Token（约 7 天有效，到期需重新获取）**

向用户说：
> "需要手动更新一下登录凭证：
> 1. 打开 https://dreammaker.netease.com（用公司账号登录）
> 2. 按 F12 → 点 Network 标签 → 随便点一下页面上的任何操作
> 3. 在任意一条请求 → 右侧 Headers → 找到 `x-access-token` → 复制完整的值（eyJ 开头）
> 4. 把复制的内容粘贴给我"

用户粘贴后，运行：
```bash
node {baseDir}/scripts/update-token.js "用户粘贴的token"
```

### 第三步：生图

```bash
node {baseDir}/scripts/generate.js "" "英文prompt" "输出文件名.png" "模型名"
```

- 第一个参数（token）**留空 `""`**，脚本自动按优先级获取认证
- 模型默认 `nano-banana-pro`，用户未指定时不必传
- 图片保存在 `{baseDir}/output/` 目录下

等待期间告知用户：「AI 正在生图，通常需要 15~40 秒 ☕」

### 第四步：展示结果

生图成功后：
1. 告知用户图片保存的**完整路径**
2. 用 `read_file` 工具读取图片展示给用户
3. 询问："效果满意吗？需要调整风格或重新生成吗？"

---

## 异常处理速查

| 错误信息 | 原因 | 解决方法 |
|---------|------|---------|
| `ECONNREFUSED` / 代理错误 | 代理未启动 | `generate.js` 会自动拉起；或手动 `start /min node {baseDir}/scripts/proxy.js` |
| `下载内容非图片` | Token 过期 | 引导更新认证（第二步） |
| `提交失败 code: 401` | Token 无效 | 引导更新认证（第二步） |
| `auth key 换取 token 失败` | Auth Key 无效 | 引导用户重新申请 Auth Key 并更新 `.config.json` |
| `生图超时（180s）` | 服务器繁忙 | 稍后重试 |

---

## 脚本说明

| 脚本 | 用途 |
|------|------|
| `generate.js` | 生图主脚本，支持 `--check` 环境检查模式；首次运行缺少配置时自动弹出交互引导 |
| `proxy.js` | 本地 CORS 代理，监听 `127.0.0.1:7788`（`generate.js` 会自动拉起，一般无需手动启动） |
| `update-token.js` | Token 更新工具（支持交互模式和命令行传参两种方式） |
| `更新Token.bat` | Windows 双击更新 Token（调用 `update-token.js`） |
| `setup-autorun.bat` | 将 `proxy.js` 加入 Windows 开机自启 |

### generate.js 参数

```
参数顺序: token → prompt → 文件名前缀 → checkpoint → 张数 → 参考图路径 → 4K
所有参数均可留空 "" 使用默认值
```

```bash
node generate.js ""                                           # 只用默认值
node generate.js "" "a warrior in armor"                      # 指定 prompt
node generate.js "" "a warrior" "warrior"                     # 指定文件名前缀（多张自动加 -1 -2）
node generate.js "" "a warrior" "out" "" "4"                  # 生成 4 张
node generate.js "" "refine" "out" "" "4" "C:/ref.png"        # 带参考图生成 4 张
node generate.js "" "refine" "out" "" "4" "C:/ref.png" "4K"   # 带参考图生成 4 张 4K
node generate.js "" "" "" "" "1" "" "4K"                      # 只开 4K
```

> **参考图**：通过 `control[0].image` 传 base64，`annotator: "i2i"`，与网页「添加参考图」按钮一致。

> **4K 分辨率**：`2048×2048`，`size_str: "2K"`，`ar: "1:1"`。普通分辨率为 `1024×768`，`ar: "4:3"`。

---

## 认证配置参考

### Token 自动读取优先级

```
Auth Key（.config.json 中的 authKey）> 命令行参数 argv[2] > .token 文件 > CONFIG.defaultToken
```

推荐配置 Auth Key 实现永久免维护；若未配置 Auth Key，将依次尝试后续来源。

### Auth Key 配置文件格式

在 `{baseDir}/.config.json` 中填写个人信息（参考 `.config.example.json`）：

```json
{
  "aigwApp":     "_dm_prod_9d140b2256a77b4641db3521",
  "authUser":    "yourname",
  "groupId":     "your-group-id",
  "authKeyUser": "yourname",
  "authKey":     "your-auth-key"
}
```

> - `authKey`：从 https://console-auth.nie.netease.com/ 获取
> - `aigwApp`（即 app_code）：从 https://dreammaker.netease.com/permission 用户组管理页获取
> - `authUser` / `authKeyUser`：企业邮箱 @ 前面的部分
> - `groupId`：DreamMaker 项目页面 URL 中可找到

### 浏览器书签一键同步 Token

在 DreamMaker 页面点一下书签即可自动复制 Token 到剪贴板并写入 `.token` 文件。详见 `{baseDir}/BOOKMARKLET.md`。

---

## 注意事项

- Token 有效期约 7 天，配置 Auth Key 后可自动续期
- 生图通常 15~40 秒，脚本轮询超时 180 秒
- 图片验证：PNG 首字节 `0x89`，JPEG 首字节 `0xFF`；首字节不匹配说明下载到了错误页（认证问题）
- 并发多任务可能限流，建议串行执行

---

## 附录：配合 Figma 插件使用（可选）

Figma 插件（`ui.html`）通过同一个本地代理（`proxy.js`）调用 DreamMaker，**共用同一套代理和认证体系**。

- 插件界面有「更新 Token」按钮，粘贴后自动保存到 `localStorage`
- 插件中更新 Token 后，仍需同步更新本地 `.token` 文件供命令行脚本使用：
  ```bash
  node {baseDir}/scripts/update-token.js "同一个token"
  ```
- 下载后的图片字节通过 `figma.createImageAsync` 写入图层填充