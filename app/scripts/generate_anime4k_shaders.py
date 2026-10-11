#!/usr/bin/env python3
"""把 vendored 的 Anime4K GLSL 着色器翻译成 Metal Shading Language。

输入：`vendor/Anime4K/glsl/*.glsl`（mpv user-shader 格式）
输出：`app/TubeKit/Sources/TubeKit/Resources/Anime4K/`
      ├── <ShaderID>.metal   每个 pass 一个 compute kernel
      └── manifest.json      pass 元数据（Swift 侧的 Anime4KShaderCatalog 读它）

产物入 git。改了这个脚本或换了上游 shader 之后重跑一次，然后 review diff。

## mpv user-shader 格式回顾

一个 `.glsl` 文件里串了多个 pass，每个 pass 由一段 `//!` 指令头 + 一个 `vec4 hook()` 组成：

    //!DESC    人类可读描述
    //!HOOK    MAIN | PREKERNEL      在哪个阶段插入
    //!BIND    <名字>                 绑定一张输入纹理，可重复
    //!SAVE    <名字>                 输出写到哪张纹理（缺省 = 写回 HOOK 的那张）
    //!WIDTH   <逆波兰表达式>          输出宽（缺省 = HOOKED.w）
    //!HEIGHT  <逆波兰表达式>          输出高（缺省 = HOOKED.h）
    //!COMPONENTS <1|4>               输出分量数（缺省 4）
    //!WHEN    <逆波兰表达式>          非零才执行（缺省恒执行）

body 里可以用 `<名字>_tex(p)` / `<名字>_texOff(off)` / `<名字>_pos` / `<名字>_pt` /
`<名字>_size` 这些宏。`HOOKED` 是「当前 HOOK 阶段那张纹理」的别名。

## 翻译策略

不做 GLSL 语法树解析 —— 没必要。Anime4K 用到的构造面很窄（见 vendor/Anime4K/README.md），
所以走两步：

1. **类型名替换**：`vec4`→`float4`、`ivec2`→`int2`，以及 `mat4(16 个标量)`→
   `float4x4(4 个 float4 列)`（GLSL 的 16 标量构造是列优先，直接四个一组切）。
2. **纹理访问交给 C 预处理器**：每个 pass 前面生成一组 `#define`，把 `MAIN_texOff(o)`
   之类展开成对 kernel 形参的真实采样调用，pass 结束后 `#undef` 掉。
   body 里原有的 `#define go_0(...)` 不用动，预处理器会自己套娃展开。

逆波兰表达式（WIDTH/HEIGHT/WHEN）不在这里求值 —— 它们依赖运行时的输入 / 输出尺寸，
所以原样写进 manifest，由 Swift 侧的 Anime4KSizeExpression 求值。
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
GLSL_DIR = REPO_ROOT / "vendor" / "Anime4K" / "glsl"
OUT_DIR = REPO_ROOT / "app" / "TubeKit" / "Sources" / "TubeKit" / "Resources" / "Anime4K"

# 一个 pass 最多能绑几张纹理。A4KUniforms 里的数组长度要和它一致，
# Swift 侧 Anime4KPassUniforms 也是。当前 Anime4K 的 M 档最宽一层绑 8 张（Restore_CNN_M 的最后一个 conv）。
MAX_BINDS = 8

# HOOK 阶段的执行顺序。Anime4K 只用到这两个。
STAGE_ORDER = ["MAIN", "PREKERNEL"]


# --------------------------------------------------------------------------
# 解析
# --------------------------------------------------------------------------


@dataclass
class Pass:
    desc: str = ""
    hook: str = "MAIN"
    binds: list[str] = field(default_factory=list)
    save: str | None = None
    width: list[str] = field(default_factory=list)
    height: list[str] = field(default_factory=list)
    components: int = 4
    when: list[str] = field(default_factory=list)
    body: list[str] = field(default_factory=list)
    function: str = ""


def parse_glsl(text: str, path: Path) -> list[Pass]:
    """把一个 .glsl 文件切成若干 pass。

    mpv 的规则：指令行是连续的一段；当一个 `//!` 行紧跟在 body 内容之后时，
    说明新的 pass 开始了。文件开头的许可证注释（`//` 但不是 `//!`）直接跳过。
    """
    passes: list[Pass] = []
    current: Pass | None = None
    seen_body = False

    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip()
        stripped = line.strip()

        if stripped.startswith("//!"):
            if current is None or seen_body:
                current = Pass()
                passes.append(current)
                seen_body = False
            _apply_directive(current, stripped[3:].strip(), path, lineno)
            continue

        if current is None:
            # 还没进入任何 pass —— 只能是文件头的许可证注释或空行。
            if stripped and not stripped.startswith("//"):
                raise SyntaxError(f"{path.name}:{lineno}: 第一个 //! 指令之前出现了代码: {stripped!r}")
            continue

        if stripped:
            seen_body = True
        current.body.append(line)

    if not passes:
        raise SyntaxError(f"{path.name}: 没解析出任何 pass")
    return passes


def _apply_directive(p: Pass, text: str, path: Path, lineno: int) -> None:
    parts = text.split(None, 1)
    if not parts:
        return
    key = parts[0].upper()
    value = parts[1].strip() if len(parts) > 1 else ""

    if key == "DESC":
        p.desc = value
    elif key == "HOOK":
        if value not in STAGE_ORDER:
            raise SyntaxError(f"{path.name}:{lineno}: 不认识的 HOOK 阶段 {value!r}（只支持 {STAGE_ORDER}）")
        p.hook = value
    elif key == "BIND":
        if value not in p.binds:
            p.binds.append(value)
    elif key == "SAVE":
        p.save = value
    elif key == "WIDTH":
        p.width = value.split()
    elif key == "HEIGHT":
        p.height = value.split()
    elif key == "COMPONENTS":
        p.components = int(value)
    elif key == "WHEN":
        p.when = value.split()
    else:
        raise SyntaxError(f"{path.name}:{lineno}: 不认识的指令 //!{key}")


# --------------------------------------------------------------------------
# GLSL -> MSL
# --------------------------------------------------------------------------

TYPE_MAP = {
    "vec2": "float2",
    "vec3": "float3",
    "vec4": "float4",
    "ivec2": "int2",
    "ivec3": "int3",
    "ivec4": "int4",
    "bvec2": "bool2",
    "bvec3": "bool3",
    "bvec4": "bool4",
    "mat2": "float2x2",
    "mat3": "float3x3",
    "mat4": "float4x4",
}


def split_top_level_args(text: str) -> list[str]:
    """按顶层逗号切分参数列表（忽略括号内部的逗号）。"""
    args: list[str] = []
    depth = 0
    start = 0
    for i, ch in enumerate(text):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            args.append(text[start:i].strip())
            start = i + 1
    tail = text[start:].strip()
    if tail:
        args.append(tail)
    return args


def rewrite_matrix_constructors(src: str) -> str:
    """`mat4(a0..a15)` -> `float4x4(float4(a0..a3), ...)`。

    MSL 的 float4x4 构造函数只吃「4 个列向量」或「1 个标量」，不吃 16 个标量，
    所以必须显式分组。GLSL 的 16 标量构造是列优先的，前 4 个就是第 0 列，
    分组方式和 MSL 的列构造一一对应，不用转置。
    """
    for glsl_name, dim in (("mat4", 4), ("mat3", 3), ("mat2", 2)):
        pattern = re.compile(r"\b" + glsl_name + r"\s*\(")
        while True:
            m = pattern.search(src)
            if not m:
                break
            open_paren = m.end() - 1
            depth = 0
            close_paren = -1
            for i in range(open_paren, len(src)):
                if src[i] == "(":
                    depth += 1
                elif src[i] == ")":
                    depth -= 1
                    if depth == 0:
                        close_paren = i
                        break
            if close_paren < 0:
                raise SyntaxError(f"{glsl_name}( 括号没闭合")

            args = split_top_level_args(src[open_paren + 1 : close_paren])
            msl_type = TYPE_MAP[glsl_name]
            vec_type = f"float{dim}"
            if len(args) == dim * dim:
                cols = [
                    f"{vec_type}({', '.join(args[c * dim : (c + 1) * dim])})" for c in range(dim)
                ]
                replacement = f"{msl_type}({', '.join(cols)})"
            else:
                # 1 个标量（对角矩阵）或 dim 个列向量 —— MSL 语义一致，直接换名字。
                replacement = f"{msl_type}({', '.join(args)})"
            src = src[: m.start()] + replacement + src[close_paren + 1 :]
    return src


def rewrite_types(src: str) -> str:
    for glsl_name, msl_name in TYPE_MAP.items():
        if glsl_name.startswith("mat"):
            continue  # 已经在 rewrite_matrix_constructors 里处理掉了
        src = re.sub(r"\b" + glsl_name + r"\b", msl_name, src)
    return src


def translate_body(body_lines: list[str]) -> tuple[str, list[str]]:
    """翻译 pass body，返回 (MSL 源码, body 里自己 #define 的宏名列表)。"""
    src = "\n".join(body_lines)
    src = rewrite_matrix_constructors(src)
    src = rewrite_types(src)

    local_macros = re.findall(r"^\s*#define\s+([A-Za-z_][A-Za-z0-9_]*)", src, flags=re.MULTILINE)

    # `vec4 hook()` 已经被 rewrite_types 换成了 `float4 hook()`，
    # 这里再把它改名成 pass 私有的 inline 函数并补上形参 —— 形参名和下面
    # emit_pass 生成的 #define 里引用的名字对齐。
    if not re.search(r"\bfloat4\s+hook\s*\(\s*\)", src):
        raise SyntaxError("pass body 里没找到 `vec4 hook()`")
    return src, local_macros


def emit_pass(p: Pass, index: int, shader_id: str) -> str:
    """生成一个 pass 的 MSL 代码（inline hook 函数 + compute kernel）。"""
    body, local_macros = translate_body(p.body)

    tex_params = ", ".join(
        f"texture2d<float, access::sample> a4k_t{i}" for i in range(len(p.binds))
    )
    hook_signature_params = (
        f"{tex_params}, float2 a4k_pos, constant A4KUniforms& a4k_u"
        if tex_params
        else "float2 a4k_pos, constant A4KUniforms& a4k_u"
    )
    hook_fn = f"{p.function}_hook"
    body = re.sub(r"\bfloat4\s+hook\s*\(\s*\)", f"float4 {hook_fn}({hook_signature_params})", body)
    # body 里的辅助函数（比如 get_luma）会跟着 hook 一起被塞进这个 pass 的作用域，
    # 名字可能和别的 pass 撞车，所以整体套一层匿名 namespace。
    body = f"namespace {p.function}_ns {{\n{body}\n}}"

    # 纹理访问宏。HOOKED 是 HOOK 阶段那张纹理的别名，所以 alias 表里可能有两个名字
    # 指向同一个 slot。
    defines: list[str] = []
    undefs: list[str] = []
    for slot, name in enumerate(p.binds):
        aliases = [name]
        if name == "HOOKED":
            aliases.append(p.hook)
        elif name == p.hook:
            aliases.append("HOOKED")
        for alias in aliases:
            defines.extend(
                [
                    f"#define {alias}_tex(p) a4k_t{slot}.sample(a4kSmp, (p))",
                    f"#define {alias}_texOff(o) a4k_t{slot}.sample(a4kSmp, a4k_pos + (o) * a4k_u.texPt[{slot}])",
                    f"#define {alias}_pos a4k_pos",
                    f"#define {alias}_pt a4k_u.texPt[{slot}]",
                    f"#define {alias}_size a4k_u.texSize[{slot}]",
                ]
            )
            undefs.extend(
                [
                    f"#undef {alias}_tex",
                    f"#undef {alias}_texOff",
                    f"#undef {alias}_pos",
                    f"#undef {alias}_pt",
                    f"#undef {alias}_size",
                ]
            )
    undefs.extend(f"#undef {name}" for name in local_macros)

    kernel_tex_params = "".join(
        f"    texture2d<float, access::sample> a4k_t{i} [[texture({i})]],\n"
        for i in range(len(p.binds))
    )
    hook_args = "".join(f"a4k_t{i}, " for i in range(len(p.binds)))

    return f"""
// ---------------------------------------------------------------------------
// pass {index}: {p.desc}
// HOOK {p.hook} | BIND {' '.join(p.binds) or '-'} | SAVE {p.save or p.hook} | COMPONENTS {p.components}
// ---------------------------------------------------------------------------
{chr(10).join(defines)}

{body}

#define A4K_HOOK {p.function}_ns::{hook_fn}

kernel void {p.function}(
{kernel_tex_params}    texture2d<float, access::write> a4k_out [[texture({MAX_BINDS})]],
    constant A4KUniforms& a4k_u [[buffer(0)]],
    uint2 a4k_gid [[thread_position_in_grid]])
{{
    if (a4k_gid.x >= a4k_out.get_width() || a4k_gid.y >= a4k_out.get_height()) {{ return; }}
    float2 a4k_pos = (float2(a4k_gid) + 0.5f) / a4k_u.outSize;
    a4k_out.write(A4K_HOOK({hook_args}a4k_pos, a4k_u), a4k_gid);
}}

#undef A4K_HOOK
{chr(10).join(undefs)}
"""


def prelude(source_name: str) -> str:
    return f"""// 本文件由 app/scripts/generate_anime4k_shaders.py 自动生成 —— 不要手改。
// 源：vendor/Anime4K/glsl/{source_name}
// 上游 Anime4K 由 bloc97 以 MIT 许可发布，见 vendor/Anime4K/LICENSE。

#include <metal_stdlib>
using namespace metal;

struct A4KUniforms {{
    float2 texSize[{MAX_BINDS}];
    float2 texPt[{MAX_BINDS}];
    float2 outSize;
    float2 pad;
}};

// mpv 的 user-shader 假定纹理采样是归一化坐标 + 双线性 + 边缘钳制。
constexpr sampler a4kSmp(coord::normalized, address::clamp_to_edge, filter::linear);
"""


def function_name(shader_id: str, index: int) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", shader_id.lower()).strip("_")
    return f"{slug}_p{index}"


def generate(glsl_path: Path) -> tuple[str, dict]:
    shader_id = glsl_path.stem
    passes = parse_glsl(glsl_path.read_text(encoding="utf-8"), glsl_path)

    for i, p in enumerate(passes):
        p.function = function_name(shader_id, i)
        if len(p.binds) > MAX_BINDS:
            raise SyntaxError(
                f"{glsl_path.name} pass {i}: 绑了 {len(p.binds)} 张纹理，超过 MAX_BINDS={MAX_BINDS}"
            )
        if p.components not in (1, 4):
            raise SyntaxError(f"{glsl_path.name} pass {i}: COMPONENTS={p.components} 不支持（只有 1 / 4）")

    metal = prelude(glsl_path.name)
    metal += "".join(emit_pass(p, i, shader_id) for i, p in enumerate(passes))

    manifest = {
        "id": shader_id,
        "source": f"{shader_id}.metal",
        "passes": [
            {
                "desc": p.desc,
                "hook": p.hook,
                "binds": p.binds,
                "save": p.save or p.hook,
                "width": p.width or [f"{_hooked_ref(p)}.w"],
                "height": p.height or [f"{_hooked_ref(p)}.h"],
                "components": p.components,
                "when": p.when,
                "function": p.function,
            }
            for p in passes
        ],
    }
    return metal, manifest


def _hooked_ref(p: Pass) -> str:
    """WIDTH/HEIGHT 缺省时参照的纹理名。"""
    return p.hook


def main() -> int:
    if not GLSL_DIR.is_dir():
        print(f"error: 找不到 {GLSL_DIR}", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sources = sorted(GLSL_DIR.glob("*.glsl"))
    if not sources:
        print(f"error: {GLSL_DIR} 下没有 .glsl 文件", file=sys.stderr)
        return 1

    shaders = []
    for path in sources:
        metal, manifest = generate(path)
        (OUT_DIR / manifest["source"]).write_text(metal, encoding="utf-8")
        shaders.append(manifest)
        print(f"  {path.name} -> {manifest['source']} ({len(manifest['passes'])} passes)")

    manifest_path = OUT_DIR / "manifest.json"
    manifest_path.write_text(
        json.dumps({"maxBinds": MAX_BINDS, "shaders": shaders}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"  -> {manifest_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
