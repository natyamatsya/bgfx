// Slang port of examples/37-gpudrivenrendering cs_gdr_copy_z.sc — compute storage image.
// SAMPLER2D + IMAGE2D_WO(r32f) + a uniform; texelFetch (Load) reads, imageStore writes.
import bgfx_compute;
import bgfx_shader;

uniform float4 u_inputRTSize;

Texture2D    s_texOcclusionDepth        : register(t0);
SamplerState s_texOcclusionDepthSampler : register(s0);

// IMAGE2D_WO(s_texOcclusionDepthOut, r32f, 1) -> a write storage image with format r32f.
[[vk::image_format("r32f")]]
RWTexture2D<float> s_texOcclusionDepthOut : register(u1);

[shader("compute")]
[numthreads(16, 16, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	int2 coord = int2(dispatchThreadId.xy);
	if (all(coord < int2(u_inputRTSize.xy) ) )
	{
		float maxDepth = s_texOcclusionDepth.Load(int3(coord, 0) ).x; // texelFetch
		imageStore(s_texOcclusionDepthOut, coord, maxDepth);         // imageStore
	}
}
