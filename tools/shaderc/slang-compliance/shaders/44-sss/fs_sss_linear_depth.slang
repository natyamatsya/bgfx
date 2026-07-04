// 1-to-1 Slang port of examples/44-sss fs_sss_linear_depth.sc.
// Only u_depthUnpackConsts (u_params[1].xy) is referenced, so u_params reflects at
// its used extent (2) -- matching glslang's dead-stripped array length.
// ScreenSpaceToViewSpaceDepth is defined inline in the stock .sc body -> stays inline.
import bgfx_shader;

Texture2D    s_depth        : register(t0);
SamplerState s_depthSampler : register(s0);

// parameters.sh: u_depthUnpackConsts == u_params[1].xy
float4 u_params[2];

// from assao sample, cs_assao_prepare_depths.sc
float ScreenSpaceToViewSpaceDepth( float screenDepth )
{
	float depthLinearizeMul = u_params[1].x;
	float depthLinearizeAdd = u_params[1].y;

	// Optimised version of "-cameraClipNear / (cameraClipFar - projDepth * (cameraClipFar - cameraClipNear)) * cameraClipFar"

	// Set your depthLinearizeMul and depthLinearizeAdd to:
	// depthLinearizeMul = ( cameraClipFar * cameraClipNear) / ( cameraClipFar - cameraClipNear );
	// depthLinearizeAdd = cameraClipFar / ( cameraClipFar - cameraClipNear );

	return depthLinearizeMul / ( depthLinearizeAdd - screenDepth );
}

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0;
	float depth = texture2D(s_depth, s_depthSampler, texCoord).x;
	float linearDepth = ScreenSpaceToViewSpaceDepth(depth);
	return vec4_splat(linearDepth);
}
