// Slang port of examples/39-assao cs_assao_prepare_depths_half.sc.
// SAMPLER2D depth source + 2x IMAGE2D_WO(r16f) targets; texelFetch -> .Load. Non-GLSL branch.
import bgfx_shader;
import bgfx_compute;

uniform float4 u_params[2];

Texture2D    s_depthSource        : register(t0);
SamplerState s_depthSourceSampler : register(s0);

[[vk::image_format("r16f")]] RWTexture2D<float> s_target0 : register(u1);
[[vk::image_format("r16f")]] RWTexture2D<float> s_target1 : register(u2);

float ScreenSpaceToViewSpaceDepth( float screenDepth )
{
    float depthLinearizeMul = u_params[1].x;
    float depthLinearizeAdd = u_params[1].y;

    return depthLinearizeMul / ( depthLinearizeAdd - screenDepth );
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy);

	uvec2 dim = uvec2(imageSize(s_target0).xy);
	if (all(dtID.xy < dim) )
	{
		ivec2 baseCoord = ivec2(dtID.xy) * 2;
		float a = s_depthSource.Load( ivec3(baseCoord + ivec2( 0, 0 ), 0) ).x;
		float d = s_depthSource.Load( ivec3(baseCoord + ivec2( 1, 1 ), 0) ).x;

		imageStore(s_target0, ivec2(dtID.xy), ScreenSpaceToViewSpaceDepth( a ));
		imageStore(s_target1, ivec2(dtID.xy), ScreenSpaceToViewSpaceDepth( d ));
	}
}
