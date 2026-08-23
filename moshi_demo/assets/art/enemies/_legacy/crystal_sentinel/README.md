# Crystal Sentinel — Godot 4 2D Asset Pack

Copy this folder into a Godot 4 project, or open this folder directly as a project. The ready scene is `godot_resources/crystal_sentinel.tscn`.

- All animation frames are transparent RGBA PNG, 256×256.
- Pivot convention: `(128, 224)` in source pixels; the scene offsets the centered sprite accordingly.
- Character animations: `idle`, `move`, `attack_shard_barrage`, `attack_halo_beam`, `spawn`, `death`.
- VFX animations: `crystal_projectile`, `halo_beam`, `spawn_crystal_vortex`, `death_shards`, `hit_spark`.
- SpriteSheets are single rows ordered left-to-right.
- Texture filtering: use Linear for painterly appearance, or Nearest for hard-edged scaling.

Godot files are text resources using format 3 and `AnimatedSprite2D`/`SpriteFrames`, compatible with Godot 4.x.
