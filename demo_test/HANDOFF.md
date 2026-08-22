# HANDOFF · 时间刺客 v0.3 原型期

> 交接时间：2026-08-22
> 交出方：本次 AI Coding 会话（proto/clock-swing）
> 接手方：下一位开发同学
> 基准 commit：`78848f4`

---

## 一、项目背景（30 秒速读）

《时间刺客》GameJam 版，Godot 4.7.2。

**核心卖点**：割草蓄力 → 回溯引爆。左键斩击是唯一移动方式（朝脚下时钟表盘指针方向），斩击路径可被回溯大招二次利用引爆。

**策划案**：[`时间刺客-v0.3.md`](file:///c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\时间刺客-v0.3.md)
**工程**：`gamejam-godot/demo_test/`
**分支**：`proto/clock-swing`（7+ commit 领先 main，后续 P1 稳后开 PR merge main）

---

## 二、当前进度

### ✅ 已完成（本轮 AI Coding 全部 commit 进 proto/clock-swing）

| 模块 | 改动 | commit |
|---|---|---|
| 表盘修复 | `_paint_clock` draw_* 加 l. 前缀，表盘不再黑 | `85ddbde` |
| 行动点系统 | 取代 swing_cd，指针2s/圈+1点，表盘圆点显示 | `8aef772` |
| 怪不冻结 | DASH/BURST/REWIND 态敌人继续移动 | `8bd7f38` |
| 数值对齐 | 怪血/速/密度×3调大，REWIND_MULT 1.0 | `25155a7` |
| 相机无限画布 | ARENA 3000×3000 + Camera2D 死区跟随 + 纸纹平铺 | `919f62f` + `163f784` |
| P0 BUG-01 | 玩家不死亡，受击扣 8s 充能+清 combo | `9073b06` |
| P1 BUG-03/04/06 | 斩击500 + 回溯5段 + 60s时限+HUD倒计时 | `2626b99` |
| P1 BUG-08 | 万象斩「斩」全屏-30HP + TV数值5倍对齐 + 施法UI提示 | `fd8cc9d` |
| P1 task-8 | 右键子弹时间 0.3×（time_scale+音频，四处恢复点，HUD real_time 补偿）；顺手修 hud.gd 存量 parse error（上棒"提示消失"根因） | `9aa742e` |
| P2 BUG-13/15 | v2 画墨死代码清理（-374 行）+ smoke 重写 v0.3 协议 | `875c9b7` |
| P2 BUG-10 | 得分倍率系统：+0.1/杀、上限 3.0、受击减半下限 1.0，HUD 显示 ×N.N | `f50005c` |
| P2 BUG-07 | 爆魉连锁怪：死亡起爆 130px/-32HP，只伤怪，Wave5+ 占 15% | `78848f4` |
| 数值表 | [`BALANCE.md`](file:///c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\gamejam-godot\demo_test\BALANCE.md) | `9073b06` |
| 测试文档 | [`docs/TEST_v0.3_P0_P1.md`](file:///c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\gamejam-godot\demo_test\docs\TEST_v0.3_P0_P1.md) 9条用例 | `fd8cc9d` |

---

## 三、代码地图（关键位置）

| 功能 | 文件 | 行/函数 |
|---|---|---|
| 时钟斩主逻辑 | `scripts/main.gd` | `_begin_swing_dash()` L~392 |
| 行动点回复 | `scripts/main.gd` | `_process()` State.PLAY 分支 L~248 |
| 表盘绘制 | `scripts/main.gd` | `_paint_clock(l)` L~404 |
| 相机死区跟随 | `scripts/main.gd` | `_process()` 末尾 L~290 |
| 受击不死亡 | `scripts/main.gd` | `_check_contact()` L~702 |
| 60s 时限 | `scripts/main.gd` | `round_timer` + `_process()` L~283 |
| 咒语识别 | `scripts/spell_recognizer.gd` | `recognize()` |
| 咒语执行 | `scripts/spell_caster.gd` | `_cast_shi()` / `_cast_zan()` |
| HUD 绘制 | `scripts/hud.gd` | `_paint()` |
| 怪物速度 | `scripts/main.gd` | `enemy_speed_factor()` L~283 |

---

## 四、下一棒待做（按优先级）

### 🔴 P1 还剩（0 条，全部完成 ✅）

~~**task-8 右键子弹时间**~~（已完成）
- `_begin_spell()` 进 SPELL_DRAW 时 `Engine.time_scale = 0.3` + `AudioServer.playback_speed_scale = 0.3`
- `_release_spell()` / `_game_over()` / `_ready()` / `_on_editor_closed()` 四处恢复 1.0，防 time_scale 残留
- HUD 闪烁动画改用 `real_time`（delta/time_scale 补偿），子弹时间下动画速度正常
- SPELL_DRAW 怪速因子归一为 1.0（全局 time_scale 已减速，防双重减速）
- 附带修复：hud.gd:72-73 `:=` 类型推断 parse error（fd8cc9d 存量 bug，上棒"提示消失"根因）

### 🟡 P2 内容缺失（bug_list 里的）

按 [`bug_list_v0.3对齐.md`](file:///c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\bug_list_v0.3对齐.md) 顺序：

1. **BUG-06** 结算评级 C~SS（框架在 `hud.gd` `_rating()` 函数，已有 5档评级逻辑，数值参数需校准）
2. ~~**BUG-07** 爆裂怪~~（已完成）：第四类"爆魉"boom，死亡 0.08s 后起爆，半径 130 内怪 -32 HP，只伤怪不伤玩家，链式级联；Wave 5+ 占 15%；占位外观（红棕墨团+朱砂脉冲核），`enemy_boom.png` 到位自动替换；smoke 有"boom chain kills 8"断言
3. ~~**BUG-10** 受击扣得分倍率~~（已完成）：击杀分 = 10 × 倍率；+0.1/杀、上限 3.0、受击减半下限 1.0；HUD 右上显示 ×N.N；参数见 BALANCE.md 第十节
4. ~~**BUG-13** 清理 v2 死代码~~（已完成）
   - `State.DRAW`/画墨四函数/v2 版 `_begin_dash`/`ink_path`/`dry_pen`/`path_alpha`/`DRAW_ENEMY_FACTOR` 全删
   - `ink_editor.gd` + `ink_editor.tscn` 删除（F1/F10 入口移除）
   - **保留**：`bleed_canvas.gd`（v0.3 冲刺/回溯墨痕在用）、`InkStyle` autoload（bleed/renderer 依赖）、ink 资源（combo 回墨在用；完全清理由 P3 task-11 处理）
   - BUG-15 顺带：`tests/smoke.gd` 重写为 v0.3 协议，13 断言全绿（含子弹时间/受击不死亡/时限）

### 🟢 P3 锦上添花

- `task-5` 引爆顿帧 + 范围扩散（`BURST_RADIUS`）
- `task-10` combo 里程碑重做（5连→充能加速，10连→范围溅射，15连→免费回溯）
- `task-9` 咒语识别模板扩充（目前每个咒语 2-3 样本，需 5+ 样本）
- `task-11` SpellCaster 双轨 ink 清理（`main.ink` vs `player.ink`）

---

## 五、已知坑（避免踩同一个坑）

| 坑 | 触发条件 | 处理方法 |
|---|---|---|
| 表盘黑屏 | `_paint_clock` 内 `draw_*` 不加 `l.` 前缀 | 必须写 `l.draw_line(...)` |
| 相机飘出 | 相机 lerp 系数太小追不上瞬移 | 用死区跟随，超 `CAM_SAFE=400` 时强制 snap |
| 背景全黑 | 纸纹固定世界坐标但 ARENA 太大玩家跑出范围 | `draw_texture_rect(..., tile=true)` 平铺世界坐标 |
| `Engine.time_scale` 副作用 | 改了 time_scale 影响 Audio + delta 全局 | HUD 倒计时用 real_time，Audio 速率要补偿 |
| .import 缓存残留 | 替换图片资源后游戏仍用旧图 | 删 `assets/*.png.import` + `.godot/imported/` 缓存，重跑自动重建 |
| bleed_canvas 世界坐标 | bleed 渲染固定在世界 0,0（1152×648）| 玩家从世界 (1500,1500) 出发，远离后墨痕消失，v0.4 再修 |

---

## 六、验收清单（上 main 之前必须全绿）

测试用例见 [`docs/TEST_v0.3_P0_P1.md`](file:///c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\gamejam-godot\demo_test\docs\TEST_v0.3_P0_P1.md)。

| 用例 ID | 描述 | 重要度 |
|---|---|---|
| TC-P0-01 | 表盘显示正常 | 阻塞 |
| TC-P0-02 | 玩家不死亡（被贴 20s 不 GameOver） | 阻塞 |
| TC-P0-03 | 鼠标乱晃玩家不动 | 阻塞 |
| TC-P1-01 | 行动点 3 连斩第 4 下无响应 | 高 |
| TC-P1-02 | 斩击距离明显大（500px） | 高 |
| TC-P1-03 | 回溯最多 5 段路径 | 高 |
| TC-P1-04 | 60s 后出结算面板 | 高 |
| TC-P1-05 | 连续斩击不出框 | 高 |
| TC-P1-06 | 右键画横线触发万象斩 | 中 |

---

## 七、合流时机建议

- P0+P1 全绿 → 开 PR: `proto/clock-swing` → `main`
- PR 时 main 上如有新美术（怪图/玩家图），cherry-pick assets 目录即可，不涉及代码冲突
- 另一位程序同学在 main 上的改动是 v0.2 旧架构（画墨冲刺），**会和 v0.3 玩法冲突**，需沟通让他暂停 main 玩法改动，只做美术/资源，等 PR 合入后再在新 main 上继续

---

*下一棒加油 ✊*
