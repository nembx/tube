// 本文件由 cezzu/scripts/generate_anime4k_shaders.py 自动生成 —— 不要手改。
// 源：vendor/Anime4K/glsl/Anime4K_Clamp_Highlights.glsl
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
// pass 0: Anime4K-v4.0-De-Ring-Compute-Statistics
// HOOK MAIN | BIND HOOKED | SAVE STATSMAX | COMPONENTS 1
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

namespace anime4k_clamp_highlights_p0_ns {

#define KERNELSIZE 5 //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE 2 //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).

float get_luma(float4 rgba) {
	return dot(float4(0.299, 0.587, 0.114, 0.0), rgba);
}

float4 anime4k_clamp_highlights_p0_hook(texture2d<float, access::sample> a4k_t0, float2 a4k_pos, constant A4KUniforms& a4k_u) {

	float gmax = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float g = get_luma(MAIN_texOff(float2(i - KERNELHALFSIZE, 0)));

		gmax = max(g, gmax);
	}

	return float4(gmax, 0.0, 0.0, 0.0);
}

}

#define A4K_HOOK anime4k_clamp_highlights_p0_ns::anime4k_clamp_highlights_p0_hook

kernel void anime4k_clamp_highlights_p0(
    texture2d<float, access::sample> a4k_t0 [[texture(0)]],
    texture2d<float, access::write> a4k_out [[texture(8)]],
    constant A4KUniforms& a4k_u [[buffer(0)]],
    uint2 a4k_gid [[thread_position_in_grid]])
{
    if (a4k_gid.x >= a4k_out.get_width() || a4k_gid.y >= a4k_out.get_height()) { return; }
    float2 a4k_pos = (float2(a4k_gid) + 0.5f) / a4k_u.outSize;
    a4k_out.write(A4K_HOOK(a4k_t0, a4k_pos, a4k_u), a4k_gid);
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
#undef KERNELSIZE
#undef KERNELHALFSIZE

// ---------------------------------------------------------------------------
// pass 1: Anime4K-v4.0-De-Ring-Compute-Statistics
// HOOK MAIN | BIND HOOKED STATSMAX | SAVE STATSMAX | COMPONENTS 1
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
#define STATSMAX_tex(p) a4k_t1.sample(a4kSmp, (p))
#define STATSMAX_texOff(o) a4k_t1.sample(a4kSmp, a4k_pos + (o) * a4k_u.texPt[1])
#define STATSMAX_pos a4k_pos
#define STATSMAX_pt a4k_u.texPt[1]
#define STATSMAX_size a4k_u.texSize[1]

namespace anime4k_clamp_highlights_p1_ns {

#define KERNELSIZE 5 //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE 2 //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).

float4 anime4k_clamp_highlights_p1_hook(texture2d<float, access::sample> a4k_t0, texture2d<float, access::sample> a4k_t1, float2 a4k_pos, constant A4KUniforms& a4k_u) {

	float gmax = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float g = STATSMAX_texOff(float2(0, i - KERNELHALFSIZE)).x;

		gmax = max(g, gmax);
	}

	return float4(gmax, 0.0, 0.0, 0.0);
}

}

#define A4K_HOOK anime4k_clamp_highlights_p1_ns::anime4k_clamp_highlights_p1_hook

kernel void anime4k_clamp_highlights_p1(
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
#undef STATSMAX_tex
#undef STATSMAX_texOff
#undef STATSMAX_pos
#undef STATSMAX_pt
#undef STATSMAX_size
#undef KERNELSIZE
#undef KERNELHALFSIZE

// ---------------------------------------------------------------------------
// pass 2: Anime4K-v4.0-De-Ring-Clamp
// HOOK PREKERNEL | BIND HOOKED STATSMAX | SAVE PREKERNEL | COMPONENTS 4
// ---------------------------------------------------------------------------
#define HOOKED_tex(p) a4k_t0.sample(a4kSmp, (p))
#define HOOKED_texOff(o) a4k_t0.sample(a4kSmp, a4k_pos + (o) * a4k_u.texPt[0])
#define HOOKED_pos a4k_pos
#define HOOKED_pt a4k_u.texPt[0]
#define HOOKED_size a4k_u.texSize[0]
#define PREKERNEL_tex(p) a4k_t0.sample(a4kSmp, (p))
#define PREKERNEL_texOff(o) a4k_t0.sample(a4kSmp, a4k_pos + (o) * a4k_u.texPt[0])
#define PREKERNEL_pos a4k_pos
#define PREKERNEL_pt a4k_u.texPt[0]
#define PREKERNEL_size a4k_u.texSize[0]
#define STATSMAX_tex(p) a4k_t1.sample(a4kSmp, (p))
#define STATSMAX_texOff(o) a4k_t1.sample(a4kSmp, a4k_pos + (o) * a4k_u.texPt[1])
#define STATSMAX_pos a4k_pos
#define STATSMAX_pt a4k_u.texPt[1]
#define STATSMAX_size a4k_u.texSize[1]

namespace anime4k_clamp_highlights_p2_ns {

float get_luma(float4 rgba) {
	return dot(float4(0.299, 0.587, 0.114, 0.0), rgba);
}

float4 anime4k_clamp_highlights_p2_hook(texture2d<float, access::sample> a4k_t0, texture2d<float, access::sample> a4k_t1, float2 a4k_pos, constant A4KUniforms& a4k_u) {

	float current_luma = get_luma(HOOKED_tex(HOOKED_pos));
	float new_luma = min(current_luma, STATSMAX_tex(HOOKED_pos).x);

	//This trick is only possible if the inverse Y->RGB matrix has 1 for every row... (which is the case for BT.709)
	//Otherwise we would need to convert RGB to YUV, modify Y then convert back to RGB.
    return HOOKED_tex(HOOKED_pos) - (current_luma - new_luma);
}
}

#define A4K_HOOK anime4k_clamp_highlights_p2_ns::anime4k_clamp_highlights_p2_hook

kernel void anime4k_clamp_highlights_p2(
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
#undef PREKERNEL_tex
#undef PREKERNEL_texOff
#undef PREKERNEL_pos
#undef PREKERNEL_pt
#undef PREKERNEL_size
#undef STATSMAX_tex
#undef STATSMAX_texOff
#undef STATSMAX_pos
#undef STATSMAX_pt
#undef STATSMAX_size
