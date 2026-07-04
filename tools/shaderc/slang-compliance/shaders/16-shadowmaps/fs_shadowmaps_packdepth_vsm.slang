// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_packdepth_vsm.sc
import bgfx_shader;
import shaderlib; // packHalfFloat

struct V2F
{
	vec4 pos        : SV_Position;
	vec4 v_position : TEXCOORD7;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	float depth = input.v_position.z/input.v_position.w * 0.5 + 0.5;
	float depthSq = depth*depth;

	return vec4(packHalfFloat(depth), packHalfFloat(depthSq));
}
