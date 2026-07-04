// 1-to-1 Slang port of examples/21-deferred vs_deferred_debug_line.sc.
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
	vec4 a_color0   : COLOR0;
};

struct V2F
{
	vec4 pos      : SV_Position;
	vec4 v_color0 : COLOR0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	output.v_color0 = input.a_color0;
	return output;
}
