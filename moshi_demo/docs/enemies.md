# 怪物系统速查

所有怪物的数值、素材、行为参数，以及刷怪节奏与配比，**全部收在一份总表**
`res://data/balance.tres` 里（资源类型 `BalanceConfig`）。
**在 Godot 编辑器里双击它，Inspector 里改完 Ctrl+S 就生效，不用碰代码。**

总表分三组：

| 组 | 字段 | 管什么 |
|---|---|---|
| 刷怪全局 | `max_enemies` / `spawn_margin` | 全场怪物数硬顶、刷怪点边界内缩 |
| 怪物 | `enemies`（9 项 `EnemyData`） | 每只怪的血量 / 伤害 / 速度 / 半径 / 素材 / 行为参数 |
| 波表 | `waves`（5 段 `WaveData`） | 每段的时段、**刷怪频率 `interval`**、场上上限 `cap`、配比 `mix` |

全场**只有 4 种怪**（4 套素材，一种行为一只），精英与分裂子体全部复用本体的图。

---

## 1. 一览表

### 4 种基础怪

| 行为 | id | 中文名 | 素材路径 |
|---|---|---|---|
| 近战 | `melee_mite` | 影蚋 | `assets/art/enemies/bear/frames/` |
| 远程 | `ranged_crystal` | 晶哨 | `assets/art/enemies/bat_enemy/frames/` |
| 冲锋 | `charger_fast` | 疾影 | `assets/art/enemies/small_boar/frames/` |
| 分裂 | `splitter_bomber` | 磐妖 | `assets/art/enemies/horned_blob/frames/` |

| id | hp | speed | dmg | radius |
|---|---|---|---|---|
| `melee_mite` | 10 | 60 | 8 | 30 |
| `ranged_crystal` | 24 | 50 | 12 | 48 |
| `charger_fast` | 14 | 130 | 6 | 22 |
| `splitter_bomber` | 16 | 80 | 10 | 26 |

### 派生（不新增素材）

| id | 中文名 | 说明 | 素材 |
|---|---|---|---|
| `splitter_bomber_shard` | 磐妖碎块 | 磐妖死亡分裂出的子体，`tex_target 77`＝本体 128 的 **0.6 倍** | 同磐妖 |
| `elite_melee` | 影蚋·精英 | 复用影蚋帧动画，放大 + 发光 | 同影蚋 |
| `elite_ranged` | 晶哨·精英 | 复用晶哨帧动画 | 同晶哨 |
| `elite_charger` | 疾影·精英 | 复用疾影帧动画 | 同疾影 |
| `elite_splitter` | 磐妖·精英 | 复用磐妖帧动画，死后同样炸出 2 只**普通**碎块 | 同磐妖 |

> `enemies` 一共 9 项，但**只用到 4 套美术资源**，且四套全是帧动画。
> 弃用素材全部收在 `assets/art/enemies/_legacy/`：`shadow_mite/`（旧近战帧动画包）、
> 旧水墨单图 `enemy_fast/tank/blob.png`、`boss_wuming.png` 等，均已无人引用。

---

## 2. 我要改 XX，该动哪一行

下表的「改哪里」都指 **`data/balance.tres` → `enemies` 里对应那一项**（波表相关的指 `waves`）。

| 想改什么 | 改哪里 |
|---|---|
| **换模型（单张贴图）** | `tex`，填 png 路径；同时把 `anim_dir` 清空 |
| **换模型（帧动画）** | `anim_dir`，指向动画根目录；`tex` 清空 |
| **贴图太大/太小** | `tex_target`（缩放后的目标边长，像素） |
| **换动作** | 在 `anim_dir` 下加/改子目录即可，目录名 = 状态名，见第 4 节 |
| **攻击动画对不上** | `anim_attack` 填该怪攻击动画的**子目录名**（如 `attack_shard_barrage`） |
| **锚点飘了 / 人物偏出判定圈** | 勾 `use_pivot`，`pivot_frac` 填主体在画布里的**相对锚点**：填主体外接框中心（如 `(0.5, 0.66)`）＝主体压在判定圆心上；填 `(0.5, 0.875)` ＝脚底对齐节点原点。注意 x 一般保持 `0.5`，否则左右镜像会偏 |
| **朝向反了（往左走却朝右）** | 素材原图**朝左**的包才勾 `art_faces_left`；朝右或正面对称的包保持不勾。现行四包全是不勾 |
| **画布留白多导致人物太小** | `tex_target` 按 `想要的主体尺寸 ÷ 主体占画布比例` 反推。512 画布主体只占 0.6，就要填约 1.6 倍 |
| **血量/速度/伤害** | `hp` / `speed` / `dmg` |
| **技能打不打得到** | `radius`——所有技能命中都拿它算，调大即变好打 |
| **分裂子体太容易被秒 / 太肉** | `split_child_invuln`，子体出生无敌秒数，默认 0.5 |
| **掉落与计分** | `score` / `coin` / `tv` |
| **换了本体图，精英跟着换** | 精英那项的 `tex` / `anim_dir` 要**手动同步**成本体的（测试会卡这条） |
| **刷怪时段与配比** | `waves` 里对应那一段的 `until_time` / `mix`，见第 7 节 |
| **刷怪快慢 / 场上上限** | `waves` 对应段的 `interval` / `cap`，见第 7 节 |
| **全场怪物数硬顶** | 总表根部的 `max_enemies`（默认 130） |
| **刷怪点离边界多远** | 总表根部的 `spawn_margin`（默认 26） |
| **加一只新怪** | `enemies` 数组 `+` 一项 → 选 `New EnemyData` → 填 `id` 与数值 |
| **加一段新波次** | `waves` 数组 `+` 一项 → 选 `New WaveData` → 填 `until_time` / `interval` / `mix` |

### 帧动画怪必须是「透明底」

现行 4 只怪全走帧动画分支，素材一律**透明底 PNG**，不挂 shader。

`key_mat`（`shaders/paper_key.gdshader`）只在**单图分支**（填 `tex` 而非 `anim_dir`）才挂，
按亮度把米白宣纸底键控成透明（`threshold 0.55`）。所以：
- 填 `anim_dir` → 素材必须自带 alpha，**给纸底会直接显示成白方块**；
- 填 `tex` → 素材要**深墨主体 + 亮纸底**，别给透明底或深色底。

---

## 3. 行为与专属参数

`behavior` 决定这只怪每帧走哪条分支（`scripts/enemy.gd`）。

### 近战（`behavior = 0` MELEE）
直追玩家，只靠触碰造成 `dmg` 伤害，没有技能。
- `inertia`：勾上则高速惯性过弯（会冲过头再拐回来）。影蚋默认**关**，疾影开着。

### 远程（`behavior = 1` RANGED）
朝玩家移动，进到 `attack_range` 就停步开火。**子弹能被玩家的左键斩和右键神纹销毁。**

| 字段 | 含义 |
|---|---|
| `attack_range` | 进到这个距离停下来打 |
| `attack_cd` | 两发之间的间隔（秒） |
| `attack_windup` | 抬手时间，这段时间播 `anim_attack` 的动画 |
| `bullet_speed` / `bullet_dmg` / `bullet_radius` / `bullet_life` | 子弹速度 / 伤害 / 半径 / 存活秒数 |
| `bullet_color` | 子弹的染色：残影、外发光、描边环、销毁碎屑都用它。贴图缺失时退回画圆也用它 |

#### 子弹长什么样：贴图帧 + 残影 + 圆形兜底

弹体统一用蝙蝠包那套 7 帧贴图，与是哪只远程怪无关：

| 项 | 值 |
|---|---|
| 帧目录 | `assets/art/enemies/bat_enemy/effects/projectile_fly/`（7 帧） |
| 源图尺寸 | 176 × 88（`BULLET_TEX_W` / `BULLET_TEX_H`），弹头朝右、拖尾画在左边 |
| 图里亮核 | 位于横向 `0.65`（`BULLET_CORE_FRAC`），直径 44 px（`BULLET_CORE_DIA`） |
| 放大倍率 | 亮核画到判定直径的 `1.8` 倍（`BULLET_VIS_MUL`） |
| 残影 | 身后 3 节等距递减副本（`BULLET_GHOSTS`），叠一层外发光圆 |
| 播放速度 | 16 fps（`BULLET_ANIM_FPS`），按子弹自身寿命 `b.t` 循环 |

亮核对齐到判定点 `b.pos`，所以**改 `bullet_radius` 会同时改贴图大小和判定半径**。
残影 + 外发光是为了让高速位移的弹体在整条轨迹上都读得出来 —— 单张贴图一帧一跳，
静止看清楚、动起来就断片。贴图目录缺失时（`bullet_frames` 为空）退回旧的
「拖尾线 + 实心圆」，外圈描边环任何情况下都照画，它是给玩家的可击落提示。

#### 开火与受击特效

同一套蝙蝠包里的一次性序列帧，由 `main.gd` 的 `fx_packs` / `fx_sprites` 统一驱动：

| 时机 | 特效 | 位置 |
|---|---|---|
| 抬手前摇（`attacking` 置位那一帧） | `power_charge` | 怪身上 |
| 出弹瞬间 | `projectile_charge` | 枪口，朝飞行方向 |
| 玩家受伤（中弹与接触伤害共用） | `impact_flash` + `impact_ring` | 玩家身上 |
| 子弹被技能销毁 / 命中消失 | `vanish` | 消失点 |

特效跟着 `enemy_speed_factor()` 走：子弹时间里一起慢放，冻结时一起停。
播完最后一帧自动回收，不用手动清。

代码：`main.gd._load_bullet_frames()` / `_load_frame_dir()` 加载，`spawn_fx()` 起特效，
`_update_fx_sprites()` 推进，`_paint_enemy_bullet()` 与 `_paint_fx()` 绘制。

### 冲锋（`behavior = 2` CHARGER）
朝玩家移动，进到 `charge_range` 停步蓄力，**在预警红线出现的那一帧就把冲锋方向钉死**，
蓄满后沿这条线直冲出去。红线画的就是最终落点，蓄力途中玩家怎么跑都不会再修正方向——
所以走位躲得开才算数。方向锁定在 `enemy.gd` 的 `_lock_charge_dir()`，只在进 `windup` 时调一次。

| 字段 | 默认 | 含义 |
|---|---|---|
| `charge_range` | 600 | 进到这个距离开始蓄力 |
| `charge_time` | 2.0 | 蓄力时长（秒），预警条铺满的时间 |
| `charge_dist` | 900 | 冲锋总距离 |
| `charge_speed` | 900 | 冲锋速度 |
| `charge_cd` | 2.5 | 冲完到下次能再蓄力的间隔 |
| `charge_warn_color` | 朱砂红 | 预警带颜色 |

### 分裂（`behavior = 3` SPLITTER）
移动行为同近战。被击杀时炸出 **2 只子体**，子体用同一张图缩到 0.6 倍，再打死就彻底消失。
子体出生自带一段无敌，期间免疫一切伤害与标记，贴图会快速闪烁提示。

| 字段 | 值 | 含义 |
|---|---|---|
| `split_count` | 2 | 分裂出几个 |
| `split_child_id` | `splitter_bomber_shard` | 子体用哪份配置。**留空 = 不分裂** |
| `split_spread` | 34 | 子体围着尸体散开的半径 |
| `split_child_invuln` | 0.5 | 子体出生无敌秒数。**填 0 就等于关掉** |

> **为什么必须有这段无敌**：分裂怪的 `legacy_type` 是 `bomber`，死亡时会在原地埋一颗
> 爆裂连锁（半径 90px），而子体就撒在爆心 34px 内。没有无敌的话，子体生出来的下一瞬
> 就被自家爆炸连同范围技能一起清场，玩家根本看不到分裂。

> 子体的 `split_child_id` 是空的，所以不会二次分裂。
> `elite_splitter` 死后同样炸出 2 只**普通**碎块，不是精英碎块。

---

## 4. 帧动画目录规范

**所有怪物美术统一放在 `assets/art/enemies/<包名>/frames/` 下**，`anim_dir` 一律指到 `frames/`。
`frames/` 下**每个子目录 = 一个动画状态**，目录名随美术包，代码不写死。
子目录内所有 `.png` 按文件名排序即帧序列（要补零，`00/01` 不能写成 `0/1`）。
名为 `effects` 的子目录会被跳过。特效 / 部件 / 拼图大图放在包根的 `effects/`、`vfx/`、
`characters/`、`sheets/` 里，不会被当动作读。

```
assets/art/enemies/
├── bear/                   影蚋（近战）
│   ├── frames/  idle/ move/ attack/ death/
│   └── sheets/  bear_sprite_frames.tres
├── bat_enemy/              晶哨（远程）
│   ├── frames/   idle/ move/ hit/ death/ attack_windup/ attack_release/
│   ├── effects/  projectile_fly/ projectile_charge/ power_charge/
│   │              impact_flash/ impact_ring/ vanish/ orbit_particle/
│   └── sheets/ animations.json README_zh.md
├── small_boar/             疾影（冲锋）
│   └── frames/  idle/ move/ attack/ death/
├── horned_blob/            磐妖（分裂）
│   └── frames/  idle/ move/ attack/ death/
├── preview/                美术包预览场景（不参与游戏）
└── _legacy/                弃用素材：shadow_mite/ crystal_sentinel/ 与旧单图
```

> `bat_enemy/effects/` 不在 `frames/` 里，所以不会被当动作读；它由 `main.gd` 单独加载，
> 见第 6 节。

必备与可选：

| 状态目录 | 必要性 |
|---|---|
| `idle` | **必须**，没有 idle 就不会走帧动画分支 |
| `move` | 强烈建议，缺了移动时会回落 idle |
| `death` | 有才播死亡动画，否则死了直接消失 |
| `hit` / `spawn` | 可选，名字**写死**为 `hit` / `spawn` |
| 攻击 / 蓄力 / 收招 | 目录名任意，在 `.tres` 里用 `anim_attack` / `anim_charge` / `anim_release` 指过来 |

> 远程怪一次开火的动作顺序：`anim_attack`（前摇，`attack_windup` 期间播）→ 出弹瞬间切
> `anim_release`（收招，按帧数自动算时长）→ 回 `move` / `idle`。
> 现行四包**只有蝙蝠有 `hit`**，其余受击回落 idle；四包都没有 `spawn`。
> 帧率固定 `anim_fps = 12`（`enemy.gd`），不能按怪单配；同一状态内**所有帧尺寸必须一致**，
> 缩放只看 `idle[0]` 的最长边。

### 左右朝向

`enemy.gd:_update_facing()` 每帧算一次朝向：**在动**就按 `velocity.x`，**停着**就看向玩家
（阈值 5px/s，低于阈值不翻，避免原地抖动）。结果写进 `sprite.flip_h`：

```
flip_h = face_left != cfg.art_faces_left
```

即代码默认**素材朝右**，往左走时水平镜像；素材本身画的是朝左的包，勾上 `art_faces_left`
把镜像逻辑反过来。单图怪（填 `tex`）走同一套逻辑。

> 镜像是 `Sprite2D.flip_h`，只翻贴图不动绘制矩形，所以 `pivot_frac.x` 必须是 `0.5`，
> 否则翻转后主体会左右偏移。

状态切换规则（`scripts/enemy.gd` 的 `_update_anim`）：
`spawn` → `hit`（受击 0.22s）→ `anim_attack`（远程抬手中）→ `anim_charge`（蓄力中，留空则不切）
→ `move`（速度 > 5）→ `idle`。找不到的状态一律回落 `idle`。

---

## 5. 精英怪

精英**不新建行为、不新建素材**，就是拿本体的图放大 + 改色发光 + 独立数值。

| 字段 | 作用 |
|---|---|
| `is_elite` | 勾上，身周多三层呼吸光环（`_draw_elite_glow()`） |
| `elite_of` | 本体的 id。测试会拿它校验「精英必须复用本体素材」 |
| `scale_mul` | 放大倍率。**同时放大 `tex_target` 与 `radius`**，填完不用再手调这两个 |
| `tint` | 改色，叠乘到 sprite。分量可以超过 1（提亮） |

现行统一倍率（4 份精英一致）：

| 项 | 相对本体 |
|---|---|
| `scale_mul` | 1.5 |
| `hp` | ×4 |
| `dmg` | ×1.8 |
| `speed` | ×0.85 |
| `score` / `coin` | ×3 |
| `tv` | ×2.5 |
| `tint` | `(1.3, 1.05, 0.75)` 暖金提亮 |

实际数值：

| id | hp | speed | dmg | 实效 radius | score | coin | tv |
|---|---|---|---|---|---|---|---|
| `elite_melee` | 40 | 51 | 14.4 | 45 | 30 | 3 | 20 |
| `elite_ranged` | 96 | 42.5 | 21.6 | 72 | 135 | 9 | 65 |
| `elite_charger` | 56 | 110.5 | 10.8 | 33 | 45 | 3 | 25 |
| `elite_splitter` | 64 | 68 | 18 | 39 | 75 | 6 | 30 |

> 「实效 radius」= `radius × scale_mul`，是技能真正拿去判定命中的值。
> 精英的远程/冲锋参数（`attack_cd`、`charge_time` 等）也单独调过，比本体更凶。

---

## 6. 代码入口

| 文件 | 职责 |
|---|---|
| `data/balance.tres` | **配平总表**（`BalanceConfig`）：刷怪全局 + 9 只怪 + 5 段波表，编辑器双击即改 |
| `scripts/balance_config.gd` | `BalanceConfig` 资源类，总表的结构定义 + 全局单例读取 |
| `scripts/enemy_data.gd` | `EnemyData` 资源类，怪物条目的字段定义都在这 |
| `scripts/enemy_db.gd` | `EnemyDB`，读总表的 `enemies` 建 id 索引 |
| `scripts/enemy.gd` | `Enemy` 单类，按 `behavior` 分发行为 + 绘制 + 预警与精英光环 |
| `scripts/wave_data.gd` | `WaveData` 资源类，波段条目的字段定义 + 按权重抽怪 |
| `scripts/wave_db.gd` | `WaveDB`，读总表的 `waves` 按 `until_time` 排段 + 配表体检 |
| `scripts/main.gd` | 刷怪（`spawn_enemy_at`）、分裂（`_split_on_death`）、敌方弹幕、伤害与击杀 |

### 命中判定说明
本项目**不用物理引擎**，所有命中都是距离数学：技能遍历 `Game.enemies` 数组，
比 `距离 <= 技能半径 + cfg.radius`。所以：

- 加新怪不用配碰撞层，填好 `radius` 就能被所有技能打中。
- 敌方子弹同理，被 `clear_enemy_bullets_in()` / `clear_enemy_bullets_seg()` 按半径销毁。
  左键斩、雷霆、山崩、水漫、领域、剑阵、爆裂连锁都已接上清弹。

### 精英光环画在哪
`_draw_elite_glow()` 由 `_draw()` **无条件调用**，不能塞回 `_draw_body()`——
后者只在「既没贴图也没帧动画」时才走，而现在四种怪全是贴图怪。

### BOSS
BOSS 配置已删。`EnemyData.Behavior.BOSS` 枚举与 `enemy.gd` 的 `_tick_boss()`
保留为休眠骨架（枚举在末位，不影响 0–3 的取值），以后要加 BOSS 时直接在总表的
`enemies` 里加一项、填 `behavior = 4` 即可。

---

## 7. 刷怪表（可配）

### 7.1 局的结束条件

**本局没有时限。** 唯一的结束方式是**体力耗尽**：血量归零进一次时滞（满血复活继续打），
时滞用满 `LAG_MAX = 3` 次后结算。HUD 右上角常驻显示 `体力 3/3`，剩最后一格会转朱砂红。
`run_time` 依然在跑，但已降级为「本局撑了多久」的统计量 + 波表推进依据。

### 7.2 配置位置

`data/balance.tres` → `waves` 数组，5 段：

```
waves
├── seg1_opening     0 – 5s      开局
├── seg2_rush        5 – 12s     冲锋入场
├── seg3_ranged      12 – 20s    远程 + 分裂 + 首精英
├── seg4_elite       20 – 27s    三种精英
└── seg5_plateau     27s 以后    永久平台期
```

段与段按 `until_time` 从小到大自动排队，**数组顺序不影响段序**。
加一段新波次 = `waves` 数组加一项，把 `until_time` 排在想插入的位置即可，不用改代码。

### 7.3 字段说明

| 字段 | 含义 |
|---|---|
| `id` | 段名，只用于调试和文档对照 |
| `until_time` | `run_time` 小于它就走这一段（秒）。**最大的那一段兼作永久平台期** |
| `interval` | 每隔多少秒刷一只。**越小刷得越快**——这就是刷怪频率 |
| `cap` | 本段场上怪物数上限，还受总表 `max_enemies = 130` 硬顶约束 |
| `mix` | `EnemyData.id` → 权重的字典，**权重和要等于 1.0** |
| `note` | 这一段想营造什么节奏，写给人看的 |

### 7.4 五段总表

| 段 | 时间 | 刷新间隔 | 场上上限 | 强度 |
|---|---|---|---|---|
| `seg1_opening` | 0 – 5s | 0.50s / 只 | 18 | 摸手感 |
| `seg2_rush` | 5 – 12s | 0.38s / 只 | 28 | 开始要走位 |
| `seg3_ranged` | 12 – 20s | 0.30s / 只 | 38 | 弹幕登场 |
| `seg4_elite` | 20 – 27s | 0.24s / 只 | 48 | 场面拥挤 |
| `seg5_plateau` | 27s 以后（**永久**） | 0.18s / 只 | 64 | 全局最高强度 |

> 实测：钉在平台期打 12 秒，场上稳定在 50～55 只。

### 7.5 每只怪什么时候出、占多少

横排是时间段，格子里是该怪在这一段的**出现权重**（空 = 这段还不刷它）。每段合计 100%。

| 怪 | 0–5s | 5–12s | 12–20s | 20–27s | 27s+ |
|---|---|---|---|---|---|
| `melee_mite` 影蚋（近战） | **100%** | 75% | 45% | 34% | 26% |
| `charger_fast` 疾影（冲锋） | — | 25% | 20% | 18% | 16% |
| `ranged_crystal` 晶哨（远程） | — | — | 20% | 18% | 18% |
| `splitter_bomber` 磐妖（分裂） | — | — | 10% | 14% | 14% |
| `elite_melee` 影蚋·精英 | — | — | 5% | 6% | 8% |
| `elite_charger` 疾影·精英 | — | — | — | 5% | 7% |
| `elite_ranged` 晶哨·精英 | — | — | — | 5% | 6% |
| `elite_splitter` 磐妖·精英 | — | — | — | — | 5% |

各阶段的登场节奏：

- **0–5 秒**：只有影蚋。纯近战，先让玩家把斩击手感摸熟。
- **5 秒**：冲锋兵入场。冲锋预警条第一次出现，开始需要走位。
- **12 秒**：晶哨（远程）+ 磐妖（分裂）+ 首只精英（影蚋·精英）。战场开始有弹幕，逼玩家用技能清弹。
- **20 秒**：精英扩到三种（近战 / 冲锋 / 远程），近战占比继续下滑。
- **27 秒以后**：进入永久平台期，磐妖·精英补位，四种精英到齐、合计占 26%，比例定死不再变化。
  想让后期更凶就调 `waves` 里 `seg5_plateau` 那一项的 `interval` / `cap`。

> `splitter_bomber_shard`（磐妖碎块）**不在任何波段里**，它只由磐妖死亡分裂产生。

### 7.6 配表体检

`WaveDB.validate()` 会把配歪的地方列出来，测试里已经接上，跑测试就能发现：

- `interval` / `cap` 不是正数
- `mix` 是空的
- `mix` 引用了 `enemies` 里不存在的怪 id
- 某个权重不是正数
- **权重和不等于 1.0**

---

## 8. 测试

```cmd
:: 怪物系统单测
start "" /b "D:\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe" --headless --path d:\zhanji\moshi_demo res://tests/enemy_refactor_test.tscn > d:\zhanji\moshi_demo\run_enemy.log 2>&1

:: 实机刷怪 + 波表配表校验
start "" /b "D:\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe" --headless --path d:\zhanji\moshi_demo res://tests/wave_live_test.tscn > d:\zhanji\moshi_demo\run_wave.log 2>&1
```

跑完读对应日志，末行应为 `ENEMY_REFACTOR PASS` / `WAVE_LIVE PASS`。

- `enemy_refactor_test`：配置加载、**四类行为各只有 1 只**、**全场只用 4 套素材**、
  **精英复用本体图**、四类行为实测、清弹接口、分裂 2 子体、精英倍率、标记/伤害/击杀链路。
- `wave_live_test`：波表配表体检、时段查询、提速数值、真实主循环刷怪、无时限验证、敌弹致死进时滞。

> **注意**：这些测试对帧时序敏感，**必须串行跑**。同时开两个 Godot 实例会让 `smoke`
> 之类的用例假失败。
