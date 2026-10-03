# Anime4K（vendored）

这里是从 [bloc97/Anime4K](https://github.com/bloc97/Anime4K) 原样复制的 GLSL 着色器源码，
只保留 Cezzu 实际用到的那几个文件。

| 项 | 值 |
| --- | --- |
| 上游 | https://github.com/bloc97/Anime4K |
| commit | `7684e9586f8dcc738af08a1cdceb024cc184f426` |
| 日期 | 2024-04-25 |
| 许可 | MIT（见 `LICENSE`）；`Anime4K_AutoDownscalePre_*.glsl` 由上游标注为 Unlicense / public domain |

## 为什么要 vendored

`cezzu/scripts/generate_anime4k_shaders.py` 会把这些 `.glsl` 翻译成 Metal Shading Language，
产物落在 `cezzu/CezzuKit/Sources/CezzuKit/Resources/Anime4K/`。产物也入 git ——
这样 CI 和普通 clone 都不需要 Python 环境，翻译结果的 diff 也能被 review。

## 不要手改这个目录

这里的文件是上游原样拷贝。要升级 Anime4K：

1. 换掉 `glsl/` 下的文件，更新上面表格里的 commit / 日期
2. 重跑 `python3 cezzu/scripts/generate_anime4k_shaders.py`
3. 跑 `swift test --filter Anime4K` 确认 manifest 解析和渲染图规划没退化

## 文件清单与用途

| 文件 | 用在哪个预设 |
| --- | --- |
| `Anime4K_Restore_CNN_S/M.glsl` | 高质档（Mode A）|
| `Anime4K_Upscale_CNN_x2_S/M.glsl` | 两个档位都用 |
| `Anime4K_Upscale_Denoise_CNN_x2_S/M.glsl` | 快速档（Mode C）|
| `Anime4K_Clamp_Highlights.glsl` | 全部预设（去振铃） |
| `Anime4K_AutoDownscalePre_x2/x4.glsl` | 全部预设（按输出尺寸提前降采样） |
