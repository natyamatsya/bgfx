// Slang port of examples/39-assao cs_assao_prepare_depths_and_normals.sc.
// SAMPLER2D depth + 4x IMAGE2D_WO(r16f) depth targets + IMAGE2D_WO(rgba8) normals target;
// texelFetchOffset -> .Load with offset, texture2DLodOffset -> .SampleLevel with offset.
// ScreenSpaceToViewSpaceDepth/NDCToViewspace/CalculateEdges/CalculateNormal kept inline. Non-GLSL branch.
import bgfx_shader;
import bgfx_compute;

uniform float4 u_params[5];

Texture2D    s_depthSource        : register(t0);
SamplerState s_depthSourceSampler : register(s0);

[[vk::image_format("r16f")]] RWTexture2D<float> s_target0 : register(u1);
[[vk::image_format("r16f")]] RWTexture2D<float> s_target1 : register(u2);
[[vk::image_format("r16f")]] RWTexture2D<float> s_target2 : register(u3);
[[vk::image_format("r16f")]] RWTexture2D<float> s_target3 : register(u4);
[[vk::image_format("rgba8")]] RWTexture2D<float4> s_normalsOutputUAV : register(u5);

float ScreenSpaceToViewSpaceDepth( float screenDepth )
{
    float depthLinearizeMul = u_params[1].x;
    float depthLinearizeAdd = u_params[1].y;

    return depthLinearizeMul / ( depthLinearizeAdd - screenDepth );
}

vec3 NDCToViewspace( vec2 pos, float viewspaceDepth )
{
    vec3 ret;

    ret.xy = (u_params[2].xy * pos.xy + u_params[2].zw) * viewspaceDepth;

    ret.z = viewspaceDepth;

    return ret;
}

vec4 CalculateEdges( const float centerZ, const float leftZ, const float rightZ, const float topZ, const float bottomZ )
{
    vec4 edgesLRTB = vec4( leftZ, rightZ, topZ, bottomZ ) - centerZ;
    vec4 edgesLRTBSlopeAdjusted = edgesLRTB + edgesLRTB.yxwz;
    edgesLRTB = min( abs( edgesLRTB ), abs( edgesLRTBSlopeAdjusted ) );
    return saturate( ( 1.3 - edgesLRTB / (centerZ * 0.040) ) );
}

vec3 CalculateNormal( const vec4 edgesLRTB, vec3 pixCenterPos, vec3 pixLPos, vec3 pixRPos, vec3 pixTPos, vec3 pixBPos )
{
    vec4 acceptedNormals  = vec4( edgesLRTB.x*edgesLRTB.z, edgesLRTB.z*edgesLRTB.y, edgesLRTB.y*edgesLRTB.w, edgesLRTB.w*edgesLRTB.x );

    pixLPos = normalize(pixLPos - pixCenterPos);
    pixRPos = normalize(pixRPos - pixCenterPos);
    pixTPos = normalize(pixTPos - pixCenterPos);
    pixBPos = normalize(pixBPos - pixCenterPos);

    vec3 pixelNormal = vec3( 0, 0, -0.0005 );
    pixelNormal += ( acceptedNormals.x ) * cross( pixLPos, pixTPos );
    pixelNormal += ( acceptedNormals.y ) * cross( pixTPos, pixRPos );
    pixelNormal += ( acceptedNormals.z ) * cross( pixRPos, pixBPos );
    pixelNormal += ( acceptedNormals.w ) * cross( pixBPos, pixLPos );
    pixelNormal = normalize( pixelNormal );

    return pixelNormal;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy);

	uvec2 dim = uvec2(imageSize(s_target0).xy);
	if (all(dtID.xy < dim) )
	{
		ivec2 baseCoords = ivec2(dtID.xy) * 2;
		vec2 upperLeftUV = (vec2(dtID.xy) + vec2(0.25,0.25)) * u_params[4].xy;

		ivec2 baseCoord = ivec2(dtID.xy) * 2;
		float z0 = ScreenSpaceToViewSpaceDepth( s_depthSource.Load( ivec3(baseCoord, 0), ivec2( 0, 0 ) ).x );
		float z1 = ScreenSpaceToViewSpaceDepth( s_depthSource.Load( ivec3(baseCoord, 0), ivec2( 1, 0 ) ).x );
		float z2 = ScreenSpaceToViewSpaceDepth( s_depthSource.Load( ivec3(baseCoord, 0), ivec2( 0, 1 ) ).x );
		float z3 = ScreenSpaceToViewSpaceDepth( s_depthSource.Load( ivec3(baseCoord, 0), ivec2( 1, 1 ) ).x );

		imageStore(s_target0, ivec2(dtID.xy), z0 );
		imageStore(s_target1, ivec2(dtID.xy), z1 );
		imageStore(s_target2, ivec2(dtID.xy), z2 );
		imageStore(s_target3, ivec2(dtID.xy), z3 );

		float pixZs[4][4];

		// middle 4
		pixZs[1][1] = z0;
		pixZs[2][1] = z1;
		pixZs[1][2] = z2;
		pixZs[2][2] = z3;

		// left 2
		pixZs[0][1] = ScreenSpaceToViewSpaceDepth(  s_depthSource.SampleLevel(s_depthSourceSampler, upperLeftUV, 0.0, ivec2( -1, 0 ) ).x );
		pixZs[0][2] = ScreenSpaceToViewSpaceDepth(  s_depthSource.SampleLevel(s_depthSourceSampler, upperLeftUV, 0.0, ivec2( -1, 1 ) ).x );
		// right 2
		pixZs[3][1] = ScreenSpaceToViewSpaceDepth(  s_depthSource.SampleLevel(s_depthSourceSampler, upperLeftUV, 0.0, ivec2(  2, 0 ) ).x );
		pixZs[3][2] = ScreenSpaceToViewSpaceDepth(  s_depthSource.SampleLevel(s_depthSourceSampler, upperLeftUV, 0.0, ivec2(  2, 1 ) ).x );
		// top 2
		pixZs[1][0] = ScreenSpaceToViewSpaceDepth(  s_depthSource.SampleLevel(s_depthSourceSampler, upperLeftUV, 0.0, ivec2(  0, -1 ) ).x );
		pixZs[2][0] = ScreenSpaceToViewSpaceDepth(  s_depthSource.SampleLevel(s_depthSourceSampler, upperLeftUV, 0.0, ivec2(  1, -1 ) ).x );
		// bottom 2
		pixZs[1][3] = ScreenSpaceToViewSpaceDepth(  s_depthSource.SampleLevel(s_depthSourceSampler, upperLeftUV, 0.0, ivec2(  0,  2 ) ).x );
		pixZs[2][3] = ScreenSpaceToViewSpaceDepth(  s_depthSource.SampleLevel(s_depthSourceSampler, upperLeftUV, 0.0, ivec2(  1,  2 ) ).x );

		vec4 edges0 = CalculateEdges( pixZs[1][1], pixZs[0][1], pixZs[2][1], pixZs[1][0], pixZs[1][2] );
		vec4 edges1 = CalculateEdges( pixZs[2][1], pixZs[1][1], pixZs[3][1], pixZs[2][0], pixZs[2][2] );
		vec4 edges2 = CalculateEdges( pixZs[1][2], pixZs[0][2], pixZs[2][2], pixZs[1][1], pixZs[1][3] );
		vec4 edges3 = CalculateEdges( pixZs[2][2], pixZs[1][2], pixZs[3][2], pixZs[2][1], pixZs[2][3] );

		vec2 viewportPixelSize = u_params[0].xy;

			vec3 pixPos[4][4];
		// middle 4
		pixPos[1][1] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( 0.0,  0.0 ), pixZs[1][1] );
		pixPos[2][1] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( 1.0,  0.0 ), pixZs[2][1] );
		pixPos[1][2] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( 0.0,  1.0 ), pixZs[1][2] );
		pixPos[2][2] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( 1.0,  1.0 ), pixZs[2][2] );
		// left 2
		pixPos[0][1] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( -1.0,  0.0), pixZs[0][1] );
		pixPos[0][2] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( -1.0,  1.0), pixZs[0][2] );
		// right 2
		pixPos[3][1] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2(  2.0,  0.0), pixZs[3][1] );
		pixPos[3][2] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2(  2.0,  1.0), pixZs[3][2] );
		// top 2
		pixPos[1][0] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( 0.0, -1.0 ), pixZs[1][0] );
		pixPos[2][0] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( 1.0, -1.0 ), pixZs[2][0] );
		// bottom 2
		pixPos[1][3] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( 0.0,  2.0 ), pixZs[1][3] );
		pixPos[2][3] = NDCToViewspace( upperLeftUV + viewportPixelSize * vec2( 1.0,  2.0 ), pixZs[2][3] );

		vec3 norm0 = CalculateNormal( edges0, pixPos[1][1], pixPos[0][1], pixPos[2][1], pixPos[1][0], pixPos[1][2] );
		vec3 norm1 = CalculateNormal( edges1, pixPos[2][1], pixPos[1][1], pixPos[3][1], pixPos[2][0], pixPos[2][2] );
		vec3 norm2 = CalculateNormal( edges2, pixPos[1][2], pixPos[0][2], pixPos[2][2], pixPos[1][1], pixPos[1][3] );
		vec3 norm3 = CalculateNormal( edges3, pixPos[2][2], pixPos[1][2], pixPos[3][2], pixPos[2][1], pixPos[2][3] );

		imageStore(s_normalsOutputUAV, baseCoords + ivec2( 0, 0 ), vec4( norm0 * 0.5 + 0.5, 0.0 ));
		imageStore(s_normalsOutputUAV, baseCoords + ivec2( 1, 0 ), vec4( norm1 * 0.5 + 0.5, 0.0 ));
		imageStore(s_normalsOutputUAV, baseCoords + ivec2( 0, 1 ), vec4( norm2 * 0.5 + 0.5, 0.0 ));
		imageStore(s_normalsOutputUAV, baseCoords + ivec2( 1, 1 ), vec4( norm3 * 0.5 + 0.5, 0.0 ));
	}
}
