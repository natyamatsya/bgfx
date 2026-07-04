// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_packdepth_vsm_linear.sc
import bgfx_shader;
import shaderlib; // packHalfFloat

struct V2F
{
	vec4  pos     : SV_Position;
	float v_depth : TEXCOORD8;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	float depth = input.v_depth;
	float depthSq = depth*depth;

	return vec4(packHalfFloat(depth), packHalfFloat(depthSq));
}
