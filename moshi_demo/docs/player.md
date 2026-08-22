# 人物系统速查

人物的血量、冲刺斩、表盘行动点、回溯、**笔墨消耗**、七道神纹的数值，**全部收在一份总表**
`res://data/player.tres` 里（资源类型 `PlayerConfig`）。
**在 Godot 编辑器里双击它，Inspector 里改完 Ctrl+S 就生效，不用碰代码。**

怪物那边（血量 / 伤害 / 刷怪频率）在另一份 `res://data/balance.tres`，见 `docs/enemies.md`。
两份表互不重叠：**打人的数值在人物表，挨打的数值在怪物表。**

总表分七组：

| 组 | 管什么 |
|---|---|
| 生存 | 血量、受击无敌、**撞怪 / 中弹的受伤倍率**、时滞（体力）、挨打惩罚 |
| 冲刺斩 | 左键表盘斩与右键笔画斩共用的**速度 / 距离 / 命中半径 / 伤害** |
| 表盘 | 行动点上限与回复速率 |
| 回溯 | 钟表充能时长、回溯格数、重放伤害倍率、标记保留 |
| 笔墨 | 时间之力上限 / 回复、**每像素墨耗**、子弹时间流逝 |
| 觉醒 | 点亮空碑的门槛与概率 |
| 神纹 | 七道技能各自的**冷却**与效果参数 |

---

## 1. 我要改 XX，该动哪一行

下表的「改哪里」都指 **`data/player.tres` 的对应字段**。

| 想改什么 | 改哪里 | 默认 |
|---|---|---|
| **人物血量** | `player_hp` | 100 |
| **撞到怪掉多少血** | `contact_dmg_mult`——乘在怪自己的 `dmg` 上。0.5 = 只掉一半，0 = 撞不死人 | 1.0 |
| **中弹掉多少血** | `bullet_dmg_mult`——同上，乘在敌弹的 `bullet_dmg` 上 | 1.0 |
| **挨完一下无敌多久** | `hit_invuln`（秒）。调大更抗连击 | 0.6 |
| **一局能死几次** | `lag_max`（体力格数），HUD 右上角显示的就是它 | 3 |
| **死一次停多久** | `lag_time`（秒） | 3.0 |
| **一刀冲多远** | `dash_dist_base`（像素）。上限由 `dash_dist_cap` 卡 | 520 / 800 |
| **冲得多快** | `dash_speed`（像素/秒）。只影响速度，不影响落点 | 3200 |
| **一刀打多宽** | `dash_radius`（像素）。调大就更容易扫到怪 | 140 |
| **一刀打多疼** | `dash_dmg` | 20 |
| **连点太快 / 太卡** | `slash_min_gap`（两次左键斩的最小间隔，秒） | 0.15 |
| **挨打要不要打断 R 的蓄力** | `hit_charge_penalty`——**默认 0，挨打不掉充能**；填 3.0 恢复旧手感 | 0.0 |
| **能连砍几刀** | `ap_max_base`（行动点上限），回得多快看 `hour_period` / `ap_per_hour` | 3 |
| **回溯多久能按一次** | `clock_time`（钟表充满要几秒） | 12 |
| **回溯能重放几条** | `rewind_slots` | 5 |
| **回溯伤害够不够** | `rewind_mult`（乘在 `dash_dmg` 上） | 0.5 |
| **一管墨有多少** | `tv_max_base`（代码里 `tv_max()` 另有 1000 的封顶） | 1000 |
| **想画更长的线** | **`tv_cost_per_px` 调小**（1 px 花多少墨）。0.5 = 同一管墨画两倍长，0 = 不限长 | 1.0 |
| **画着画着墨就没了** | `bullet_tv_drain`（书写期间每秒白烧的墨）调小 | 30 |
| **子弹时间够不够慢** | `bullet_factor`（书写时怪的倍速），越小越慢 | 0.10 |
| **觉醒太难 / 太容易** | `bind_energy_ratio`（要烧掉起笔余额的几成）、`bind_chance`（过闸后的概率） | 0.70 / 0.50 |
| **某道神纹冷却** | 「神纹」组里那道技能的 `*_cd` | 见下表 |
| **某道神纹的威力 / 数量 / 范围** | 「神纹」组对应的子组，见第 3 节 | — |

---

## 2. 数值一览

### 2.1 生存与冲刺

| 字段 | 默认 | 说明 |
|---|---|---|
| `player_hp` | 100 | 归零进一次时滞，满血复活继续打 |
| `contact_dmg_mult` | 1.0 | 撞怪受伤倍率 |
| `bullet_dmg_mult` | 1.0 | 中弹受伤倍率 |
| `hit_invuln` | 0.6 | 挨完一下的无敌秒数 |
| `lag_max` / `lag_time` | 3 / 3.0 | 体力格数 / 单次时滞时长 |
| `hit_charge_penalty` | 0.0 | 挨打扣掉的钟表充能（秒）。**0 = 受伤不打断 R 的蓄力**，这是现行手感 |
| `hit_mult_penalty` | 0.2 | 挨打扣掉的分数倍率 |
| `dash_speed` | 3200 | 沿轨迹推进速度 |
| `dash_dist_base` / `dash_dist_cap` | 520 / 800 | 表盘斩距离 / 养成上限 |
| `dash_radius` | 140 | 冲刺命中半径 |
| `dash_dmg` | 20 | 冲刺沿途挂的标记伤害 |
| `post_dash_invuln` | 0.3 | 冲完的无敌秒数 |
| `slash_min_gap` | 0.15 | 两次左键斩的最小间隔 |

### 2.2 表盘与回溯

| 字段 | 默认 | 说明 |
|---|---|---|
| `ap_max_base` / `ap_max_cap` | 3 / 6 | 行动点上限 / 养成天花板 |
| `hour_period` | 1.0 | 时针一圈的秒数，也决定左键斩朝向变化快慢。1 秒一圈 = 每秒回 1 AP |
| `ap_per_hour` | 1.0 | 时针一圈回多少行动点 |
| `sec_period` / `ap_per_sec` | 0.5 / 0.25 | 秒针，买了指针升级才生效 |
| `min_period` / `ap_per_min` | 1.0 / 0.25 | 分针，二级指针升级才生效 |
| `clock_time` | 12.0 | 钟表充满要几秒（充满按 R 回溯） |
| `rewind_slots` | 5 | 能重放最近几条轨迹 |
| `rewind_mult` | 0.5 | 重放伤害倍率 |
| `rewind_path_time` | 0.15 | 重放单条轨迹的时长 |
| `burst_freeze` | 0.16 | 引爆结算的顿帧 |
| `mark_retain` | 1.5 | 标记保留时长，超时就重新计 |

### 2.3 笔墨（这就是「画多长」的账）

| 字段 | 默认 | 说明 |
|---|---|---|
| `tv_max_base` | 1000 | 一管墨有多少。**上面还压着 `Game.tv_max()` 的成长封顶 1000**，填更大不生效 |
| `tv_regen_base` | 240 | 每秒回多少（只在不书写时回）。满管约 4 秒回满 |
| `tv_cost_per_px` | 1.0 | **每画 1 px 花多少墨** |
| `bullet_factor` | 0.10 | 书写期间怪的倍速 |
| `bullet_tv_drain` | 30 | 书写期间每秒白烧的墨 |
| `bullet_min_time` | 0.2 | 起笔后至少多久才允许因墨尽自动收笔 |
| `bullet_exit_tv` | 10 | 墨低于它起不了笔 / 自动收笔 |

**一笔最长能画多少像素 ≈ `tv_max_base ÷ tv_cost_per_px`**（还要扣掉书写期间
`bullet_tv_drain × 秒数` 的流逝）。默认 1000 ÷ 1.0 = 1000 px；把 `tv_cost_per_px`
改成 0.5 就是 2000 px。写着写着墨见底时笔尖会「干涸」（`dry_pen`），线只画到买得起的位置。

> ⚠️ **封顶在代码里，不在总表**：`main.gd` 的 `tv_max()` 写着
> `minf(TV_MAX_BASE + 50 × 墨量升级, 1000.0)`。总表把 `tv_max_base` 调到 1000 以上不会有任何效果，
> 要更大的墨管得连这条封顶一起改。

### 2.4 神纹

| 神纹 | 冷却 | 主要参数（子组内） |
|---|---|---|
| 时·回溯 | `time_cd` 10 | 效果参数在「回溯」组 |
| 雷霆万钧 | `thunder_cd` 6 | `thunder_bolts` 6 道 / `thunder_dmg` 20 / `thunder_radius` 82 |
| 山崩地裂 | `quake_cd` 12 | `quake_waves` 6 轮 / `quake_gap` 0.5s / `quake_radius` 155 / `quake_dmg` 12 |
| 妖木精灵 | `ent_cd` 20 | `ent_count` 4 个 / `ent_life` 12s / `ent_speed` 155 / `ent_reach` 44 / `ent_dmg` 10 / `ent_gap` 0.7s |
| 水漫金山 | `flood_cd` 10 | `flood_dirs` 8 向 / `flood_speed` 540 / `flood_range` 640 / `flood_width` 34 / `flood_dmg` 16 |
| 时间领域 | `domain_cd` 16 | `domain_time` 6s / `domain_radius` 195 / `domain_dps` 14 / `domain_charge` 2.0 |
| 无限剑阵 | `swords_cd` 14 | 内 `sword_inner` 6 + 外 `sword_outer` 12 把 / 半径 115 与 245 / `sword_fall` 0.4s / `sword_radius` 58 / `sword_dmg` 22 |
| 阿尔法突袭 | `alpha_cd` 12 | `alpha_hits` 8 段 / `alpha_gap` 0.1s / `alpha_radius` 265 / `alpha_dmg` 12 |

> 所有神纹伤害还会再乘一道局外养成的 `skill_power()`（默认 1.0）。
> 神纹的**笔形**不在这份表里 —— 那是玩家画出来的，在 F2 调试台改，存 `user://spell_strokes.json`。

---

## 3. 代码入口

| 文件 | 职责 |
|---|---|
| `data/player.tres` | **人物总表**（`PlayerConfig`），编辑器双击即改 |
| `scripts/player_config.gd` | `PlayerConfig` 资源类：字段定义 + 全局单例读取 + `skill_cd(id)` |
| `scripts/main.gd` | `Game`：`_load_player_config()` 在 `_ready` 里把总表灌进本文件的大写量 |
| `scripts/player.gd` | `Player`：`take_hit(dmg, invuln_time)`，无敌秒数由 Game 按总表传入 |
| `scripts/spell_match.gd` | 笔形识别与神纹录骨架。冷却由总表覆盖，`SKILL_DEFS` 里的 `cd` 只是兜底 |

### 为什么 main.gd 里还是一堆大写名

那些 `DASH_SPEED` / `TV_COST_PER_PX` 已经不是 `const` 而是 `var`，只是**沿用大写命名**：
HUD、F2 调试台、十来个测试都按这些名字取值，改名等于连坐一大片。
它们的值在 `_load_player_config()` 里被总表覆盖，声明处写的字面量只是**加载失败时的兜底**。
**改数值请改 `data/player.tres`，改 main.gd 里的字面量没用**（会被总表盖掉）。

---

## 4. 测试

```cmd
:: 人物总表专项：数值灌入、受伤倍率、神纹参数与冷却、墨耗与可画长度
start "" /b "D:\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe" --headless --path d:\zhanji\moshi_demo res://tests/player_config_test.tscn > d:\zhanji\moshi_demo\run_player.log 2>&1
```

跑完读 `run_player.log`，末行应为 `PLAYERCFG PASS`。

改完总表建议再跑一遍 `smoke` / `spell_test` / `skill_fx_test`，确认没把数值调到玩法跑不通。

> `skill_fx_test` 对帧时序敏感，偶发假失败（阿尔法突袭 / 落剑清空这两条卡在余量边缘），
> 跟总表无关，重跑即可 —— 这条在改造前就存在。
