// Slang port of examples/39-assao cs_assao_prepare_depth_mip.sc.
// 4x IMAGE2D_RO(r16f) sources (Texture2D<float>) + 4x IMAGE2D_WO(r16f) targets; imageLoad.
// CalculateRadiusParameters kept inline (defined in the .sc body).
import bgfx_shader;
import bgfx_compute;

uniform float4 u_params[7];
// stock uniforms.sh declares u_params[19] then u_rect; glslang reflects u_params at its used
// extent (7) but reserves the full [19] in $Globals, so u_rect keeps byte offset 304 and the UBO
// size stays 320. Reproduce the reserved tail with a struct member (not reflected as a uniform).
struct ParamsTailPad { float4 _unused[12]; };
ParamsTailPad _paramsTailPad;
uniform float4 u_rect;

[[vk::image_format("r16f")]] Texture2D<float> s_viewspaceDepthSource0 : register(t0);
[[vk::image_format("r16f")]] Texture2D<float> s_viewspaceDepthSource1 : register(t1);
[[vk::image_format("r16f")]] Texture2D<float> s_viewspaceDepthSource2 : register(t2);
[[vk::image_format("r16f")]] Texture2D<float> s_viewspaceDepthSource3 : register(t3);

[[vk::image_format("r16f")]] RWTexture2D<float> s_target0 : register(u4);
[[vk::image_format("r16f")]] RWTexture2D<float> s_target1 : register(u5);
[[vk::image_format("r16f")]] RWTexture2D<float> s_target2 : register(u6);
[[vk::image_format("r16f")]] RWTexture2D<float> s_target3 : register(u7);

// calculate effect radius and fit our screen sampling pattern inside it
void CalculateRadiusParameters( const float pixCenterLength, const vec2 pixelDirRBViewspaceSizeAtCenterZ, out float pixLookupRadiusMod, out float effectRadius, out float falloffCalcMulSq )
{
    effectRadius = u_params[5].x;

    const float tooCloseLimitMod = saturate( pixCenterLength * u_params[6].w ) * 0.8 + 0.2;

    effectRadius *= tooCloseLimitMod;

    pixLookupRadiusMod = (0.85 * effectRadius) / pixelDirRBViewspaceSizeAtCenterZ.x;

    falloffCalcMulSq= -1.0f / (effectRadius*effectRadius);
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy);

	uvec2 dim = uvec2(u_rect.zw);
	if (all(dtID.xy < dim) )
	{
		ivec2 baseCoords = ivec2(dtID.xy) * 2;

		vec4 depthsArr[4];
		float depthsOutArr[4];

		// how to Gather a specific mip level?
		depthsArr[0].x = imageLoad(s_viewspaceDepthSource0, baseCoords + ivec2( 0, 0 )).x ;
		depthsArr[0].y = imageLoad(s_viewspaceDepthSource0, baseCoords + ivec2( 1, 0 )).x ;
		depthsArr[0].z = imageLoad(s_viewspaceDepthSource0, baseCoords + ivec2( 0, 1 )).x ;
		depthsArr[0].w = imageLoad(s_viewspaceDepthSource0, baseCoords + ivec2( 1, 1 )).x ;
		depthsArr[1].x = imageLoad(s_viewspaceDepthSource1, baseCoords + ivec2( 0, 0 )).x;
		depthsArr[1].y = imageLoad(s_viewspaceDepthSource1, baseCoords + ivec2( 1, 0 )).x;
		depthsArr[1].z = imageLoad(s_viewspaceDepthSource1, baseCoords + ivec2( 0, 1 )).x;
		depthsArr[1].w = imageLoad(s_viewspaceDepthSource1, baseCoords + ivec2( 1, 1 )).x;
		depthsArr[2].x = imageLoad(s_viewspaceDepthSource2, baseCoords + ivec2( 0, 0 )).x;
		depthsArr[2].y = imageLoad(s_viewspaceDepthSource2, baseCoords + ivec2( 1, 0 )).x;
		depthsArr[2].z = imageLoad(s_viewspaceDepthSource2, baseCoords + ivec2( 0, 1 )).x;
		depthsArr[2].w = imageLoad(s_viewspaceDepthSource2, baseCoords + ivec2( 1, 1 )).x;
		depthsArr[3].x = imageLoad(s_viewspaceDepthSource3, baseCoords + ivec2( 0, 0 )).x;
		depthsArr[3].y = imageLoad(s_viewspaceDepthSource3, baseCoords + ivec2( 1, 0 )).x;
		depthsArr[3].z = imageLoad(s_viewspaceDepthSource3, baseCoords + ivec2( 0, 1 )).x;
		depthsArr[3].w = imageLoad(s_viewspaceDepthSource3, baseCoords + ivec2( 1, 1 )).x;

	    const uvec2 SVPosui         = uvec2( dtID.xy );
		const uint pseudoRandomA    = (SVPosui.x ) + 2 * (SVPosui.y );

		float dummyUnused1;
		float dummyUnused2;
		float falloffCalcMulSq, falloffCalcAdd;

		for( int i = 0; i < 4; i++ )
		{
			vec4 depths = depthsArr[i];
			float closest = min( min( depths.x, depths.y ), min( depths.z, depths.w ) );

			CalculateRadiusParameters( abs( closest ), vec2(1.0,1.0), dummyUnused1, dummyUnused2, falloffCalcMulSq );

			vec4 dists = depths - closest.xxxx;

			vec4 weights = saturate( dists * dists * falloffCalcMulSq + 1.0 );

			float smartAvg = dot( weights, depths ) / dot( weights, vec4( 1.0, 1.0, 1.0, 1.0 ) );

			const uint pseudoRandomIndex = ( pseudoRandomA + i ) % 4;

			depthsOutArr[i] = smartAvg;
		}

		imageStore(s_target0, ivec2(dtID.xy), depthsOutArr[0]);
		imageStore(s_target1, ivec2(dtID.xy), depthsOutArr[1]);
		imageStore(s_target2, ivec2(dtID.xy), depthsOutArr[2]);
		imageStore(s_target3, ivec2(dtID.xy), depthsOutArr[3]);
	}
}
