# 墨时 InkTime — 项目总览

> 面向 AI 与人共读的单一入口文档。工程规则见 `AGENTS.md`（测试跑法/编码禁忌）。
> 生成时间：2026-08-23

---

## 0. 一句话

水墨风格 2D 俯视角割草游戏。玩家按住右键**画符**（$Q 点云手势识别）触发神纹技能，松手沿笔画**冲刺斩击**；左键按表盘时针方向斩；血空进「时滞」，3 次耗尽结算。视觉走**渗墨反馈画布 + 矢量笔触**双管线。

- 引擎：**Godot 4.7.1 stable mono**（`gl_compatibility` 渲染器）
- 主工程：`moshi_demo/`（当前）；`demo_test/` 是早期原型，已被取代
- 导出产物：`墨时 InkTime.exe`（Windows x86_64，embed_pck）
- 主场景：`res://scenes/login.tscn`

---

## 1. 仓库结构

```
d:\zhanji\
├─ AGENTS.md              项目规则（headless 跑测试、日志约定、编辑禁忌）
├─ PROJECT_OVERVIEW.md    本文档
├─ 墨时 InkTime.exe        导出产物
├─ moshi_demo\            ★ 主工程
│  ├─ scripts\            全部玩法/渲染 GDScript
│  ├─ scenes\             4 个场景（都只挂脚本，节点靠代码拼）
│  ├─ shaders\            4 个 .gdshader
│  ├─ data\balance.tres   ★ 配平总表：刷怪全局 + 9 只怪 + 5 段波表
│  ├─ data\player.tres    ★ 人物总表：血量 / 冲刺斩 / 表盘 / 回溯 / 笔墨 / 七道神纹
│  ├─ assets\, art\       贴图 / 帧动画目录
│  ├─ tests\              11 套 headless 测试
│  ├─ docs\               5 份设计与改动说明
│  ├─ addons\godot_ai\    编辑器 MCP 插件（非玩法）
│  └─ run*.log            测试日志（不入库）
├─ demo_test\             早期原型，勿改
└─ .codemaker\skills\     AI 技能配置（生图等）
```

---

## 2. 运行时架构

### 场景清单

| 场景 | 根节点 | 脚本 | 说明 |
|---|---|---|---|
| `login.tscn` | Control | `login.gd` | 标题屏「时之回环」，5 图轮播 + 4 项菜单 |
| `main.tscn` | Node2D | `main.gd` | 战斗主场景，**所有节点由代码创建** |
| `spell_lab.tscn` | CanvasLayer | `spell_lab.gd` | F2 咒语调试台 |
| `ink_editor.tscn` | CanvasLayer(layer=10) | `ink_editor.gd` | F1 水痕样式编辑器 |

### Autoload（`project.godot:22-26`）

| 名 | 脚本 | 职责 |
|---|---|---|
| `AudioMgr` | `scripts/audio.gd` | 音频 |
| `InkStyle` | `scripts/ink_style_provider.gd` | 墨笔样式全局广播 + 热更新 |
| `_mcp_game_helper` | `addons/godot_ai/runtime/game_helper.gd` | AI 插件运行时 |

非 autoload 的 `class_name` 全局单例：`EnemyDB`、`WaveDB`、`BleedCanvas`、`InkRenderer`、`WaterRenderer`、`QDollar`（`vendor/q_dollar.gd`）。

### main.gd 构建的节点树

```
Game (Node2D)
├─ bg_layer     PaintLayer   z=-100   宣纸平铺 + 円相弧
├─ bleed        BleedCanvas  z=-80    渗墨画布合成输出
├─ ink_layer    PaintLayer   z=-50    水痕/冲刺/回溯轨迹
├─ player       Player                无脸兜帽剑客
├─ (enemies)    Enemy × N
├─ fx_layer     PaintLayer   z=+50    技能特效/残影/闪电
├─ camera       Camera2D              死区跟随
├─ dial_pointer Sprite2D              表盘指针（素材可选）
└─ hud          HUD (CanvasLayer)
```

**无 InputMap 自定义动作**——操作全在 `main.gd:376-413` 用原生 keycode / 鼠标按钮直判。

---

## 3. 玩法系统

### 3.1 状态机（`main.gd:8`）

| 状态 | 含义 |
|---|---|
| `PLAY` | 常态：回资源、刷怪、接触判定 |
| `SPELL` | 按住右键书写，子弹时间（敌速 ×0.10），持续扣 TV |
| `DASH` | 沿笔画冲刺，撞敌挂「标记」 |
| `BURST` | 终点顿帧，统一结算标记伤害 |
| `REWIND` | 沿历史轨迹倒走，伤害 ×0.5 |
| `LAG` | 时滞惩罚（死亡一次） |
| `GAMEOVER` | 结算面板 |

胜负：无时限、无「胜利」定义；`lag_count > 3` 即结算（`main.gd:1345`）。重开按 `ENTER/SPACE/R` 或点击。

### 3.2 操作

| 输入 | 行为 |
|---|---|
| 左键单击 | 表盘斩：沿当前时针方向固定距离冲刺，耗 1 AP，**不进子弹时间** |
| 右键按住 | 进 SPELL 书写；松开沿笔画冲刺，匹配则放技能 |
| `R` | 回溯（需时钟充满 12s） |
| `Esc` | 取消书写 / 放弃觉醒 |
| `F1` / `F2` / `F3` | 水痕编辑器 / 咒语调试台 / TV 回满（后门） |
| `1~6` | 觉醒面板选碑 |

### 3.3 玩家资源

| 组 | 常量 |
|---|---|
| 生存 | `PLAYER_HP=100`，半径 30，受击无敌 0.6s |
| 场地 | `ARENA=3000×3000`，敌上限 `MAX_ENEMIES=130` |
| 行动点 AP | 基础上限 3、封顶 6；时针 2s/点、秒针 0.5s/0.25 点、分针 1.0s/0.25 点 |
| 时间之力 TV | 上限 500，回复 20/s；书写 1 TV/px，子弹时间额外 30/s 抽干，退出留 10 |
| 冲刺 | 速度 3200，判定半径 140，伤害 20，距离 520（上限 800），后摇无敌 0.3s |
| 回溯 | 充能 12s，5 槽历史，伤害 ×0.5，标记保留 1.5s |

局外养成字典 `upgrades`（`main.gd:154`）：ap_regen / tv_max / dash_dist / dash_width / rewind_slots / rewind_mult / burst_radius / pointer / skill_power / coin_gain / tv_gain / ap_cap。**目前无存档持久化**。

---

## 4. 神纹（技能）系统

### 4.1 识别链路

```
右键松开 → _end_draw()
  → SpellMatch.feature(path)   沿弧长采样 → 重采样 32 点 → 最长弦转正 → 缩放 + 质心归一
  → SpellMatch.best_match()    与 8 神纹逐一比 cloud_rms（正向 + 180° 翻转取小）
     sim = clamp(1 - rms / 0.35)
  ├ sim ≥ 0.82 且笔长 ≥ 120 且非冷却 → _fire(skill) → _cast(id)
  ├ 未命中但够长够独特             → _try_awaken() 觉醒空碑
  └ 否则                           → 普通冲刺斩
```

识别器：**$Q Point-Cloud Recognizer**（`vendor/q_dollar.gd`，MIT 移植）。

### 4.2 神纹录（8 格）

出生仅 2 道**古代神纹**（time / thunder，自带出厂笔形，可在 F2 台精修并落盘 `user://spell_strokes.json`）；其余 6 格为**空碑**，战斗中靠「觉醒」点亮。

| id | 名称 | 古代 | CD | 效果 |
|---|---|:--:|--:|---|
| `time` | 时·回溯 | ✓ | 10s | 沿历史轨迹倒走，伤害 ×0.5，接管状态机 |
| `thunder` | 雷霆万钧 | ✓ | 6s | 6 道随机落雷，每道 20 伤 / 半径 82，清弹 |
| `quake` | 山崩地裂 | | 12s | 6 轮地震，0.5s 一跳，12 伤 / 半径 155，跟随玩家 |
| `ent` | 妖木精灵 | | 20s | 4 树人，存活 12s，速 155，0.7s 砍 10 伤 |
| `flood` | 水漫金山 | | 10s | 8 向水浪，速 540 / 程 640 / 宽 34，单目标 16 伤 |
| `domain` | 时间领域 | | 16s | 驻留 6s，DPS 14，半径 195；域内时钟充能 ×2 |
| `swords` | 无限剑阵 | | 14s | 内 6 外 12 共 18 剑，22 伤 / 落地半径 58 |
| `alpha` | 阿尔法突袭 | | 12s | 隐身 8 段，0.1s 一次，265 半径内随机斩 12 伤 |

伤害统一乘 `skill_power() = 1 + 0.15 × upgrades.skill_power`。

### 4.3 觉醒（空碑绑定）五闸

① 笔画够长 ② 烧掉起笔 TV 的 ≥70% ③ 未命中已激活神纹 ④ 全表最高形似度 `< 0.70`（太像已有的不给绑）⑤ 掷骰过 50%。通过后弹面板选碑，或随机点亮并当场施展。

---

## 5. 敌人系统（数据驱动）

### 5.0 配平总表 `data/balance.tres`

怪物数值、刷怪波表、刷怪全局参数**全部收在这一份资源**（类型 `BalanceConfig`，
定义见 `scripts/balance_config.gd`）。编辑器双击打开，Inspector 里改完存盘即生效。

| 组 | 字段 | 管什么 |
|---|---|---|
| 刷怪全局 | `max_enemies`(130) / `spawn_margin`(26) | 全场怪物数硬顶、刷怪点边界内缩 |
| 怪物 | `enemies`：9 项 `EnemyData` | 血量 / 伤害 / 速度 / 半径 / 素材 / 行为参数 |
| 波表 | `waves`：5 段 `WaveData` | 时段、**刷怪频率 `interval`**、上限 `cap`、配比 `mix` |

加怪 = `enemies` 数组加一项；加波次 = `waves` 数组加一项。都不用改代码。
`EnemyDB` 按 id 索引、`WaveDB` 按 `until_time` 排段，均为静态懒加载，读的就是这份总表。

### 5.1 EnemyData 字段（`scripts/enemy_data.gd`）

- **身份**：`id` / `display_name` / `behavior`（MELEE=0, RANGED=1, CHARGER=2, SPLITTER=3, BOSS=4）
- **数值**：`hp` `speed` `dmg` `radius`（技能判定全靠它）`score` `coin` `tv`
- **外观**：`tex` / `anim_dir`（子目录=状态）/ `tex_target` / `color` / `use_pivot` / `pivot_frac` / `draw_style` / `inertia`
- **精英**：`is_elite` / `elite_of` / `scale_mul` / `tint`
- **远程**：`attack_range` `attack_cd` `attack_windup` `bullet_*`
- **冲锋**：`charge_range` `charge_dist` `charge_time` `charge_speed` `charge_cd` `charge_warn_color`
- **分裂**：`split_count` `split_child_id` `split_spread` `split_child_invuln`
- **兼容**：`legacy_type` + `to_cfg()` 生成 main / enemy 沿用的字典

### 5.2 九只怪

| id | 名称 | 行为 | HP | 速 | 伤 | 半径 | 分 | 币 | TV | 备注 |
|---|---|---|--:|--:|--:|--:|--:|--:|--:|---|
| `melee_mite` | 影蚋 | 近战 | 10 | 60 | 8 | 30 | 10 | 1 | 8 | 直追 |
| `ranged_crystal` | 晶哨 | 远程 | 24 | 50 | 12 | 48 | 45 | 3 | 26 | 420px 停步开火 |
| `charger_fast` | 疾影 | 冲锋 | 14 | 130 | 6 | 22 | 15 | 1 | 10 | 蓄力锁向，红线即落点 |
| `splitter_bomber` | 磐妖 | 分裂 | 16 | 80 | 10 | 26 | 25 | 2 | 12 | 死后裂 2，爆裂连锁 |
| `splitter_bomber_shard` | 磐妖碎块 | 分裂 | 5 | 105 | 5 | 16 | 8 | 0 | 4 | 不二次分裂 |
| `elite_melee` | 影蚋·精英 | 近战 | 40 | 51 | 14.4 | 45 | 30 | 3 | 20 | |
| `elite_ranged` | 晶哨·精英 | 远程 | 96 | 42.5 | 21.6 | 72 | 135 | 9 | 65 | CD 1.3 / 射程 460 |
| `elite_charger` | 疾影·精英 | 冲锋 | 56 | 110.5 | 10.8 | 33 | 45 | 3 | 25 | 蓄力 1.6s / 冲速 1000 |
| `elite_splitter` | 磐妖·精英 | 分裂 | 64 | 68 | 18 | 39 | 75 | 6 | 30 | 裂出普通碎块 |

精英统一倍率：scale ×1.5、HP ×4、伤 ×1.8、速 ×0.85、分/币 ×3、TV ×2.5、暖金 tint。**全场只 4 套美术素材**（测试卡这条红线）。

### 5.3 波次表

| 段 | 时段 | 间隔 | 场上上限 | 组成 |
|---|---|--:|--:|---|
| `seg1_opening` | 0–5s | 0.5 | 18 | 影蚋 100% |
| `seg2_rush` | 5–12s | 0.38 | 28 | 影蚋 75 / 疾影 25 |
| `seg3_ranged` | 12–20s | 0.3 | 38 | +晶哨 20 / 磐妖 10 / 首精英 5 |
| `seg4_elite` | 20–27s | 0.24 | 48 | 三种精英同场 |
| `seg5_plateau` | 27s–∞ | 0.18 | 64 | 四精英到齐，永久平台期 |

`WaveDB.seg_for(run_time)` 按 `until_time` 升序查段，跑过末段永远返最后一段。`WaveDB.validate()` 做配表体检（interval/cap>0、mix 非空、id 存在、权重和 =1.0），测试已接上。

`EnemyDB` / `WaveDB` 均为 static 懒加载，从 `BalanceConfig.get_config()` 取数组，重复 id / 空 id 直接 `push_error` 丢弃。

---

## 6. 渲染与视觉

### 6.1 双管线

**A. 渗墨画布（GPU 乒乓反馈）** — `bleed_canvas.gd`

```
stamp(pts, red) → _pending
每帧：换面 _cur = 1 - _cur
  反馈底 ColorRect ← ink_bleed   （读另一面 src_tex：5-tap 模糊 + fade 消褪）
  盖章  PaintLayer ← ink_stamp   （读 prev_tex：Kubelka-Munk 减色混色）
输出 TextureRect ← ink_composite （叠纸颗粒）→ 场景 z=-80
```

双 `SubViewport` 固定 **1152×648**，`UPDATE_ALWAYS`。`bleed_enabled < 0.5` 时整条管线降级停摆。

**B. 矢量笔触（CPU）** — `ink_renderer.gd` / `water_renderer.gd` 在 bg / ink / fx 三个 `PaintLayer` 的 `_draw` 里画。

### 6.2 Shader

| shader | uniform | 默认 | 含义 |
|---|---|---|---|
| `ink_bleed` | `src_tex` / `blur_radius` / `fade` | — / 1.2 / 0.992 | 每帧模糊 + 消褪 ≈ 扩散方程 |
| `ink_stamp` | `prev_tex` | — | 减色叠墨，越叠越深 |
| `ink_composite` | `grain_tex` / `grain_strength` | — / 0.35 | 纸颗粒吃墨 |
| `paper_key` | `threshold` / `softness` | 0.55 / 0.08 | 亮度键控，抠掉 AI 图的宣纸亮底 |

### 6.3 样式资源

- **`InkBrushStyle`**（`ink_brush_style.gd`）：墨带宽 / 墨色 / 轮廓抖动 / 飞白 / 溅墨 / 收锋 / 渗墨 共 7 组约 30 项。
- **`InkStyle` provider**：加载优先级 `user://ink_style.tres` → `res://ink_style.tres` → 代码默认；`set_param()` 热改（duplicate 后写，不污染磁盘资源）+ `style_changed` 信号；渲染器每帧直读 `InkStyle.current`。
- **`WaterRenderer`**：飞鸟掠水式尾迹，40+ 参数存 `user://water_style.json`。每点带独立年龄，8 层叠画：浅水 halo → 水体主带 → V 形开尔文尾波 → 涟漪环 → 焦散丝 → 泡沫 → 接触切痕 → 脚印。
- **F1 `ink_editor`** 调的是 **WaterRenderer**（41 滑块 + 3 色板 + 试笔水面），存 `user://water_style.json`；墨笔样式走另一条 `ink_style.tres`。**两者别搞混。**

---

## 7. HUD（`hud.gd`，纯 `_draw`）

左上血条 + TV 条（带觉醒刻度）｜右上体力 / 斩杀 / 得分 / 倍率 / 存活秒数｜顶部回溯充能钟（满则闪 `R·回溯`）｜底部神纹录 8 格（古纹亮 / 神纹可绑 / 空碑暗 / 冷却黑罩 / 待觉醒）｜中央公告大字与 `斬`｜受击全屏红闪 + 伤害数字上飘｜状态调子（SPELL 淡蓝 / REWIND 红 / LAG 深）｜觉醒选碑面板｜结算面板（`时 尽` + 评级 + 总分 / 倍率 / 斩杀 / 金币 / 时砂 / 时滞数）。

---

## 8. 测试体系

规则（`AGENTS.md`）：**必须后台启动 + 重定向到 `run.log`**，再读日志搜 `<标签> PASS`。

```cmd
start "" /b "D:\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe" --headless --path d:\zhanji\moshi_demo res://tests/<场景>.tscn > d:\zhanji\moshi_demo\run.log 2>&1
```

| 测试 | 覆盖 | PASS 标签 |
|---|---|---|
| `smoke` | 主流程 PLAY→SPELL→DASH→BURST→表盘斩→REWIND→时滞→结算 | `SMOKE PASS` |
| `enemy_refactor_test` | 配置加载 / 四行为 / 4 套素材 / 精英复用 / 分裂无敌 / 清弹 | `ENEMY_REFACTOR PASS` |
| `wave_live_test` | 真实波表体检 + 时段查询 + 实机刷怪 + 敌弹致死 | `WAVE_LIVE PASS` |
| `bleed_test` | 渗墨画布：盖章队列 / 乒乓换面 / 开关降级 | `BLEED PASS` |
| `ink_style_test` | 样式加载 / 热改 / 存回读 / 重置 / 编辑器开关 | `INKSTYLE PASS` |
| `qdollar_test` | $Q 不变性（平移 / 缩放 / 倾斜 / 手抖 / 反写）+ 拒识 + 性能 | `QDOLLAR PASS` |
| `spell_test` | 施法链路、乱涂不误触、「时」接管状态 | `SPELL PASS` |
| `skill_fx_test` | 技能效果层 | `SKILLFX PASS` |
| `stroke_persist_test` | 笔形落盘，分 write / read 两趟跨进程验证 | `STROKE_PERSIST_WRITE PASS` / `STROKE_PERSIST PASS` |
| `spell_lab_test` | 调试台冒烟 | `SPELLLAB PASS` ⚠️ **禁止执行**（仍需同步维护） |

日志里没有 PASS 行 = 场景没跑到收尾，按 `AGENTS.md §2` 排查（先读日志 → `--check-only` 验语法 → `--import` 验全项目）。

---

## 9. 文档索引

| 文件 | 内容 |
|---|---|
| `docs/enemies.md` | 怪物系统速查（最全）：字段表、9 怪数值、帧动画规范、精英倍率、波表、体检、测试命令 |
| `docs/player.md` | 人物系统速查：血量 / 冲刺斩 / 表盘 / 回溯 / **笔墨消耗** / 七道神纹的字段表与改法 |
| `docs/怪物系统改动说明-v1.0.md` | 怪物精简为 4 种、精英复用、冲锋锁向、分裂无敌、删 BOSS |
| `docs/神纹系统改动说明-v1.1.md` | 6 固定咒语 → 2 古纹 + 6 空碑，$Q 识别器落地 |
| `docs/时间刺客-程序执行方案-v1.0.md` | 旧名「时间刺客」的程序执行方案（部分数值已过时，如单局 30s） |
| `AGENTS.md` | 工程规则：测试跑法、超时排查、脚本约定、编辑禁忌 |

---

## 10. 已知问题 / 技术债

1. **存档是空壳**：`login` 的「继续」只查 `user://save.cfg` 存不存在，无任何读写实现；`upgrades` 局外养成也不持久化。
2. **无胜利条件**：跑过 `seg5` 进永久平台期，只有失败结算。`时间刺客-程序执行方案` 里的「单局 30s」已与代码不符。
3. **数值已外置成两份总表**：怪表 / 波表 / 刷怪全局在 `data/balance.tres`，人物血量 / 冲刺斩 / 表盘 / 回溯 / 笔墨 / 神纹参数在 `data/player.tres`。仍留在代码里的只剩 `spell_match.gd` 的识别阈值与 `main.gd` 的演出常量（相机、抖动、拖尾、计分）。
4. **无物理层**：命中 / 接触全为纯距离数学，怪物重叠靠 `_separate` 手动推开。
5. **BOSS 骨架休眠**：`_tick_boss` 只是远程 + 冲撞组合，`boss_phase` 多阶段是空扩展位；总表 `enemies` 里也无 BOSS 条目。
6. **测试后门 `F3`** 一键回满 TV，出包前需摘。
7. **spell_lab 普通技能试录不落盘**，只有古代神纹持久化。
8. **渗墨画布固定 1152×648**，与 3000×3000 竞技场 + 未设分辨率的窗口耦合松散。
9. **`demo_test/` 与 `moshi_demo/` 共享同名旧脚本**（main / player / enemy / hud / shaders），改动时注意别改错工程。
10. **构建产物混入数据目录**：`moshi_demo/data/enemies/墨时 InkTime.exe` 应清掉。
11. **渗墨拓印层已停用**：`main.gd._ready` 不再创建 `bleed`（水面渲染改造中），调用点已加判空，恢复时记得一起去掉守卫。
12. **`skill_fx_test` 偶发假失败**：阿尔法突袭 / 落剑清空两条断言的时间余量卡得太紧，斩杀顿帧（`KILL_FREEZE`）一多就超时。与总表改造无关，改造前就存在，重跑即过。
