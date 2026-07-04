// 1-to-1 Slang port of examples/16-shadowmaps/vs_shadowmaps_packdepth_linear.sc
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
};

struct V2F
{
	vec4  pos     : SV_Position;
	float v_depth : TEXCOORD8;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	output.v_depth = output.pos.z * 0.5 + 0.5;
	return output;
}
