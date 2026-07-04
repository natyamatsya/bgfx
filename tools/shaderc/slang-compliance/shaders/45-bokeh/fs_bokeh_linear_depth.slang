// 1-to-1 Slang port of examples/45-bokeh fs_bokeh_linear_depth.sc.
// ScreenSpaceToViewSpaceDepth is defined inline in the stock body, so it stays inline here.
// u_params (from parameters.sh) is declared locally at its active extent: only [0] is read,
// so glslang reflects u_params[1] with no reserved tail (nothing follows it in $Globals).
import bgfx_shader;

Texture2D    s_depth        : register(t0);
SamplerState s_depthSampler : register(s0);

vec4 u_params[1];

#define u_depthUnpackConsts (u_params[0].xy)

// from assao sample, cs_assao_prepare_depths.sc
float ScreenSpaceToViewSpaceDepth(float screenDepth)
{
	float depthLinearizeMul = u_depthUnpackConsts.x;
	float depthLinearizeAdd = u_depthUnpackConsts.y;

	// Optimised version of "-cameraClipNear / (cameraClipFar - projDepth * (cameraClipFar - cameraClipNear)) * cameraClipFar"

	// Set your depthLinearizeMul and depthLinearizeAdd to:
	// depthLinearizeMul = ( cameraClipFar * cameraClipNear) / ( cameraClipFar - cameraClipNear );
	// depthLinearizeAdd = cameraClipFar / ( cameraClipFar - cameraClipNear );

	return depthLinearizeMul / ( depthLinearizeAdd - screenDepth );
}

struct V2F
{
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
