# Godot 4 蝙蝠敌人序列帧资产包

本包从提供的 RGBA 总览图中确定性切分，未使用生成式重绘。将本目录下的 `assets/bat_enemy` 复制到 Godot 4.x 项目的 `res://assets/` 下即可。

## 使用方式

1. 在场景中添加 `AnimatedSprite2D`。
2. 将 `sprite_frames` 指向 `res://assets/bat_enemy/sprite_frames/<动画名>.tres`。
3. 各资源内已写入建议 FPS 与循环设置；可按游戏节奏调整。
4. 原点按每帧画布中心统一，`AnimatedSprite2D.centered` 保持开启即可。

## 动画清单

| 动画 | 帧数 | FPS | 循环 | 画布 |
|---|---:|---:|:---:|---:|
| `idle` | 8 | 8.0 | 是 | 136×120 |
| `move` | 8 | 10.0 | 是 | 136×120 |
| `attack_windup` | 7 | 12.0 | 否 | 136×120 |
| `attack_release` | 8 | 12.0 | 否 | 136×120 |
| `hurt` | 7 | 12.0 | 否 | 136×120 |
| `death` | 9 | 10.0 | 否 | 136×120 |
| `projectile_charge` | 5 | 12.0 | 否 | 88×80 |
| `projectile_fly` | 7 | 16.0 | 是 | 176×88 |
| `impact_flash` | 5 | 14.0 | 否 | 112×120 |
| `impact_ring` | 5 | 14.0 | 否 | 112×120 |
| `power_charge` | 5 | 12.0 | 否 | 112×104 |
| `vanish` | 5 | 10.0 | 否 | 112×120 |
| `orbit_particle` | 19 | 16.0 | 是 | 80×128 |

## 目录

- `frames/<动画名>/`：逐帧透明 PNG。
- `sheets/`：水平等格 sprite sheets。
- `sprite_frames/`：Godot 4.x `SpriteFrames` 资源。
- `sprite_frames/bat_enemy_all.tres`：角色 6 组动画聚合资源，推荐直接用于敌人 `AnimatedSprite2D`。
- `sprite_frames/effects_all.tres`：7 组弹体与特效聚合资源。
- `animations.json`：帧数、FPS、循环与画布元数据。
- `preview/contact_sheet.png`：全资产预览。

## 源图限制

原总览图中部分弹体与底部环绕粒子存在半透明光晕互相贴合；本包按视觉中心和帧单元切分，边缘可能保留少量相邻光晕或出现截断。角色主体帧与大部分命中特效边界较清晰。
