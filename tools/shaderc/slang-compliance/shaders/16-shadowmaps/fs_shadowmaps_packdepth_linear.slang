// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_packdepth_linear.sc
import bgfx_shader;
import shaderlib; // packFloatToRgba

struct V2F
{
	vec4  pos     : SV_Position;
	float v_depth : TEXCOORD8;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return packFloatToRgba(input.v_depth);
}
