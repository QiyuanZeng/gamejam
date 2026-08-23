# 项目规则（AI 与人共用）

适用范围：仓库根目录 `d:\zhanji` 下全部工作，重点是 Godot 项目 `moshi_demo`。

---

## 1. headless 跑场景：一律后台运行 + 日志落盘

**禁止**把 `--headless` 跑场景的输出直接怼到终端等它跑完。原因有二：

- 前台等待会被工具的 300s 超时硬砍断，**一行输出都拿不到**，等于白跑；
- 人和 AI 看的是两份东西，对不上账。

**统一做法**：后台启动，输出重定向到日志文件，然后读日志。

### 标准命令模板（Windows / cmd）

```cmd
:: 启动（立即返回，不阻塞）
start "" /b "D:\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe" --headless --path d:\zhanji\moshi_demo res://tests/<场景名>.tscn > d:\zhanji\moshi_demo\run.log 2>&1
```

跑完后读 `d:\zhanji\moshi_demo\run.log` 拿结果。

### 约定

| 项 | 规定 |
|---|---|
| 日志路径 | `moshi_demo/run.log`（单一入口，人和 AI 都看它） |
| 覆盖方式 | 每次启动 `>` 覆盖，不用 `>>` 追加 —— 免得新旧结果混在一起误判 |
| 需要留档 | 改用 `run_<用途>.log`，例如 `run_spell.log`、`run_fx.log` |
| 入库 | **不入库**，见 `.gitignore` 的 `run*.log` |
| 读日志 | 用 `read_file` 直接读，不要 `type` / `cat` |

### 判定结果

每套测试末尾都会打一行 `<标签> PASS` 或 `<标签> FAIL`，日志里搜这行即可：

```
SMOKE PASS / BLEED PASS / INKSTYLE PASS / QDOLLAR PASS
SPELL PASS / SKILLFX PASS / SPELLLAB PASS
STROKE_PERSIST_WRITE PASS / STROKE_PERSIST PASS
ENEMY_REFACTOR PASS / WAVE_LIVE PASS
PLAYERCFG PASS
REWIND_SHOT PASS / THUNDER_SHOT PASS   ← 这两条要带渲染跑（**不加** --headless）
```

日志里**没有**这一行 → 场景压根没跑到收尾，属于挂死或脚本加载失败，按下节排查。

---

## 2. 超时 / 挂死的排查顺序

headless 主循环没人调 `get_tree().quit()` 就会一直转。遇到不退出：

1. **先读日志**。有输出 → 看最后一行停在哪个阶段；无输出 → 脚本没加载起来（八成是缩进/解析错误）。
2. **验语法**：
   ```cmd
   "D:\godot\...\Godot_v4.7.1-stable_mono_win64.exe" --headless --path d:\zhanji\moshi_demo --check-only --script res://tests/<脚本>.gd
   ```
   注意：这条命令**不加载 autoload**，所以 `Identifier not found: AudioMgr` / `InkStyle` 这类报错是噪声，可以无视；真正的解析错误会明确指到行号。
3. **验全项目编译**：`--headless --path d:\zhanji\moshi_demo --import`，顺带刷新 `global_script_class_cache`。
4. 每个分阶段推进的测试都要埋**看门狗**：总时长超阈值就打印当前阶段并 `quit`，别让它挂机。

---

## 3. 测试脚本约定

- 位置：`moshi_demo/tests/<名>.gd` + 同名 `.tscn`（`.tscn` 只挂脚本，节点类型 `Node`）。
- 结尾必须 `get_tree().quit(1 if 有失败 else 0)`，退出码要能反映成败。
- 断言用 `_chk(cond, msg)`，逐条打 `ok` / `BAD`，失败项攒到 `fails` 数组，收尾统一 `FAIL: xxx` 复述一遍。
- 按 **id** 查技能/神纹，**不要**锚死数组下标 —— 技能表顺序改过不止一次。

---

## 4. 编辑源码的注意事项

- **不要**用 PowerShell 的 `-replace` 批量改含中文的源文件：默认大小写不敏感，且会把编码和换行搞坏。
- GDScript 缩进是 **Tab**。改内部类的方法体这类多层嵌套时，`edit` 的匹配容易错位，宁可带足上下文整块替换，或直接整份重写。
- `:=` 类型推断对无类型值会解析失败，遇到 `Cannot infer the type of ...` 就显式标注类型。

---

## 5. 明令禁止

- 不得执行 `res://tests/spell_lab_test.tscn` 这条测试命令（用户明确要求）。该文件仍需随改动同步维护，只是不跑。
