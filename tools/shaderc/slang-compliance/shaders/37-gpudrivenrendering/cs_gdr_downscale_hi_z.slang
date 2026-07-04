// Slang port of examples/37-gpudrivenrendering cs_gdr_downscale_hi_z.sc.
// Downscales a hi-Z occlusion mip: reads a 2x2 footprint from the input storage image
// (IMAGE2D_RO r32f) and writes the max depth to the output storage image (IMAGE2D_WO r32f).
import bgfx_compute;
import bgfx_shader;

uniform float4 u_inputRTSize;

// IMAGE2D_RO(s_texOcclusionDepthIn, r32f, 0) -> read-only storage image (Texture2D<float>).
[[vk::image_format("r32f")]]
Texture2D<float> s_texOcclusionDepthIn : register(t0);

// IMAGE2D_WO(s_texOcclusionDepthOut, r32f, 1) -> write storage image.
[[vk::image_format("r32f")]]
RWTexture2D<float> s_texOcclusionDepthOut : register(u1);

[shader("compute")]
[numthreads(16, 16, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	// this shader can be used to both copy a mip over to the output and downscale it.

	int2 coord = int2(dispatchThreadId.xy);

	if (all(coord < int2(u_inputRTSize.xy) ) )
	{
		float maxDepth = 1.0;

		float4 depths = float4(
			  imageLoad(s_texOcclusionDepthIn, int2(u_inputRTSize.zw * float2(coord)                     ) )
			, imageLoad(s_texOcclusionDepthIn, int2(u_inputRTSize.zw * float2(coord) + float2(1.0, 0.0) ) )
			, imageLoad(s_texOcclusionDepthIn, int2(u_inputRTSize.zw * float2(coord) + float2(0.0, 1.0) ) )
			, imageLoad(s_texOcclusionDepthIn, int2(u_inputRTSize.zw * float2(coord) + float2(1.0, 1.0) ) )
			);

		// find and return max depth
		maxDepth = max(
			  max(depths.x, depths.y)
			, max(depths.z, depths.w)
			);

		imageStore(s_texOcclusionDepthOut, coord, maxDepth);
	}
}
