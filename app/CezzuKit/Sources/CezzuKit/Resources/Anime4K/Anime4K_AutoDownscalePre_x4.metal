// 本文件由 cezzu/scripts/generate_anime4k_shaders.py 自动生成 —— 不要手改。
// 源：vendor/Anime4K/glsl/Anime4K_AutoDownscalePre_x4.glsl
// 上游 Anime4K 由 bloc97 以 MIT 许可发布，见 vendor/Anime4K/LICENSE。

#include <metal_stdlib>
using namespace metal;

struct A4KUniforms {
    float2 texSize[8];
    float2 texPt[8];
    float2 outSize;
    float2 pad;
};

// mpv 的 user-shader 假定纹理采样是归一化坐标 + 双线性 + 边缘钳制。
constexpr sampler a4kSmp(coord::normalized, address::clamp_to_edge, filter::linear);

// ---------------------------------------------------------------------------
// pass 0: Anime4K-v3.2-AutoDownscalePre-x4
// HOOK MAIN | BIND HOOKED NATIVE | SAVE MAIN | COMPONENTS 4
// ---------------------------------------------------------------------------
#define HOOKED_tex(p) a4k_t0.sample(a4kSmp, (p))
#define HOOKED_texOff(o) a4k_t0.sample(a4kSmp, a4k_pos + (o) * a4k_u.texPt[0])
#define HOOKED_pos a4k_pos
#define HOOKED_pt a4k_u.texPt[0]
#define HOOKED_size a4k_u.texSize[0]
#define MAIN_tex(p) a4k_t0.sample(a4kSmp, (p))
#define MAIN_texOff(o) a4k_t0.sample(a4kSmp, a4k_pos + (o) * a4k_u.texPt[0])
#define MAIN_pos a4k_pos
#define MAIN_pt a4k_u.texPt[0]
#define MAIN_size a4k_u.texSize[0]
#define NATIVE_tex(p) a4k_t1.sample(a4kSmp, (p))
#define NATIVE_texOff(o) a4k_t1.sample(a4kSmp, a4k_pos + (o) * a4k_u.texPt[1])
#define NATIVE_pos a4k_pos
#define NATIVE_pt a4k_u.texPt[1]
#define NATIVE_size a4k_u.texSize[1]

namespace anime4k_autodownscalepre_x4_p0_ns {

float4 anime4k_autodownscalepre_x4_p0_hook(texture2d<float, access::sample> a4k_t0, texture2d<float, access::sample> a4k_t1, float2 a4k_pos, constant A4KUniforms& a4k_u) {
	return HOOKED_tex(HOOKED_pos);
}
}

#define A4K_HOOK anime4k_autodownscalepre_x4_p0_ns::anime4k_autodownscalepre_x4_p0_hook

kernel void anime4k_autodownscalepre_x4_p0(
    texture2d<float, access::sample> a4k_t0 [[texture(0)]],
    texture2d<float, access::sample> a4k_t1 [[texture(1)]],
    texture2d<float, access::write> a4k_out [[texture(8)]],
    constant A4KUniforms& a4k_u [[buffer(0)]],
    uint2 a4k_gid [[thread_position_in_grid]])
{
    if (a4k_gid.x >= a4k_out.get_width() || a4k_gid.y >= a4k_out.get_height()) { return; }
    float2 a4k_pos = (float2(a4k_gid) + 0.5f) / a4k_u.outSize;
    a4k_out.write(A4K_HOOK(a4k_t0, a4k_t1, a4k_pos, a4k_u), a4k_gid);
}

#undef A4K_HOOK
#undef HOOKED_tex
#undef HOOKED_texOff
#undef HOOKED_pos
#undef HOOKED_pt
#undef HOOKED_size
#undef MAIN_tex
#undef MAIN_texOff
#undef MAIN_pos
#undef MAIN_pt
#undef MAIN_size
#undef NATIVE_tex
#undef NATIVE_texOff
#undef NATIVE_pos
#undef NATIVE_pt
#undef NATIVE_size
