// Slang port of examples/39-assao cs_assao_generate_importance_map.sc.
// IMAGE2D_WO(r8) target + SAMPLER2DARRAY source; textureGather -> GatherRed. Non-GLSL branch.
import bgfx_shader;
import bgfx_compute;

uniform float4 u_params[6];

[[vk::image_format("r8")]]
RWTexture2D<float> s_target : register(u0);

Texture2DArray s_finalSSAO        : register(t1);
SamplerState   s_finalSSAOSampler : register(s1);

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy);

	uvec2 dim = uvec2(imageSize(s_target).xy);
	if (all(dtID.xy < dim) )
	{
		uvec2 basePos = uvec2(dtID.xy) * 2;

		vec2 baseUV = (vec2(basePos) + vec2( 0.5, 0.5 ) ) * u_params[0].zw;
		vec2 gatherUV = (vec2(basePos) + vec2( 1.0, 1.0 ) ) * u_params[0].zw;

		float avg = 0.0;
		float minV = 1.0;
		float maxV = 0.0;
		for( int i = 0; i < 4; i++ )
		{
			vec4 vals = s_finalSSAO.GatherRed(s_finalSSAOSampler, vec3( gatherUV, float(i) ) );

			// apply the same modifications that would have been applied in the main shader
			vals = u_params[5].y * vals;

			vals = 1-vals;

			vals = pow( saturate( vals ), u_params[5].z.xxxx );

			avg += dot( vec4( vals.x, vals.y, vals.z, vals.w ), vec4( 1.0 / 16.0, 1.0 / 16.0, 1.0 / 16.0, 1.0 / 16.0 ) );

			maxV = max( maxV, max( max( vals.x, vals.y ), max( vals.z, vals.w ) ) );
			minV = min( minV, min( min( vals.x, vals.y ), min( vals.z, vals.w ) ) );
		}

		float minMaxDiff = maxV - minV;

		imageStore(s_target, ivec2(dtID.xy), pow( saturate( minMaxDiff * 2.0 ), 0.8 ) );
	}
}
