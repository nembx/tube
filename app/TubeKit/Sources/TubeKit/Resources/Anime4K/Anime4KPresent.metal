// 这个文件是手写的，不是 generate_anime4k_shaders.py 的产物。
//
// Anime4K 的链跑完之后，MAIN 的尺寸不一定正好等于目标输出尺寸 ——
// AutoDownscalePre 只在它的 //!WHEN 成立时才把尺寸拉到 OUTPUT，放大倍率落在
// 1.0~1.2 之间时整条放大链会被跳过，MAIN 就停在原始分辨率上。
// 而且渲染图的中间纹理是 rgba16f，输出纹理是 bgra8unorm，格式也对不上，
// 不能用 blit 直接拷。所以统一走这一趟双线性重采样收尾。

#include <metal_stdlib>
using namespace metal;

constexpr sampler a4kPresentSmp(coord::normalized, address::clamp_to_edge, filter::linear);

kernel void a4k_present(
    texture2d<float, access::sample> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint w = dst.get_width();
    const uint h = dst.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 pos = (float2(gid) + 0.5f) / float2(w, h);
    float4 color = src.sample(a4kPresentSmp, pos);

    // CNN 的残差连接会把值推到 [0,1] 之外；写进 8 位输出前必须钳回来，
    // 否则高光和暗部会环绕成噪点。alpha 固定 1 —— 播放路径上没有透明度。
    dst.write(float4(clamp(color.rgb, 0.0f, 1.0f), 1.0f), gid);
}
