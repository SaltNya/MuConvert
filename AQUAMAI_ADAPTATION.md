# MuConvert × AquaMai mod 适配（2026-08 移植）

把此前 MaiConverter（Python）实现的 AquaMai mod 自定义语法全部移植到 MuConvert（C#）。
模拟器（SDEZ）+ AquaMai mod 环境下可直接游玩。

## 新增能力

| 语法 | 说明 | ma2 输出 |
|---|---|---|
| `m` 修饰符（地雷键） | tap/hold/星星头/touch/touchhold/slide 均支持 | `MNTAP`/`MNHLD`/`MNSTR`/`MNTTP`/`MNTHO`/`MNSI_`…（绝赞=MB、EX=MX、EX绝赞=MZ） |
| `<SV*...>` | 实时变速（全局/分类/NULL） | `SVSP\tbar\tgrid\t值` |
| `<HS*...>` | 传统下落速度 | `HS\tbar\tgrid\t值` |
| `<BOUNCE*...>` | 弹跳音符 | `BOUNCE\tbar\tgrid\t值` |
| `<SPAWN*...>` | 环形音符出生半径 | `SPAWN\tbar\tgrid\t值` |
| touch 区 slide 端点 | 任一端点是 touch 区（B/C/D/E）→ 自定义 slide | `NMSSS/BRSSS/MNSSS/MBSSS` + 滑条 code |
| touchstar | touch 区起点的星星头 | `NMSTP/BRSTP/MNTTP/MBTTP` |
| `*` 同头 slide | `1-5*-3` 两条路径共享一颗星（游戏=黄色 Each） | 两条 slide + 一个星头 |
| `rp`/`rq` | 反向圆弧 slide（沿 pp/qq 相反方向绕行） | 原生 `NMSXR`/`NMSXL`（Bend_R/Bend_L）+ 链段 `CNSXR`/`CNSXL` |
| 段间修饰符 | `2^4?rp2[...]` 中 `?` 无头标记写在段之间 | 正常解析并去星头 |
| 多段链 | `3-5-7>8v3` 连续星星 | `NMSI_`+`CNSI_`…（CN 段 wait=0、顺序 tick） |
| `&first` | 首小节偏移（秒，可为负） | 整体平移（音符/命令/变速） |
| UTF-8 BOM | 自动剥离 | — |

## 规则细节

- **A 区 = 按键**：slide 端点 `A3` 按按键 3 处理（原版 slide），`6>A3` → `6>3`；B/C/D/E 才转 NMSSS。
- **同头 slide**（MajdataView 约定）：`*` 后直接跟形状字符（`*-7`）= 同头（起点=星头键）；`*` 后跟显式位置（`*5-3`）= 链段续写（起点=该键，合法谱面中=上一段终点，`startKeyOverride` 供段类型计算/生成器取起点；不一致时仅警告）。原 g4 `'*' slideBody` 无法吃下 `*5-3` 的起点键 `5`，ANTLR 错误恢复会丢键并导致 `AssertionFailed` 崩溃——已修为 `'*' (KEY | TOUCH_AREA)? slideBody`。
- **链段时长**：按官方谱模型输出（每段独立时长、CN 段 wait=0、顺序 tick），游戏全程匀速。
- **统计**：地雷/NMSSS 按其判定类别并入（MNTAP→TAP、NMSSS→SLD、BRTTP→TTP）。
- **星头**：自定义 slide 的星头由转换器输出（NMSTR/MNSTR/BRSTR/MBSTR 或 NMSTP 系），同头只输出一个；**无头（`?`/`!`）不输出星头**——`Slide.NoHead` 标记在解析时设置（按键起点=去星头保留 Key；touch 区起点=去 touchstar），`AddCustomSlide` 星头分支守卫 `SharedHeadWith == null && !slide.NoHead`（曾漏掉无头检查导致 `5?<E3` 仍输出 NMSTR、`B1?<B5>B8m` 仍输出 touchstar，2026-08-23 修复）。
- **rp/rq 方向**（MajdataEdit/SimaiSharp 语义核实）：p=Curve 逆时针、q=Curve 顺时针、pp=EdgeCurve 逆时针（Bend_L）、qq=EdgeCurve 顺时针（Bend_R）；rp=反向 pp=顺时针=Bend_R（`NMSXR`）、rq=反向 qq=逆时针=Bend_L（`NMSXL`）。游戏原生类型，无需 NMSSS。
- **可重叠音符流**（majdata 新版功能）：`@{N}` 从当前时间起按 1/N 分拍独立推进，**不推进主谱时间**；多条 `@{N}` 流共用同一流起点；流内 metTag（`{8}` 等）改流内步长；流边界=行（`@{N}` 独占一行，下一非流行=主谱恢复，从流起点继续）。适合叠 SV 演出/交互。
- **流内 SV/HS 局部化（流类型化曲线）**：流内 `<SV*...>`/`<HS*...>` 是"流局部"演出，**不输出为全局 SVSP/HS 行**（否则会像全局曲线一样影响流外后续音符）。每条流分配自增类型键 `s1`/`s2`/...，流内命令输出为类型化曲线行 `SVSP <bar> <grid> s1=50.0`（`Commands` 机制原样输出，值=流键+倍率）；流内音符行尾附加 `s{N}` 标记字段（`AppendStreamId`，追加在 Extra 之后）。游戏端（AquaMai）读取行尾 `s{N}` 把该音符的曲线类型键设为 `s{N}` → 只吃本流曲线、与主谱（全局/普通类型）完全隔离（无本流曲线 = 原速 1，绝不跟随全局）。主谱命令（流外）照常输出为全局命令。
- **波形拍号**：`@分子/分母`（如 `@17/8`）仅影响编辑器波形强弱拍网格，对 ma2 输出无影响 → 忽略（不产生音符）。注意与 `@` 星头修饰（STAR_TO_TAP，如 `@5-3`）区分：`@` 后是 `数字/数字` 才是拍号。

## 改动文件

- `parser/mai/Simai.g4` — m 修饰符、COMMAND 词法、touch 区 slide 端点、touch 头、OVERLAP_MARKER/WAVE_TIME_SIG 词法（重叠流/波形拍号）、rp/rq、`*` 链段续写起点键（`'*' (KEY | TOUCH_AREA)? slideBody`）
- `parser/mai/SimaiParser.cs` — IsMine、命令提取、touch 头/端点解析、A→按键环、重叠流（overlapMode/overlapBase/streamOffset/mainStep/lastUnitLine，流内不推进主谱、行边界结束流；流 ID 计数 streamSeq/currentStreamId，流内 SV/HS 输出流类型化曲线行 `s{N}=倍率`）、波形拍号忽略、链段起点键（startKeyOverride）
- `chart/mai/Note.cs` / `Slide.cs` / `MaiChart.cs` — IsMine、StartArea/EndArea、Commands、Shift 覆盖；Slide.cs 另加 `startKeyOverride`（链段续写段起点）供 `EndKey`/`SlideSegment.StartKey` 优先返回、`NoHead`（无头标记）；Note.cs 另加 `StreamId`（所属流类型键 s1/s2/...，null=不在流内）
- `generator/mai/MA2Generator.cs` — 地雷标签、NMSSS 自定义 slide（code 生成移植自 MaiConverter）、SVSP/HS/BOUNCE/SPAWN 行、touchstar、统计改写；AddTap/AddTouch 经 `AppendStreamId` 附加流类型键 `s{N}`（流内变速由流曲线驱动）
- `chart/mai/Statistics.cs` — 自定义 slide 的 touchstar 头（NMSTP 系）计入 TTP 统计
- `Program.cs` — &first 平移、BOM 剥离
- `MuConvert.csproj` — TargetFramework net10.0 → net9.0、LangVersion preview（`field` 关键字）、移除 Antlr4BuildTasks（zh-CN Windows 路径乱码），generated 解析器直接检入
- `generated/` — ANTLR 生成的 C# 解析器（手工 `java -jar antlr4-4.13.1-complete.jar -Dlanguage=CSharp -no-listener -visitor -package MuConvert.Antlr -o generated parser\mai\Simai.g4` 生成，重新生成后无需改 csproj）
- `utils/Utils.cs` — AppVersion 不再假定 `+<sha>` 后缀（无 git 仓库时 MinVer 给 `0.0.0-alpha`）

## 构建

```
dotnet restore   # 需要网络（NuGet）
dotnet build -c Release
dotnet run -- <maidata.txt 或 .txt> [-l 难度]
```

> 注意：ANTLR jar 若损坏（antlr4buildtasks 自动下载中断），从
> `https://repo1.maven.org/maven2/org/antlr/antlr4/4.13.1/antlr4-4.13.1-complete.jar` 手动下载到
> `%USERPROFILE%\.m2\antlr4-4.13.1-complete.jar`（约 2.1MB）。

## 已知限制

- `1d` 形式的 D 区写法未支持（用 `D1`）。
- 自定义 slide 的 v/w 形状无法表达（跳过并警告）。
- 旧版 MA2_103 输出路径不支持地雷/NMSSS（降级为普通音符）。
